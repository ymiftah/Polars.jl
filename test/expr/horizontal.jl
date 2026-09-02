@testset "horizontal reductions" begin
    df = DataFrame((; a = [1, 2, missing], b = [4, missing, 6], c = [7, 8, 9]))

    r_all = select(df, alias(all_horizontal(col("a") .> 0, col("c") .> 0), "r"))
    @test isequal(r_all[:r], [true, true, missing])

    r_any = select(df, alias(any_horizontal(col("a") .> 1, col("c") .> 8), "r"))
    @test r_any[:r] == [false, true, true]

    r_min = select(df, alias(min_horizontal(col("a"), col("b"), col("c")), "r"))
    @test r_min[:r] == [1, 2, 6]

    r_max = select(df, alias(max_horizontal(col("a"), col("b"), col("c")), "r"))
    @test r_max[:r] == [7, 8, 9]

    r_sum_ignore = select(df, alias(sum_horizontal(col("a"), col("b"), col("c")), "r"))
    @test r_sum_ignore[:r] == [12, 10, 15]

    r_sum_strict = select(
        df, alias(sum_horizontal(col("a"), col("b"), col("c"); ignore_nulls = false), "r")
    )
    @test r_sum_strict[:r][1] == 12
    @test ismissing(r_sum_strict[:r][2])
    @test ismissing(r_sum_strict[:r][3])

    r_mean = select(df, alias(mean_horizontal(col("a"), col("b"), col("c")), "r"))
    @test r_mean[:r] ≈ [4.0, 5.0, 7.5]
end

@testset "concat_str" begin
    df = DataFrame((; a = ["x", "y", missing], b = [1, 2, 3], c = [1.5, missing, 3.5]))

    # default separator="" and ignore_nulls=false: a null in the row poisons the whole result
    r_default = select(df, alias(concat_str(col("a"), col("b")), "r"))
    @test isequal(collect(r_default[:r]), ["x1", "y2", missing])

    # a non-empty separator, and non-string dtypes cast to string first
    r_sep = select(df, alias(concat_str(col("a"), col("b"), col("c"); separator = "-"), "r"))
    @test r_sep[:r][1] == "x-1-1.5"
    @test ismissing(r_sep[:r][2]) # c is missing here
    @test ismissing(r_sep[:r][3]) # a is missing here

    # ignore_nulls=true: nulls are skipped rather than poisoning the row
    r_ignore = select(df, alias(concat_str(col("a"), col("b"), col("c"); ignore_nulls = true), "r"))
    @test r_ignore[:r][1] == "x11.5"
    @test r_ignore[:r][2] == "y2" # c is missing here, skipped rather than poisoning the row
    @test r_ignore[:r][3] == "33.5" # a is missing here, skipped rather than poisoning the row

    # a unicode separator exercises the `ncodeunits`-not-`length` string-marshalling convention
    r_unicode = select(df, alias(concat_str(col("a"), col("b"); separator = "→", ignore_nulls = true), "r"))
    @test r_unicode[:r][1] == "x→1"

    # LazyFrame form agrees
    r_lazy = collect(select(lazy(df), alias(concat_str(col("a"), col("b")), "r")))
    @test isequal(collect(r_lazy[:r]), collect(r_default[:r]))

    # single-expr and zero-expr calls are valid (upstream has no non-emptiness check on this one,
    # unlike concat_list below)
    r_single = select(df, alias(concat_str(col("b")), "r"))
    @test r_single[:r] == ["1", "2", "3"]
end

@testset "concat_list" begin
    df = DataFrame((; a = [1, 2, missing], b = [4, 5, 6]))

    r = select(df, alias(concat_list(col("a"), col("b")), "r"))
    @test isequal(collect(r[:r]), [[1, 4], [2, 5], [missing, 6]])

    # concatenating a List-typed expression with a scalar column flattens one level, not nested
    r_three = select(df, alias(concat_list(col("a"), col("b"), col("b") * 10), "r"))
    @test isequal(collect(r_three[:r]), [[1, 4, 40], [2, 5, 50], [missing, 6, 60]])

    # LazyFrame form agrees
    r_lazy = collect(select(lazy(df), alias(concat_list(col("a"), col("b")), "r")))
    @test isequal(collect(r_lazy[:r]), collect(r[:r]))

    # empty input errors cleanly rather than panicking (upstream's own `polars_ensure!`)
    @test_throws PolarsError concat_list()
end

@testset "as_struct" begin
    df = DataFrame((; a = [1, 2], b = ["x", "y"]))

    r = select(df, alias(as_struct(col("a"), col("b")), "s"))
    fa = select(r, Structs.field_by_name(col("s"), "a"))
    fb = select(r, Structs.field_by_name(col("s"), "b"))
    @test fa[:a] == [1, 2]
    @test fb[:b] == ["x", "y"]

    @test_throws PolarsError as_struct()
