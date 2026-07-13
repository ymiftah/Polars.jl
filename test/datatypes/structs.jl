@testset "Structs namespace" begin
    # There is no write-side arrow support for constructing a Struct column directly from a
    # Vector{<:NamedTuple} via DataFrame(table) (same gap as Lists -- see datatypes/lists.jl),
    # and this wrapper exposes no expr-level struct constructor (e.g. py-polars' pl.struct(...))
    # either -- so there is currently no way to obtain a genuine struct-typed column from pure
    # Julia. Verified correctness ad hoc instead: wrote a parquet file with a struct column via
    # `uv run --with polars python3` and read it back with read_parquet/Structs.field_by_name/
    # field_by_index/rename_fields, which all behaved correctly. That external dependency isn't
    # suitable for the committed suite (Pkg.test() shouldn't require Python/uv), so this is
    # recorded as a skip rather than asserted here.
    @test_skip false # Structs.field_by_name/field_by_index/rename_fields: untestable without an external struct-column source
end
