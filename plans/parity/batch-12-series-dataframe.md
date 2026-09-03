# Batch 12 parity note: datatypes/series.jl, binary.jl, dataframe/construction.jl, io.jl, describe.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/` (prefixed `b12_`):
`series/test_series.py` (2597 lines), `series/test_getitem.py` (118 lines),
`series/test_to_list.py` (21 lines), `dataframe/test_df.py` (3388 lines),
`dataframe/test_shape.py` (12 lines), `dataframe/test_describe.py` (259 lines),
`datatypes/test_binary.py` (39 lines), `datatypes/test_null.py` (116 lines),
`constructors/test_constructors.py` (1911 lines). All nine paths confirmed via a full
`py-polars/tests/unit/` tree listing before fetching — several of the ledger's own guessed paths
were wrong (e.g. `test_getitem.py`/`test_to_list.py` live under `series/`, not bare top-level; the
ledger also omitted `dataframe/test_df.py`'s directory prefix consistently across several batches).

Given the combined ~8,400 lines (two files over 2500 lines each), this batch triaged aggressively:
the four small files (`test_shape.py`, `test_to_list.py`, `test_binary.py`, `test_null.py`, all
under 120 lines) were read in full; the four large files were `grep`-triaged for named-regression
and edge-case (`null`/`empty`/`invalid`/`error`/`dup`/`raise`) test names before reading any bodies.

## Fixtures ported / bug fixed (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `select` | `test_raise_invalid_shape_19108` | mismatched-length expressions (`head(col, 0)`, `head(col, 1)`) in one `select` | Step-5 abort-safety | raises cleanly; added |
| `Base.unique` | `test_null_grouping_12950` | an all-`missing` column collapses to one `missing` row | domain edge | matches; added |
| `filter` | `test_null_lit_filter_16664` | `lit(true)` on an already-0-row frame stays empty | empty input | matches; added |
| binary literal comparison | `test_binary_filter` | comparing a `Binary` column to a literal byte value | non-obvious idiom | works via `Series(name, [bytes])`, **not** `lit(bytes)` (ambiguous with a numeric-array literal) — documented and added |
| `cast` | `test_string_to_binary` | `String` -> `Binary` -> `String` round-trip, empty string + `missing` + a control-byte value | null propagation, domain edge | matches; added |
| `describe` | `test_df_describe_empty_column` | a 0-row-but-typed column still describes (count/null_count = 0, rest `missing`) | empty input | matches; added |
| `describe` | `test_df_describe_quantile_precision` | fractional percentiles (`0.999`, `0.9999`) need fractional labels (`"99.9%"`, `"99.99%"`) | non-default parameter | **was wrong — fixed**, see below |
| `describe` | `test_df_describe_empty` | a genuinely columnless frame raises | Step-5 abort-safety | **diverges** — see Genuine gaps below |
| Series `getindex` | `series/test_getitem.py` (multiple) | an index-vector (`s[[1,3]]`) returns a plain `Vector`, not a `Series`; a `Vector{Bool}` mask is valid standard Julia indexing (upstream rejects it) | idiom documentation | both confirmed and pinned down as tests, not gaps — plain Julia array semantics throughout, deliberately different from Python's `__getitem__` restrictions |

## Real bug found and fixed

**`describe`'s percentile row labels lost fractional precision**, silently colliding distinct
statistic rows under the same label. `src/describe.jl`'s old `string(round(Int, q * 100), "%")`
rounds every percentile to a whole-number percent — `percentiles=[0.99, 0.999, 0.9999]` produced
`["99%", "100%", "100%"]`, i.e. two different quantile rows both labeled `"100%"` even though their
computed *values* were still correct and distinct; only the label collided. Fixed to preserve
fractional precision only when the percentage isn't already a whole number (clearing float noise
via `round(pct, digits=10)` first, since `0.999 * 100` isn't exactly `99.9` in `Float64`), matching
`test_df_describe_quantile_precision`'s expected `"99%"`/`"99.9%"`/`"99.99%"` labels exactly. This
is a Julia-side formatting bug (no FFI/Rust involvement at all) — exactly the "Julia-side cause →
fix `src/`" branch of the skill's Step 7 table, not a case for `@test_broken`.

## Genuine gaps found (flagged, not fixed)

1. **`describe` on a genuinely columnless (0-row, 0-column) frame doesn't raise.** Upstream raises
   `TypeError: cannot describe a DataFrame that has no columns`; this wrapper returns a `(9, 1)`
   frame (just the `statistic` column). `@test_broken` in `test/dataframe/describe.jl`. Not fixed
   here — it's a real behavior change to a widely-used function's error path (add an explicit
   `size(df, 2) == 0` check and raise), better done as its own small reviewed change than folded
   into this test-porting pass.
2. **No `eq_missing`/`ne_missing` `Expr` methods, and no `hash_rows`/`Series`/`Expr` `hash`.**
   Confirmed absent via `grep -rn` across `src/` (not merely untested) while investigating
   `test_null_comp_14118` and `test_null_hash_rows_14100`. Feature-gate status against the vendored
   `polars-plan`/`polars-ops` source not yet checked; recorded in `api_gap_audit.md`'s Group 11 for
   a future batch to scope properly.

## Not ported (Step 4 exclusions)

- `series/test_to_list.py` and `series/test_getitem.py`'s slicing test — both are
  `hypothesis`/`@given`-driven property tests with no fixed fixture to port.
- The overwhelming majority of `test_series.py` (2597 lines) and `test_df.py` (3388 lines) —
  numpy/pandas/pyarrow interop, `hypothesis`-parametrized round-trips, internal
  cache/CSE/streaming-engine regressions, and Python-`__repr__`/pickling checks. Skimmed via
  `grep`-triage for `null`/`empty`/`invalid`/`error` names rather than read in full, given this
  repo's existing `Series`/`DataFrame` test coverage (bulk-materialization agreement across every
  dtype, GC-stress, zero-copy round-trips) already goes well beyond upstream's own depth in this
  specific area.
