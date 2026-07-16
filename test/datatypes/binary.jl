# Vector{UInt8} (Binary) columns have real read-side support (`load_value(::Value{Vector{UInt8}})`
# in src/value.jl, and Vector{UInt8} is a first-class MaybeMissing element type in src/series.jl),
# but constructing a Series/DataFrame *from* Julia Vector{UInt8} data goes through the write-side
# arrow conversion path (src/arrow/array.jl's `arrowvector`), which has no method for
# Vector{UInt8}/Vector{Vector{UInt8}} -- every construction attempt below fails with a generic
# "something went wrong when creating dataframe" error (non-nullable and nullable) or an
# "unknow schema format vz" error (empty). This is a genuine gap, not a test bug -- see
# plans/test_porting.md. Tracked here as @test_broken so the suite stays green, and so this
# loudly starts failing (telling us to fill in real assertions) the day the gap is closed.

@testset "Binary (Vector{UInt8}) type" begin
    bytes_data = Vector{UInt8}[UInt8[1, 2, 3], UInt8[4, 5], UInt8[]]
    @test_broken (Series(:bytes, bytes_data); true)
end

@testset "Binary data with nulls" begin
    bytes_data = Union{Vector{UInt8}, Missing}[
        UInt8[1, 2, 3],
        missing,
        UInt8[255, 254],
    ]
    @test_broken (Series(:binary_col, bytes_data); true)
end

@testset "Binary DataFrame round-trip through parquet" begin
    @test_broken (
        DataFrame((;
            id = [1, 2, 3],
            data = Union{Vector{UInt8}, Missing}[
                UInt8[0x48, 0x65, 0x6c, 0x6c, 0x6f],
                missing,
                UInt8[0x57, 0x6f, 0x72, 0x6c, 0x64],
            ],
        ));
        true
    )
end

@testset "Empty binary Series" begin
    @test_broken (Series(:empty_binary, Vector{UInt8}[]); true)
end
