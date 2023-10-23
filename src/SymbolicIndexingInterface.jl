module SymbolicIndexingInterface

export Symbolic, NotSymbolic, issymbolic
include("trait.jl")

export is_variable, has_static_variable, variable_index, is_parameter, parameter_index,
    is_independent_variable, is_observed, observed, is_time_dependent, constant_structure
include("interface.jl")

@static if !isdefined(Base, :get_extension)
    using Requires
    function __init__()
        @require Symbolics="0c5d862f-8b57-4792-8d23-62f2024744c7" include("../ext/SymbolicIndexingInterfaceSymbolicsExt.jl")
        @require SymbolicUtils="d1185830-fcd6-423d-90d6-eec64667417b" include("../ext/SymbolicIndexingInterfaceSymbolicUtilsExt.jl")
    end
end

end
