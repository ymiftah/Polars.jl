# Batch 11 parity note: operations/join.jl, group_by.jl, group_by_dynamic.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/` (prefixed `b11_`):
`operations/test_join.py` (4498 lines), `operations/test_join_asof.py` (1902 lines),
`operations/test_join_right.py` (136 lines), `operations/test_cross_join.py` (133 lines),
`operations/test_group_by.py` (3330 lines), `operations/test_group_by_dynamic.py` (1451 lines),
`operations/rolling/test_rolling.py` (2486 lines). All seven paths confirmed via
`gh api search/code` before fetching.

Given the combined ~14,000 lines of upstream source and that this repo's existing coverage was
already unusually deep for this area (every join type, join options — suffix/coalesce/validate/
nulls_equal, join_asof options, multi-key/null-key group_by, maintain_order, ~15 group_by_dynamic/
rolling kwarg-variant testsets already in place before this sweep), this batch triaged aggressively
for named-regression and abort-safety tests rather than reading every file end to end — depth over
completeness, per the skill's own framing, applied here to file *selection* as well as fixture
selection.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `outerjoin` | `test_join_raise_on_redundant_keys` | joining on the same key expression twice (`[col("a"), col("a")]`) | Step-5 abort-safety | raises cleanly (`"already joined on"`, matching message); added |
| `rightjoin` | `test_right_join_schemas` | coalesced result keeps the *right* table's key column; column order interleaves left-then-right per side | non-default parameter | matches exactly (`(:b, :a, :b_right, :c)`, `(:a, :b, :a_right, :b_right, :c)`); added |
| `rightjoin` | `test_join_right_different_key` | differently-named keys on each side keep both columns, right rows all survive | domain edge | matches; added |
| `group_by`/`agg` | `test_group_by_sum_on_strings_should_error_24659` | `sum()` on a `String` column inside an agg | Step-5 abort-safety | raises cleanly; added |
| `group_by`/`agg` | `test_group_by_agg_get_oob_error_26747` | out-of-bounds `Base.get(col, 100)` inside an agg | Step-5 abort-safety | raises cleanly; added |
| `group_by_dynamic` | `test_group_by_dynamic_validation` | non-positive `every` (`"-1i"`) | Step-5 abort-safety | raises cleanly (`"'every' argument must be positive"`, matching message); added |
| `group_by_dynamic` | `test_group_by_dynamic_invalid` | parsed-integer duration (`"3000i"`) against a `Datetime` column | Step-5 abort-safety, domain mismatch | raises cleanly with a matching message; added |
| `group_by_dynamic` | `test_group_by_dynamic_invalid` | calendar duration (`"3000d"`) against a plain `Int` index column | Step-5 abort-safety, domain mismatch | raises cleanly with a matching message (mirrors `upsample`'s identical index-vs-calendar-duration check from Batch 10); added |

## Genuine gap found (flagged, not fixed)

**No join variant accepts `maintain_order`.** Confirmed live: `crossjoin(a, b;
maintain_order=:left)` is a plain `MethodError`, not a runtime rejection — the keyword doesn't
exist on any join function's signature, and grepping `c-polars/src/*.rs` for `maintain_order`
shows it's threaded through `group_by`/`unique`/`sort`/`top_k`/`bottom_k` (all previously closed
per `api_gap_audit.md`'s Status section) but never through any `join`. Upstream's
`test_cross_join_maintain_order_24663` exercises this for cross joins specifically, but the
underlying `JoinArgs::maintain_order` in real polars covers every join type. Recorded in
`api_gap_audit.md`'s Group 6 "Missing keyword arguments" list (a new no-Cargo-change follow-up
batch, same shape as the already-closed `group_by`/`unique` work) rather than implemented here.

## Not ported (Step 4 exclusions)

- The overwhelming majority of `test_join.py` (170+ tests) and `test_group_by.py` (100+ tests) —
  query-optimizer behavior (CSE, predicate/projection pushdown, cache invalidation), streaming-
  engine-specific paths, `hypothesis`/hand-rolled fuzz sweeps, and internal schema-resolution
  regressions (`test_join_lit_panic_11410`, `test_cross_join_chunking_panic_22793`,
  `test_join_nested_key_nulls_not_equal_28584`) that exercise the query planner's internals rather
  than this wrapper's thin `innerjoin`/`group_by` surface.
- `test_join_on_wildcard_error`/`test_join_on_nth_error` (joining `on=pl.all()`/`on=pl.first()`) —
  our join functions take a plain `Expr`/column-name argument for the key; passing a selector or
  `nth()` there is exactly the kind of call this wrapper's simpler API doesn't structurally allow
  in the first place (same class as Batch 10's `pivot_invalid` finding), not a runtime path to
  assert against.
- `test_cross_join_raise_on_keys` (`crossjoin(..., left_on=..., right_on=...)` raising) — our
  `crossjoin(a, b)` has no `on`/`left_on`/`right_on` parameters at all, so this specific invalid
  call can't be constructed here either.
- `test_cross_join_maintain_order_24663` itself — gated on the gap above; not portable until
  `maintain_order` exists on some join.
- `test_group_by_dynamic_*`'s ~40 remaining tests (DST-crossing arithmetic, timezone-awareness
  parametrization, `_iter`/`_get` accessor methods with no Julia equivalent, slice-pushdown/CSE
  optimizer checks) — the kwarg-variant coverage this repo already had going into this batch
  (`closed`, `label`, `include_boundaries`, `start_by`, offset/period combinations) already
  exercises the same underlying FFI surface these would re-confirm.
- `test_rolling.py` in full — this repo's `rolling`/`group_by_dynamic` tests already cover the
  shared FFI surface (`rolling` is implemented as a `group_by_dynamic` variant here, per
  `src/group_by.jl`), and the upstream file's own tests are almost entirely about
  `rolling_mean`/`rolling_sum`-style *expression* functions (`Expr.rolling_mean`, distinct from
  the frame-level `rolling`/`group_by_dynamic` this batch's files cover) plus streaming-engine
  paths — out of this batch's scope (Step 9: don't conflate same-named/adjacent functions).

## Resolved non-issues (verified before assuming a bug)

- `rightjoin`'s coalesce column-ordering was unverified going in (upstream's own doc examples
  show it differs from inner/left's "keep the left key" convention) — live-checked against the
  exact upstream fixture and it matches column-for-column, including the interleaved left/right
  ordering, with zero source changes needed.
