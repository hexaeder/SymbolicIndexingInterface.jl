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
[`parameter_timeseries`](@ref) is implemented for this type. This type does not implement
any traits.
"""
struct ParameterTimeseriesCollection{T}
    collection::T

    function ParameterTimeseriesCollection(collection::T) where {T}
        if any(x -> is_timeseries(x) == NotTimeseries(), collection)
            throw(ArgumentError("""
                All objects passed to `ParameterTimeseriesCollection` must be timeseries\
                objects.
            """))
        end
        new{T}(collection)
    end
end

Base.eachindex(ptc::ParameterTimeseriesCollection) = eachindex(ptc.collection)

Base.iterate(ptc::ParameterTimeseriesCollection, args...) = iterate(ptc.collection, args...)

Base.length(ptc::ParameterTimeseriesCollection) = length(ptc.collection)

Base.parent(ptc::ParameterTimeseriesCollection) = ptc.collection

Base.getindex(ptc::ParameterTimeseriesCollection, idx) = ptc.collection[idx]
function Base.getindex(ptc::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex)
    timeseries = ptc.collection[idx.timeseries_idx]
    return getu(timeseries, idx.parameter_idx)(timeseries)
end
function Base.getindex(
        ptc::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex, subidx)
    timeseries = ptc.collection[idx.timeseries_idx]
    return getu(timeseries, idx.parameter_idx)(timeseries, subidx)
end
function Base.getindex(ptc::ParameterTimeseriesCollection, ts_idx, subidx)
    return state_values(ptc.collection[ts_idx], subidx)
end
function Base.getindex(ptc::ParameterTimeseriesCollection, ts_idx, subidx, param_idx)
    return ptc[ParameterTimeseriesIndex(ts_idx, param_idx), subidx]
end

function parameter_values(
        ptc::ParameterTimeseriesCollection, idx::ParameterTimeseriesIndex, subidx)
    return ptc[idx, subidx]
end
function parameter_timeseries(ptc::ParameterTimeseriesCollection, idx)
    return current_time(ptc[idx])
end
