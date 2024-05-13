"""
    getp(indp, sym)

Return a function that takes an value provider, and returns the value of the
parameter `sym`. The value provider has to at least store the values of parameters
in the corresponding index provider. Note that `sym` can be an index, symbolic variable,
or an array/tuple of the aforementioned.

If `sym` is an array/tuple of parameters, then the returned function can also be used
as an in-place getter function. The first argument is the buffer (must be an
`AbstractArray`) to which the parameter values should be written, and the second argument
is the value provider.

Requires that the value provider implement [`parameter_values`](@ref). This function
may not always need to be implemented, and has a default implementation for collections
that implement `getindex`.

If the returned function is used on a timeseries object which saves parameter timeseries,
it can be used to index said timeseries. The timeseries object must implement
[`parameter_timeseries`](@ref), [`parameter_values_at_state_time`](@ref),
[`parameter_timeseries_at_state_time`](@ref) and [`is_parameter_timeseries`](@ref).

If `sym` is a timeseries parameter, the function will return the timeseries of the
parameter if the value provider is a parameter timeseries object. An additional argument
can be provided to the function indicating the specific indexes in the timeseries at
which to access the values. If `sym` is an array of parameters, the following cases
apply:

- All parameters are non-timeseries parameters: The function returns the value of each
  parameter.
- All parameters are timeseries parameters: All the parameters must belong to the same
  timeseries (otherwise `getp` will error). The function returns the timeseries of all
  parameter values, and can be accessed at specific indices in the timeseries.
- A mix of timeseries and non-timeseries parameters: The function can _only_ be used on
  non-timeseries objects and will return the value of each parameter at in the object.
"""
function getp(sys, p)
    symtype = symbolic_type(p)
    elsymtype = symbolic_type(eltype(p))
    _getp(sys, symtype, elsymtype, p)
end

struct GetParameterIndex{I} <: AbstractParameterGetIndexer
    idx::I
end

is_indexer_timeseries(::Type{GetParameterIndex{I}}) where {I} = IndexerNotTimeseries()
function is_indexer_timeseries(::Type{GetParameterIndex{I}}) where {I <:
                                                                    ParameterTimeseriesIndex}
    IndexerTimeseries()
end
function indexer_timeseries_index(gpi::GetParameterIndex{<:ParameterTimeseriesIndex})
    gpi.idx.timeseries_idx
end
function (gpi::GetParameterIndex)(::IsTimeseriesTrait, prob)
    parameter_values(prob, gpi.idx)
end
function (gpi::GetParameterIndex)(::Timeseries, prob, args)
    throw(ParameterTimeseriesValueIndexMismatchError{Timeseries}(prob, gpi, args))
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(ts::Timeseries, prob)
    gpi.((ts,), (prob,),
        eachindex(parameter_timeseries(prob, indexer_timeseries_index(gpi))))
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(
        buffer::AbstractArray, ts::Timeseries, prob)
    for (buf_idx, ts_idx) in zip(eachindex(buffer),
        eachindex(parameter_timeseries(prob, indexer_timeseries_index(gpi))))
        buffer[buf_idx] = gpi(ts, prob, ts_idx)
    end
    return buffer
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(
        ::Timeseries, prob, i::Union{Int, CartesianIndex})
    parameter_values(prob, gpi.idx, i)
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(ts::Timeseries, prob, ::Colon)
    gpi(ts, prob)
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(
        buffer::AbstractArray, ts::Timeseries, prob, ::Colon)
    gpi(buffer, ts, prob)
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(
        ts::Timeseries, prob, i::AbstractArray{Bool})
    map(only(to_indices(
        parameter_timeseries(prob, indexer_timeseries_index(gpi)), (i,)))) do idx
        gpi(ts, prob, idx)
    end
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(
        buffer::AbstractArray, ts::Timeseries, prob, i::AbstractArray{Bool})
    for (buf_idx, ts_idx) in zip(eachindex(buffer),
        only(to_indices(parameter_timeseries(prob, indexer_timeseries_index(gpi)), (i,))))
        buffer[buf_idx] = gpi(ts, prob, ts_idx)
    end
    return buffer
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(ts::Timeseries, prob, i)
    gpi.((ts,), (prob,), i)
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(
        buffer::AbstractArray, ts::Timeseries, prob, i)
    for (buf_idx, subidx) in zip(eachindex(buffer), i)
        buffer[buf_idx] = gpi(ts, prob, subidx)
    end
    return buffer
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(::NotTimeseries, prob)
    throw(ParameterTimeseriesValueIndexMismatchError{NotTimeseries}(prob, gpi))
