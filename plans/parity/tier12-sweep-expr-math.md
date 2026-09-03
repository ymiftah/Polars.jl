# Tier 1/2 sweep parity note: arctan2 / dot / entropy / to_physical / lower_bound / upper_bound (Expr-level)

## Status

**Done.** Re-anchored `test/expr/math.jl`'s `arctan2/dot`, `entropy`, `lower_bound/upper_bound`, and
`to_physical` testsets on upstream fixtures per the `pypolars-test-parity` skill. These six
functions were added in `a999dbc` with tests derived from live-observed behavior of our own
implementation rather than from upstream; this note re-derives them from py-polars' actual test
suite. No genuine divergence was found -- all six functions are thin 1:1 passthroughs to upstream
Rust `Expr::arctan2`/`Expr::dot`/`Expr::entropy`/`Expr::to_physical`/`Expr::lower_bound`/
`Expr::upper_bound` (`c-polars/src/expr.rs:537-539,566-567`, `src/expr/expr.jl:580-583`), and every
upstream fixture matched on first live run. No `src/` fix, no `@test_broken`.

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_exprs.py` (expr),
`test_series.py` (series), `test_trigonometric.py` (sql), `test_ufunc_expr.py` (numpy interop),
`series.py` (full `Series` source, to check `entropy`'s Python-side default kwargs), and
`trigonometry.rs` (Rust `polars-expr` dispatch source, to explain the arctan2 dtype-coercion
finding below).

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `arctan2` | `test_arctan2` (`sql/test_trigonometric.py`) | `y=[√2/2,-√2/2,√2/2,-√2/2]`, `x=[√2/2,√2/2,-√2/2,-√2/2]` → `atan2d=[45,-45,135,-135]°` (converted to radians: `[π/4,-π/4,3π/4,-3π/4]`) | happy path, quadrant coverage | matches exactly; added (replaces the old single-quadrant fixture, which only checked one point) |
| `dot` | `test_dot_in_group_by` (`expr/test_exprs.py`) | `group=[a,a,a,b,b,b]`, `x=[1]*6`, `y=[1..6]` → grouped dot `{a: 6, b: 15}` | happy path, aggregation context | matches (`[6, 15]`); added |
| `entropy` | `test_entropy` (`expr/test_exprs.py`) | `group=[A,A,A,B,B,B,B,C]`, `id=[1,2,1,4,5,4,6,7]`, `normalize=True` → `{A: 1.0397207708399179, B: 1.371381017771811, C: 0.0}` | happy path, aggregation context, non-default fixture (0-entropy group `C`) | matches exactly; added |
| `entropy` | `Series.entropy` docstring (`series/series.py`) | `[0.99, 0.005, 0.005]`, `normalize=True` → `0.06293300616044681` | happy path, default-parameter confirmation | matches; added as a base/normalize-default sanity check |
| `lower_bound`/`upper_bound` | `test_upper_lower_bounds` (`series/test_series.py`) | empty series per dtype: `Int8/UInt8/Int16/UInt16/Int32/UInt32/Int64/UInt64` → exact `typemin`/`typemax`; `Float32/Float64` → `±Inf` | happy path, non-default dtype table, **empty input** (upstream's own fixture is a 0-row series -- bounds are dtype-derived, not data-derived) | matches every dtype exactly, including the Float32/Float64 `±Inf` case (not a finite float max, unlike the integer cases); added |
| `to_physical` | `test_to_physical` (`series/test_series.py`) | `["cat1"]` cast to `Categorical` → physical dtype `UInt32`, value `0` | non-default dtype (Categorical) | matches (`UInt32`, `0x00000000`); added. The Enum→UInt8 half of the same upstream test does not port -- this package has no `Enum` dtype (Step 8 divergence, below) |

## Domain-edge finding: arctan2 non-strictly coerces non-float dtypes (Step 4 "domain edge", not a divergence)

Testing wrong-dtype input on `arctan2` (Step 5) turned up a behavior worth recording precisely,
because it looks at first glance like the same "silent wrong answer" class of bug the frame-verbs
sweep found, but isn't:

```julia
df_str = DataFrame((; a = ["1.0", "2.0", "abc"]))
select(df_str, alias(arctan2(col("a"), col("a")), "a"))
# => [atan(1.0, 1.0), atan(2.0, 2.0), missing]  -- no error
```

A parseable numeric string coerces to `Float64` and computes; an unparseable one becomes `missing`
rather than raising `PolarsError`. This is **not** a Julia-side bug and not a divergence from
upstream -- it is upstream Rust's own behavior. `arctan2_on_columns`
(`crates/polars-expr/src/dispatch/trigonometry.rs:52-72`) matches on `y.dtype()`; for any
non-float dtype it falls through to `y.cast(&DataType::Float64)?` (a non-strict cast, which nulls
out unparseable values instead of raising) and recurses. This is architecturally different from
the *unary* trig functions (`sin`, `cosh`, ...), which upstream's own
`test_trigonometric_invalid_input` (`series/test_series.py:1825`) asserts DO raise
`InvalidOperationError` on a String column -- confirmed live that our `sin(col("a"))` on a String
column raises `PolarsError` too, matching that half of upstream's test. Recorded as a "dtype
coercion, not a raise" test case in `arctan2/dot`'s testset rather than folded into the
`@test_throws` case, since asserting a raise here would be asserting the wrong thing.

`dot` and `entropy`, by contrast, DO raise `PolarsError` cleanly on a String column (both ported as
`@test_throws PolarsError`, Step 5) -- no process abort in either case.

## Not ported (Step 4 exclusions)

- `test_ufunc_expr.py`'s `np.arctan2(pl.col(...), ...)` -- numpy ufunc-protocol interop, not
  applicable (Step 4 exclusion list).
- `series/test_series.py::test_dot`'s `s1 @ [4, 5, 6, 7, 8]` raising `ShapeError` on length
  mismatch -- this is the `Series.__matmul__` operator overload (a different binding from
  `Expr.dot`, Step 9), and doesn't translate cleanly to the `Expr`-level context this package
  wraps (a shape mismatch inside `select` is a broader engine-level condition, not specific to
  `dot`). Not ported.
- `series/test_series.py::test_dot`'s `pl.Series.dot` accepting a raw Julia list/numpy-array
  argument -- see the Step 8 divergence entry below; not forced into another test row.
- `expr/test_exprs.py::test_dot_in_group_by`'s exact call shape `pl.col("x").dot("y")` (a bare
  string naming the other column) -- ported using `dot(col("gx"), col("gy"))` instead; see Step 8.
- `series/test_series.py::test_to_physical_rechunked_21285` -- exercises `Array(Struct(...))`/
  `List(Struct(...))` with a `Time`/`Null` field and multi-chunk rechunking; a regression test for
  an internal rechunking bug on a dtype combination well outside this package's currently wrapped
  surface (`Struct` fields with a `Null` dtype specifically). Skipped as out of scope.
- `dataframe/test_df.py`, `io/test_scan_options.py`, `operations/namespaces/temporal/test_datetime.py`,
  etc. from the `to_physical`/`lower_bound`/`upper_bound` search hits -- incidental uses of these
  functions inside unrelated tests (I/O options, temporal namespace features), not dedicated
  fixtures; confirmed they add nothing beyond what `test_series.py`'s dedicated tests already cover.

## API divergences found (Step 8)

1. **`Expr.dot`/`Expr.arctan2` require both arguments to already be `Polars.Expr`** (`a::Expr,
   b::Expr` in the `@wrap_simple_ops`-generated signature, `src/macros.jl`), unlike upstream
   Python's `Expr.dot`, which accepts a bare string (interpreted as `pl.col(name)`) or a raw list/
   `Series`/numpy array as its second argument (`pl.col("x").dot("y")`, `s1.dot(s2)`,
   `s1 @ np.array([4,5,6])`). Passing a Julia `String` where this package's `dot`/`arctan2` expects
   an `Expr` does NOT resolve to a column reference -- `Base.convert(::Type{Expr}, ::String)`
   (`src/expr/expr.jl:57`) builds a **string literal** via `polars_expr_literal_utf8`, not
   `col(s)`. This is consistent with every other `gen_impl_expr_binary!`-generated op in the
   package (`eq`, `lt`, `pow`, ...), so it isn't unique to this batch -- noted here because
   upstream's `dot` test happens to exercise exactly this string-as-column-name shape. Not fixed;
   this is the package's established, deliberate API shape (callers write `col("y")` explicitly).
2. **This package has no `Enum` dtype**, so `to_physical`'s Enum→`UInt8` case from upstream's
   `test_to_physical` doesn't port (only the Categorical→`UInt32` case does). Pre-existing,
   deliberate omission (not introduced by this batch); flagged here as the sweep's Step 8 record
   rather than fixed, since adding `Enum` support is a much larger feature than this test-parity
   sweep's scope.

## Running ledger

| function | our test file | upstream file::test | status | note |
|---|---|---|---|---|
| `arctan2` | `test/expr/math.jl` | `sql/test_trigonometric.py::test_arctan2` | done | four-quadrant fixture ported; dtype-coercion (not raise) documented |
| `dot` | `test/expr/math.jl` | `expr/test_exprs.py::test_dot_in_group_by` | done | grouped-aggregation fixture ported; wrong-dtype raise confirmed |
| `entropy` | `test/expr/math.jl` | `expr/test_exprs.py::test_entropy`, `series/series.py` docstring | done | grouped fixture + default-kwarg docstring example ported; wrong-dtype raise confirmed |
| `to_physical` | `test/expr/math.jl` | `series/test_series.py::test_to_physical` | done | Categorical case ported; Enum case n/a (no Enum dtype, Step 8) |
| `lower_bound` | `test/expr/math.jl` | `series/test_series.py::test_upper_lower_bounds` | done | full dtype table incl. Float32/Float64 `±Inf`, doubles as empty-input coverage |
| `upper_bound` | `test/expr/math.jl` | `series/test_series.py::test_upper_lower_bounds` | done | same fixture as `lower_bound` |

## Verification

- `test/expr/math.jl` alone: all testsets pass, including the two new/expanded ones (`arctan2/dot`:
  9/9, `entropy`: 7/7, `lower_bound/upper_bound`: 23/23, `to_physical`: 4/4).
- `timeout 900 julia --project=. -e 'using Pkg; Pkg.test()'`: **3173 passed, 4 broken** (baseline
  3143 passed / 4 broken -- the delta is +30 passing assertions, no new `@test_broken`; the 4
  pre-existing broken are unrelated Aqua/`Strings.titlecase` exclusions, per the frame-verbs
  sibling sweep).
- `pre-commit run --all-files`: all hooks passed (no Rust or docstring changes in this batch, so
  `docs/make.jl` was not run).
