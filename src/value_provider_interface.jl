###########
# Parameter Indexing
###########

"""
    parameter_values(valp)
    parameter_values(valp, i)
    parameter_values(valp, i::ParameterTimeseriesIndex, j)

Return an indexable collection containing the value of each parameter in `valp`. The two-
argument version of this function returns the parameter value at index `i`. The
two-argument version of this function will default to returning
`parameter_values(valp)[i]`.

For a parameter timeseries object, this should return the parameter values at the final
time. The two-argument version for a parameter timeseries object should also access
parameter values at the final time. An additional three-argument version is also
necessary for parameter timeseries objects. It accepts a [`ParameterTimeseriesIndex`](@ref)
object passed as `i`, the index in the corresponding timeseries `j` and returns the value
of that parameter at the specified time index `j` in the appropriate parameter timeseries.

If this function is called with an `AbstractArray` or `Tuple`, it will return the same
array/tuple.
"""
function parameter_values end

parameter_values(arr::AbstractArray) = arr
parameter_values(arr::Tuple) = arr
parameter_values(arr::AbstractArray, i) = arr[i]
parameter_values(arr::Tuple, i) = arr[i]
parameter_values(prob, i) = parameter_values(parameter_values(prob), i)

"""
    parameter_values_at_time(valp, t) # t is float
"""
function parameter_values_at_time end

"""
    parameter_values_at_state_time(valp, i)
    parameter_values_at_state_time(valp)

Return an indexable collection containing the value of all parameters in `valp` at time
index `i`. This is useful when parameter values change during the simulation (such as
through callbacks) and their values are saved. `i` is the time index in the timeseries
formed by dependent variables.

By default, this function relies on [`parameter_values_at_time`](@ref) and
[`current_time`](@ref) for a default implementation.

The single-argument version of this function is a shorthand to return parameter values
at each point in the state timeseries. This has a default implementation relying on
[`current_time`](@ref) and the two-argument version of this function.
"""
function parameter_values_at_state_time end

function parameter_values_at_state_time(p, i)
    state_time = current_time(p, i)
    return parameter_values_at_time(p, state_time)
end
function parameter_values_at_state_time(p)
    parameter_values_at_state_time.((p,), eachindex(current_time(p)))
end

"""
    parameter_timeseries(valp, i)

Return a vector of the time steps at which the parameter values in the parameter
timeseries at index `i` are saved. This is only required for objects where
`is_parameter_timeseries(valp) === Timeseries()`. It will not be called otherwise. It is
assumed that the timeseries is sorted in increasing order.

See also: [`is_parameter_timeseries`](@ref).
"""
function parameter_timeseries end

"""
    parameter_timeseries_at_state_time(valp, i, j)
    parameter_timeseries_at_state_time(valp, i)

Return the index of the timestep in the parameter timeseries at timeseries index `i` which
occurs just before or at the same time as the state timestep with index `j`. The two-
argument version of this function returns an iterable of indexes, one for each timestep in
the state timeseries. If `j` is an object that refers to multiple values in the state
timeseries (e.g. `Colon`), return an iterable of the indexes in the parameter timeseries
at the appropriate points.

Both versions of this function have default implementations relying on
[`current_time`](@ref) and [`parameter_timeseries`](@ref), for the cases where `j` is one
of: `Int`, `CartesianIndex`, `AbstractArray{Bool}`, `Colon` or an iterable of the
aforementioned.
"""
function parameter_timeseries_at_state_time end

function parameter_timeseries_at_state_time(valp, i, j::Union{Int, CartesianIndex})
    state_time = current_time(valp, j)
    timeseries = parameter_timeseries(valp, i)
    searchsortedlast(timeseries, state_time)
end

function parameter_timeseries_at_state_time(valp, i, ::Colon)
    parameter_timeseries_at_state_time(valp, i)
end

function parameter_timeseries_at_state_time(valp, i, j::AbstractArray{Bool})
    parameter_timeseries_at_state_time(valp, i, only(to_indices(current_time(valp), (j,))))
end

function parameter_timeseries_at_state_time(valp, i, j)
    (parameter_timeseries_at_state_time(valp, i, jj) for jj in j)
end

function parameter_timeseries_at_state_time(valp, i)
    parameter_timeseries_at_state_time(valp, i, eachindex(current_time(valp)))
end