end

@testset "format (py-polars operations/test_format.py::test_format_expr, test_format_with_nulls_25347, test_format_group_by_23858, test_format_on_multiple_chunks_concat_25159)" begin
    df = DataFrame((; name = ["a", "b"], age = [1, 2]))

    r = select(df, alias(format("{} is {}", col("name"), col("age")), "f"))
    @test r[:f] == ["a is 1", "b is 2"]

    # a non-ASCII template exercises the `ncodeunits`-not-`length` string-marshalling convention
    r_unicode = select(df, alias(format("héllo {}", col("age")), "f"))
    @test r_unicode[:f] == ["héllo 1", "héllo 2"]

    # test_format_with_nulls_25347: a missing argument poisons the whole formatted row, not the
    # literal string "null"
    df2 = DataFrame((; a = [1, missing], b = ["x", "y"]))
    r_missing = select(df2, alias(format("{}-{}", col("a"), col("b")), "m"))
    @test isequal(collect(r_missing[:m]), ["1-x", missing])

    dfn = DataFrame((; a = [missing, "a"]))
    r_missing2 = select(dfn, alias(format("prefix: {}", col("a")), "a"))
    @test isequal(collect(r_missing2[:a]), [missing, "prefix: a"])

    dfn2 = DataFrame((; a = [missing, "y", "z"], b = ["a", "b", missing]))
    r_missing3 = select(dfn2, alias(format("prefix: {} {}", col("a"), col("b")), "a"))
    @test isequal(collect(r_missing3[:a]), [missing, "prefix: y b", missing])

    # a mismatched placeholder/argument count raises a PolarsError rather than aborting
    @test_throws PolarsError select(df, format("{} {}", col("age")))

    # test_format_expr: the full upstream fixture (`{0}`/`{name}` positional/named placeholders,
    # not just bare `{}`) -- ported live against the real `polars-plan::format_str`, the same
    # upstream Rust function this package's `format` calls directly (`c-polars/src/expr.rs`), so
    # `{0}`/`{name}` resolve exactly as upstream: `{0}` by argument index, a bare identifier as an
    # implicit column reference. Numeric literal args must be wrapped in `lit(...)` first -- a bare
    # `String`/`Symbol` argument means a column name here, not a string literal (see `format`'s own
    # docstring); this differs from upstream, where a raw Python int is accepted directly.
    dfx = DataFrame((; x = [1, 2], y = [3, 4]))
    a = [1, 2]
    b = Union{String, Missing}["a", "b", missing][1:2]
    dfab = DataFrame((; a = a, b = b))
    out = select(
        dfab,
        alias(format("{} abc", lit("xyz")), "y"),
        alias(format("{} abc", col("a")), "z"),
        alias(format("{} abc {}", col("a"), lit("xyz")), "w"),
        alias(format("{} abc {}", lit("xyz"), col("a")), "a2"),
        alias(format("abc {} {}", lit("xyz"), col("a")), "b2"),
        alias(format("abc {} {}", col("a"), col("b")), "d"),
        alias(format("{} abc {}", col("a"), col("b")), "e"),
        alias(format("{} {} abc", col("a"), col("b")), "f"),
        alias(format("{}{}", col("a"), col("b")), "g"),
        alias(format("{}", col("a")), "h"),
        alias(format("{}", col("b")), "i"),
    )
    @test out[:y] == ["xyz abc", "xyz abc"]
    @test out[:z] == ["1 abc", "2 abc"]
    @test out[:w] == ["1 abc xyz", "2 abc xyz"]
    @test out[:a2] == ["xyz abc 1", "xyz abc 2"]
    @test out[:b2] == ["abc xyz 1", "abc xyz 2"]
    @test isequal(collect(out[:d]), ["abc 1 a", "abc 2 b"])
    @test isequal(collect(out[:e]), ["1 abc a", "2 abc b"])
    @test isequal(collect(out[:f]), ["1 a abc", "2 b abc"])
    @test isequal(collect(out[:g]), ["1a", "2b"])
    @test out[:h] == ["1", "2"]
    @test isequal(collect(out[:i]), ["a", "b"])

    # test_format_arg_passing: `{0}` positional indexing, `{name}` implicit column reference,
    # automatic-vs-manual field numbering, out-of-bounds index, and shape mismatches -- upstream
    # distinguishes several exception types here (InvalidOperationError, ShapeError,
    # ColumnNotFoundError), all of which surface as PolarsError from this Rust FFI, per CLAUDE.md.
    @test_throws PolarsError select(dfx, format("{} {0}", lit(1)))
    @test_throws PolarsError select(dfx, format("{0} {}", lit(1)))
    @test_throws PolarsError select(dfx, format("test{", lit(1)))
    @test_throws PolarsError select(dfx, format("test}", lit(1)))
    @test_throws PolarsError select(dfx, format("{2}", lit(1)))
    @test_throws PolarsError select(dfx, format("{0a}", lit(1)))
    @test_throws PolarsError select(dfx, format("{} {}", lit(1)))
    @test_throws PolarsError select(dfx, format("{} {}", lit(1), lit(2), lit(3)))
    @test_throws PolarsError select(dfx, format("{x} {y}", lit(1)))
    @test_throws PolarsError select(dfx, format("{abc}"))

    @test select(dfx, alias(format("{0} {0} {0}", lit(1), lit(2)), "literal"))[:literal] == ["1 1 1"]
    @test select(dfx, alias(format("{0}", lit(1), lit(2)), "literal"))[:literal] == ["1"]
    @test select(dfx, format("{y} {1}", lit(1), lit(2)))[:y] == ["3 2", "4 2"]
    @test select(dfx, format("{1} {y}", lit(1), lit(2)))[:literal] == ["2 3", "2 4"]
    @test select(dfx, format("{x} {}", lit("test")))[:x] == ["1 test", "2 test"]
    @test select(dfx, format("{y} {y}"))[:y] == ["3 3", "4 4"]

    # test_format_group_by_23858: agrees inside an aggregation context
    r_gb = collect(
        agg(
            group_by(lazy(DataFrame((; x = [0], y = [0]))), "x"),
            [alias(format("'{}'", col("y")), "quoted_ys")],
        )
    )
    @test size(r_gb) == (1, 2)

    # test_format_on_multiple_chunks_concat_25159: agrees across a `concat`-produced multi-chunk
    # frame
    df1 = DataFrame((; a = ["123"]))
    df2 = DataFrame((; a = ["456"]))
    dfc = concat([df1, df2])
    @test select(dfc, format("{}", col("a")))[:a] == dfc[:a]

    # LazyFrame form agrees
    r_lazy = collect(select(lazy(df), alias(format("{} is {}", col("name"), col("age")), "f")))
    @test collect(r_lazy[:f]) == r[:f]
