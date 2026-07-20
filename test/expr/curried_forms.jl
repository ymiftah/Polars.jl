# Curried (Fix2-style) forms enabling `|>` composition, e.g. `col("x") |> top_k(3)`, mirroring
# Python polars' fluent `.method(...)` style. Each testset checks the curried form agrees with
# the non-curried form on the same fixture.

@testset "curried top-level: is_in / fill_null / fill_nan / shift / pct_change" begin
    df = DataFrame((; x = [1, missing, 4], y = [1.0, NaN, 3.0], z = [1, 2, 3, 4]))

    r_direct = select(df, alias(is_in(col("x"), implode(lit([1, 4]))), "in"))
    r_curried = select(df, alias(col("x") |> is_in([1, 4]), "in"))
    @test isequal(r_direct[:in], r_curried[:in])

    r_direct2 = select(df, alias(fill_null(col("x"), lit(0)), "fn"))
    r_curried2 = select(df, alias(col("x") |> fill_null(0), "fn"))
    @test r_direct2[:fn] == r_curried2[:fn]

    r_direct3 = select(df, alias(fill_nan(col("y"), lit(0.0)), "fn"))
    r_curried3 = select(df, alias(col("y") |> fill_nan(0.0), "fn"))
    @test r_direct3[:fn] == r_curried3[:fn]

    dfz = DataFrame((; z = [1, 2, 3, 4]))
    r_direct4 = select(dfz, alias(shift(col("z"), lit(1)), "sh"))
    r_curried4 = select(dfz, alias(col("z") |> shift(1), "sh"))
    @test isequal(r_direct4[:sh], r_curried4[:sh])

    r_direct5 = select(dfz, alias(pct_change(col("z"), lit(1)), "pc"))
    r_curried5 = select(dfz, alias(col("z") |> pct_change(1), "pc"))
    @test isequal(r_direct5[:pc], r_curried5[:pc])
end

@testset "curried top-level: clip / replace_strict / top_k / sample_n / sample_frac" begin
    df = DataFrame((; x = [1, 2, 3, 4]))

    r_direct = select(df, alias(clip(col("x"), 2, 3), "c"))
    r_curried = select(df, alias(col("x") |> clip(2, 3), "c"))
    @test r_direct[:c] == r_curried[:c] == [2, 2, 3, 3]

    r_direct2 = select(df, alias(replace_strict(col("x"), [1, 2], [10, 20]; default = -1), "rs"))
    r_curried2 = select(df, alias(col("x") |> replace_strict([1, 2], [10, 20]; default = -1), "rs"))
    @test r_direct2[:rs] == r_curried2[:rs] == [10, 20, -1, -1]

    # `quantile` has no curried (`|>`) form now that it extends `Statistics.quantile` (see
    # expr/expr.jl) -- a bare `x -> quantile(x, 0.5)` lambda is the documented replacement for
    # `|>`-composition.
    r_direct3 = select(df, alias(quantile(col("x"), 0.5), "q"))
    r_lambda3 = select(df, alias(col("x") |> (x -> quantile(x, 0.5)), "q"))
    @test r_direct3[:q] == r_lambda3[:q]

    r_direct4 = select(df, alias(top_k(col("x"), 2), "tk"))
    r_curried4 = select(df, alias(col("x") |> top_k(2), "tk"))
    @test sort(r_direct4[:tk]) == sort(r_curried4[:tk]) == [3, 4]

    r_direct5 = select(df, alias(sample_n(col("x"), 2; seed = 1), "sn"))
    r_curried5 = select(df, alias(col("x") |> sample_n(2; seed = 1), "sn"))
    @test r_direct5[:sn] == r_curried5[:sn]

    r_direct6 = select(df, alias(sample_frac(col("x"), 0.5; seed = 1), "sf"))
    r_curried6 = select(df, alias(col("x") |> sample_frac(0.5; seed = 1), "sf"))
    @test r_direct6[:sf] == r_curried6[:sf]
end

@testset "curried Lists: get / contains / head" begin
    df = DataFrame((; l = [[1, 2, 3], [4, 5]]))

    r_direct = select(df, alias(Lists.get(col("l"), lit(0)), "g"))
    r_curried = select(df, alias(col("l") |> Lists.get(0), "g"))
    @test r_direct[:g] == r_curried[:g] == [1, 4]

    r_direct2 = select(df, alias(Lists.contains(col("l"), lit(2)), "c"))
    r_curried2 = select(df, alias(col("l") |> Lists.contains(2), "c"))
    @test r_direct2[:c] == r_curried2[:c] == [true, false]

    r_direct3 = select(df, alias(Lists.head(col("l"), lit(1)), "h"))
    r_curried3 = select(df, alias(col("l") |> Lists.head(1), "h"))
    @test collect(r_direct3[:h][1]) == collect(r_curried3[:h][1]) == [1]
end

