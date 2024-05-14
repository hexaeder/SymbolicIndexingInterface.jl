"""
    struct SymbolCache
    function SymbolCache(vars, [params, [indepvars]]; defaults = Dict(), timeseries_parameters = nothing)

A struct implementing the index provider interface for the trivial case of having a
vector of variables, parameters, and independent variables. It is considered time
dependent if it contains at least one independent variable. It returns `true` for
`is_observed(::SymbolCache, sym)` if `sym isa Expr`. Functions can be generated using
`observed` for `Expr`s involving variables in the `SymbolCache` if it has at most one
independent variable. `defaults` is an `AbstractDict` mapping variables and/or parameters
to their default initial values. The default initial values can also be other variables/
parameters or expressions of them. `timeseries_parameters` is an `AbstractDict` the
timeseries parameters in `params` to their [`ParameterTimeseriesIndex`](@ref) indexes.

Instead of arrays, the variables and parameters can also be provided as `AbstractDict`s
mapping symbols to indices.

The independent variable may be specified as a single symbolic variable instead of an
array containing a single variable if the system has only one independent variable.
"""
struct SymbolCache{
    V <: Union{Nothing, AbstractDict},
    P <: Union{Nothing, AbstractDict},
    T <: Union{Nothing, AbstractDict},
    I,
    D <: AbstractDict
}
    variables::V
    parameters::P
    timeseries_parameters::T
    independent_variables::I
    defaults::D
end

function to_dict_or_nothing(arr::Union{AbstractArray, Tuple})
    eltype(arr) <: Pair && return Dict(arr)
    isempty(arr) && return nothing
    return Dict(v => k for (k, v) in enumerate(arr))
end
to_dict_or_nothing(d::AbstractDict) = d
to_dict_or_nothing(::Nothing) = nothing

function SymbolCache(vars = nothing, params = nothing, indepvars = nothing;
        defaults = Dict(), timeseries_parameters = nothing)
    vars = to_dict_or_nothing(vars)
    params = to_dict_or_nothing(params)
    timeseries_parameters = to_dict_or_nothing(timeseries_parameters)
    if timeseries_parameters !== nothing
        if indepvars === nothing
            throw(ArgumentError("Independent variable is required for timeseries parameters to exist"))
        end
        for (k, v) in timeseries_parameters
            if !haskey(params, k)
                throw(ArgumentError("Timeseries parameter $k must also be present in parameters."))
            end
            if !isa(v, ParameterTimeseriesIndex)
                throw(TypeError(:SymbolCache, "index of timeseries parameter $k",
                    ParameterTimeseriesIndex, v))
            end
        end
    end
    return SymbolCache{typeof(vars), typeof(params), typeof(timeseries_parameters),
        typeof(indepvars), typeof(defaults)}(
        vars,
        params,
        timeseries_parameters,
        indepvars,
        defaults)
end

function is_variable(sc::SymbolCache, sym)
    sc.variables !== nothing && haskey(sc.variables, sym)
end
function variable_index(sc::SymbolCache, sym)
    sc.variables === nothing ? nothing : get(sc.variables, sym, nothing)
end
function variable_symbols(sc::SymbolCache, i = nothing)
    sc.variables === nothing && return []
    buffer = collect(keys(sc.variables))
    for (k, v) in sc.variables
        buffer[v] = k
    end
    return buffer
end
function is_parameter(sc::SymbolCache, sym)
    sc.parameters !== nothing && haskey(sc.parameters, sym)
end
function parameter_index(sc::SymbolCache, sym)
    sc.parameters === nothing ? nothing : get(sc.parameters, sym, nothing)
end
function parameter_symbols(sc::SymbolCache)
    sc.parameters === nothing ? [] : collect(keys(sc.parameters))
end
function is_timeseries_parameter(sc::SymbolCache, sym)
    sc.timeseries_parameters !== nothing && haskey(sc.timeseries_parameters, sym)
end
function timeseries_parameter_index(sc::SymbolCache, sym)
    sc.timeseries_parameters === nothing ? nothing :
    get(sc.timeseries_parameters, sym, nothing)
end
function is_independent_variable(sc::SymbolCache, sym)
    sc.independent_variables === nothing && return false
    if symbolic_type(sc.independent_variables) == NotSymbolic()
        return any(isequal(sym), sc.independent_variables)
    elseif symbolic_type(sc.independent_variables) == ScalarSymbolic()
        return sym == sc.independent_variables
    else
        return any(isequal(sym), collect(sc.independent_variables))
    end
end
function independent_variable_symbols(sc::SymbolCache)
    sc.independent_variables === nothing && return []
    if symbolic_type(sc.independent_variables) == NotSymbolic()
        return sc.independent_variables
    elseif symbolic_type(sc.independent_variables) == ScalarSymbolic()
        return [sc.independent_variables]
    else
        return collect(sc.independent_variables)
    end
end
is_observed(sc::SymbolCache, sym) = false
is_observed(::SymbolCache, ::Expr) = true
is_observed(::SymbolCache, ::AbstractArray{Expr}) = true
is_observed(::SymbolCache, ::Tuple{Vararg{Expr}}) = true

# TODO: Make this less hacky
struct ExpressionSearcher
    parameters::Set{Symbol}
    declared::Set{Symbol}
    fnbody::Expr
end

ExpressionSearcher() = ExpressionSearcher(Set{Symbol}(), Set{Symbol}(), Expr(:block))

function (exs::ExpressionSearcher)(sys, expr::Expr)
    for arg in expr.args
        exs(sys, arg)
    end
    exs(sys, expr.head)
    return nothing
end

