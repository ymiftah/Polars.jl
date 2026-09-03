# Tier 1/2 sweep parity note: arg_unique / extend_constant / shuffle / Base.reshape / Strings.escape_regex

## Status

**Done.** Re-anchored `test/expr/selection.jl`'s `arg_unique`/`extend_constant`/`shuffle`/
`Base.reshape` testsets and `test/datatypes/strings.jl`'s `Strings.escape_regex` testset on
upstream fixtures per the `pypolars-test-parity` skill. These five functions were added in
`a999dbc` with tests derived from live-observed behavior of our own implementation rather than
from upstream; this note re-derives them from py-polars' actual test suite. One genuine
process-safety finding was made (a Rust-side panic correctly caught by `guard_error`, not a
process abort); no functional divergence from upstream was found.

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_unique.py` (operations),
`series/test_series.py` (`arg_unique` dtype-pinning fixture), `lazyframe/test_lazyframe.py`
(`test_arg_unique`), `datatypes/test_float.py` (`arg_unique`/NaN dedup fixture),
`datatypes/test_decimal.py` (incidental hit, not ported — see below), `test_extend_constant.py`
(operations), `test_random.py` (operations, `shuffle`), `test_reshape.py` (operations),
`functions/test_functions.py` (`escape_regex`, top-level), `operations/namespaces/string/test_string.py`
(`escape_regex`, `Expr.str`), `meta/test_errors.py` (incidental hit, not ported).

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `arg_unique` | `lazyframe/test_lazyframe.py::test_arg_unique` | `a=[4,1,4]` → `[0,1]`, dtype `pl.get_index_type()` (`UInt32`) | happy path, dtype-pinning | matches exactly; added |
| `arg_unique` | `series/test_series.py:427-431` | `a=[2,1,1,4,4,4]` → `[0,1,3]` | happy path, longer run of duplicates | matches; added (our old test only had two adjacent-pair duplicates, `[1,1,2,2]`, which can't distinguish "first occurrence" from "any occurrence within the run") |
| `arg_unique` | `datatypes/test_float.py::test_unique` (nulls variant) | `x=[-0.0,-NaN,0.0,None,1.0,NaN]`, checked via `s.gather(s.arg_unique())` | domain edge (NaN/−0.0 dedup) + null propagation | matches: `-0.0`/`0.0` collapse (IEEE-754 equal) and `-NaN`/`NaN` collapse into one group each, first occurrence kept — `gather(arg_unique(...))` round-trips to `[-0.0, NaN, missing, 1.0]`; added |
| `arg_unique` | n/a (own addition) | empty `Int64` column | empty input | `UInt32[]`; added |
| `extend_constant` | `operations/test_extend_constant.py::test_extend_constant` | `Int64`/`Float64`/`String`/`missing`-const cases, `[None] extend_constant(const, 3)]` | happy path, non-default parameter (dtype) | matches for every dtype our literal `convert(Expr, ...)` overloads cover (see Not ported); added |
| `extend_constant` | same test, `n` as `pl.lit(2)` | `n` as an expression, not a literal `Int` | non-default parameter shape | matches (`[missing,1,1]`); added |
| `extend_constant` | same test, `value` as `pl.lit(const, dtype=dtype)` | `value` as an expression | non-default parameter shape | matches; added |
| `extend_constant` | `operations/test_extend_constant.py::test_extend_by_not_uint_expr` | non-scalar `value`/`n` (a multi-element `Expr`) | wrong-shape raises (Step 5 analog) | matches, both raise `PolarsError` (upstream: `ShapeError`, "must be a scalar value"); added |
| `shuffle` | `operations/test_random.py::test_shuffle_series` | `a=[1,2,3]`, `seed=1` → `[2,3,1]` (upstream's own exact pinned permutation) | happy path, non-default parameter, exact-value fixture | matches bit-for-bit on live run (same Rust RNG/seeding scheme); added as a real pinned-permutation assertion (not a self-observed one — see below) |
| `shuffle` | `operations/test_random.py::test_shuffle_group_by_reseed` | 5 groups of `[1,2,3]`, `seed=0xDEADBEEF` inside `group_by(...).agg(shuffle(...))` | non-default context (grouped aggregation) | matches: a fixed seed reseeds identically per group, so every group's shuffled order is the same; added |
| `shuffle` | n/a (own addition) | empty column, null-propagation | empty input, null propagation | multiset-preservation still holds; added |
| `Base.reshape` | `operations/test_reshape.py::test_reshape` | length-4 column, `(-1,2)`/`(2,2)`/`(2,-1)`-family shapes all resolve when the non-`-1` dims already fit | happy path, non-default dims | matches; added (`(2,-1)` here is a **resolvable** shape — see below for the dedicated error case) |
| `Base.reshape` | `operations/test_reshape.py::test_reshape` | `pl.col("a").reshape((2,-1))` on a length-4 column — upstream's own **dedicated** non-first-`-1` error case | wrong-parameter raises | matches: raises cleanly (upstream: `InvalidOperationError`, "can only infer the first dimension"; here: `PolarsError`) — confirms this package's first-position-only `-1` restriction is not a divergence, it matches upstream exactly; added |
| `Base.reshape` | `operations/test_reshape.py::test_reshape` | `s.reshape(())` — zero dimensions | empty input / wrong-parameter | **panics** deep in `polars-plan`'s schema resolution (`range start index 1 out of range for slice of length 0`, live-observed at `polars-plan-0.54.4/src/plans/aexpr/function_expr/schema.rs:320`) but is caught by `guard_error` before crossing the FFI boundary — surfaces as a clean `PolarsError`, no process abort; added, with the panic-catching behavior called out explicitly (Step 5 concern, confirmed *not* to manifest as an abort) |
| `Base.reshape` | `operations/test_reshape.py::test_reshape_invalid_multiple_unknown_dims` | `(-1,-1)` | wrong-parameter raises | matches (`PolarsError`); added |
| `Base.reshape` | `operations/test_reshape.py::test_reshape_invalid_dimension_size` | `(5,1)` on a length-4 column (size doesn't fit) | wrong-parameter raises | matches; added |
| `Base.reshape` | `operations/test_reshape.py::test_reshape_invalid_zero_dimension` | `(-1,0)` on a non-empty column | domain edge, wrong-parameter raises | matches; added |
| `Base.reshape` | `operations/test_reshape.py::test_reshape_empty_valid_1d` / `test_reshape_empty_invalid_1d` | empty column, `(0,)` valid vs `(1,)` invalid | empty input | matches: `(0,)` builds a plan, `(1,)` raises `PolarsError` (size mismatch); added |
| `Base.reshape` | `operations/test_reshape.py::test_reshape` | `3*5*7*2`-length column, `(3,5,7,2)` vs `(-1,5,7,2)` | non-default dims, higher-dimensional | both plans build (`explain` confirms); added |
| `Strings.escape_regex` | `operations/namespaces/string/test_string.py::test_escape_regex` | `text=["abc","def",None,"abc(\\w+)"]` → `["abc","def",None,"abc\\(\\\\w\\+\\)"]` (escapes the literal backslash too, not just `(`/`+`) | happy path, null propagation, non-trivial fixture | matches exactly; replaces the old hand-picked `["a.b","c*d"]` fixture, which never exercised escaping a literal backslash | 
| `Strings.escape_regex` | n/a (own addition) | `Int64` column | wrong-dtype raises (Step 5) | matches, raises `PolarsError` cleanly; added |

The self-matching-pattern check (`Strings.contains(col, escape_regex(col))` → all `true`) and the
no-metacharacters no-op case from the original test were kept as-is; they were already sound,
just not upstream-derived.

## Not ported (Step 4 exclusions)

- `operations/test_unique.py::test_list_unique`/`test_array_unique` — `arg_unique` on `List`/
  `Array`-typed elements; incidental hits from the same search term, not dedicated `arg_unique`
  fixtures (the assertion is really about `unique`/`n_unique`). Skipped.
- `datatypes/test_decimal.py:757` (`arg_unique` on a `Decimal` series) — this package has no
  `Decimal` dtype; n/a.
- `meta/test_errors.py:380` (`col("col2").arg_unique()` inside a `sort_by` group-length-mismatch
  regression test) — tests `sort_by`'s own group-length validation, `arg_unique` only incidentally
  appears as an argument. Skipped.
- `test_extend_constant.py`'s `Int8`/`UInt32`/`Date`/`Datetime`/`Time`/`Duration` parametrized
  cases — `Base.convert(::Type{Expr}, ...)` in `src/expr/expr.jl` only has literal overloads for
  `Int32`/`Int64`/`UInt32`/`UInt64`/`Bool`/`Float32`/`Float64`/`Missing`/`String` (`Colon`
  aside); an `Int8` or temporal constant can't be passed as a bare Julia literal the way upstream's
  `1` (inferred as `pl.Int8` from context) can. Not a bug in `extend_constant` itself — the same
  restriction applies to every other function taking a scalar literal in this package — so not
  fixed here; only the dtypes reachable through the existing `convert` overloads were ported.
- `test_extend_constant.py::test_extend_constant_arr` — exercises `Series.list.eval(...)`, the
  `List`-namespace `eval` context; out of scope for this batch's `Expr`-level `extend_constant`.
- `operations/test_random.py::test_sample_expr`/`test_sample_df`/`test_sample_16232` — these test
  `sample`, a different (and unwrapped) function; only incidentally live in the same file as
  `shuffle`'s tests (Step 9-adjacent: same file, different function). Skipped.
- `operations/test_reshape.py::test_array_ndarray_reshape` — `to_numpy()` interop; not applicable
  (Step 4 exclusion).
- `operations/test_reshape.py::test_reshape_sliced_list_25114` — a `List`-dtype-source regression
  test for a sliced-list reshape bug; this package's `reshape` takes a plain numeric column, and
  the underlying bug is specific to a `List` source representation this batch doesn't exercise.
  Skipped as out of scope.
- `operations/test_reshape.py::test_reshape_invalid_zero_dimension2`, `test_reshape_empty` — more
  members of the same zero-dimension/empty-array parametrized families already covered by the
  `(-1,0)` and `(0,)`/`(1,)` cases ported above; redundant additional parametrizations, not ported
  individually to avoid bloating the testset with near-duplicates.
- `functions/test_functions.py::test_escape_regex` — this is `pl.escape_regex`, a **top-level**
  function operating on a plain Python `str`, not `Expr.str.escape_regex` (Step 9: same name,
  different function). See the API divergence note below — this package has no counterpart to
  port against.

## API divergence found (Step 8)

**This package has no top-level `escape_regex(::AbstractString)`.** Upstream `pl.escape_regex` is
a plain string function (`pl.escape_regex("abc(\\w+)")` → `"abc\\(\\\\w\\+\\)"`, operating outside
any `Expr`/`DataFrame` context) distinct from `Expr.str.escape_regex`, which this package's
`Strings.escape_regex` already wraps. Upstream's own test additionally documents that
`pl.escape_regex(pl.col("text"))` deliberately raises `TypeError` ("unsupported for `Expr`, you
may want use `Expr.str.escape_regex` instead") and `pl.escape_regex(3)` raises `TypeError`
("supports only `str` type") — i.e. upstream keeps the two functions strictly separate on
purpose. This package covers only the `Expr`-level half; a bare-string `escape_regex` utility
(useful e.g. for building a `Strings.contains` pattern from a Julia string constant without going
through an `Expr` round-trip) doesn't exist here. Noted as a deliberate omission, not fixed in
this batch (small, self-contained addition — a candidate for a future low-hanging-fruit batch, not
forced into this test-parity sweep).

## Verification

- `test/expr/selection.jl` + `test/datatypes/strings.jl` run together in isolation: **129/129
  pass** (includes all pre-existing testsets in both files, not just the five re-anchored ones).
- `timeout 900 julia --project=. -e 'using Pkg; Pkg.test()'`: **3196 passed, 4 broken** (baseline
  3173 passed / 4 broken -- delta is +23 passing assertions, no new `@test_broken`; the 4
  pre-existing broken are unrelated Aqua/`Strings.titlecase` exclusions, per the sibling sweeps).
- `pre-commit run --all-files`: all hooks passed (no Rust or docstring changes in this batch, so
  `docs/make.jl` was not run).

## Running ledger

| function | our test file | upstream file::test | status | note |
|---|---|---|---|---|
| `arg_unique` | `test/expr/selection.jl` | `lazyframe/test_lazyframe.py::test_arg_unique`, `series/test_series.py:427`, `datatypes/test_float.py::test_unique` | done | dtype pinned (`UInt32`); NaN/−0.0 dedup + empty input added |
| `extend_constant` | `test/expr/selection.jl` | `operations/test_extend_constant.py::test_extend_constant`, `test_extend_by_not_uint_expr` | done | value-as-expr, n-as-expr, non-scalar-raises all ported |
| `shuffle` | `test/expr/selection.jl` | `operations/test_random.py::test_shuffle_series`, `test_shuffle_group_by_reseed` | done | exact pinned permutation (seed=1) + grouped-reseed fixture, both live-verified |
| `Base.reshape` | `test/expr/selection.jl` | `operations/test_reshape.py::test_reshape` + 4 error-case tests | done | first-position-only `-1` confirmed to match upstream (not a divergence); zero-dim panic confirmed caught by `guard_error` |
| `Strings.escape_regex` | `test/datatypes/strings.jl` | `operations/namespaces/string/test_string.py::test_escape_regex` | done | exact upstream fixture (backslash-escaping case); wrong-dtype raise added; top-level `pl.escape_regex` omission noted (Step 8) |