@testset "curried Strings: binary namespace ops" begin
    df = DataFrame((; s = ["hello world", "foo bar", "baz"]))

    @test select(df, alias(col("s") |> Strings.starts_with("foo"), "r"))[:r] ==
        select(df, alias(Strings.starts_with(col("s"), lit("foo")), "r"))[:r] ==
        [false, true, false]

    @test select(df, alias(col("s") |> Strings.ends_with("bar"), "r"))[:r] ==
        select(df, alias(Strings.ends_with(col("s"), lit("bar")), "r"))[:r] ==
        [false, true, false]

    @test select(df, alias(col("s") |> Strings.contains_literal("foo"), "r"))[:r] ==
        select(df, alias(Strings.contains_literal(col("s"), lit("foo")), "r"))[:r] ==
        [false, true, false]

    @test select(df, alias(col("s") |> Strings.strip_prefix("hello "), "r"))[:r] ==
        select(df, alias(Strings.strip_prefix(col("s"), lit("hello ")), "r"))[:r]

    @test select(df, alias(col("s") |> Strings.strip_suffix("bar"), "r"))[:r] ==
        select(df, alias(Strings.strip_suffix(col("s"), lit("bar")), "r"))[:r]

    @test select(df, alias(col("s") |> Strings.strip_chars("bz"), "r"))[:r] ==
        select(df, alias(Strings.strip_chars(col("s"), lit("bz")), "r"))[:r]

    r1 = select(df, alias(col("s") |> Strings.split(" "), "r"))
    r2 = select(df, alias(Strings.split(col("s"), lit(" ")), "r"))
    @test collect(r1[:r][1]) == collect(r2[:r][1]) == ["hello", "world"]

    @test select(df, alias(col("s") |> Strings.extract_all("\\w+"), "r"))[:r][1] isa Vector

    df_pad = DataFrame((; n = ["1", "22", "333"]))
    @test select(df_pad, alias(col("n") |> Strings.zfill(5), "r"))[:r] ==
        select(df_pad, alias(Strings.zfill(col("n"), lit(5)), "r"))[:r] ==
        ["00001", "00022", "00333"]

    @test select(df, alias(col("s") |> Strings.head(3), "r"))[:r] ==
        select(df, alias(Strings.head(col("s"), lit(3)), "r"))[:r] ==
        ["hel", "foo", "baz"]

    @test select(df, alias(col("s") |> Strings.tail(3), "r"))[:r] ==
        select(df, alias(Strings.tail(col("s"), lit(3)), "r"))[:r] ==
        ["rld", "bar", "baz"]
end

@testset "curried Strings: hand-written ops (contains, slice, replace, replace_all, extract, count_matches)" begin
    df = DataFrame((; s = ["hello world", "foo bar", "baz"]))

    r_direct = select(df, alias(Strings.contains(col("s"), lit("^h")), "r"))
    r_curried = select(df, alias(col("s") |> Strings.contains("^h"), "r"))
    @test r_direct[:r] == r_curried[:r] == [true, false, false]

    r_direct2 = select(df, alias(Strings.slice(col("s"), lit(0), lit(3)), "r"))
    r_curried2 = select(df, alias(col("s") |> Strings.slice(0, 3), "r"))
    @test r_direct2[:r] == r_curried2[:r] == ["hel", "foo", "baz"]

    r_direct3 = select(df, alias(Strings.replace(col("s"), lit("o"), lit("0")), "r"))
    r_curried3 = select(df, alias(col("s") |> Strings.replace("o", "0"), "r"))
    @test r_direct3[:r] == r_curried3[:r]

    r_direct4 = select(df, alias(Strings.replace_all(col("s"), lit("a"), lit("A")), "r"))
    r_curried4 = select(df, alias(col("s") |> Strings.replace_all("a", "A"), "r"))
    @test r_direct4[:r] == r_curried4[:r]

    r_direct5 = select(df, alias(Strings.extract(col("s"), lit("(\\w+)"), 1), "r"))
    r_curried5 = select(df, alias(col("s") |> Strings.extract("(\\w+)", 1), "r"))
    @test r_direct5[:r] == r_curried5[:r] == ["hello", "foo", "baz"]

    r_direct6 = select(df, alias(Strings.count_matches(col("s"), lit("o")), "r"))
    r_curried6 = select(df, alias(col("s") |> Strings.count_matches("o"), "r"))
    @test r_direct6[:r] == r_curried6[:r] == [2, 2, 0]
end

