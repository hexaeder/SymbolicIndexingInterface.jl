# Implementing the Complete Symbolic Indexing Interface

## Index Provider Interface
This tutorial will show how to define the entire Symbolic Indexing Interface on an
`ExampleSystem`:

```julia
struct ExampleSystem
  state_index::Dict{Symbol,Int}
  parameter_index::Dict{Symbol,Int}
  independent_variable::Union{Symbol,Nothing}
  defaults::Dict{Symbol, Float64}
  # mapping from observed variable to Expr to calculate its value
  observed::Dict{Symbol,Expr}
end
```

Not all the methods in the interface are required. Some only need to be implemented if a type
supports specific functionality. Consider the following struct, which needs to implement the interface:

### Mandatory methods

#### Simple Indexing Functions

These are the simple functions which describe how to turn symbols into indices.

```julia
function SymbolicIndexingInterface.is_variable(sys::ExampleSystem, sym)
  haskey(sys.state_index, sym)
end

function SymbolicIndexingInterface.variable_index(sys::ExampleSystem, sym)
  get(sys.state_index, sym, nothing)
end

function SymbolicIndexingInterface.variable_symbols(sys::ExampleSystem)
  collect(keys(sys.state_index))
end

function SymbolicIndexingInterface.is_parameter(sys::ExampleSystem, sym)
  haskey(sys.parameter_index, sym)
end

function SymbolicIndexingInterface.parameter_index(sys::ExampleSystem, sym)
  get(sys.parameter_index, sym, nothing)
end

function SymbolicIndexingInterface.parameter_symbols(sys::ExampleSystem)
  collect(keys(sys.parameter_index))
end

function SymbolicIndexingInterface.is_independent_variable(sys::ExampleSystem, sym)
  # note we have to check separately for `nothing`, otherwise
  # `is_independent_variable(p, nothing)` would return `true`.
  sys.independent_variable !== nothing && sym === sys.independent_variable
end

function SymbolicIndexingInterface.independent_variable_symbols(sys::ExampleSystem)
  sys.independent_variable === nothing ? [] : [sys.independent_variable]
end

function SymbolicIndexingInterface.is_time_dependent(sys::ExampleSystem)
  sys.independent_variable !== nothing
end

SymbolicIndexingInterface.constant_structure(::ExampleSystem) = true

function SymbolicIndexingInterface.all_solvable_symbols(sys::ExampleSystem)
  return vcat(
    collect(keys(sys.state_index)),
    collect(keys(sys.observed)),
  )
end

function SymbolicIndexingInterface.all_symbols(sys::ExampleSystem)
  return vcat(
    all_solvable_symbols(sys),
    collect(keys(sys.parameter_index)),
    sys.independent_variable === nothing ? Symbol[] : sys.independent_variable
  )
end

function SymbolicIndexingInterface.default_values(sys::ExampleSystem)
  return sys.defaults
end
```

#### Observed Equation Handling

These are for handling symbolic expressions and generating equations which are not directly
in the solution vector.

```julia
using RuntimeGeneratedFunctions
RuntimeGeneratedFunctions.init(@__MODULE__)

# this type accepts `Expr` for observed expressions involving state/parameter/observed
# variables
SymbolicIndexingInterface.is_observed(sys::ExampleSystem, sym) = sym isa Expr || sym isa Symbol && haskey(sys.observed, sym)

function SymbolicIndexingInterface.observed(sys::ExampleSystem, sym::Expr)
  # generate a function with the appropriate signature
  if is_time_dependent(sys)
    fn_expr = :(
      function gen(u, p, t)
        # assign a variable for each state symbol it's value in u
        $([:($var = u[$idx]) for (var, idx) in pairs(sys.state_index)]...)
        # assign a variable for each parameter symbol it's value in p
        $([:($var = p[$idx]) for (var, idx) in pairs(sys.parameter_index)]...)
        # assign a variable for the independent variable
        $(sys.independent_variable) = t
        # return the value of the expression
        return $sym
      end
    )
  else
    fn_expr = :(
      function gen(u, p)
        # assign a variable for each state symbol it's value in u
        $([:($var = u[$idx]) for (var, idx) in pairs(sys.state_index)]...)
        # assign a variable for each parameter symbol it's value in p
        $([:($var = p[$idx]) for (var, idx) in pairs(sys.parameter_index)]...)
        # return the value of the expression
        return $sym
      end
    )
  end
  return @RuntimeGeneratedFunction(fn_expr)
end
```

