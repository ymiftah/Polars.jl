module API

include("./types.jl")
include("./dataframe.jl")
include("./expr.jl")
include("./series.jl")
include("./value.jl")

# exports
const PREFIXES = ["polars_", "Polars"]
for name in names(@__MODULE__; all = true), prefix in PREFIXES
    if startswith(string(name), prefix)
        @eval export $name
    end
end

end # module
