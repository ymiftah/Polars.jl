@testset "Strings namespace" begin
    df = DataFrame((; names = ["John", "alice", "BOB"]))

    r = select(df, col("names") |> Strings.lowercase |> alias("lower"),
                   col("names") |> Strings.len_bytes |> alias("bytes"),
                   col("names") |> Strings.len_chars |> alias("chars"),
                   Strings.starts_with(col("names"), lit("J")) |> alias("startsJ"),
                   Strings.ends_with(col("names"), lit("e")) |> alias("endsE"),
                   Strings.contains_literal(col("names"), lit("li")) |> alias("hasli"))
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
