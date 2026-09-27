@testset "alias/prefix/suffix" begin
    df = DataFrame((; x = [1, 2, 3]))

    r_alias = select(df, col("x") |> alias("renamed"))
    @test Tables.columnnames(r_alias) == (:renamed,)
    @test r_alias[:renamed] == [1, 2, 3]

    r_prefix = select(df, col("x") |> prefix("pre_"))
    @test Tables.columnnames(r_prefix) == (:pre_x,)

    r_suffix = select(df, col("x") |> suffix("_suf"))
    @test Tables.columnnames(r_suffix) == (:x_suf,)

    # curried forms compose the same way through |>
    r_curried = select(df, col("x") |> alias("renamed") |> prefix("pre_"))
    @test Tables.columnnames(r_curried) == (:pre_renamed,)
end

@testset "to_lowercase/to_uppercase" begin
    df = DataFrame((; x = [1, 2, 3], MixedCase = [1, 2, 3], café = [4, 5, 6]))

    r_lower = select(df, col("MixedCase") |> to_lowercase)
    @test Tables.columnnames(r_lower) == (:mixedcase,)
    @test r_lower[:mixedcase] == [1, 2, 3]

    r_upper = select(df, col("MixedCase") |> to_uppercase)
    @test Tables.columnnames(r_upper) == (:MIXEDCASE,)

    # non-ASCII column name
    r_nonascii = select(df, col("café") |> to_uppercase)
    @test Tables.columnnames(r_nonascii) == (:CAFÉ,)

    # --- chained renames ---
    #
    # `prefix`/`suffix`/`to_lowercase`/`to_uppercase`/`alias` apply in sequence, each to the name
    # the previous one produced (not the root column name, despite the Rust docs). `keep_name`
    # restores the original column name regardless of position.

    # alias("RENAMED") then to_lowercase: lowercases "RENAMED" (the alias), not root "x" (which
    # is already lowercase and would be indistinguishable from a no-op if that were the target).
    r_alias_then_lower = select(df, col("MixedCase") |> alias("RENAMED") |> to_lowercase)
    @test Tables.columnnames(r_alias_then_lower) == (:renamed,)

    # to_lowercase then prefix: prefixes the *lowercased* name, not the original "MixedCase" root.
    r_lower_then_prefix = select(df, col("MixedCase") |> to_lowercase |> prefix("pre_"))
    @test Tables.columnnames(r_lower_then_prefix) == (:pre_mixedcase,)

    # prefix then to_uppercase: uppercases "pre_x" wholesale (including the added prefix), not
    # just the original root "x" in isolation.
    r_prefix_then_upper = select(df, col("x") |> prefix("pre_") |> to_uppercase)
    @test Tables.columnnames(r_prefix_then_upper) == (:PRE_X,)

    # suffix, then to_lowercase, then suffix again: each op keeps folding onto the running name.
    r_chain = select(df, col("MixedCase") |> suffix("_A") |> to_lowercase |> suffix("_B"))
    @test Tables.columnnames(r_chain) == (:mixedcase_a_B,)

    # to_lowercase then alias then to_uppercase: `alias` hard-overrides the running name (not
    # just adding to it, like prefix/suffix/case do), and the following to_uppercase then folds
    # onto *that* override, not back onto the pre-alias "mixedcase".
    r_lower_alias_upper = select(df, col("MixedCase") |> to_lowercase |> alias("z") |> to_uppercase)
    @test Tables.columnnames(r_lower_alias_upper) == (:Z,)

    # keep_name after to_lowercase: reverts all the way back to the true original root
    # "MixedCase", unlike prefix/suffix/to_lowercase/to_uppercase chained after each other (which
    # never see back past their immediate predecessor).
    r_lower_then_keep = select(df, col("MixedCase") |> to_lowercase |> keep_name)
    @test Tables.columnnames(r_lower_then_keep) == (:MixedCase,)
end
