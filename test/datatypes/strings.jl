@testset "Strings namespace" begin
    df = DataFrame((; names = ["John", "alice", "BOB"]))

    r = select(
        df, col("names") |> Strings.lowercase |> alias("lower"),
        col("names") |> Strings.len_bytes |> alias("bytes"),
        col("names") |> Strings.len_chars |> alias("chars"),
        Strings.starts_with(col("names"), lit("J")) |> alias("startsJ"),
        Strings.ends_with(col("names"), lit("e")) |> alias("endsE"),
        Strings.contains_literal(col("names"), lit("li")) |> alias("hasli")
    )
    @test r[:lower] == ["john", "alice", "bob"]
    @test r[:bytes] == [4, 5, 3]
    @test r[:chars] == [4, 5, 3]
    @test r[:startsJ] == [true, false, false]
    @test r[:endsE] == [false, true, false]
    @test r[:hasli] == [false, true, false]

    # len_bytes vs len_chars: multi-byte unicode strings distinguish the two
    df2 = DataFrame((; s = ["café", "emoji 🥚"]))
    r2 = select(df2, col("s") |> Strings.len_bytes |> alias("bytes"), col("s") |> Strings.len_chars |> alias("chars"))
    @test r2[:bytes] == [5, 10]
    @test r2[:chars] == [4, 7]

    # already covered elsewhere but included here for a self-contained namespace testset
    upper = select(df, col("names") |> Strings.uppercase)[:names]
    @test upper == ["JOHN", "ALICE", "BOB"]

    # Strings.titlecase is unavailable: to_titlecase in upstream polars-plan requires polars' own
    # "nightly" Cargo feature, which this repo deliberately doesn't enable (stable toolchain only,
    # see CLAUDE.md) -- so no ccall binding exists for it either. It must fail with an explanation
    # of that rather than a bare UndefVarError for the missing symbol.
    @test_throws "requires" select(df, col("names") |> Strings.titlecase)
end

@testset "Strings namespace expansion" begin
    df = DataFrame((; s = ["  hello world  ", "  foo bar  "]))

    r = select(
        df, alias(Strings.strip_chars(col("s"), lit(" ")), "stripped"),
        alias(Strings.strip_prefix(col("s"), lit("  hello")), "noprefix"),
        alias(Strings.strip_suffix(col("s"), lit("  ")), "nosuffix"),
        alias(Strings.zfill(col("s"), lit(20)), "z"),
        alias(Strings.head(col("s"), lit(5)), "h"),
        alias(Strings.tail(col("s"), lit(5)), "t")
    )
    @test r[:stripped] == ["hello world", "foo bar"]
    @test r[:noprefix] == [" world  ", "  foo bar  "]
    @test r[:nosuffix] == ["  hello world", "  foo bar"]
    @test all(x -> length(x) == 20, r[:z])
    @test r[:h] == ["  hel", "  foo"]
    @test r[:t] == ["rld  ", "bar  "]

    df2 = DataFrame((; s = ["a,b,c", "x,y"]))
    parts = select(df2, Strings.split(col("s"), lit(",")))[:s]
    @test collect(parts[1]) == ["a", "b", "c"]
    @test collect(parts[2]) == ["x", "y"]

    df3 = DataFrame((; s = ["hello123world", "no numbers here", "foo42bar99"]))
    r3 = select(
        df3, alias(Strings.contains(col("s"), lit(raw"\d+")), "has_num"),
        alias(Strings.extract(col("s"), lit(raw"(\d+)"), 1), "first_num"),
        alias(Strings.extract_all(col("s"), lit(raw"\d+")), "all_nums"),
        alias(Strings.count_matches(col("s"), lit(raw"\d+")), "n_matches")
    )
    @test r3[:has_num] == [true, false, true]
    @test isequal(r3[:first_num], ["123", missing, "42"])
    @test collect(r3[:all_nums][1]) == ["123"]
    @test isempty(collect(r3[:all_nums][2]))
    @test collect(r3[:all_nums][3]) == ["42", "99"]
    @test r3[:n_matches] == [1, 0, 2]

    df4 = DataFrame((; s = ["hello world", "foo bar baz"]))
    r4 = select(
        df4, alias(Strings.slice(col("s"), lit(0), lit(5)), "sl"),
        alias(Strings.slice(col("s"), lit(-3), lit(3)), "sl_neg"),
        alias(Strings.replace(col("s"), lit("o"), lit("0")), "repl_first"),
        alias(Strings.replace_all(col("s"), lit("o"), lit("0")), "repl_all"),
        alias(Strings.replace(col("s"), lit("[aeiou]"), lit("_")), "repl_regex")
    )
    @test r4[:sl] == ["hello", "foo b"]
    @test r4[:sl_neg] == ["rld", "baz"]
    @test r4[:repl_first] == ["hell0 world", "f0o bar baz"]
    @test r4[:repl_all] == ["hell0 w0rld", "f00 bar baz"]
    @test r4[:repl_regex] == ["h_llo world", "f_o bar baz"]

    # literal=true treats the pattern as a plain substring, not a regex
    df5 = DataFrame((; s = ["a.b.c"]))
    r5 = select(df5, alias(Strings.replace_all(col("s"), lit("."), lit("-"); literal = true), "r"))
    @test only(r5[:r]) == "a-b-c"