- `series/test_getitem.py`'s `TypeError`-raising cases (boolean mask via `__getitem__`, mixed-type
  sequences, `object()` as a key) — these are Python `__getitem__` duck-typing rejections with no
  Julia analogue; this wrapper's `Series <: AbstractVector` inherits ordinary Julia indexing
  semantics instead (see the fixture ported above, which documents this as a deliberate idiom
  difference rather than porting the rejection).
- `constructors/test_constructors.py` (1911 lines) — grep-triaged for `null`/`empty`/`invalid`/
  `error`/`dup`/`infer` names; every hit exercises Python-side type-inference paths (numpy dtype
  inference, `dict`/`list`-of-`dict` construction, pyarrow interop, dtype-inference from mixed
  Python objects) that don't apply to this wrapper's `NamedTuple`/`Tables.jl`-based constructor,
  which has its own, already-tested type-mapping logic (`src/arrow/array.jl`'s `format(T)`, exercised
  throughout the existing test suite).
- `test_null.py`'s `test_null_comp_14118`/`test_null_hash_rows_14100` — gated on the two missing
  capabilities recorded above (`eq_missing`/`ne_missing`, `hash`); nothing to assert against.
- `test_null.py`'s `test_null_fused_not_28845` (`is_nan`/`is_finite`/`is_infinite` on a `Null`-dtype
  column) — spot-checked live (all three propagate `missing` correctly, matching upstream), but
  these functions live in `src/expr/aggregation.jl`/`test/expr/aggregation.jl`, outside this
  batch's assigned files (Step 9: don't fold in an adjacent function's tests just because a fixture
  happened to surface while investigating something else).
- `dataframe/test_describe.py`'s `test_df_describe_nested`, `test_df_describe_object`,
  `test_df_describe_thousands_separator_string_columns_25946` — nested (`List`/`Struct`) column
  describe behavior, `Object`-dtype (unsupported here, no `object` Cargo feature), and a
  locale-formatting cosmetic default; none exercise new behavior beyond what's already covered.

## Resolved non-issues (verified before assuming a bug)

- The binary-literal-comparison failure was initially suspected to be a real FFI/comparison bug
  (`lit(UInt8[...])` produced a length-mismatch error against the column, not a clean comparison)
  — traced instead to `lit`'s inherent ambiguity for `Vector{UInt8}` (numeric array vs. binary
  scalar) rather than a defect; `Series(name, [bytes])` already does the right thing with zero
  source changes needed. Documented as an idiom rather than fixed or flagged broken.
- `Series` fancy/boolean-mask indexing was suspected (per an earlier aborted investigation) to be
  entirely unsupported ("gaps to record, not fixes") — live-checked and found to actually work,
  just via plain inherited `AbstractVector` semantics rather than a dedicated method; the only
  genuine surprise is the *return type* (`Vector`, not `Series`) for non-`UnitRange` index forms,
  now pinned down as a test rather than left as an assumption either way.