end
function (gpi::GetParameterIndex{<:ParameterTimeseriesIndex})(
        ::AbstractArray, ::NotTimeseries, prob)
    throw(ParameterTimeseriesValueIndexMismatchError{NotTimeseries}(prob, gpi))
end

function _getp(sys, ::NotSymbolic, ::NotSymbolic, p)
    return GetParameterIndex(p)
end

struct GetParameterTimeseriesIndex{
    I <: GetParameterIndex, J <: GetParameterIndex{<:ParameterTimeseriesIndex}} <:
       AbstractParameterGetIndexer
    param_idx::I
    param_timeseries_idx::J
end

is_indexer_timeseries(::Type{G}) where {G <: GetParameterTimeseriesIndex} = IndexerBoth()
function indexer_timeseries_index(gpti::GetParameterTimeseriesIndex)
    indexer_timeseries_index(gpti.param_timeseries_idx)
end
as_not_timeseries_indexer(::IndexerBoth, gpti::GetParameterTimeseriesIndex) = gpti.param_idx
function as_timeseries_indexer(::IndexerBoth, gpti::GetParameterTimeseriesIndex)
    gpti.param_timeseries_idx
end

function (gpti::GetParameterTimeseriesIndex)(ts::Timeseries, prob, args...)
    gpti.param_timeseries_idx(ts, prob, args...)
end
function (gpti::GetParameterTimeseriesIndex)(
        buffer::AbstractArray, ts::Timeseries, prob, args...)
    gpti.param_timeseries_idx(buffer, ts, prob, args...)
end
function (gpti::GetParameterTimeseriesIndex)(ts::NotTimeseries, prob)
    gpti.param_idx(ts, prob)
end

function _getp(sys, ::ScalarSymbolic, ::SymbolicTypeTrait, p)
    idx = parameter_index(sys, p)
    if is_timeseries_parameter(sys, p)
        ts_idx = timeseries_parameter_index(sys, p)
        return GetParameterTimeseriesIndex(
            GetParameterIndex(idx), GetParameterIndex(ts_idx))
    else
        return GetParameterIndex(idx)
    end
end

struct MixedTimeseriesIndexes
    indexes::Any
end

struct MultipleParametersGetter{T <: IsIndexerTimeseries, G, I} <:
       AbstractParameterGetIndexer
    getters::G
    timeseries_idx::I

    function MultipleParametersGetter(getters)
        has_timeseries_indexers = any(getters) do g
            is_indexer_timeseries(g) == IndexerTimeseries()
        end
        has_non_timeseries_indexers = any(getters) do g
            is_indexer_timeseries(g) == IndexerNotTimeseries()
        end
        if has_timeseries_indexers && has_non_timeseries_indexers
            throw(ArgumentError("Cannot mix timeseries and non-timeseries indexers in `$MultipleParametersGetter`"))
        end
        indexer_type = if has_timeseries_indexers
            getters = as_timeseries_indexer.(getters)
            timeseries_idx = indexer_timeseries_index(first(getters))
            IndexerTimeseries
        elseif has_non_timeseries_indexers
            getters = as_not_timeseries_indexer.(getters)
            timeseries_idx = nothing
            IndexerNotTimeseries
        else
            timeseries_idx = indexer_timeseries_index(first(getters))
            IndexerBoth
        end

        if indexer_type != IndexerNotTimeseries &&
           !allequal(indexer_timeseries_index(g) for g in getters)
            if indexer_type == IndexerTimeseries
                throw(ArgumentError("All parameters must belong to the same timeseries"))
            else
                indexer_type = IndexerNotTimeseries
                timeseries_idx = MixedTimeseriesIndexes(indexer_timeseries_index.(getters))
                getters = as_not_timeseries_indexer.(getters)
            end
        end

        return new{indexer_type, typeof(getters), typeof(timeseries_idx)}(
            getters, timeseries_idx)
    end
