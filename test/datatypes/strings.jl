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

    # Strings.titlecase is unavailable: to_titlecase in upstream polars-plan requires
    # polars' own "nightly" Cargo feature, which this repo deliberately doesn't enable
    # (stable toolchain only, see CLAUDE.md) -- so no ccall binding exists for it either.
    @test_broken select(df, col("names") |> Strings.titlecase) isa Any
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
