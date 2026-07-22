# `Polars.Selectors` (py-polars' `cs.*` / `polars.selectors`) -- see
# `plans/definitive_guide_gap_closure.md`'s Phase 2. `S` is a local alias for brevity, matching
# how `Lists`/`Strings`/`Structs` are used unqualified elsewhere via their top-level export --
# `Selectors` itself is exported, so `Selectors.numeric()` also works directly; `S` just saves
# typing in this file.
const S = Selectors

@testset "Selectors.by_name: strict vs non-strict, empty" begin
    df = DataFrame((; a = [1, 2, 3], b = [4, 5, 6], c = [7, 8, 9]))

    @test sort(names(select(df, S.by_name("a", "c")))) == ["a", "c"]
    @test names(select(df, S.by_name("b"))) == ["b"]

    # strict (default): a missing name raises
    @test_throws PolarsError select(df, S.by_name("a", "nonexistent"))
    @test_throws PolarsError select(df, S.by_name("a", "nonexistent"; strict = true))

    # non-strict: a missing name is silently skipped
    @test names(select(df, S.by_name("a", "nonexistent"; strict = false))) == ["a"]

    # zero names is a legitimate selector matching zero columns, not an error
    @test size(select(df, S.by_name())) == (0, 0)
end

@testset "Selectors.by_index: 1-based, negative, cross-checked against nth" begin
    df = DataFrame((; a = [1, 2, 3], b = [4, 5, 6], c = [7, 8, 9]))

    # `0` is included deliberately: `by_index` mirrors `nth`'s exact conversion formula
    # (`n < 0 ? n : n - 1`), including its edge-case quirk that `0` silently converts to `-1`
    # (the *last* column) rather than erroring -- verified live against `nth` itself below, not
    # assumed, since this is exactly the kind of off-by-one corner a hand rederivation could get
    # wrong in only one of the two places.
    for i in (1, 2, 3, 0, -1, -2, -3)
        @test names(select(df, S.by_index(i))) == names(select(df, nth(i)))
    end

    @test names(select(df, S.by_index(1, 3))) == ["a", "c"]
    # `ByIndex` (like `ByName`) returns columns in call order, not schema order -- verified live,
    # not assumed (it would be an easy, wrong guess that these come back schema-sorted instead).
    @test names(select(df, S.by_index(3, 1))) == ["c", "a"]
    @test names(select(df, S.by_index(-1, 1))) == ["c", "a"]

    # strict (default): an out-of-range index raises
    @test_throws PolarsError select(df, S.by_index(99))

    # non-strict: an out-of-range index is silently skipped
    @test names(select(df, S.by_index(99; strict = false))) == String[]

    # zero indices is a legitimate selector matching zero columns, not an error
    @test size(select(df, S.by_index())) == (0, 0)
end

@testset "Selectors.matches/starts_with/ends_with/contains: regex-special and non-ASCII names" begin
    # Column names containing regex metacharacters that would change meaning if not escaped
    # (`.` as wildcard, `^`/`$` as anchors, `(`/`)`/`[`/`]` as groups/classes, `+` as quantifier).
    backslash_name = "e" * "\\" * "f" # unambiguous single-backslash literal, not a string escape
    df = DataFrame(
        (;
            Symbol("a.b") => [1, 2],
            Symbol("aXb") => [3, 4], # would spuriously match "a." if "." were treated as a wildcard
            Symbol("x+y") => [5, 6],
            Symbol("q(1)") => [7, 8],
            Symbol("z[0]") => [9, 10],
            Symbol("a^b") => [11, 12],
            Symbol("c\$d") => [13, 14],
            Symbol(backslash_name) => [17, 18],
            plain = [15, 16],
        )
    )

    @test names(select(df, S.starts_with("a."))) == ["a.b"] # not ["a.b", "aXb"] -- "." is literal
    @test names(select(df, S.contains("+"))) == ["x+y"]
    @test names(select(df, S.contains("("))) == ["q(1)"]
    @test names(select(df, S.contains("["))) == ["z[0]"]
    @test names(select(df, S.contains("^"))) == ["a^b"]
    @test names(select(df, S.contains("\$"))) == ["c\$d"]
    @test names(select(df, S.contains("\\"))) == [backslash_name]
    @test names(select(df, S.ends_with(")"))) == ["q(1)"]
    @test names(select(df, S.ends_with("]"))) == ["z[0]"]

    # `matches` takes a real regex, unlike the other three
    @test names(select(df, S.matches("^[a-z]\\.[a-z]\$"))) == ["a.b"]
    @test sort(names(select(df, S.matches("^[a-z]\\(")))) == ["q(1)"]

    # multiple prefixes/suffixes/substrings behave as a union (match any)
    @test sort(names(select(df, S.starts_with("a.", "x+")))) == ["a.b", "x+y"]
    @test sort(names(select(df, S.ends_with(")", "]")))) == ["q(1)", "z[0]"]

    # at least one pattern is required
    @test_throws ArgumentError S.starts_with()
    @test_throws ArgumentError S.ends_with()
    @test_throws ArgumentError S.contains()

    # non-ASCII column names (this repo's string-marshaling history -- CLAUDE.md's `ncodeunits`
    # note -- makes this an important case to exercise, not a nice-to-have)
    dfu = DataFrame(
        (;
            Symbol("café") => [1, 2],
            Symbol("日本語") => [3, 4],
            plain = [5, 6],
        )
    )
    @test names(select(dfu, S.starts_with("café"))) == ["café"]
    @test names(select(dfu, S.contains("本"))) == ["日本語"]
    @test names(select(dfu, S.ends_with("語"))) == ["日本語"]
    @test names(select(dfu, S.by_name("café"))) == ["café"]
    @test names(select(dfu, S.matches("^日"))) == ["日本語"]

    # empty-match selector: a well-formed pattern that matches no column is 0 columns, not an error
    @test size(select(dfu, S.starts_with("zzz_nonexistent_prefix_xyz"))) == (0, 0)
    @test size(select(dfu, S.matches("^zzz_nonexistent_zzz\$"))) == (0, 0)