"""
    set_parameter!(valp, val, idx)

Set the parameter at index `idx` to `val` for value provider `valp`. This defaults to
modifying `parameter_values(valp)`. If any additional bookkeeping needs to be performed
or the default implementation does not work for a particular type, this method needs to
be defined to enable the proper functioning of [`setp`](@ref).

See: [`parameter_values`](@ref)
"""
function set_parameter! end

# Tuple only included for the error message
function set_parameter!(sys::Union{AbstractArray, Tuple}, val, idx)
    sys[idx] = val
end
set_parameter!(sys, val, idx) = set_parameter!(parameter_values(sys), val, idx)

"""
    finalize_parameters_hook!(valp, sym)

This is a callback run one for each call to the function returned by [`setp`](@ref)
which can be used to update internal data structures when parameters are modified.
This is in contrast to [`set_parameter!`](@ref) which is run once for each parameter
that is updated.
"""
finalize_parameters_hook!(valp, sym) = nothing

###########
# State Indexing
###########

"""
    state_values(valp)
    state_values(valp, i)

Return an indexable collection containing the values of all states in the value provider
`p`. If `is_timeseries(valp)` is [`Timeseries`](@ref), return a vector of arrays,
each of which contain the state values at the corresponding timestep. In this case, the
two-argument version of the function can also be implemented to efficiently return
the state values at timestep `i`. By default, the two-argument method calls
`state_values(valp)[i]`. If `i` consists of multiple indices (for example, `Colon`,
`AbstractArray{Int}`, `AbstractArray{Bool}`) specialized methods may be defined for
efficiency. By default, `state_values(valp, ::Colon) = state_values(valp)` to avoid
copying the timeseries.

If this function is called with an `AbstractArray`, it will return the same array.

See: [`is_timeseries`](@ref)
"""
function state_values end

state_values(arr::AbstractArray) = arr
state_values(arr, i) = state_values(arr)[i]
state_values(arr, ::Colon) = state_values(arr)

"""
    set_state!(valp, val, idx)

Set the state at index `idx` to `val` for value provider `valp`. This defaults to modifying
`state_values(valp)`. If any additional bookkeeping needs to be performed or the
default implementation does not work for a particular type, this method needs to be
defined to enable the proper functioning of [`setu`](@ref).

See: [`state_values`](@ref)
"""
function set_state! end

"""
    current_time(valp)
    current_time(valp, i)

Return the current time in the value provider `valp`. If
`is_timeseries(valp)` is [`Timeseries`](@ref), return the vector of timesteps at which
the state value is saved. In this case, the two-argument version of the function can
also be implemented to efficiently return the time at timestep `i`. By default, the two-
argument method calls `current_time(p)[i]`. It is assumed that the timeseries is sorted
in increasing order.

If `i` consists of multiple indices (for example, `Colon`, `AbstractArray{Int}`,
`AbstractArray{Bool}`) specialized methods may be defined for efficiency. By default,
`current_time(valp, ::Colon) = current_time(valp)` to avoid copying the timeseries.

By default, the single-argument version acts as the identity function if
`valp isa AbstractVector`.

See: [`is_timeseries`](@ref)
"""
function current_time end

current_time(arr::AbstractVector) = arr
current_time(valp, i) = current_time(valp)[i]
current_time(valp, ::Colon) = current_time(valp)

###########
# Utilities
###########

abstract type AbstractIndexer end

abstract type AbstractGetIndexer <: AbstractIndexer end
abstract type AbstractStateGetIndexer <: AbstractGetIndexer end
abstract type AbstractParameterGetIndexer <: AbstractGetIndexer end
abstract type AbstractSetIndexer <: AbstractIndexer end

(ai::AbstractStateGetIndexer)(prob) = ai(is_timeseries(prob), prob)
(ai::AbstractStateGetIndexer)(prob, i) = ai(is_timeseries(prob), prob, i)
(ai::AbstractParameterGetIndexer)(prob) = ai(is_parameter_timeseries(prob), prob)
(ai::AbstractParameterGetIndexer)(prob, i) = ai(is_parameter_timeseries(prob), prob, i)
function (ai::AbstractParameterGetIndexer)(buffer::AbstractArray, prob)
    ai(buffer, is_parameter_timeseries(prob), prob)
end
function (ai::AbstractParameterGetIndexer)(buffer::AbstractArray, prob, i)
    ai(buffer, is_parameter_timeseries(prob), prob, i)