In case a type does not support such observed quantities, `is_observed` must be
defined to always return `false`, and `observed` does not need to be implemented.

The same process can be followed for [`parameter_observed`](@ref), with the exception
that the returned function must not have `u` in its signature, and must be wrapped in a
[`ParameterObservedFunction`](@ref). In-place versions can also be implemented for
`parameter_observed`.

#### Note about constant structure

Note that the method definitions are all assuming `constant_structure(p) == true`.

In case `constant_structure(p) == false`, the following methods would change:
- `constant_structure(::ExampleSystem) = false`
- `variable_index(sys::ExampleSystem, sym)` would become
  `variable_index(sys::ExampleSystem, sym i)` where `i` is the time index at which
  the index of `sym` is required.
- `variable_symbols(sys::ExampleSystem)` would become
  `variable_symbols(sys::ExampleSystem, i)` where `i` is the time index at which
  the variable symbols are required.
- `observed(sys::ExampleSystem, sym)` would become
  `observed(sys::ExampleSystem, sym, i)` where `i` is either the time index at which
  the index of `sym` is required or a `Vector` of state symbols at the current time index.

### Optional methods

Note that `observed` is optional if `is_observed` is always `false`, or the type is
only responsible for identifying observed values and `observed` will always be called
on a type that wraps this type. An example is `ModelingToolkit.AbstractSystem`, which
can identify whether a value is observed, but cannot implement `observed` itself.

## Value Provider Interface

Other interface methods relate to indexing functions. If a type contains the values of
parameter variables, it must implement [`parameter_values`](@ref). This allows the
default definitions of [`getp`](@ref) and [`setp`](@ref) to work. While `setp` is
not typically useful for solution objects, it may be useful for integrators. Typically,
the default implementations for `getp` and `setp` will suffice, and manually defining
them is not necessary.

```julia
function SymbolicIndexingInterface.parameter_values(sys::ExampleSystem)
  sys.p
end
```

If a type contains the value of state variables, it can define [`state_values`](@ref) to
enable the usage of [`getu`](@ref) and [`setu`](@ref). These methods retturn getter/
setter functions to access or update the value of a state variable (or a collection of
them). If the type also supports generating [`observed`](@ref) functions, `getu` also
enables returning functions to access the value of arbitrary expressions involving
the system's symbols. This also requires that the type implement
[`parameter_values`](@ref) and [`current_time`](@ref) (if the system is time-dependent).

Consider the following `ExampleIntegrator`

```julia
mutable struct ExampleIntegrator
  u::Vector{Float64}
  p::Vector{Float64}
  t::Float64
  sys::ExampleSystem
end

# define a fallback for the interface methods
SymbolicIndexingInterface.symbolic_container(integ::ExampleIntegrator) = integ.sys
SymbolicIndexingInterface.state_values(sys::ExampleIntegrator) = sys.u
SymbolicIndexingInterface.parameter_values(sys::ExampleIntegrator) = sys.p
SymbolicIndexingInterface.current_time(sys::ExampleIntegrator) = sys.t
```

Then the following example would work:
```julia
sys = ExampleSystem(Dict(:x => 1, :y => 2, :z => 3), Dict(:a => 1, :b => 2), :t, Dict())
integrator = ExampleIntegrator([1.0, 2.0, 3.0], [4.0, 5.0], 6.0, sys)
getx = getu(sys, :x)
getx(integrator) # 1.0

get_expr = getu(sys, :(x + y + t))
get_expr(integrator) # 13.0

setx! = setu(sys, :y)
setx!(integrator, 0.0)
getx(integrator) # 0.0
```

In case a type stores timeseries data (such as solutions), then it must also implement
the [`Timeseries`](@ref) trait. The type would then return a timeseries from
[`state_values`](@ref) and [`current_time`](@ref) and the function returned from
[`getu`](@ref) would then return a timeseries as well. For example, consider the
`ExampleSolution` below:

```julia
struct ExampleSolution
  u::Vector{Vector{Float64}}
  t::Vector{Float64}
  p::Vector{Float64}
  sys::ExampleSystem
end

# define a fallback for the interface methods
SymbolicIndexingInterface.symbolic_container(sol::ExampleSolution) = sol.sys
SymbolicIndexingInterface.parameter_values(sol::ExampleSolution) = sol.p
# define the trait
SymbolicIndexingInterface.is_timeseries(::Type{ExampleSolution}) = Timeseries()
# both state_values and current_time return a timeseries, which must be
# the same length
SymbolicIndexingInterface.state_values(sol::ExampleSolution) = sol.u
SymbolicIndexingInterface.current_time(sol::ExampleSolution) = sol.t
```

Then the following example would work:
```julia
# using the same system that the ExampleIntegrator used
sol = ExampleSolution([[1.0, 2.0, 3.0], [1.5, 2.5, 3.5]], [4.0, 5.0], [6.0, 7.0], sys)
getx = getu(sys, :x)
getx(sol) # [1.0, 1.5]

get_expr = getu(sys, :(x + y + t))
get_expr(sol) # [9.0, 11.0]

get_arr = getu(sys, [:y, :(x + a)])
get_arr(sol) # [[2.0, 5.0], [2.5, 5.5]]

get_tuple = getu(sys, (:z, :(z * t)))
get_tuple(sol) # [(3.0, 18.0), (3.5, 24.5)]
```

Note that `setu` is not designed to work for `Timeseries` objects.

If a type needs to perform some additional actions when updating the state/parameters
or if it is not possible to return a mutable reference to the state/parameter vector
which can directly be modified, the functions [`set_state!`](@ref) and/or
[`set_parameter!`](@ref) can be used. For example, suppose our `ExampleIntegrator`
had an additional field `u_modified::Bool` to allow it to keep track of when a
discontinuity occurs and handle it appropriately. This flag needs to be set to `true`
whenever the state is modified. The `set_state!` function can then be implemented as
follows:

```julia
function SymbolicIndexingInterface.set_state!(integrator::ExampleIntegrator, val, idx)
  integrator.u[idx] = val
  integrator.u_modified = true
end
```

### Using `finalize_parameters_hook!`

The function [`finalize_parameters_hook!`](@ref) is called exactly _once_ every time the
function returned by `setp` is called. This allows performing any additional bookkeeping
required when parameter values are updated. [`set_parameter!`](@ref) also allows performing
similar functionality, but is called for every parameter that is updated, instead of just
once. Thus, `finalize_parameters_hook!` is better for expensive computations that can be
performed for a bulk parameter update.

## The `ParameterIndexingProxy`

[`ParameterIndexingProxy`](@ref) is a wrapper around another type which implements the
interface and allows using [`getp`](@ref) and [`setp`](@ref) to get and set parameter 
values. This allows for a cleaner interface for parameter indexing. Consider the
following example for `ExampleIntegrator`:

```julia
function Base.getproperty(obj::ExampleIntegrator, sym::Symbol)
  if sym === :ps
    return ParameterIndexingProxy(obj)
  else
    return getfield(obj, sym)
  end
end
```

This enables the following API:

```julia
integrator = ExampleIntegrator([1.0, 2.0, 3.0], [4.0, 5.0], 6.0, Dict(:x => 1, :y => 2, :z => 3), Dict(:a => 1, :b => 2), :t)

integrator.ps[:a] # 4.0
getp(integrator, :a)(integrator) # functionally the same as above

integrator.ps[:b] = 3.0
setp(integrator, :b)(integrator, 3.0) # functionally the same as above
```

## Parameter Timeseries

If a solution object saves modified parameter values (such as through callbacks) during the
simulation, it must implement several additional functions for correct functioning of
[`getu`](@ref) and [`getp`](@ref). [`ParameterTimeseriesCollection`](@ref) helps in
implementing parameter timeseries objects. The following mockup gives an example of
correct implementation of these functions and the indexing syntax they enable.