end

@testset "Selectors dtype families" begin
    df = DataFrame(
        (;
            i64 = Int64[1, 2],
            u32 = UInt32[1, 2],
            f64 = Float64[1.0, 2.0],
            s = ["a", "b"],
            b = [true, false],
            bin = [UInt8[1, 2], UInt8[3]],
            dt_ = [Date(2024, 1, 1), Date(2024, 1, 2)],
            tm = [Time(1, 2, 3), Time(2, 3, 4)],
            datetime_ = [DateTime(2024, 1, 1), DateTime(2024, 1, 2)],
        )
    )
    df = with_columns(lazy(df), col("i64") |> cast(Dates.Nanosecond) |> alias("dur")) |> collect

    @test sort(names(select(df, S.numeric()))) == ["f64", "i64", "u32"]
    @test sort(names(select(df, S.integer()))) == ["i64", "u32"]
    @test names(select(df, S.unsigned_integer())) == ["u32"]
    @test names(select(df, S.signed_integer())) == ["i64"]
    @test names(select(df, S.float())) == ["f64"]
    @test names(select(df, S.string())) == ["s"]
    @test names(select(df, S.boolean())) == ["b"]
    @test names(select(df, S.binary())) == ["bin"]
    @test names(select(df, S.date())) == ["dt_"]
    @test names(select(df, S.time())) == ["tm"]
    @test names(select(df, S.datetime())) == ["datetime_"]
    @test names(select(df, S.duration())) == ["dur"]
    @test sort(names(select(df, S.temporal()))) == ["datetime_", "dt_", "dur", "tm"]

    # Categorical
    dfc = DataFrame((; c = ["x", "y", "x"], n = [1, 2, 3]))
    dfc = select(dfc, cast_categorical(col("c")) |> alias("c"), col("n"))
    @test names(select(dfc, S.categorical())) == ["c"]

    # Decimal -- `names()` itself can't introspect a Decimal column's schema (a pre-existing,
    # unrelated gap -- see `cast_decimal`'s own docstring), so check via `size` instead.
    dfd = DataFrame((; x = [1, 2, 3]))
    dfd = select(dfd, cast_decimal(col("x"), 10, 2) |> alias("d"), col("x"))
    @test size(select(dfd, S.decimal())) == (3, 1)
    @test size(select(dfd, S.numeric())) == (3, 2) # Decimal counts as numeric upstream too

    # Struct/List/nested
    dfs = DataFrame((; st = [(a = 1, b = "x"), (a = 2, b = "y")], n = [1, 2]))
    @test names(select(dfs, S.struct_())) == ["st"]
    @test names(select(dfs, S.nested())) == ["st"]

    dfl = DataFrame((; l = [[1, 2], [3]], n = [1, 2]))
    @test names(select(dfl, S.list())) == ["l"]
    @test names(select(dfl, S.nested())) == ["l"]

    # Array: `dtype-array` is not enabled in this build's Cargo features (unlike the other
    # DataTypeSelector kinds), so `DataTypeSelector::Array`'s own upstream matcher compiles to an
    # unconditional `false` rather than a panic -- `array()` is safe to call, it just never
    # matches anything in this build. Confirmed here as a regression guard: this must stay a
    # clean 0-column result forever, not start crashing if that upstream code ever changes.
    @test size(select(df, S.array())) == (0, 0)
end