end

@testset "Strings.replace: null propagation and a column (with a null) as the replacement value (py-polars test_string_replace_with_nulls_10124 / test_str_replace_null_19601)" begin
    df = DataFrame((; col1 = Union{Missing, String}["S", "S", "S", missing, "S"]))
    r = select(df, alias(Strings.replace(col("col1"), lit("S"), lit("O")), "n1"))
    @test isequal(collect(r[:n1]), ["O", "O", "O", missing, "O"])

    df2 = DataFrame((; key = ["1", "2"], one = Union{Missing, String}["---", missing]))
    r2 = select(df2, alias(Strings.replace(col("key"), lit("1"), col("one")), "result"))
    @test collect(r2[:result]) == ["---", "2"]
end

@testset "Strings.zfill: byte-based width (not character count), and null passthrough (py-polars test_str_zfill_unicode_not_respected)" begin
    df = DataFrame((; a = Union{Missing, String}["Café", "345", "東京", missing]))
    r = select(df, alias(Strings.zfill(col("a"), lit(6)), "z"))
    @test isequal(collect(r[:z]), ["0Café", "000345", "東京", missing])
end

@testset "Strings.to_date / Strings.to_datetime" begin
    df = DataFrame((; d = ["2024-01-15", "2024-06-30"]))

    r = select(df, alias(Strings.to_date(col("d")), "date"))
    @test collect(r[:date]) == [Date(2024, 1, 1) + Day(14), Date(2024, 6, 30)]
    # composes with the Dt namespace from Milestone B
    @test collect(select(r, alias(Dt.year(col("date")), "y"))[:y]) == [2024, 2024]
    @test collect(select(r, alias(Dt.month(col("date")), "m"))[:m]) == [1, 6]
    @test collect(select(r, alias(Dt.day(col("date")), "d"))[:d]) == [15, 30]

    # explicit format string
    df_fmt = DataFrame((; d = ["15/01/2024", "30/06/2024"]))
    r_fmt = select(df_fmt, alias(Strings.to_date(col("d"); format = "%d/%m/%Y"), "date"))
    @test collect(r_fmt[:date]) == collect(r[:date])

    df2 = DataFrame((; d = ["2024-01-15 09:30:00", "2024-06-30 14:00:00"]))
    r2 = select(df2, alias(Strings.to_datetime(col("d")), "dt"))
    @test collect(r2[:dt]) == [DateTime(2024, 1, 15, 9, 30, 0), DateTime(2024, 6, 30, 14, 0, 0)]

    # time_unit variants parse without error
    for tu in (:ns, :us, :ms)
        r_tu = select(df2, alias(Strings.to_datetime(col("d"); time_unit = tu), "dt"))
        @test r_tu[:dt][1] == DateTime(2024, 1, 15, 9, 30, 0)
    end

    @test_throws ErrorException Strings.to_datetime(col("d"); time_unit = :bogus)

    # strict=false turns unparseable values into null instead of erroring
    df_bad = DataFrame((; d = ["2024-01-15", "not a date"]))
    r_bad = select(df_bad, alias(Strings.to_date(col("d"); strict = false), "date"))
    @test ismissing(r_bad[:date][2])
end

@testset "Strings.contains strict parameter" begin
    df = DataFrame((; s = ["hello", "world", "testing"]))

    # Valid regex with strict=true (default, should error on invalid regex)
    r_valid = select(df, alias(Strings.contains(col("s"), lit("he")), "match"))
    @test r_valid[:match] == [true, false, false]

    # Invalid regex with strict=true should raise an error
    @test_throws PolarsError select(df, alias(Strings.contains(col("s"), lit("[invalid")), "match"))

    # Invalid regex with strict=false should return missing instead of erroring
    r_strict_false = select(df, alias(Strings.contains(col("s"), lit("[invalid"); strict = false), "match"))
    @test all(ismissing, collect(r_strict_false[:match]))