end

const AtLeastTimeseriesMPG = Union{
    MultipleParametersGetter{IndexerTimeseries}, MultipleParametersGetter{IndexerBoth}}
const MixedTimeseriesIndexMPG = MultipleParametersGetter{
    IndexerNotTimeseries, G, MixedTimeseriesIndexes} where {G}

is_indexer_timeseries(::Type{<:MultipleParametersGetter{T}}) where {T} = T()
function indexer_timeseries_index(mpg::MultipleParametersGetter)
    mpg.timeseries_idx
end
function as_not_timeseries_indexer(::IndexerBoth, mpg::MultipleParametersGetter)
    MultipleParametersGetter(as_not_timeseries_indexer.(mpg.getters))
end

function as_timeseries_indexer(::IndexerBoth, mpg::MultipleParametersGetter)
    MultipleParametersGetter(as_timeseries_indexer.(mpg.getters))
end

for (indexerTimeseriesType, timeseriesType) in [
    (IndexerNotTimeseries, IsTimeseriesTrait),
    (IndexerBoth, NotTimeseries)
]
    @eval function (mpg::MultipleParametersGetter{$indexerTimeseriesType})(
            ::$timeseriesType, prob)
        CallWith(prob).(mpg.getters)
    end
    @eval function (mpg::MultipleParametersGetter{$indexerTimeseriesType})(
            buffer::AbstractArray, ::$timeseriesType, prob)
        for (buf_idx, getter) in zip(eachindex(buffer), mpg.getters)
            buffer[buf_idx] = getter(prob)
        end
        return buffer
    end
end

function (mpg::MixedTimeseriesIndexMPG)(::Timeseries, prob, args...)
    throw(MixedParameterTimeseriesIndexError(prob, mpg.timeseries_idx.indexes))
end

function (mpg::MultipleParametersGetter{IndexerNotTimeseries})(::Timeseries, prob, args)
    throw(ParameterTimeseriesValueIndexMismatchError{Timeseries}(prob, mpg, args))
end
function (mpg::MultipleParametersGetter{IndexerNotTimeseries})(
        ::AbstractArray, ::Timeseries, prob, args)
    throw(ParameterTimeseriesValueIndexMismatchError{Timeseries}(prob, mpg, args))
end
function (mpg::AtLeastTimeseriesMPG)(ts::Timeseries, prob)
    map(eachindex(parameter_timeseries(prob, indexer_timeseries_index(mpg)))) do i
        mpg(ts, prob, i)
    end
end
function (mpg::AtLeastTimeseriesMPG)(::Timeseries, prob, i::Union{Int, CartesianIndex})
    CallWith(prob, i).(mpg.getters)
end
function (mpg::AtLeastTimeseriesMPG)(ts::Timeseries, prob, ::Colon)
    mpg(ts, prob)
end
function (mpg::AtLeastTimeseriesMPG)(ts::Timeseries, prob, i::AbstractArray{Bool})
    map(only(to_indices(
        parameter_timeseries(prob, indexer_timeseries_index(mpg)), (i,)))) do idx
        mpg(ts, prob, idx)
    end
end
function (mpg::AtLeastTimeseriesMPG)(ts::Timeseries, prob, i)
    mpg.((ts,), (prob,), i)
end
function (mpg::AtLeastTimeseriesMPG)(buffer::AbstractArray, ts::Timeseries, prob)
    for (buf_idx, ts_idx) in zip(eachindex(buffer),
        eachindex(parameter_timeseries(prob, indexer_timeseries_index(mpg))))
        mpg(buffer[buf_idx], ts, prob, ts_idx)
    end
    return buffer
end
function (mpg::AtLeastTimeseriesMPG)(
        buffer::AbstractArray, ::Timeseries, prob, i::Union{Int, CartesianIndex})
    for (buf_idx, getter) in zip(eachindex(buffer), mpg.getters)
        buffer[buf_idx] = getter(prob, i)
    end
    return buffer
end
function (mpg::AtLeastTimeseriesMPG)(buffer::AbstractArray, ts::Timeseries, prob, ::Colon)
    mpg(buffer, ts, prob)