@testset "Selectors.by_dtype: explicit dtypes and the parametrized-dtype error path" begin
    df = DataFrame((; i = Int64[1, 2], f = Float64[1.0, 2.0], s = ["a", "b"]))

    @test sort(names(select(df, S.by_dtype(Int64, Float64)))) == ["f", "i"]
    @test names(select(df, S.by_dtype(Int64))) == ["i"]
    @test size(select(df, S.by_dtype())) == (0, 0)

    # Datetime/Duration/Decimal/List/Struct need parameters a plain dtype code can't carry --
    # `to_dtype` rejects them, surfacing a real `PolarsError`, not a bug (see `by_dtype`'s
    # docstring and `polars_value_type_t::to_dtype` on the Rust side).
    @test_throws PolarsError S.by_dtype(DateTime)
    @test_throws PolarsError S.by_dtype(DateTime, Int64)
    @test_throws PolarsError S.by_dtype(Dates.Nanosecond)
end

@testset "Selectors combinators: |, &, -, xor" begin
    df = DataFrame((; a = Int64[1, 2], b = Float64[3.0, 4.0], x = ["p", "q"], y = [true, false]))

    @test sort(names(select(df, S.numeric() | S.boolean()))) == ["a", "b", "y"]
    @test names(select(df, S.numeric() & S.starts_with("a"))) == ["a"]
    @test sort(names(select(df, S.all() - S.numeric()))) == ["x", "y"]
    @test sort(names(select(df, xor(S.numeric(), S.starts_with("a"))))) == ["b"]

    # nested/chained combinators
    @test sort(names(select(df, (S.numeric() | S.string()) & (S.all() - S.by_name("b"))))) ==
        ["a", "x"]

    # `all()` is the identity for `-`'s complement and matches everything on its own
    @test sort(names(select(df, S.all()))) == ["a", "b", "x", "y"]
end

@testset "Selector composes with with_columns/sort, and mixing Selector/Expr is a MethodError" begin
    df = DataFrame((; a = Int64[3, 1, 2], b = Float64[30.0, 10.0, 20.0], x = ["p", "q", "r"]))

    # inside with_columns (a Selector flows through `_as_expr` exactly like a column-name string)
    r = with_columns(lazy(df), S.numeric()) |> collect
    @test sort(names(r)) == ["a", "b", "x"]

    # inside sort
    r2 = sort(df, S.numeric())
    @test collect(r2[:a]) == [1, 2, 3]

    # `Selector` composes with `select` too (a boolean-dtype selector picks out which *column* is
    # returned, not which *rows* -- that's `filter`'s job, exercised separately right below)
    dfb = DataFrame((; a = [1, 2, 3], flag = [true, false, true]))
    only_flag = select(dfb, S.boolean())
    @test names(only_flag) == ["flag"]

    # inside filter: `_as_expr` composes a `Selector` there too, so a boolean-dtype selector can be
    # passed directly as the row predicate (regression test for the `filter` docs' claim that it
    # supports `Selector` like `select`/`with_columns`/`sort` do)
    r3 = filter(dfb, S.boolean())
    @test collect(r3[:a]) == [1, 3]
    @test collect(r3[:flag]) == [true, true]

    # regression: filter still works normally with a plain Expr/String/Symbol predicate (all three
    # go through the same `_as_expr` coercion the `Selector` case above just started using)
    @test collect(filter(dfb, col(:a) .> 1)[:a]) == [2, 3]
    @test collect(filter(dfb, "flag")[:a]) == [1, 3]
    @test collect(filter(dfb, :flag)[:a]) == [1, 3]

    # Mixing a plain Expr with a Selector via |/&/-/xor is a decided, deliberate `MethodError` in
    # both operand orders -- not a silent (and possibly wrong) promotion of `col("x")` to a
    # selector. Verified live, not assumed: this exercises the actual dispatch, not just a read
    # of the source.
    @test_throws MethodError S.numeric() | col("x")
    @test_throws MethodError col("x") | S.numeric()
    @test_throws MethodError S.numeric() & col("x")
    @test_throws MethodError col("x") & S.numeric()
    @test_throws MethodError S.numeric() - col("x")
    @test_throws MethodError col("x") - S.numeric()
    @test_throws MethodError xor(S.numeric(), col("x"))
    @test_throws MethodError xor(col("x"), S.numeric())
end

@testset "Selectors: Enum/Object have no public constructor; empty() is not part of the public surface" begin
    # First-cut scope: the Rust primitive supports a strict superset of `DataTypeSelector` kinds
    # (including Enum/Object), and `polars_expr_selector_empty` exists as the combinators'
    # identity element -- neither is meant to be reachable as a public `Selectors.*` constructor.

    # Enum/Object: no binding of either name exists in the `Selectors` module at all (unlike
    # `empty` below, neither is a `Base` name, so a plain `isdefined` check is real proof here --
    # not just "not exported", genuinely absent).
    @test !isdefined(Selectors, :enum_)
    @test !isdefined(Selectors, :object)

    @test hasmethod(Selectors.by_dtype, Tuple{}) # sanity: by_dtype() itself IS a valid call
    @test_throws MethodError Selectors.empty() # resolves to Base.empty, not a Selectors constructor
end