@testset "curried top-level: arg_sort / rank / value_counts / interpolate / cum_*" begin
    df = DataFrame((; g = ["a", "a", "b"], x = [3, 1, 2]))

    r_direct = select(df, alias(arg_sort(col("x"); descending = true), "as"))
    r_curried = select(df, alias(col("x") |> arg_sort(descending = true), "as"))
    @test r_direct[:as] == r_curried[:as]

    r_direct2 = select(df, alias(rank(col("x"); method = :ordinal), "rk"))
    r_curried2 = select(df, alias(col("x") |> rank(method = :ordinal), "rk"))
    @test r_direct2[:rk] == r_curried2[:rk]

    r_direct3 = select(df, alias(value_counts(col("g"); sort = true), "vc"))
    r_curried3 = select(df, alias(col("g") |> value_counts(sort = true), "vc"))
    @test collect(r_direct3[:vc]) == collect(r_curried3[:vc])

    dfi = DataFrame((; y = [missing, 1.0, missing, 4.0]))
    r_direct4 = select(dfi, alias(interpolate(col("y"); method = :nearest), "i"))
    r_curried4 = select(dfi, alias(col("y") |> interpolate(method = :nearest), "i"))
    @test isequal(r_direct4[:i], r_curried4[:i])

    r_direct5 = select(df, alias(cum_sum(col("x"); reverse = true), "cs"))
    r_curried5 = select(df, alias(col("x") |> cum_sum(reverse = true), "cs"))
    @test r_direct5[:cs] == r_curried5[:cs]

    r_direct6 = select(df, alias(cum_max(col("x")), "cm"))
    r_curried6 = select(df, alias(col("x") |> cum_max(), "cm"))
    @test r_direct6[:cm] == r_curried6[:cm]

    r_direct7 = select(df, alias(cum_prod(col("x")), "cp"))
    r_curried7 = select(df, alias(col("x") |> cum_prod(), "cp"))
    @test r_direct7[:cp] == r_curried7[:cp]

    r_direct8 = select(df, alias(cum_min(col("x")), "cn"))
    r_curried8 = select(df, alias(col("x") |> cum_min(), "cn"))
    @test r_direct8[:cn] == r_curried8[:cn]

    r_direct9 = select(df, alias(cum_count(col("x")), "cc"))
    r_curried9 = select(df, alias(col("x") |> cum_count(), "cc"))
    @test r_direct9[:cc] == r_curried9[:cc]
end

@testset "std/var have no curried form -- lambda is the documented replacement (P2.2)" begin
    # `std`/`var` extend `Statistics.std`/`Statistics.var` now (see expr/expr.jl); a curried
    # (Fix2-style) form taking only keyword arguments would be type piracy (nothing in
    # `std(; ddof=0)`'s signature mentions `Expr`). `x -> std(x; ddof=0)` is the replacement.
    df = DataFrame((; x = [3, 1, 2]))

    r_direct = select(df, alias(std(col("x"); ddof = 0), "s"))
    r_lambda = select(df, alias(col("x") |> (x -> std(x; ddof = 0)), "s"))
    @test r_direct[:s] == r_lambda[:s]

    r_direct2 = select(df, alias(var(col("x"); ddof = 0), "v"))
    r_lambda2 = select(df, alias(col("x") |> (x -> var(x; ddof = 0)), "v"))
    @test r_direct2[:v] == r_lambda2[:v]
end

@testset "curried Strings: to_date / to_datetime" begin
    df = DataFrame((; d = ["2024-01-15", "2024-06-30"]))

    r_direct = select(df, alias(Strings.to_date(col("d")), "date"))
    r_curried = select(df, alias(col("d") |> Strings.to_date(), "date"))
    @test collect(r_direct[:date]) == collect(r_curried[:date])

    df2 = DataFrame((; d = ["2024-01-15 09:30:00", "2024-06-30 14:00:00"]))
    r_direct2 = select(df2, alias(Strings.to_datetime(col("d")), "dt"))
    r_curried2 = select(df2, alias(col("d") |> Strings.to_datetime(), "dt"))
    @test collect(r_direct2[:dt]) == collect(r_curried2[:dt])
end

@testset "curried Dt: truncate / round / offset_by / strftime" begin
    df = DataFrame((; d = [Date(2024, 1, 15), Date(2024, 6, 30)]))

    r_direct = select(df, alias(Dt.truncate(col("d"), lit("1mo")), "r"))
    r_curried = select(df, alias(col("d") |> Dt.truncate("1mo"), "r"))
    @test r_direct[:r] == r_curried[:r] == [Date(2024, 1, 1), Date(2024, 6, 1)]

    r_direct2 = select(df, alias(Dt.offset_by(col("d"), lit("1d")), "r"))
    r_curried2 = select(df, alias(col("d") |> Dt.offset_by("1d"), "r"))
    @test r_direct2[:r] == r_curried2[:r] == [Date(2024, 1, 16), Date(2024, 7, 1)]

    r_direct3 = select(df, alias(Dt.round(col("d"), lit("1mo")), "r"))
    r_curried3 = select(df, alias(col("d") |> Dt.round("1mo"), "r"))
    @test r_direct3[:r] == r_curried3[:r]

    r_direct4 = select(df, alias(Dt.strftime(col("d"), "%Y-%m"), "r"))
    r_curried4 = select(df, alias(col("d") |> Dt.strftime("%Y-%m"), "r"))
    @test r_direct4[:r] == r_curried4[:r] == ["2024-01", "2024-06"]
end
