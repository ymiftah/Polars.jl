# Batch 10 parity note: operations/frame_verbs.jl, reshape.jl, concat.jl, select_with_columns.jl, filter.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/` (prefixed `b10_` to avoid
collisions with other batches' fetches into the same shared cache): `operations/test_pivot.py`,
`operations/test_unpivot.py`, `operations/test_transpose.py`, `operations/test_drop.py`,
`operations/test_rename.py`, `operations/test_select.py`, `operations/test_with_columns.py`,
`operations/test_filter.py`, `functions/test_concat.py`, `dataframe/test_vstack.py`,
`dataframe/test_upsample.py`. All eleven paths were confirmed via `gh api search/code` before
fetching (the ledger's own `test_upsample.py` guess omitted the `dataframe/` prefix).

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `filter` | `test_filter_on_empty` | `is_null()` against a zero-row column, across `Int32`/`Bool`/`String`/binary-like dtypes | empty input | matches; added |
| `filter` | `test_filter_19771` | `lit(true)` predicate against an all-`missing` column | null propagation | matches; added |
| `select` | `test_select_duplicate_name` | two expressions producing the same output name (`select(df, "x", "x")`) | Step-5 abort-safety | raises cleanly (`PolarsError`, not a crash); added |
| `with_columns` | `test_with_columns_empty` | zero expressions is a no-op | empty input | matches; added |
| `drop` | `test_drop` | `"*"` wildcard-drops every column | non-default parameter | **diverges** — see Genuine gaps below |
| `drop_nulls` | `test_drop_nulls_empty_subset` | explicit empty `subset` is a no-op | domain edge | **diverges** — see Genuine gaps below |
| `rename` | `test_rename_swap` | simultaneous `a<->b` swap (both renames apply against original names, not sequentially) | non-default parameter | matches; added |
| `rename` | `test_rename_same_name` | identity rename(s), single and all-columns-at-once | domain edge | matches; added |
| `vstack` | `test_vstack_with_null_column` | a `Null`-dtype (all-`missing`) column vstacks onto a typed one; the reverse direction raises | domain edge, asymmetric | matches; added |
| `upsample` | `test_upsample_date` | `Date` (not just `DateTime`) time column | non-default dtype | matches; added |
| `upsample` | `test_upsample_index_invalid` | a calendar duration (`"1h"`) against an `Int64` index column | Step-5 abort-safety | raises cleanly with a matching message; added |
| `upsample` | `test_upsample_with_group_by_15530` | `by` naming the same column as `time_column` (degenerate no-op case) | domain edge | matches; added |
| `upsample` | `test_upsample_with_group_by_15530` | duplicate `by` names | Step-5 abort-safety | raises cleanly; added |
| `upsample` | `test_upsample_empty_dataframe_with_group_by_26342` | empty (0-row) frame with `group_by` | empty input, Step-5 abort-safety | raises cleanly with a matching message; added |
| `unpivot` | `test_unpivot_no_on` | index covers every column, nothing left to melt | empty result, domain edge | matches; added |
| `unpivot` | `test_unpivot_index_not_found_23165` | nonexistent index column | Step-5 abort-safety | raises cleanly; added |
| `unpivot` | `test_unpivot_name_collides_with_existing_column` | `variable_name` colliding with a real column | Step-5 abort-safety | raises cleanly; added |
| `pivot` | `test_pivot_empty_index_dtypes` | zero-row input across integer index dtypes | empty input | matches; added |
| `pivot` | `test_duplicate_column_names_which_should_raise_14305` | `index` naming the same column twice via a list | Step-5 abort-safety | raises cleanly; added |
| `concat` | `test_concat_with_empty_dataframes` | a 0-row-but-typed frame concats with real data, either order | empty input | matches; added |
| `concat` | `test_concat_to_empty` | a genuinely 0-column frame concats with real data | empty input | **diverges** — see Genuine gaps below |
| `transpose` | `test_transpose_empty` | transposing a 0-row frame | empty input | **version-pinned divergence, already correctly asserted** — see Genuine gaps below |

## Genuine gaps / divergences found (flagged, not fixed — consistent with prior batches' precedent
of recording rather than implementing new capability during a test-porting pass)

