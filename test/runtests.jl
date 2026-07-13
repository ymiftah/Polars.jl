using Polars, Test, Dates, Tables

include("fixtures.jl")

@testset "Polars.jl" begin
    include("aqua.jl")

    include("dataframe/construction.jl")
    include("dataframe/gc.jl")
    include("dataframe/io.jl")

    include("lazyframe/lazy_vs_eager.jl")
    include("lazyframe/scan_parquet.jl")
    include("lazyframe/head.jl")
    include("lazyframe/collect_schema.jl")

    include("operations/select_with_columns.jl")
    include("operations/filter.jl")
    include("operations/sort.jl")
    include("operations/join.jl")
    include("operations/group_by.jl")
    include("operations/group_by_dynamic.jl")
    include("operations/empty.jl")

    include("expr/literals_cast.jl")
    include("expr/arithmetic.jl")
    include("expr/aggregation.jl")
    include("expr/naming.jl")

    include("datatypes/strings.jl")
    include("datatypes/lists.jl")
    include("datatypes/structs.jl")
    include("datatypes/series.jl")

    include("misc.jl")
end