end

@testset "Strings.pad_start / Strings.pad_end (py-polars test_str_pad_start / test_str_pad_end)" begin
    df = DataFrame((; a = ["foo", "longer_foo", "longest_fooooooo", "hi"]))

    r_start = select(df, alias(Strings.pad_start(col("a"), 10), "padded"))
    @test collect(r_start[:padded]) == ["       foo", "longer_foo", "longest_fooooooo", "        hi"]

    r_end = select(df, alias(Strings.pad_end(col("a"), 10), "padded"))
    @test collect(r_end[:padded]) == ["foo       ", "longer_foo", "longest_fooooooo", "hi        "]

    # a custom fill_char, and null passthrough
    df2 = DataFrame((; a = Union{Missing, String}["a", "bbbbbb", "cc", "d", missing]))
    r2_start = select(df2, alias(Strings.pad_start(col("a"), 4), "p"))
    @test isequal(collect(r2_start[:p]), ["   a", "bbbbbb", "  cc", "   d", missing])
    r2_end = select(df2, alias(Strings.pad_end(col("a"), 4), "p"))
    @test isequal(collect(r2_end[:p]), ["a   ", "bbbbbb", "cc  ", "d   ", missing])

    # non-ASCII fill_char, char-count (not byte-count) width -- py-polars test_pad_end_unicode /
    # test_pad_start_unicode (this repo has a documented history of non-ASCII string bugs, see
    # CLAUDE.md's ncodeunits note, so this matters more here than it looks upstream)
    df3 = DataFrame((; a = Union{Missing, String}["Café", "345", "東京", missing]))
    r3_end = select(df3, alias(Strings.pad_end(col("a"), 6; fill_char = '日'), "p"))
    @test isequal(collect(r3_end[:p]), ["Café日日", "345日日日", "東京日日日日", missing])
    r3_start = select(df3, alias(Strings.pad_start(col("a"), 6; fill_char = '日'), "p"))
    @test isequal(collect(r3_start[:p]), ["日日Café", "日日日345", "日日日日東京", missing])

    # curried forms for |> pipelines
    r_curried_start = select(df, alias(col("a") |> Strings.pad_start(10), "p"))
    @test collect(r_curried_start[:p]) == collect(r_start[:padded])
    r_curried_end = select(df, alias(col("a") |> Strings.pad_end(10), "p"))
    @test collect(r_curried_end[:p]) == collect(r_end[:padded])

    # `length` also accepts a column expression, not just an integer literal (py-polars
    # test_str_pad_start_expr: `int | IntoExprColumn`) -- a per-row target length
    df4 = DataFrame((; a = Union{Missing, String}["a", "bbbbbb", "cc", "d", missing], b = Union{Missing, Int64}[1, 2, missing, 4, 4]))
    r4 = select(df4, alias(Strings.pad_start(col("a"), col("b")), "p"))
    @test isequal(collect(r4[:p]), ["a", "bbbbbb", missing, "   d", missing])
end

@testset "Strings.find (py-polars test_str_find)" begin
    city = Union{Missing, String}[
        "Dubai", "Abu Dhabi", "Sharjah", "Al Ain", "Ajman", "Ras Al Khaimah", "Fujairah",
        "Umm Al Quwain", missing,
    ]
    pat = Union{Missing, String}["b[ai]", "b[ai]", "[ai]n", "[ai]n", "[ai]n", "a.+a", "a.+a", "a.+a", missing]
    df = DataFrame((; city = city, pat = pat))

    r_regex = select(df, alias(Strings.find(col("city"), lit("(?i)a")), "f"))
    @test isequal(collect(r_regex[:f]), Union{Missing, UInt32}[3, 0, 2, 0, 0, 1, 3, 4, missing])

    r_col_pat = select(df, alias(Strings.find(col("city"), col("pat")), "f"))
    @test isequal(collect(r_col_pat[:f]), [2, 7, missing, 4, 3, 1, 3, missing, missing])

    # invalid regex: strict=true raises, strict=false returns null (py-polars
    # test_str_find_invalid_regex)
    df2 = DataFrame((; txt = ["AbCdEfG"]))
    rx_invalid = "(?i)AB.))"
    @test_throws PolarsError select(df2, alias(Strings.find(col("txt"), lit(rx_invalid); strict = true), "f"))
    r_lenient = select(df2, alias(Strings.find(col("txt"), lit(rx_invalid); strict = false), "f"))
    @test ismissing(only(r_lenient[:f]))

    # curried form for |> pipelines
    r_curried = select(df, alias(col("city") |> Strings.find("(?i)a"), "f"))
    @test isequal(collect(r_curried[:f]), collect(r_regex[:f]))
