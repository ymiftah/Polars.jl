# Batch 14 parity note: expr/selectors.jl, meta.jl, horizontal.jl, naming.jl, sample.jl, curried_forms.jl, misc.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/` (prefixed `b14_`):
`operations/test_selectors.py` (1167 lines), `operations/namespaces/test_meta.py` (207 lines),
`expr/test_meta.py` (47 lines — a second, distinct `test_meta.py`; both fetched and read, since
the ledger's guess didn't disambiguate them), `operations/namespaces/test_name.py` (171 lines),
`functions/test_horizontal.py` (42 lines), `operations/aggregation/test_horizontal.py` (784
lines), `operations/test_random.py` (169 lines), `functions/test_col.py` (127 lines),
`functions/test_nth.py` (29 lines). All nine paths confirmed via a full tree listing before
fetching. This is the last unswept batch on `plans/parity/LEDGER.md`.

The six small files (under 210 lines each) were read in full; `operations/test_selectors.py` and
`operations/aggregation/test_horizontal.py` (the two files over 700 lines) were `grep`-triaged for
issue-numbered regression tests given this repo's existing `selectors.jl`/`curried_forms.jl` are
already 342/338 lines respectively — unusually deep going into this batch.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `nth` | `functions/test_nth.py` (`test_nth`, `test_nth_duplicate`) | single-index access, adjusted for this wrapper's 1-based indexing (`nth(1)` = upstream's `pl.nth(0)`, negative indices unchanged); duplicate resolution across two `nth` calls | non-default parameter, Step-5 abort-safety | matches (index semantics) and raises cleanly (duplicate); added |
| `min_horizontal`/`max_horizontal`/`sum_horizontal`/`mean_horizontal` | `test_shape_mismatch_19336` | mismatched-length literal `Series` inputs | Step-5 abort-safety | raises cleanly for all four; added |
| `Selectors.by_name` | `test_by_name_order_19384` | multiple names preserve the ORDER given, not the frame's own column order | non-obvious/previously-untested behavior | matches — and the *existing* test for `by_name` `sort()`-normalized its comparison, silently masking this; added an order-sensitive assertion alongside it |

## Genuine gaps found (flagged, not fixed)

1. **`Meta` is missing `is_scalar`/`is_known_length`/`is_row_separable`/`is_length_preserving`/
   `eq`.** Confirmed absent via `grep` (not merely untested) while porting `expr/test_meta.py`'s
   `test_meta_properties`/`test_meta_eq_tot_cmp_28469`. Every other introspection method this repo
   already has a matching upstream counterpart for; these five don't yet. Recorded in
   `api_gap_audit.md`'s Group 11.
2. **`nth` has no multi-argument or vector form** (`pl.nth(2, 1)`, `pl.nth([2, -2, 0])`) — this
   wrapper's `nth(n)` takes exactly one integer. Every other multi-column selector (`by_name`,
   `by_index`) already accepts varargs, so this is a real inconsistency, not by design.
3. **No `shuffle` kwarg on `sample_n`/`sample_frac`** (upstream's `shuffle=False` preserves the
   sampled rows' relative order) — confirmed absent via `grep`. There is also no frame-level
   `sample` at all (only the `Expr`-level `sample_n`/`sample_frac`).

## Not ported (Step 4 exclusions)

- The overwhelming majority of `operations/test_selectors.py` (1167 lines) and
  `operations/aggregation/test_horizontal.py` (784 lines) — the former is almost entirely
  regex-expansion/query-optimizer-projection edge cases specific to Python's `cs.*` frontend
  (`test_regex_expansion_group_by_9947`, `test_pickle_selector_11425`,
  `test_list_eval_selector_23667`) with no clean 1:1 mapping onto this wrapper's `Selectors`
  namespace, which already has its own dedicated 342-line test file; the latter is almost
  entirely about the `Expr`-level *aggregating* horizontal reductions (`Expr.sum_horizontal`-style
  chains inside `group_by().agg(...)`) rather than the free-function `min_horizontal`/etc. this
  batch's `horizontal.jl` actually covers.
- `test_selectors_radd_21978` (`"$" + cs.by_name(...)` — a string literal on the *left* of a
  `+` with a selector on the right) — this wrapper's `Selector` type doesn't overload arithmetic
  operators any more than it overloads comparison operators (see the existing, still-unresolved
  `isless(::Polars.Selector, ::Int64)` finding from Batch 10's sibling investigation into
  `test_filter_horizontal_selector_15428`); same class of gap, not re-recorded separately.
- `test_fold_reduce_output_dtype_24011` (`pl.fold`/`pl.reduce`/`pl.cum_fold`/`pl.cum_reduce`) —
  these all take a Rust closure; `plans/parity/api_gap_audit.md` already classifies them as
  "Group 9 callback work, not thin wrappers," out of scope for a test-porting pass (confirmed
  still accurate, not re-recorded).
- `operations/namespaces/test_name.py`'s `test_name_map_chain_21164`,
  `test_when_then_keep_map_13858`, `test_keep_name_struct_field_23669` — exercise `name.map`
  (arbitrary Python-lambda column renaming), which has no Julia-callback equivalent exposed here
  (same callback-infrastructure gap as `fold`/`reduce` above), and struct-field-specific
  `keep_name` interactions that depend on that same missing capability.
- `functions/test_col.py` — grep-triaged; every test exercises `pl.col`'s dtype-based selection
  overloads (`pl.col(pl.Int64, pl.Float64)`, `pl.col(*dtype_list)`) or regex-string column
  selection, both already covered by this repo's existing `Selectors.by_dtype`/`Selectors.matches`
  (the idiomatic equivalents here, per `docs/src/limitations.md`'s documented design choice to
  route dtype/regex selection through `Selectors` rather than overloading `col` itself).
- `operations/test_random.py`'s `test_shuffle_group_by_reseed`, `test_sample_16232` — internal
  RNG-reseeding-across-group-by-partitions regressions; not observable through this wrapper's
  thin `shuffle`/`sample_n` bindings without reproducing polars' own internal partition-execution
  model.

## Resolved non-issues (verified before assuming a bug)

- `nth(0)` (this wrapper's own 1-indexed convention makes `0` an out-of-domain input, not upstream
  parity) was checked directly: it currently silently resolves to the *last* column rather than
  erroring, since the internal 1-based-to-0-based conversion (`n - 1`) sends `0` to `-1`. This is
  arguably a minor input-validation gap (an explicit range check would be more robust than relying
  on Rust's own negative-index wraparound for an input this wrapper's own docstring doesn't
  actually sanction), but it's not a upstream-parity divergence — upstream's `pl.nth(0)` is a
  perfectly valid *first*-column reference in its 0-indexed world, so there is no fixture to port
  here either way. Noted for awareness, not fixed or flagged broken.
