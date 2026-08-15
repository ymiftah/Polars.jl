import Polars as Pl
using Test

@testset "scan_parquet cast_policy" begin
    @testset "default cast_policy=nothing behaves as before" begin
        path = mktempdir()
        Pl.write_parquet("$path/a.parquet", Pl.DataFrame((; x = Int32[1, 2, 3])))

        result = Pl.collect(Pl.scan_parquet("$path/a.parquet"))
        @test size(result) == (3, 1)
    end

    @testset "cast_policy accepts a CastPolicy struct" begin
        path = mktempdir()
        Pl.write_parquet("$path/a.parquet", Pl.DataFrame((; x = Int32[1, 2, 3])))

        policy = Pl.CastPolicy(integer_upcast = true)
        result = Pl.collect(Pl.scan_parquet("$path/a.parquet"; cast_policy = policy))
        @test size(result) == (3, 1)
    end

    @testset "cast_policy accepts a Dict" begin
        path = mktempdir()
        Pl.write_parquet("$path/a.parquet", Pl.DataFrame((; x = Int32[1, 2, 3])))

        result = Pl.collect(
            Pl.scan_parquet("$path/a.parquet"; cast_policy = Dict(:float_upcast => true))
        )
        @test size(result) == (3, 1)
    end

    @testset "read_parquet forwards cast_policy" begin
        path = mktempdir()
        Pl.write_parquet("$path/a.parquet", Pl.DataFrame((; x = Int32[1, 2, 3])))

        result = Pl.read_parquet("$path/a.parquet"; cast_policy = Pl.CastPolicy(integer_upcast = true))
        @test size(result) == (3, 1)
    end

    @testset "CastPolicy defaults match upstream ERROR_ON_MISMATCH" begin
        p = Pl.CastPolicy()
        @test p.integer_upcast == false
        @test p.null_upcast == true
        @test p.missing_struct_fields_raise == true
        @test p.extra_struct_fields_raise == true
    end

    @testset "_dict_to_cast_policy rejects unknown keys" begin
        @test_throws MethodError Pl._dict_to_cast_policy(Dict(:not_a_real_field => true))
    end
end