Full detail (root cause, exact live-verified behavior, why each wasn't fixed here) is in
`plans/parity/api_gap_audit.md`'s Group 11 "Batch 10 findings" — summarized:

1. **`drop(df, ["*"])`** doesn't wildcard-drop every column; raises `ColumnNotFoundError`-
   equivalent instead of upstream's `(n, 0)` result. `@test_broken` in
   `test/operations/frame_verbs.jl`'s `"drop"` testset.
2. **`drop_nulls(df, String[])`** (explicit empty subset) behaves identically to the default
   (check all columns), not upstream's no-op — traced to `c-polars/src/ffi_util.rs`'s
   `selector_by_name_opt` collapsing "empty" and "unspecified" onto the same `None`. Docstring
   fixed in `src/verbs.jl` to say so explicitly; `@test_broken` added documenting the diverging
   case.
3. **`concat([schemaless_df, real_df])`** fails where upstream succeeds, specifically for a
   genuinely 0-column frame (distinct from a 0-row-but-typed one, which works fine either order —
   also confirmed and added as a passing test). `@test_broken` in `test/operations/concat.jl`.
4. **`transpose` on a 0-row frame** raises here (`no data: unable to transpose an empty
   DataFrame`) where the current upstream *main* test suite expects success — a real
   Rust-crate-version-pinned difference between the vendored `polars` 0.54.4 and whatever newer
   version py-polars' main branch tests against. The pre-existing test already asserted our
   (correct-for-this-version) behavior; no code change needed, just confirmed against the actual
   upstream test name instead of an untraced assumption.
5. **`drop` has no `strict` keyword** at all (upstream's `strict=False` silently ignores an
   unknown column) — the FFI function hardcodes `strict: true`. Needs a Rust signature change;
   recorded in the audit, not implemented.
6. **No frame-level `drop_nans`** — only the `Expr`-level one exists (`MethodError` confirmed
   live for `drop_nans(::DataFrame)`), unlike `drop_nulls` which has both forms. Recorded in the
   audit.

## Not ported (Step 4 exclusions)

- The overwhelming majority of `test_pivot.py` (48 tests) and `test_concat.py` (36 tests) —
  categorical/struct/temporal-logical-type pivot edge cases, `hypothesis`-adjacent associativity
  sweeps (`test_concat_align_associativity_26788`, `@pytest.mark.slow`), pandas/pyarrow interop
  (`test_concat_multiple_parquet_inmem`'s `use_pyarrow=True` branch), and Python-object-identity
  checks (`test_concat_single_element`'s `result is df`, which has no Julia equivalent — our
  values-equal check is the idiomatic substitute and wasn't worth a dedicated assertion given
  `concat`'s other single-frame-input coverage already in place).
- `test_with_columns_invalid_type`, `test_select_args_kwargs`'s keyword-argument forms
  (`ldf.select(oof="foo")`), `test_lazy_with_columns_to_select_28285` — all exercise Python's
  `**kwargs`-based column naming or duck-typed argument coercion, which has no Julia-idiomatic
  analogue (dynamic keyword names aren't a natural fit); this is the Step-4 "argument-type overload
  we don't have" exclusion, not a gap.
- `test_filter_expand_20014` (multiple positional predicates ANDed via `df.filter(p1, p2, p3)`) —
  our `filter(df, expr)` takes exactly one predicate `Expr`; the equivalent multi-predicate form
  already works via manual `&` (see the existing `"filter with combined predicates"` testset), so
  this is a convenience-surface gap already covered functionally, not a missing capability worth a
  dedicated `@test_broken`.
- `test_filter_is_in_4572`, `test_filter_aggregation_any`, `test_filter_group_aware_17030`,
  `test_filter_group_by_23681`, `test_invalid_filter_18295` — these exercise `Expr.filter()` (the
  per-expression method used inside `group_by().agg(...)`), a *different* function from this
  batch's frame-level `Base.filter(df, expr)` (Step 9: don't conflate same-named functions). Out of
  this batch's scope; would belong wherever `Expr.filter`'s own tests live if ported.
- `test_filter_horizontal_selector_15428` (`cs.matches(...) & cs.integer() <= 2` as a filter
  predicate) — our `Selector` type doesn't overload comparison operators the way upstream's
  selector-as-expression combinators do (`isless(::Polars.Selector, ::Int64)` has no method,
  confirmed live); would need new capability on `Selector`, not attempted.
- `test_pivot_invalid` (calling `pivot` with too few arguments to determine index/values) — our
  `pivot(df, on, index, values)` requires all three positionally, so the invalid call upstream
  tests (missing `index`/`values` entirely) can't even be constructed here; Julia's dispatch
  enforces it structurally (`MethodError`) rather than at runtime, so there's no equivalent runtime
  path to assert against.
- `test_concat_horizontal_zero_width_height_mismatch_26876` — exercises a frame with nonzero row
  count but zero columns, which cannot be constructed in this wrapper (a 0-column frame always
  collapses to 0 rows too, confirmed live via `drop(df, allcolumns)` — "no columns to carry a row
  count" per this repo's own existing comments); not portable.
- `test_rename_invalidate_cache_15884`, `test_rename_schema_order_6660`, `test_rename_schema_17427`,
  `test_transpose_name_from_column_13777`, `test_transpose_multiple_chunks`,
  `test_nested_struct_transpose_21923` — internal query-optimizer cache-invalidation and
  schema-consistency checks, or exercise upstream-only `column_names=` (deriving new column names
  from an existing column's row values), which this wrapper's `transpose` docstring already
  documents as unsupported.
- The remaining `test_pivot.py`/`test_unpivot.py` categorical/struct/temporal-dtype tests
  (`test_pivot_categorical_3968`, `test_pivot_struct_13120`, `test_unpivot_categorical`, etc.) —
  each just re-confirms pivot/unpivot's already-tested reshaping logic under a different column
  dtype; no new behavior to assert once the shape/null-handling fixtures above are in place.

## Resolved non-issues (verified before assuming a bug)

- `rename`'s simultaneous-swap semantics (`{"a": "b", "b": "a"}`) were unverified going in — a
  naively sequential implementation could plausibly collide (renaming `a`→`b` while `b` still
  exists) or silently duplicate. Live-checked: both apply against the original schema at once,
  matching upstream exactly.
- `unpivot`'s `on=[]` (explicit empty list) was suspected of possibly diverging the same way
  `drop_nulls`'s `subset=[]` does (see gap 2 above) — checked live and it does **not**: `on=[]`
  behaves identically to `on` unspecified (melt every non-index column) in *both* implementations,
  matching upstream's own `@pytest.mark.parametrize("on", [[], ["b"], None])` treating `[]` and
  `None` as equivalent. Not every empty-vs-unspecified-list case is a divergence; each needed its
  own live check rather than a blanket assumption from the `drop_nulls` case.
- `concat`'s `:horizontal` mode with a 0-row/0-column frame in the mix was suspected of a
  shape-mismatch abort-safety gap (mirroring `test_concat_horizontal_zero_width_height_mismatch_26876`)
  — checked live and found not portable at all (see Not ported above) rather than either broken or
  fixed.

## Infrastructure note (not a parity finding, logged for visibility)

A full `Pkg.test()` run on this branch (freshly branched off `origin/main`, no Rust/Cargo changes)
errors on 8 pre-existing testsets unrelated to this batch: `fill_null`/`cast`/frame-level
aggregations (`frame_verbs.jl`), `top_k`/`bottom_k`/`slice` (`sort.jl`), `len`
(`expr/aggregation.jl`), `concat_str`/`concat_list` (`expr/horizontal.jl`) — all
`could not load symbol "polars_lazy_frame_..."` from `libpolars.so`. `src/api/generated.jl` on
`main` already references FFI symbols the currently-published `Artifacts.toml`-pinned binary
doesn't export — the exact "invisible until a new libpolars release is cut" hazard `CLAUDE.md`
documents. Confirmed unrelated to this batch by running only this batch's own testsets in
isolation: 285 passed, 0 failed, 3 broken (exactly the three `@test_broken` divergences above, no
more). See `plans/parity/api_gap_audit.md`'s Group 11 for the full note; a new artifact release is
needed to clear this, out of scope for a no-Cargo-change PR.