```@example param_timeseries
using SymbolicIndexingInterface

struct ExampleSolution2
    sys::SymbolCache
    u::Vector{Vector{Float64}}
    t::Vector{Float64}
    p::Vector{Float64} # the parameter object. Only some parameters are timeseries params
    p_idxs::Vector{Vector{Int}}
    p_ts::ParameterTimeseriesCollection
end

# Add the `:ps` property to automatically wrap in `ParameterIndexingProxy`
function Base.getproperty(fs::ExampleSolution2, s::Symbol)
    s === :ps ? ParameterIndexingProxy(fs) : getfield(fs, s)
end
# Use the contained `SymbolCache` for indexing
SymbolicIndexingInterface.symbolic_container(fs::ExampleSolution2) = fs.sys
# State indexing methods
SymbolicIndexingInterface.state_values(fs::ExampleSolution2) = fs.u
SymbolicIndexingInterface.current_time(fs::ExampleSolution2) = fs.t
# By default, `parameter_values` refers to the last value
SymbolicIndexingInterface.parameter_values(fs::ExampleSolution2) = fs.p
SymbolicIndexingInterface.parameter_values(fs::ExampleSolution2, i) = fs.p[i]
function SymbolicIndexingInterface.parameter_values(fs::ExampleSolution2, i::ParameterTimeseriesIndex, j)
  return fs.p_ts[i, j]
end
# Index into the parameter timeseries vector
function SymbolicIndexingInterface.parameter_values_at_time(fs::ExampleSolution2, t)
    newp = copy(fs.p)
    # iterating over `ParameterTimeseriesCollection` iterates over the contained timeseries
    # objects
    for (idxs, timeseries) in zip(fs.p_idxs, fs.p_ts)
      # find the index of the last point in time the parameter values were saved
      # before the requested time `t`
      index_in_timeseries = searchsortedlast(current_time(timeseries), t)
      # obtain the required values
      timeseries_values = state_values(timeseries, index_in_timeseries)
      # update parameter vector
      newp[idxs] = timeseries_values
    end
    return newp
end
function SymbolicIndexingInterface.parameter_timeseries(fs::ExampleSolution2, i)
  # `ParameterTimeseriesCollection` implements this for us
  return parameter_timeseries(fs.p_ts, i)
end
# Mark the object as a timeseries object
SymbolicIndexingInterface.is_timeseries(::Type{ExampleSolution2}) = Timeseries()
# Mark the object as a parameter timeseries object
SymbolicIndexingInterface.is_parameter_timeseries(::Type{ExampleSolution2}) = Timeseries()
```

We will also need a timeseries object which will store individual parameter timeseries.
`DiffEqArray` in `RecursiveArrayTools.jl` satisfies this use case, but we will implement
one manually here.

```@example param_timeseries
struct MyDiffEqArray
  t::Vector{Float64}
  u::Vector{Vector{Float64}}
end

# Must be a timeseries object, and implement `current_time` and `state_values`
SymbolicIndexingInterface.is_timeseries(::Type{MyDiffEqArray}) = Timeseries()
SymbolicIndexingInterface.current_time(a::MyDiffEqArray) = a.t
SymbolicIndexingInterface.state_values(a::MyDiffEqArray) = a.u
```

Now we can create an example object and observe the new functionality. Note that
`sol.ps[sym, args...]` is identical to `getp(sol, sym)(sol, args...)`.

```@example param_timeseries
sys = SymbolCache(
  [:x, :y, :z], [:a, :b, :c, :d], :t;
  # specify that :b, :c and :d are timeseries parameters
  # :b and :c belong to the same timeseries
  # :d is in a different timeseries
  timeseries_parameters = Dict(
    :b => ParameterTimeseriesIndex(1, 1),
    :c => ParameterTimeseriesIndex(1, 2),
    :d => ParameterTimeseriesIndex(2, 1),
  ))
b_c_timeseries = MyDiffEqArray(
  collect(0.0:0.1:1.0),
  [[0.25i, 0.35i] for i in 1:11]
)
d_timeseries = MyDiffEqArray(
  collect(0.0:0.2:1.0),
  [[0.17i] for i in 1:6]
)
sol = ExampleSolution2(
    sys,
    [i * ones(3) for i in 1:5], # u
    collect(0.0:0.25:1.0), # t
    [4.2, b_c_timeseries.u[end]..., d_timeseries.u[end]...], # p must contain final values
    [[2, 3], 4], # p_idxs
    ParameterTimeseriesCollection([b_c_timeseries, d_timeseries]) # p_ts
)
sol.ps[:a] # returns the value of non-timeseries parameter
```