end

@testset "concat_arr: builds an Array-dtype plan; materializing/introspecting it is not yet supported (py-polars functions/as_datatype/test_concat_arr.py)" begin
    df = DataFrame((; age = [1, 2]))
    lf = select(lazy(df), alias(concat_arr(col("age"), col("age")), "arr"))

    # building the plan and running `explain` on it both succeed
    @test occursin("arr.concat", explain(lf))

    # collect() itself succeeds -- the failure is in resolving the Array dtype afterward
    d = collect(lf)

    # neither collect_schema nor indexing into the Array column can materialize/introspect it yet
    # (src/arrow/schema.jl:136, per CLAUDE.md's Array-dtype caveat) -- so upstream's own
    # `test_concat_arr`/`test_concat_arr_broadcast`/`test_concat_arr_logical_types_20917` value
    # assertions cannot be ported: there is no way from this package's public API to read the
    # resulting Array-typed values back out. Only plan-construction/collect-success is checked.
    @test_throws ErrorException collect_schema(lf)
    @test_throws ErrorException d[:arr]

    @test_throws PolarsError concat_arr()

    # test_concat_arr_broadcast: a scalar (literal) argument broadcasts against the column arg
    lf_bcast1 = select(lazy(df), alias(concat_arr(col("age"), cast(lit(missing), Int64)), "arr"))
    @test occursin("arr.concat", explain(lf_bcast1))
    @test size(collect(lf_bcast1)) == (2, 1)

    lf_bcast2 = select(lazy(df), alias(concat_arr(col("age"), lit(9)), "arr"))
    @test size(collect(lf_bcast2)) == (2, 1)

    # dtype mismatch between concat_arr's inputs raises a PolarsError (upstream: a dtype/shape
    # error inside `concat_arr` itself) rather than aborting
    dfmix = DataFrame((; a = [1, 3, 5]))
    @test_throws PolarsError collect(
        select(lazy(dfmix), alias(concat_arr(col("a"), cast(lit(missing), Float64)), "arr"))
    )

    # null propagation: a missing element in one input column still builds/collects
    dfnull = DataFrame((; a = [1, 3, 5], b = Union{Int, Missing}[2, missing, 6]))
    lf_null = select(lazy(dfnull), alias(concat_arr(col("a"), col("b")), "arr"))
    @test occursin("arr.concat", explain(lf_null))
    @test size(collect(lf_null)) == (3, 1)

    # empty input (0 rows) still builds/collects
    df0 = DataFrame((; a = Int[], b = Int[]))
    lf0 = select(lazy(df0), alias(concat_arr(col("a"), col("b")), "arr"))
    @test size(collect(lf0)) == (0, 1)
end
