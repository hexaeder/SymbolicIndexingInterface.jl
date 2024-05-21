"""
    struct ParameterTimeseriesCollection{T}
    function ParameterTimeseriesCollection(collection)

A utility struct that helps in storing multiple parameter timeseries. It expects a
collection of timseries objects ([`is_timeseries`](@ref) returns [`Timeseries`](@ref))
for each. Each of the timeseries objects should implement [`state_values`](@ref) and
[`current_time`](@ref). Effectively, the "states" of each contained timeseries object are
the parameter values it stores the timeseries of.

The collection is expected to implement `Base.eachindex`, `Base.iterate` and
`Base.getindex`. The indexes of the collection should agree with the timeseries indexes
returned by calling [`timeseries_parameter_index`](@ref) on the corresponding index
provider.

This type forwards `eachindex`, `iterate` and `length` to the contained `collection`. It
implements `Base.parent` to allow access to the contained `collection`, and has the
following `getindex` methods:

- `getindex(ptc::ParameterTimeseriesCollection, idx) = ptc.collection[idx]`.
- `getindex(::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex)` returns the
  timeseries of the parameter referred to by `idx`.
- `getindex(::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex, subidx)`
  returns the value of the parameter referred to by `idx` at the time index `subidx`.
- Apart from these cases, if multiple indexes are provided the first is treated as a
  timeseries index, the second the time index in the timeseries, and the (optional)
  third the index of the parameter in an element of the timeseries.

The three-argument version of [`parameter_values`](@ref) is implemented for this type.
The single-argument version of `parameter_values` returns the cached parameter object.
[`parameter_timeseries`](@ref) is implemented for this type. This type does not implement
any traits.
"""
struct ParameterTimeseriesCollection{T, P}
    collection::T
    paramcache::P

    function ParameterTimeseriesCollection(collection::T, paramcache::P) where {T, P}
        if any(x -> is_timeseries(x) == NotTimeseries(), collection)
            throw(ArgumentError("""
                All objects in the collection `ParameterTimeseriesCollection` must be \
                timeseries objects.
            """))
        end
        new{T, P}(collection, paramcache)
    end
end

Base.eachindex(ptc::ParameterTimeseriesCollection) = eachindex(ptc.collection)

Base.iterate(ptc::ParameterTimeseriesCollection, args...) = iterate(ptc.collection, args...)

Base.length(ptc::ParameterTimeseriesCollection) = length(ptc.collection)

Base.parent(ptc::ParameterTimeseriesCollection) = ptc.collection

Base.getindex(ptc::ParameterTimeseriesCollection, idx) = ptc.collection[idx]
function Base.getindex(ptc::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex)
    timeseries = ptc.collection[idx.timeseries_idx]
    return getindex.(state_values(timeseries), (idx.parameter_idx,))
end
function Base.getindex(
        ptc::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex, subidx::Union{
            Int, CartesianIndex})
    timeseries = ptc.collection[idx.timeseries_idx]
    return state_values(timeseries, subidx)[idx.parameter_idx]
end
function Base.getindex(
        ptc::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex, ::Colon)
    return ptc[idx]
end
function Base.getindex(
        ptc::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex, subidx::AbstractArray{Bool})
    timeseries = ptc.collection[idx.timeseries_idx]
    map(only(to_indices(current_time(timeseries), (subidx,)))) do i
        state_values(timeseries, i)[idx.parameter_idx]
    end
end
function Base.getindex(
        ptc::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex, subidx)
    timeseries = ptc.collection[idx.timeseries_idx]
    getindex.(state_values.((timeseries,), subidx), idx.parameter_idx)
end
function Base.getindex(ptc::ParameterTimeseriesCollection, ts_idx, subidx)
    return state_values(ptc.collection[ts_idx], subidx)
end
function Base.getindex(ptc::ParameterTimeseriesCollection, ts_idx, subidx, param_idx)
    return ptc[ParameterTimeseriesIndex(ts_idx, param_idx), subidx]
end

function parameter_values(ptc::ParameterTimeseriesCollection)
    return ptc.paramcache
end

function parameter_values(
        ptc::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex, subidx)
    return ptc[idx, subidx]
end
function parameter_values(prob, i::ParameterTimeseriesIndex, j)
    parameter_values(get_parameter_timeseries_collection(prob), i, j)
end
function parameter_timeseries(ptc::ParameterTimeseriesCollection, idx)
    return current_time(ptc[idx])
end

function _timeseries_value(ptc::ParameterTimeseriesCollection, ts_idx, t)
    ts_obj = ptc[ts_idx]
    time_idx = searchsortedlast(current_time(ts_obj), t)
    value = state_values(ts_obj, time_idx)
    return value
end

"""
    parameter_values_at_time(valp, t)

Return an indexable collection containing the value of all parameters in `valp` at time
`t`. Note that `t` here is a floating-point time, and not an index into a timeseries.

This has a default implementation relying on [`get_parameter_timeseries_collection`](@ref)
and [`with_updated_parameter_timeseries_values`](@ref).
"""
function parameter_values_at_time(valp, t)
    ptc = get_parameter_timeseries_collection(valp)
    with_updated_parameter_timeseries_values(ptc.paramcache,
        (ts_idx => _timeseries_value(ptc, ts_idx, t) for ts_idx in eachindex(ptc))...)
end

"""
    parameter_values_at_state_time(valp, i)
    parameter_values_at_state_time(valp)

Return an indexable collection containing the value of all parameters in `valp` at time
index `i` in the state timeseries.

By default, this function relies on [`parameter_values_at_time`](@ref) and
[`current_time`](@ref) for a default implementation.

The single-argument version of this function is a shorthand to return parameter values
at each point in the state timeseries. This also has a default implementation relying on
[`parameter_values_at_time`](@ref) and [`current_time`](@ref).
"""
function parameter_values_at_state_time end

function parameter_values_at_state_time(p, i)
    state_time = current_time(p, i)
    return parameter_values_at_time(p, state_time)
end
function parameter_values_at_state_time(p)
    return (parameter_values_at_time(p, t) for t in current_time(p))
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

function parameter_timeseries(valp, i)
    return parameter_timeseries(get_parameter_timeseries_collection(valp), i)
end

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
