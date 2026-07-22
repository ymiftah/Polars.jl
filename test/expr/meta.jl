# `Polars.Meta` (`Expr.meta()` introspection namespace) -- see
# `plans/definitive_guide_gap_closure.md`'s Phase 3. Unlike `Lists`/`Strings`/`Dt`/`Structs`/
# `Selectors`, `Meta` is NOT exported from `Polars` (it would collide with `Base.Meta`, itself an
# *exported* Base submodule -- `using Polars` would otherwise ambiguous-error on the bare name).
# Always reached fully qualified, `Polars.Meta.output_name(...)` etc. -- `M` is a local alias for
# brevity, matching `Selectors.jl`'s own `S` alias convention.
const M = Polars.Meta

@testset "Meta.output_name: plain/aliased/arithmetic/error paths" begin
    @test M.output_name(col("x")) == "x"
    @test M.output_name(col("x") |> alias("y")) == "y"
    # arithmetic: output name follows the left/first root column
    @test M.output_name(col("x") + col("y")) == "x"

    # wildcard/selector-expanded expr has no single well-defined output name -- must error
    # cleanly (a PolarsError, not a crash), not silently pick one column.
    @test_throws PolarsError M.output_name(col("*"))
    @test_throws PolarsError M.output_name(Selectors.numeric())
end

@testset "Meta.is_column" begin
    @test M.is_column(col("x"))
    @test !M.is_column(col("x") |> alias("y"))
    @test !M.is_column(lit(1))
    @test !M.is_column(col("x") + col("y"))
end

@testset "Meta.is_literal: allow_aliasing both ways" begin
    @test M.is_literal(lit(1))
    @test !M.is_literal(col("x"))
    @test !M.is_literal(col("x") + col("y"))

    aliased_literal = lit(1) |> alias("y")
    @test !M.is_literal(aliased_literal) # allow_aliasing defaults to false
    @test !M.is_literal(aliased_literal; allow_aliasing = false)
    @test M.is_literal(aliased_literal; allow_aliasing = true)
end

@testset "Meta.has_multiple_outputs" begin
    @test M.has_multiple_outputs(Selectors.numeric())
    @test !M.has_multiple_outputs(col("x"))
    @test !M.has_multiple_outputs(col("x") + col("y"))
end

@testset "Meta.root_names: simple/binary/literal-only, empty-vs-non-empty" begin
    @test M.root_names(col("x")) == ["x"]
    @test M.root_names(col("x") + col("y")) == ["x", "y"]
    # A literal-only expr has no column reference at all -- an empty Vector{String}, not an
    # error (this was actually a real bug during development: the Rust-side `_len`/`_get` pair
    # is correct, but the naive Julia `0:(n - 1)` loop underflowed for `n::Csize_t == 0`, since
    # `Csize_t` is unsigned -- `0 - 1` wraps around to a huge range instead of the intended empty
    # one. Caught by exercising this exact case live before writing this test).
    names = M.root_names(lit(1))
    @test names == String[]
    @test names isa Vector{String}
end

@testset "Meta.undo_aliases: round trip" begin
    aliased = col("x") |> alias("y")
    @test M.output_name(aliased) == "y"
    unaliased = M.undo_aliases(aliased)
    @test M.output_name(unaliased) == "x"

    # multiple aliases in a row all get undone
    double_aliased = col("z") |> alias("a") |> alias("b")
    @test M.output_name(M.undo_aliases(double_aliased)) == "z"
end

@testset "Meta.tree_format / Meta.show_graph: smoke tests" begin
    expr = col("x") + col("y")

    tf = M.tree_format(expr)
    @test tf isa String
    @test !isempty(tf)

    sg = M.show_graph(expr)
    @test sg isa String
    @test !isempty(sg)
    # Graphviz output starts with a `graph { ... }` block (undirected -- upstream's own
    # `tree_fmt_dot` emits `graph`, not `digraph`); check for the marker rather than asserting an
    # exact string.
    @test occursin("graph", sg)
end

@testset "Meta on a deeply chained expr (.dt()/.str()/arithmetic mixed)" begin
    chained = (col("x") |> Dt.truncate("1d")) + (col("y") |> Strings.uppercase |> alias("_ignored"))

    # `alias("_ignored")` is nested inside the right-hand operand of `+`, not at the top of the
    # tree, so it must NOT affect the overall output name/root names -- confirms no choking (and
    # no silent misattribution) on a non-trivial tree.
    @test M.output_name(chained) == "x"
    @test sort(M.root_names(chained)) == ["x", "y"]
    @test !M.has_multiple_outputs(chained)
    @test !M.is_column(chained)
    @test !M.is_literal(chained)

    tf = M.tree_format(chained)
    @test tf isa String
    @test !isempty(tf)
end