end
function (mpg::AtLeastTimeseriesMPG)(
        buffer::AbstractArray, ts::Timeseries, prob, i::AbstractArray{Bool})
    mpg(buffer, ts, prob,
        only(to_indices(parameter_timeseries(prob, indexer_timeseries_index(mpg)), (i,))))
end
function (mpg::AtLeastTimeseriesMPG)(buffer::AbstractArray, ts::Timeseries, prob, i)
    for (buf_idx, ts_idx) in zip(eachindex(buffer), i)
        mpg(buffer[buf_idx], ts, prob, ts_idx)
    end
    return buffer
end
function (mpg::MultipleParametersGetter{IndexerTimeseries})(::NotTimeseries, prob)
    throw(ParameterTimeseriesValueIndexMismatchError{NotTimeseries}(prob, mpg))
end
function (mpg::MultipleParametersGetter{IndexerTimeseries})(
        ::AbstractArray, ::NotTimeseries, prob)
    throw(ParameterTimeseriesValueIndexMismatchError{NotTimeseries}(prob, mpg))
end

for (t1, t2) in [
    (ArraySymbolic, Any),
    (ScalarSymbolic, Any),
    (NotSymbolic, Union{<:Tuple, <:AbstractArray})
]
    @eval function _getp(sys, ::NotSymbolic, ::$t1, p::$t2)
        return MultipleParametersGetter(getp.((sys,), p))
    end
end

function _getp(sys, ::ArraySymbolic, ::SymbolicTypeTrait, p)
    if is_parameter(sys, p)
        idx = parameter_index(sys, p)
        if is_timeseries_parameter(sys, p)
            ts_idx = timeseries_parameter_index(sys, p)
            return GetParameterTimeseriesIndex(idx, ts_idx)
        else
            return GetParameterIndex(idx)
        end
    end
    return getp(sys, collect(p))
end

struct ParameterHookWrapper{S, O} <: AbstractSetIndexer
    setter::S
    original_index::O
end

function (phw::ParameterHookWrapper)(prob, args...)
    res = phw.setter(prob, args...)
    finalize_parameters_hook!(prob, phw.original_index)
    return res
end

"""
    setp(indp, sym)

Return a function that takes an index provider and a value, and sets the parameter `sym`
to that value. Note that `sym` can be an index, a symbolic variable, or an array/tuple of
the aforementioned.

Requires that the value provider implement [`parameter_values`](@ref) and the returned
collection be a mutable reference to the parameter object. In case `parameter_values`
cannot return such a mutable reference, or additional actions need to be performed when
updating parameters, [`set_parameter!`](@ref) must be implemented.
"""
function setp(sys, p; run_hook = true)
    symtype = symbolic_type(p)
    elsymtype = symbolic_type(eltype(p))
    return if run_hook
        return ParameterHookWrapper(_setp(sys, symtype, elsymtype, p), p)
    else
        _setp(sys, symtype, elsymtype, p)
    end
end

struct SetParameterIndex{I} <: AbstractSetIndexer
    idx::I
end

function (spi::SetParameterIndex)(prob, val)
    set_parameter!(prob, val, spi.idx)
end

function _setp(sys, ::NotSymbolic, ::NotSymbolic, p)
    return SetParameterIndex(p)
end

function _setp(sys, ::ScalarSymbolic, ::SymbolicTypeTrait, p)
    idx = parameter_index(sys, p)
    return SetParameterIndex(idx)
end

struct MultipleSetters{S} <: AbstractSetIndexer
    setters::S
end

function (ms::MultipleSetters)(prob, val)
    map((s!, v) -> s!(prob, v), ms.setters, val)
end

for (t1, t2) in [
    (ArraySymbolic, Any),
    (ScalarSymbolic, Any),
    (NotSymbolic, Union{<:Tuple, <:AbstractArray})
]
    @eval function _setp(sys, ::NotSymbolic, ::$t1, p::$t2)
        setters = setp.((sys,), p; run_hook = false)
        return MultipleSetters(setters)
    end
end

function _setp(sys, ::ArraySymbolic, ::SymbolicTypeTrait, p)
    if is_parameter(sys, p)
        idx = parameter_index(sys, p)
        return setp(sys, idx; run_hook = false)
    end
    return setp(sys, collect(p); run_hook = false)
end