```@example param_timeseries
sol.ps[:b] # returns the timeseries of :b
```

```@example param_timeseries
sol.ps[:b, 3] # index at a specific index in the parameter timeseries
```

```@example param_timeseries
sol.ps[:a, [3, 6, 8]] # index using arrays
```

```@example param_timeseries
idxs = @show rand(Bool, 11) # boolean mask for indexing
sol.ps[:a, idxs]
```

```@example param_timeseries
sol.ps[[:a, :b]] # returns the values at the last timestep, since :a is not timeseries
```

```@example param_timeseries
# throws an error since :b and :d belong to different timeseries
try
  sol.ps[[:b, :d]]
catch e
  @show e
end
```

```@example param_timeseries
sol.ps[:(b + c)] # observed quantities work too
```

```@example param_timeseries
getu(sol, :b)(sol) # returns the values :b takes at the times in the state timeseries
```

```@example param_timeseries
getu(sol, [:b, :d])(sol) # works
```

## Custom containers

A custom container object (such as `ModelingToolkit.MTKParameters`) should implement
[`remake_buffer`](@ref) to allow creating a new buffer with updated values, possibly
with different types. This is already implemented for `AbstractArray`s (including static
arrays).

# Implementing the `SymbolicTypeTrait` for a type

The `SymbolicTypeTrait` is used to identify values that can act as symbolic variables. It
has three variants:

- [`NotSymbolic`](@ref) for quantities that are not symbolic. This is the default for all
  types.
- [`ScalarSymbolic`](@ref) for quantities that are symbolic, and represent a single
  logical value.
- [`ArraySymbolic`](@ref) for quantities that are symbolic, and represent an array of
  values. Types implementing this trait must return an array of `ScalarSymbolic` variables
  of the appropriate size and dimensions when `collect`ed.

The trait is implemented through the [`symbolic_type`](@ref) function. Consider the following
example types:

```julia
struct MySym
  name::Symbol
end

struct MySymArr{N}
  name::Symbol
  size::NTuple{N,Int}
end
```

They must implement the following functions:

```julia
SymbolicIndexingInterface.symbolic_type(::Type{MySym}) = ScalarSymbolic()
SymbolicIndexingInterface.hasname(::MySym) = true
SymbolicIndexingInterface.getname(sym::MySym) = sym.name

SymbolicIndexingInterface.symbolic_type(::Type{<:MySymArr}) = ArraySymbolic()
SymbolicIndexingInterface.hasname(::MySymArr) = true
SymbolicIndexingInterface.getname(sym::MySymArr) = sym.name
function Base.collect(sym::MySymArr)
  [
    MySym(Symbol(sym.name, :_, join(idxs, "_")))
    for idxs in Iterators.product(Base.OneTo.(sym.size)...)
  ]
end
```

[`hasname`](@ref) is not required to always be `true` for symbolic types. For example,
`Symbolics.Num` returns `false` whenever the wrapped value is a number, or an expression.

Introducing a type to represent expression trees:

```julia
struct MyExpr
  op::Function
  args::Vector{Union{MyExpr, MySym, MySymArr, Number, Array}}
end
```

[`symbolic_evaluate`](@ref) can be implemented as follows:

```julia
function symbolic_evaluate(expr::Union{MySym, MySymArr}, syms::Dict)
  get(syms, expr, expr)
end
function symbolic_evaluate(expr::MyExpr, syms::Dict)
  for i in eachindex(expr.args)
    if expr.args[i] isa Union{MySym, MySymArr, MyExpr}
      expr.args[i] = symbolic_evaluate(expr.args[i], syms)
    end
  end
  if all(x -> symbolic_type(x) === NotSymbolic(), expr.args)
    return expr.op(expr.args...)
  end
end
```

Note the evaluation of the operation if all of the arguments are not symbolic. This is
required since `symbolic_evaluate` must return an evaluated value if all symbolic variables
are substituted.