end

abstract type IsIndexerTimeseries end

struct IndexerTimeseries <: IsIndexerTimeseries end
struct IndexerNotTimeseries <: IsIndexerTimeseries end
struct IndexerBoth <: IsIndexerTimeseries end

const AtLeastTimeseriesIndexer = Union{IndexerTimeseries, IndexerBoth}
const AtLeastNotTimeseriesIndexer = Union{IndexerNotTimeseries, IndexerBoth}

is_indexer_timeseries(x) = is_indexer_timeseries(typeof(x))
function indexer_timeseries_index end

as_not_timeseries_indexer(x) = as_not_timeseries_indexer(is_indexer_timeseries(x), x)
as_not_timeseries_indexer(::IndexerNotTimeseries, x) = x
function as_not_timeseries_indexer(::IndexerTimeseries, x)
    error("""
        Tried to convert an `$IndexerTimeseries` to an `$IndexerNotTimeseries`. This \
        should never happen. Please file an issue with an MWE.
    """)
end

as_timeseries_indexer(x) = as_timeseries_indexer(is_indexer_timeseries(x), x)
as_timeseries_indexer(::IndexerTimeseries, x) = x
function as_timeseries_indexer(::IndexerNotTimeseries, x)
    error("""
        Tried to convert an `$IndexerNotTimeseries` to an `$IndexerTimeseries`. This \
        should never happen. Please file an issue with an MWE.
    """)
end

struct CallWith{A}
    args::A

    CallWith(args...) = new{typeof(args)}(args)
end

function (cw::CallWith)(arg)
    arg(cw.args...)
end

###########
# Errors
###########

struct ParameterTimeseriesValueIndexMismatchError{P <: IsTimeseriesTrait} <: Exception
    valp::Any
    indexer::Any
    args::Any

    function ParameterTimeseriesValueIndexMismatchError{Timeseries}(valp, indexer, args)
        if is_parameter_timeseries(valp) != Timeseries()
            throw(ArgumentError("""
                This should never happen. Expected parameter timeseries value provider, \
                got $(valp). Open an issue in SymbolicIndexingInterface.jl with an MWE.
            """))
        end
        if is_indexer_timeseries(indexer) != IndexerNotTimeseries()
            throw(ArgumentError("""
                This should never happen. Expected non-timeseries indexer, got \
                $(indexer). Open an issue in SymbolicIndexingInterface.jl with an MWE.
            """))
        end
        return new{Timeseries}(valp, indexer, args)
    end
    function ParameterTimeseriesValueIndexMismatchError{NotTimeseries}(valp, indexer)
        if is_parameter_timeseries(valp) != NotTimeseries()
            throw(ArgumentError("""
                This should never happen. Expected non-parameter timeseries value \
                provider, got $(valp). Open an issue in SymbolicIndexingInterface.jl \
                with an MWE.
            """))
        end
        if is_indexer_timeseries(indexer) != IndexerTimeseries()
            throw(ArgumentError("""
                This should never happen. Expected timeseries indexer, got $(indexer). \
                Open an issue in SymbolicIndexingInterface.jl with an MWE.
            """))
        end
        return new{NotTimeseries}(valp, indexer, nothing)
    end
end

function Base.showerror(io::IO, err::ParameterTimeseriesValueIndexMismatchError{Timeseries})
    print(io, """
        Invalid indexing operation: tried to access object of type $(typeof(err.valp)) \
        (which is a parameter timeseries object) with non-timeseries indexer \
        $(err.indexer) at index $(err.args) in the timeseries.
    """)
end

function Base.showerror(
        io::IO, err::ParameterTimeseriesValueIndexMismatchError{NotTimeseries})
    print(io, """
        Invalid indexing operation: tried to access object of type $(typeof(err.valp)) \
        (which is not a parameter timeseries object) using timeseries indexer \
        $(err.indexer).
    """)
end

struct MixedParameterTimeseriesIndexError <: Exception
    valp::Any
    ts_idxs::Any
end

function Base.showerror(io::IO, err::MixedParameterTimeseriesIndexError)
    print(io, """
        Invalid indexing operation: tried to access object of type $(typeof(err.valp)) \
        (which is a parameter timeseries object) with variables having mixed timeseries \
        indexes $(err.ts_idxs).
    """)
end