end

@testset "Strings.to_integer / Strings.reverse unavailable in this build (each needs its own Cargo feature)" begin
    df = DataFrame((; s = ["ab", "cd"]))
    @test_throws "string_to_integer" Strings.to_integer(col("s"))
    @test_throws "string_reverse" Strings.reverse(col("s"))
end

@testset "Strings.join: aggregating join-with-separator across all rows (see plans/parity/gap_closure_scope.md Group C, batch-7-strings.md)" begin
    df = DataFrame((; s = ["a", "b", "c"]))
    r = select(df, alias(Strings.join(col("s"), "-"), "j"))
    @test only(r[:j]) == "a-b-c"

    # ignore_nulls=true (default): nulls are skipped
    df_null = DataFrame((; s = Union{Missing, String}["a", missing, "c"]))
    r_ignore = select(df_null, alias(Strings.join(col("s"), "-"), "j"))
    @test only(r_ignore[:j]) == "a-c"

    # ignore_nulls=false: any null poisons the whole result
    r_poison = select(df_null, alias(Strings.join(col("s"), "-"; ignore_nulls = false), "j"))
    @test ismissing(only(r_poison[:j]))

    # empty input -> empty string, not missing/error
    r_empty = select(DataFrame((; s = String[])), alias(Strings.join(col("s"), "-"), "j"))
    @test only(r_empty[:j]) == ""

    # per-group aggregation, not just whole-column
    df_g = DataFrame((; g = ["x", "x", "y"], s = ["a", "b", "c"]))
    r_g = collect(agg(group_by(lazy(df_g), "g"), alias(Strings.join(col("s"), "-"), "j")))
    by_group = Dict(zip(r_g[:g], r_g[:j]))
    @test by_group == Dict("x" => "a-b", "y" => "c")
end

@testset "Strings.extract_groups: named-capture regex into a Struct (see plans/parity/gap_closure_scope.md Group C, batch-7-strings.md)" begin
    df = DataFrame((; s = ["2024-01-15"]))
    r = select(df, alias(Strings.extract_groups(col("s"), raw"(?<year>\d+)-(?<month>\d+)-(?<day>\d+)"), "g"))
    val = only(r[:g])
    @test val.year == "2024"
    @test val.month == "01"
    @test val.day == "15"

    # no match -> every field missing, not an error
    df_nomatch = DataFrame((; s = ["not-a-date"]))
    r_nomatch = select(df_nomatch, alias(Strings.extract_groups(col("s"), raw"(?<year>\d{4})"), "g"))
    @test ismissing(only(r_nomatch[:g]).year)
end

@testset "Strings.escape_regex: escapes regex metacharacters so the result matches itself literally" begin
    # operations/namespaces/string/test_string.py::test_escape_regex -- the exact upstream fixture:
    # a null alongside a string that mixes several metacharacters, including a literal backslash
    # (`abc(\w+)` -> `abc\(\\w\+\)`, escaping the backslash itself as well as the parens and `+`)
    df = DataFrame((; text = Union{String, Missing}["abc", "def", missing, "abc(\\w+)"]))
    r = select(df, alias(Strings.escape_regex(col("text")), "escaped"))
    @test isequal(collect(r[:escaped]), ["abc", "def", missing, "abc\\(\\\\w\\+\\)"])

    # the escaped pattern matches its own source string literally
    df2 = DataFrame((; s = ["a.b", "c*d"]))
    r_contains = select(df2, alias(Strings.contains(col("s"), Strings.escape_regex(col("s"))), "c"))
    @test r_contains[:c] == [true, true]

    # a string with no metacharacters is left unchanged
    df_plain = DataFrame((; s = ["hello"]))
    r_plain = select(df_plain, alias(Strings.escape_regex(col("s")), "esc"))
    @test only(r_plain[:esc]) == "hello"

    # wrong-dtype raises cleanly rather than aborting the process (Step 5)
    df_int = DataFrame((; a = [1, 2, 3]))
    @test_throws PolarsError collect(select(lazy(df_int), alias(Strings.escape_regex(col("a")), "e")))
end
