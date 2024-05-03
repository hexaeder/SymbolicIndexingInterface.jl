# Interface Functions

## Index provider interface

### Mandatory methods

```@docs
symbolic_container
is_variable
variable_index
variable_symbols
is_parameter
parameter_index
parameter_symbols
is_independent_variable
independent_variable_symbols
is_observed
default_values
is_time_dependent
constant_structure
all_variable_symbols
all_symbols
solvedvariables
allvariables
```

### Optional Methods

#### Observed equation handling

```@docs
observed
```

## Value provider interface

### State indexing

```@docs
Timeseries
NotTimeseries
is_timeseries
state_values
set_state!
current_time
getu
setu
```

### Parameter indexing

```@docs
parameter_values
set_parameter!
finalize_parameters_hook!
getp
setp
ParameterIndexingProxy
```

#### Parameter timeseries

If a solution object saves a timeseries of parameter values that are updated during the
simulation (such as by callbacks), it must implement the following methods to ensure
correct functioning of [`getu`](@ref) and [`getp`](@ref).

```@docs
is_parameter_timeseries
parameter_timeseries
parameter_values_at_time
parameter_values_at_state_time
```

### Batched Queries and Updates

```@docs
BatchedInterface
associated_systems
```

## Container objects

```@docs
remake_buffer
```

# Symbolic Trait

```@docs
ScalarSymbolic
ArraySymbolic
NotSymbolic
symbolic_type
hasname
getname
symbolic_evaluate
```

# Types

```@docs
SymbolCache
ProblemState
```