function (exs::ExpressionSearcher)(sys, sym::Symbol)
    sym in exs.declared && return
    if is_variable(sys, sym)
        idx = variable_index(sys, sym)
        push!(exs.fnbody.args, :($sym = u[$idx]))
    elseif is_parameter(sys, sym)
        idx = parameter_index(sys, sym)
        push!(exs.parameters, sym)
        push!(exs.fnbody.args, :($sym = p[$idx]))
    elseif is_independent_variable(sys, sym)
        push!(exs.fnbody.args, :($sym = t))
    end
    push!(exs.declared, sym)
    return nothing
end

(::ExpressionSearcher)(sys, sym) = nothing

function observed(sc::SymbolCache, expr::Expr)
    let cache = Dict{Expr, Function}()
        return get!(cache, expr) do
            exs = ExpressionSearcher()
            exs(sc, expr)
            fnexpr = if is_time_dependent(sc)
                :(function (u, p, t)
                    $(exs.fnbody)
                    return $expr
                end)
            else
                :(function (u, p)
                    $(exs.fnbody)
                    return $expr
                end)
            end
            return RuntimeGeneratedFunctions.@RuntimeGeneratedFunction(fnexpr)
        end
    end
end

to_expr(exprs::AbstractArray) = :(reshape([$(exprs...)], $(size(exprs))))
to_expr(exprs::Tuple) = :(($(exprs...),))

function inplace_observed(sc::SymbolCache, exprs::Union{AbstractArray, Tuple})
    let cache = Dict{Expr, Function}()
        return get!(cache, to_expr(exprs)) do
            exs = ExpressionSearcher()
            for expr in exprs
                exs(sc, expr)
            end
            update_expr = Expr(:block)
            for (i, expr) in enumerate(exprs)
                push!(update_expr.args, :(buffer[$i] = $expr))
            end
            fnexpr = if is_time_dependent(sc)
                :(function (buffer, u, p, t)
                    $(exs.fnbody)
                    $update_expr
                    return buffer
                end)
            else
                :(function (buffer, u, p)
                    $(exs.fnbody)
                    $update_expr
                    return buffer
                end)
            end
            return RuntimeGeneratedFunctions.@RuntimeGeneratedFunction(fnexpr)
        end
    end
end

function observed(sc::SymbolCache, exprs::Union{AbstractArray, Tuple})
    for expr in exprs
        if !(expr isa Union{Symbol, Expr})
            throw(TypeError(:observed, "SymbolCache", Union{Symbol, Expr}, expr))
        end
    end
    return observed(sc, to_expr(exprs))
end

function parameter_observed(sc::SymbolCache, expr::Expr)
    if is_time_dependent(sc)
        exs = ExpressionSearcher()
        exs(sc, expr)
        ts_idxs = Set()
        for p in exs.parameters
            is_timeseries_parameter(sc, p) || continue
            push!(ts_idxs, timeseries_parameter_index(sc, p).timeseries_idx)
        end
        f = let fn = observed(sc, expr)
            f1(p, t) = fn(nothing, p, t)
        end
        if length(ts_idxs) == 1
            return ParameterObservedFunction(only(ts_idxs), f)
        else
            return ParameterObservedFunction(nothing, f)
        end
    else
        f = let fn = observed(sc, expr)
            f2(p) = fn(nothing, p)
        end
        return ParameterObservedFunction(nothing, f)
    end
end

function parameter_observed(sc::SymbolCache, exprs::Union{AbstractArray, Tuple})
    for ex in exprs
        if !(ex isa Union{Symbol, Expr})
            throw(TypeError(:parameter_observed, "SymbolCache", Union{Symbol, Expr}, ex))
        end
    end
    if is_time_dependent(sc)
        exs = ExpressionSearcher()
        exs(sc, to_expr(exprs))
        ts_idxs = Set()
        for p in exs.parameters
            is_timeseries_parameter(sc, p) || continue
            push!(ts_idxs, timeseries_parameter_index(sc, p).timeseries_idx)
        end

        f = let oop = observed(sc, to_expr(exprs)), iip = inplace_observed(sc, exprs)
            f1(p, t) = oop(nothing, p, t)
            f1(buffer, p, t) = iip(buffer, nothing, p, t)
        end
        if length(ts_idxs) == 1
            return ParameterObservedFunction(only(ts_idxs), f)
        else
            return ParameterObservedFunction(nothing, f)
        end
    else
        f = let oop = observed(sc, to_expr(exprs)), iip = inplace_observed(sc, exprs)
            f2(p) = oop(nothing, p)
            f2(buffer, p) = iip(buffer, nothing, p)
        end
        return ParameterObservedFunction(nothing, f)
    end
end

function is_time_dependent(sc::SymbolCache)
    sc.independent_variables === nothing && return false
    if symbolic_type(sc.independent_variables) == NotSymbolic()
        return !isempty(sc.independent_variables)
    else
        return true
    end
end
constant_structure(::SymbolCache) = true
all_variable_symbols(sc::SymbolCache) = variable_symbols(sc)
function all_symbols(sc::SymbolCache)
    vcat(variable_symbols(sc), parameter_symbols(sc), independent_variable_symbols(sc))
end
default_values(sc::SymbolCache) = sc.defaults

function Base.copy(sc::SymbolCache)
    return SymbolCache(sc.variables === nothing ? nothing : copy(sc.variables),
        sc.parameters === nothing ? nothing : copy(sc.parameters),
        sc.timeseries_parameters === nothing ? nothing : copy(sc.timeseries_parameters),
        sc.independent_variables isa AbstractArray ? copy(sc.independent_variables) :
        sc.independent_variables, copy(sc.defaults))
end
