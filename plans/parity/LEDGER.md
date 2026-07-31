# py-polars test-parity ledger

## Status

**Sweep in progress.** Baseline (before this sweep): 1863 passed, 0 failed, 2 errored, 2 broken —
the 2 errors were `UndefVarError`s from Batch 0's Wave-1 tests calling FFI symbols
(`polars_expr_arccos`, `polars_expr_rle`) that existed in the built `.so` but not yet in
`src/api/generated.jl`. **Batch 0 is now done**: the `api-wave1-unary-fns` branch finished
independently (commits `a763de6`..`446c320`) with the header/bindings regen, the `rle`/`arccos`
upstream-fixture ports, `log`'s argument-order fix, and `get_column`'s `default` keyword all
already landed — better than this sweep's own draft, which was discarded in favor of it (see
`c50542b API gap batch four Wave 1: unary math/rle exprs, item/get_column, log arg order` and
`dc8ac24`/`446c320`). This worktree was reset onto that branch as its new base; only Batch 1's
work (below) is layered on top of it. The 2 broken are the pre-existing deliberate exclusions
(Aqua ambiguities, `Strings.titlecase`) from `plans/test_porting.md`.

This ledger is generated (one row per exported name, from `names(Polars)` /
`names(Polars.Lists/.Strings/.Dt/.Structs/.Selectors)`, 200 names total) then refined per batch as
the sweep actually reads each test file against its upstream counterpart — see
`.claude/skills/pypolars-test-parity/SKILL.md` for the procedure. "our test file(s)" below is
grep-derived (word-boundary match against the exported name) and may include incidental
mentions, not just primary coverage; each batch corrects this for the functions it actually
sweeps. Status values: `unswept` (not yet reached) / `covered` (upstream fixtures ported, nothing
to fix) / `gaps-filled` (test and/or source patched) / `broken-flagged` (divergence found, needs a
Rust/FFI change, `@test_broken` + note added) / `n-a` (no py-polars counterpart, e.g. internal
combinators).

## Batch order

See `plans/pypolars_test_parity_recipe.md` for the methodology. Batches, in sweep order (no-Rust-
rebuild batches first per session instruction; Batch 0 needs `src/api/generated.jl` regenerated
from the already-regenerated header before its 2 errors can even run):

| # | Our test files | Upstream sources | Status |
|---|---|---|---|
| 1 | expr/math.jl, expr/arithmetic.jl | operations/arithmetic/test_arithmetic.py, test_pow.py, test_neg.py, operations/test_abs.py, test_clip.py | unswept — see separate Batch 1 PR |
| 2 | expr/aggregation.jl, expr/statistics.jl | operations/aggregation/test_aggregations.py, test_vertical.py, operations/test_statistics.py | unswept |
| 3 | expr/null_handling.jl | operations/test_fill_null.py, test_is_null.py, test_has_nulls.py, test_drop_nulls.py | unswept |
| 4 | expr/order_window.jl, expr/over.jl | operations/test_over.py, test_window.py, test_shift.py, test_diff.py, test_pct_change.py, test_interpolate.py, test_rank.py, functions/test_cum_count.py | unswept |
| 5 | expr/sort_top_k.jl, expr/is_unique_dup.jl, operations/sort.jl, operations/unique.jl | operations/test_sort.py, test_top_k.py, test_is_first_last_distinct.py, unique/test_unique.py, test_n_unique.py, test_is_unique.py | unswept |
| 6 | expr/replace.jl, expr/when_then_otherwise.jl, expr/literals_cast.jl, expr/lit_vector.jl | operations/test_replace.py, test_replace_strict.py, operations/test_cast.py, functions/test_when_then.py, functions/test_lit.py, expr/test_literal.py | unswept |
| 7 | datatypes/strings.jl | operations/namespaces/string/test_string.py, test_pad.py, test_concat.py, operations/namespaces/test_strptime.py | unswept |
| 8 | datatypes/datetimes.jl, times.jl, durations.jl, timezones.jl | operations/namespaces/temporal/test_datetime.py, test_offset_by.py, test_round.py, test_truncate.py, test_replace.py, datatypes/test_temporal.py, test_duration.py, test_time.py | **done** — see `plans/parity/batch-8-temporal.md` (commit `2f2467f`); two fixtures ported, one gap cross-referenced to Batch 6, durations.jl/timezones.jl already adequately covered |
| 9 | datatypes/lists.jl, structs.jl, list_struct_write.jl, operations/reshape.jl (explode) | operations/namespaces/list/test_list.py, test_set_operations.py, test_unique.py, operations/namespaces/test_struct.py, datatypes/test_list.py, test_struct.py, operations/test_explode.py | **done** — see `plans/parity/batch-9-lists-structs.md`; 11 fixtures ported, 3 sizeable gaps flagged (most of `Lists` namespace missing incl. all set operations, `explode`'s `empty_as_null`/`keep_nulls` kwargs, `Structs.with_fields`/`json_encode`) |
| 10 | operations/frame_verbs.jl, reshape.jl, concat.jl, select_with_columns.jl, filter.jl | operations/test_pivot.py, test_unpivot.py, test_transpose.py, test_drop.py, test_rename.py, test_select.py, test_with_columns.py, test_filter.py, functions/test_concat.py, dataframe/test_vstack.py, test_upsample.py | unswept |
| 11 | operations/join.jl, group_by.jl, group_by_dynamic.jl | operations/test_join.py, test_join_asof.py, test_join_right.py, test_cross_join.py, test_group_by.py, test_group_by_dynamic.py, operations/rolling/test_rolling.py | unswept |
| 12 | datatypes/series.jl, binary.jl, dataframe/construction.jl, io.jl, describe.jl | series/test_series.py, test_getitem.py, test_to_list.py, dataframe/test_df.py, test_shape.py, test_describe.py, datatypes/test_binary.py, test_null.py, constructors/test_constructors.py | unswept |
| 13 | lazyframe/scan_*.jl, sink_*.jl, collect_schema.jl, head.jl | io/test_csv.py, test_parquet.py, test_ipc.py, test_lazy_csv.py, test_lazy_parquet.py, test_lazy_ipc.py, test_scan_options.py, io/test_sink.py, lazyframe/test_collect_schema.py | unswept |
| 14 | expr/selectors.jl, meta.jl, horizontal.jl, naming.jl, sample.jl, curried_forms.jl, misc.jl | operations/test_selectors.py, namespaces/test_meta.py, test_name.py, functions/test_horizontal.py, operations/aggregation/test_horizontal.py, operations/test_random.py, functions/test_col.py, functions/test_nth.py | unswept |
| 0 | expr/order_window.jl, expr/arithmetic.jl, operations/frame_verbs.jl | operations/test_rle.py, series/test_series.py (trig), expr/test_exprs.py, dataframe/test_df.py, test_item.py, series/test_item.py | **done** — landed independently on `api-wave1-unary-fns` (commits `c50542b`/`dc8ac24`/`446c320`), this worktree now based on it |

Out of scope (no counterpart here): upstream `sql/`, `streaming/`, `interop/`, `interchange/`,
`ml/`, `io/database/`, `io/cloud/`, `operations/map/`, `testing/parametric/`.

## Per-function skeleton


### Polars

| function | our test file(s) | status |
|---|---|---|
| `DataFrame` | aqua.jl, dataframe/construction.jl, dataframe/describe.jl, dataframe/gc.jl, dataframe/io.jl, datatypes/binary.jl, datatypes/datetimes.jl, datatypes/durations.jl, datatypes/list_struct_write.jl, datatypes/lists.jl, datatypes/series.jl, datatypes/strings.jl, datatypes/structs.jl, datatypes/times.jl, datatypes/timezones.jl, expr/aggregation.jl, expr/arithmetic.jl, expr/curried_forms.jl, expr/horizontal.jl, expr/is_unique_dup.jl, expr/lit_vector.jl, expr/literals_cast.jl, expr/math.jl, expr/naming.jl, expr/null_handling.jl, expr/order_window.jl, expr/over.jl, expr/replace.jl, expr/sample.jl, expr/selectors.jl, expr/sort_top_k.jl, expr/statistics.jl, expr/when_then_otherwise.jl, lazyframe/collect_schema.jl, lazyframe/head.jl, lazyframe/lazy_vs_eager.jl, lazyframe/scan_csv.jl, lazyframe/scan_ipc.jl, lazyframe/scan_parquet.jl, lazyframe/sink_csv.jl, lazyframe/sink_ipc.jl, lazyframe/sink_parquet.jl, misc.jl, misc_ffi_safety.jl, operations/concat.jl, operations/empty.jl, operations/filter.jl, operations/frame_verbs.jl, operations/group_by.jl, operations/join.jl, operations/reshape.jl, operations/select_with_columns.jl, operations/sort.jl, operations/unique.jl | unswept |
| `Dt` | datatypes/datetimes.jl, datatypes/durations.jl, datatypes/strings.jl, datatypes/times.jl, datatypes/timezones.jl, expr/curried_forms.jl, expr/meta.jl, misc_ffi_safety.jl | unswept |
| `Lists` | datatypes/lists.jl, expr/curried_forms.jl, expr/meta.jl, expr/selectors.jl | unswept |
| `PolarsError` | datatypes/series.jl, datatypes/strings.jl, datatypes/structs.jl, expr/horizontal.jl, expr/meta.jl, expr/replace.jl, expr/selectors.jl, lazyframe/scan_parquet.jl, misc.jl, operations/frame_verbs.jl, operations/reshape.jl, operations/select_with_columns.jl | unswept |
| `Selectors` | expr/meta.jl, expr/selectors.jl | unswept |
| `Series` | datatypes/binary.jl, datatypes/list_struct_write.jl, datatypes/series.jl, expr/literals_cast.jl, misc_ffi_safety.jl, operations/frame_verbs.jl | unswept |
| `Strings` | datatypes/strings.jl, expr/curried_forms.jl, expr/meta.jl, expr/selectors.jl, operations/sort.jl | unswept |
| `Structs` | datatypes/list_struct_write.jl, datatypes/structs.jl, expr/horizontal.jl, expr/meta.jl, expr/selectors.jl, misc_ffi_safety.jl | unswept |
| `add` | expr/arithmetic.jl | unswept |
| `agg` | datatypes/lists.jl, expr/sort_top_k.jl, lazyframe/lazy_vs_eager.jl, lazyframe/scan_csv.jl, lazyframe/scan_parquet.jl, operations/empty.jl, operations/group_by.jl, operations/group_by_dynamic.jl, operations/reshape.jl, operations/select_with_columns.jl, operations/unique.jl | unswept |
| `alias` | datatypes/datetimes.jl, datatypes/durations.jl, datatypes/lists.jl, datatypes/series.jl, datatypes/strings.jl, datatypes/times.jl, datatypes/timezones.jl, expr/aggregation.jl, expr/arithmetic.jl, expr/curried_forms.jl, expr/horizontal.jl, expr/is_unique_dup.jl, expr/lit_vector.jl, expr/literals_cast.jl, expr/math.jl, expr/meta.jl, expr/naming.jl, expr/null_handling.jl, expr/order_window.jl, expr/over.jl, expr/replace.jl, expr/sample.jl, expr/selectors.jl, expr/sort_top_k.jl, expr/statistics.jl, expr/when_then_otherwise.jl, lazyframe/collect_schema.jl, lazyframe/lazy_vs_eager.jl, lazyframe/scan_parquet.jl, lazyframe/sink_csv.jl, lazyframe/sink_ipc.jl, lazyframe/sink_parquet.jl, misc_ffi_safety.jl, operations/group_by.jl, operations/reshape.jl, operations/select_with_columns.jl, operations/unique.jl | unswept |
| `all_horizontal` | expr/horizontal.jl | unswept |
| `and` | aqua.jl, dataframe/construction.jl, dataframe/gc.jl, dataframe/io.jl, datatypes/binary.jl, datatypes/durations.jl, datatypes/lists.jl, datatypes/series.jl, datatypes/structs.jl, datatypes/times.jl, expr/arithmetic.jl, expr/literals_cast.jl, expr/meta.jl, expr/naming.jl, expr/over.jl, expr/selectors.jl, expr/sort_top_k.jl, expr/when_then_otherwise.jl, lazyframe/collect_schema.jl, lazyframe/lazy_vs_eager.jl, lazyframe/scan_csv.jl, lazyframe/scan_ipc.jl, lazyframe/scan_parquet.jl, lazyframe/sink_csv.jl, lazyframe/sink_ipc.jl, lazyframe/sink_parquet.jl, misc.jl, misc_ffi_safety.jl, operations/concat.jl, operations/empty.jl, operations/filter.jl, operations/frame_verbs.jl, operations/group_by_dynamic.jl, operations/join.jl, operations/reshape.jl | unswept |
| `antijoin` | operations/join.jl | unswept |
| `any_horizontal` | expr/horizontal.jl | unswept |
| `arccos` | expr/arithmetic.jl | unswept |
| `arg_max` | datatypes/lists.jl, expr/aggregation.jl | unswept |
| `arg_min` | datatypes/lists.jl, expr/aggregation.jl | unswept |
| `arg_sort` | expr/curried_forms.jl, expr/sort_top_k.jl | unswept |
| `as_struct` | datatypes/series.jl, datatypes/times.jl, expr/horizontal.jl, operations/unique.jl | unswept |
| `cast` | datatypes/durations.jl, datatypes/times.jl, expr/literals_cast.jl, expr/selectors.jl, misc.jl, misc_ffi_safety.jl, operations/concat.jl, operations/reshape.jl | unswept |
| `cast_categorical` | expr/literals_cast.jl, expr/selectors.jl | unswept |
| `cast_datetime` | expr/literals_cast.jl | unswept |
| `cast_decimal` | expr/literals_cast.jl, expr/selectors.jl | unswept |
| `cast_duration` | expr/literals_cast.jl | unswept |
| `clip` | expr/curried_forms.jl, expr/math.jl | unswept |
| `col` | dataframe/construction.jl, datatypes/datetimes.jl, datatypes/durations.jl, datatypes/list_struct_write.jl, datatypes/lists.jl, datatypes/series.jl, datatypes/strings.jl, datatypes/structs.jl, datatypes/times.jl, datatypes/timezones.jl, expr/aggregation.jl, expr/arithmetic.jl, expr/curried_forms.jl, expr/horizontal.jl, expr/is_unique_dup.jl, expr/lit_vector.jl, expr/literals_cast.jl, expr/math.jl, expr/meta.jl, expr/naming.jl, expr/null_handling.jl, expr/order_window.jl, expr/over.jl, expr/replace.jl, expr/sample.jl, expr/selectors.jl, expr/sort_top_k.jl, expr/statistics.jl, expr/when_then_otherwise.jl, lazyframe/collect_schema.jl, lazyframe/lazy_vs_eager.jl, lazyframe/scan_csv.jl, lazyframe/scan_parquet.jl, lazyframe/sink_csv.jl, lazyframe/sink_ipc.jl, lazyframe/sink_parquet.jl, misc.jl, misc_ffi_safety.jl, operations/empty.jl, operations/filter.jl, operations/frame_verbs.jl, operations/group_by.jl, operations/group_by_dynamic.jl, operations/join.jl, operations/reshape.jl, operations/select_with_columns.jl, operations/sort.jl, operations/unique.jl | unswept |
| `collect_schema` | lazyframe/collect_schema.jl, lazyframe/lazy_vs_eager.jl, runtests.jl | unswept |
| `concat` | lazyframe/collect_schema.jl, operations/concat.jl, operations/frame_verbs.jl, runtests.jl | unswept |
| `crossjoin` | operations/join.jl | unswept |
| `cum_count` | expr/curried_forms.jl, expr/order_window.jl | unswept |
| `cum_max` | expr/curried_forms.jl, expr/order_window.jl | unswept |
| `cum_min` | expr/curried_forms.jl, expr/order_window.jl | unswept |
| `cum_prod` | expr/curried_forms.jl, expr/order_window.jl | unswept |
| `cum_sum` | expr/curried_forms.jl, expr/order_window.jl | unswept |
| `degrees` | expr/arithmetic.jl | unswept |
| `describe` | dataframe/describe.jl, runtests.jl | unswept |
| `drop` | dataframe/gc.jl, expr/order_window.jl, misc_ffi_safety.jl, operations/frame_verbs.jl | unswept |
| `drop_nans` | expr/aggregation.jl | unswept |
| `drop_nulls` | expr/aggregation.jl, operations/frame_verbs.jl | unswept |
| `element` | dataframe/construction.jl, datatypes/binary.jl, datatypes/list_struct_write.jl, datatypes/series.jl, datatypes/times.jl, expr/aggregation.jl, expr/lit_vector.jl, expr/selectors.jl, expr/statistics.jl, misc_ffi_safety.jl, operations/reshape.jl | unswept |
| `eq` | expr/arithmetic.jl | unswept |
| `explode` | dataframe/construction.jl, operations/reshape.jl | unswept |
| `fill_nan` | expr/curried_forms.jl, expr/null_handling.jl | unswept |
| `fill_null` | expr/curried_forms.jl, expr/null_handling.jl | unswept |
| `flatten` | datatypes/list_struct_write.jl, expr/aggregation.jl, operations/reshape.jl | unswept |
| `get_column` | operations/frame_verbs.jl | unswept |
| `group_by` | datatypes/lists.jl, expr/sort_top_k.jl, lazyframe/lazy_vs_eager.jl, lazyframe/scan_csv.jl, lazyframe/scan_parquet.jl, operations/empty.jl, operations/group_by.jl, operations/reshape.jl, operations/select_with_columns.jl, operations/unique.jl, runtests.jl | unswept |
| `group_by_dynamic` | operations/group_by_dynamic.jl, runtests.jl | unswept |
| `gt` | expr/arithmetic.jl | unswept |
| `head` | datatypes/lists.jl, datatypes/series.jl, datatypes/strings.jl, expr/curried_forms.jl, lazyframe/head.jl, lazyframe/scan_parquet.jl, operations/frame_verbs.jl, runtests.jl | unswept |
| `hstack` | operations/frame_verbs.jl | unswept |
| `implode` | datatypes/lists.jl, datatypes/series.jl, datatypes/times.jl, expr/aggregation.jl, expr/curried_forms.jl, expr/lit_vector.jl, expr/null_handling.jl, operations/reshape.jl | unswept |
| `innerjoin` | datatypes/durations.jl, datatypes/times.jl, operations/join.jl, operations/select_with_columns.jl | unswept |
| `interpolate` | expr/curried_forms.jl, expr/null_handling.jl | unswept |
| `is_duplicated` | expr/is_unique_dup.jl, operations/unique.jl | unswept |
| `is_finite` | expr/aggregation.jl | unswept |
| `is_in` | expr/curried_forms.jl, expr/lit_vector.jl, expr/null_handling.jl | unswept |
| `is_infinite` | expr/aggregation.jl | unswept |
| `is_nan` | expr/aggregation.jl | unswept |
| `is_not_null` | expr/aggregation.jl | unswept |
| `is_null` | expr/aggregation.jl, operations/filter.jl | unswept |
| `is_unique` | expr/is_unique_dup.jl, operations/unique.jl | unswept |
| `join_asof` | operations/join.jl | unswept |
| `keep_name` | expr/aggregation.jl, expr/naming.jl | unswept |
| `lazy` | dataframe/io.jl, datatypes/lists.jl, datatypes/series.jl, expr/order_window.jl, expr/over.jl, expr/selectors.jl, expr/sort_top_k.jl, lazyframe/collect_schema.jl, lazyframe/head.jl, lazyframe/lazy_vs_eager.jl, lazyframe/scan_ipc.jl, lazyframe/sink_csv.jl, lazyframe/sink_ipc.jl, lazyframe/sink_parquet.jl, misc_ffi_safety.jl, operations/concat.jl, operations/empty.jl, operations/filter.jl, operations/frame_verbs.jl, operations/group_by.jl, operations/group_by_dynamic.jl, operations/join.jl, operations/reshape.jl, operations/select_with_columns.jl, operations/sort.jl, operations/unique.jl | unswept |
| `leftjoin` | operations/join.jl | unswept |
| `lit` | datatypes/datetimes.jl, datatypes/lists.jl, datatypes/strings.jl, datatypes/structs.jl, expr/arithmetic.jl, expr/curried_forms.jl, expr/lit_vector.jl, expr/literals_cast.jl, expr/math.jl, expr/meta.jl, expr/null_handling.jl, expr/order_window.jl, expr/replace.jl, expr/sort_top_k.jl, expr/when_then_otherwise.jl, misc_ffi_safety.jl, operations/reshape.jl | unswept |
| `max_horizontal` | expr/horizontal.jl | unswept |
| `mean` | dataframe/describe.jl, datatypes/lists.jl, expr/aggregation.jl, expr/null_handling.jl, operations/group_by.jl, operations/reshape.jl | unswept |
| `mean_horizontal` | expr/horizontal.jl | unswept |
| `median` | expr/aggregation.jl | unswept |
| `min_horizontal` | expr/horizontal.jl | unswept |
| `mul` | expr/arithmetic.jl | unswept |
| `n_unique` | expr/aggregation.jl, operations/group_by.jl, operations/unique.jl | unswept |
| `names` | dataframe/construction.jl, datatypes/series.jl, datatypes/strings.jl, expr/meta.jl, expr/naming.jl, expr/over.jl, expr/selectors.jl, lazyframe/collect_schema.jl, lazyframe/lazy_vs_eager.jl, misc_ffi_safety.jl, operations/concat.jl, operations/frame_verbs.jl, operations/reshape.jl | unswept |
| `nan_max` | expr/aggregation.jl | unswept |
| `nan_min` | expr/aggregation.jl | unswept |
| `not` | dataframe/construction.jl, dataframe/gc.jl, dataframe/io.jl, datatypes/durations.jl, datatypes/list_struct_write.jl, datatypes/series.jl, datatypes/strings.jl, datatypes/structs.jl, datatypes/times.jl, expr/arithmetic.jl, expr/literals_cast.jl, expr/meta.jl, expr/naming.jl, expr/order_window.jl, expr/over.jl, expr/replace.jl, expr/selectors.jl, expr/sort_top_k.jl, lazyframe/collect_schema.jl, lazyframe/lazy_vs_eager.jl, lazyframe/scan_parquet.jl, lazyframe/sink_csv.jl, lazyframe/sink_ipc.jl, lazyframe/sink_parquet.jl, misc_ffi_safety.jl, operations/filter.jl, operations/frame_verbs.jl, operations/group_by_dynamic.jl, operations/join.jl, operations/reshape.jl, operations/sort.jl, operations/unique.jl | unswept |
| `nth` | expr/literals_cast.jl, expr/selectors.jl | unswept |
| `null_count` | dataframe/describe.jl, datatypes/series.jl, expr/aggregation.jl | unswept |
| `or` | dataframe/gc.jl, datatypes/lists.jl, expr/arithmetic.jl, lazyframe/scan_parquet.jl, misc_ffi_safety.jl, operations/filter.jl, operations/join.jl, operations/select_with_columns.jl | unswept |
| `outerjoin` | operations/join.jl | unswept |
| `over` | dataframe/construction.jl, dataframe/io.jl, datatypes/durations.jl, datatypes/times.jl, expr/arithmetic.jl, expr/order_window.jl, expr/over.jl, lazyframe/sink_csv.jl, lazyframe/sink_ipc.jl, operations/empty.jl, operations/reshape.jl, operations/select_with_columns.jl, runtests.jl | unswept |
| `pct_change` | expr/curried_forms.jl, expr/order_window.jl | unswept |
| `pivot` | operations/reshape.jl | unswept |
| `pow` | expr/arithmetic.jl | unswept |
| `prefix` | expr/naming.jl, misc_ffi_safety.jl | unswept |
| `quantile` | expr/curried_forms.jl, expr/statistics.jl | unswept |
| `radians` | expr/arithmetic.jl | unswept |
| `rank` | expr/curried_forms.jl, expr/order_window.jl | unswept |
| `read_csv` | dataframe/io.jl, lazyframe/scan_csv.jl, lazyframe/sink_csv.jl | unswept |
| `read_ipc` | lazyframe/scan_ipc.jl, lazyframe/sink_ipc.jl | unswept |
| `read_parquet` | dataframe/io.jl, datatypes/binary.jl, datatypes/list_struct_write.jl, datatypes/structs.jl, lazyframe/scan_parquet.jl, lazyframe/sink_parquet.jl, misc_ffi_safety.jl | unswept |
| `read_series` | datatypes/series.jl | unswept |
| `rename` | expr/naming.jl, misc_ffi_safety.jl, operations/frame_verbs.jl | unswept |
| `replace_strict` | expr/curried_forms.jl, expr/replace.jl | unswept |
| `rightjoin` | operations/join.jl | unswept |
| `rle` | expr/order_window.jl | unswept |
| `rle_id` | expr/order_window.jl | unswept |
| `rolling` | operations/group_by_dynamic.jl | unswept |
| `sample_frac` | expr/curried_forms.jl, expr/sample.jl | unswept |
| `sample_n` | expr/curried_forms.jl, expr/sample.jl | unswept |
| `scan_csv` | lazyframe/scan_csv.jl, lazyframe/scan_parquet.jl, misc_ffi_safety.jl, runtests.jl | unswept |
| `scan_ipc` | datatypes/times.jl, lazyframe/scan_ipc.jl, lazyframe/scan_parquet.jl, lazyframe/sink_ipc.jl, runtests.jl | unswept |
| `scan_parquet` | datatypes/times.jl, lazyframe/scan_parquet.jl, misc_ffi_safety.jl, runtests.jl | unswept |
| `select` | dataframe/construction.jl, datatypes/datetimes.jl, datatypes/durations.jl, datatypes/list_struct_write.jl, datatypes/lists.jl, datatypes/series.jl, datatypes/strings.jl, datatypes/structs.jl, datatypes/times.jl, datatypes/timezones.jl, expr/aggregation.jl, expr/arithmetic.jl, expr/curried_forms.jl, expr/horizontal.jl, expr/is_unique_dup.jl, expr/lit_vector.jl, expr/literals_cast.jl, expr/math.jl, expr/naming.jl, expr/null_handling.jl, expr/order_window.jl, expr/replace.jl, expr/sample.jl, expr/selectors.jl, expr/sort_top_k.jl, expr/statistics.jl, expr/when_then_otherwise.jl, lazyframe/sink_csv.jl, lazyframe/sink_ipc.jl, lazyframe/sink_parquet.jl, misc.jl, misc_ffi_safety.jl, operations/empty.jl, operations/frame_verbs.jl, operations/reshape.jl, operations/select_with_columns.jl, operations/unique.jl | unswept |
| `semijoin` | operations/join.jl | unswept |
| `shift` | expr/curried_forms.jl, expr/order_window.jl | unswept |
| `sink_csv` | lazyframe/scan_parquet.jl, lazyframe/sink_csv.jl, runtests.jl | unswept |
| `sink_ipc` | lazyframe/scan_parquet.jl, lazyframe/sink_ipc.jl, runtests.jl | unswept |
| `sink_parquet` | lazyframe/scan_parquet.jl, lazyframe/sink_parquet.jl, runtests.jl | unswept |
| `sort_by` | expr/sort_top_k.jl, operations/select_with_columns.jl | unswept |
| `std` | dataframe/describe.jl, expr/curried_forms.jl, expr/statistics.jl | unswept |
| `sub` | datatypes/series.jl, expr/arithmetic.jl | unswept |
| `suffix` | expr/naming.jl | unswept |
| `sum_horizontal` | expr/horizontal.jl | unswept |
| `tail` | datatypes/strings.jl, expr/curried_forms.jl, misc_ffi_safety.jl, operations/frame_verbs.jl | unswept |
| `to_lowercase` | expr/naming.jl | unswept |
| `to_uppercase` | expr/naming.jl | unswept |
| `top_k` | expr/curried_forms.jl, expr/sort_top_k.jl | unswept |
| `transpose` | operations/reshape.jl | unswept |
| `unnest` | operations/reshape.jl | unswept |
| `unpivot` | operations/reshape.jl | unswept |
| `upsample` | operations/frame_verbs.jl | unswept |
| `value_counts` | datatypes/structs.jl, expr/curried_forms.jl, expr/sort_top_k.jl, misc_ffi_safety.jl | unswept |
| `var` | expr/curried_forms.jl, expr/statistics.jl, operations/reshape.jl | unswept |
| `vstack` | operations/frame_verbs.jl | unswept |
| `when` | expr/when_then_otherwise.jl, misc_ffi_safety.jl, operations/reshape.jl | unswept |
| `with_columns` | expr/literals_cast.jl, expr/order_window.jl, expr/over.jl, expr/selectors.jl, lazyframe/collect_schema.jl, lazyframe/lazy_vs_eager.jl, operations/reshape.jl, operations/select_with_columns.jl | unswept |
| `with_row_index` | misc_ffi_safety.jl, operations/frame_verbs.jl | unswept |
| `write_csv` | dataframe/io.jl, lazyframe/scan_csv.jl, lazyframe/sink_csv.jl, misc_ffi_safety.jl | unswept |
| `write_ipc` | datatypes/times.jl, lazyframe/scan_ipc.jl, lazyframe/sink_ipc.jl | unswept |
| `write_parquet` | dataframe/io.jl, datatypes/binary.jl, datatypes/times.jl, lazyframe/scan_parquet.jl, lazyframe/sink_parquet.jl, misc_ffi_safety.jl | unswept |

### Lists

| function | our test file(s) | status |
|---|---|---|
| `arg_max` | datatypes/lists.jl, expr/aggregation.jl | unswept |
| `arg_min` | datatypes/lists.jl, expr/aggregation.jl | unswept |
| `lengths` | datatypes/lists.jl, operations/sort.jl | unswept |
| `mean` | dataframe/describe.jl, datatypes/lists.jl, expr/aggregation.jl, expr/null_handling.jl, operations/group_by.jl, operations/reshape.jl | unswept |
| `unique_stable` | datatypes/lists.jl | unswept |

### Strings

| function | our test file(s) | status |
|---|---|---|
| `contains_literal` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `count_matches` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `ends_with` | datatypes/strings.jl, expr/curried_forms.jl, expr/selectors.jl | unswept |
| `extract` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `extract_all` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `len_bytes` | datatypes/strings.jl | unswept |
| `len_chars` | datatypes/strings.jl, operations/sort.jl | unswept |
| `replace_all` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `slice` | datatypes/series.jl, datatypes/strings.jl, expr/curried_forms.jl, misc_ffi_safety.jl | unswept |
| `starts_with` | datatypes/strings.jl, expr/curried_forms.jl, expr/selectors.jl | unswept |
| `strip_chars` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `strip_prefix` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `strip_suffix` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `to_date` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `to_datetime` | datatypes/strings.jl, expr/curried_forms.jl | unswept |
| `zfill` | datatypes/strings.jl, expr/curried_forms.jl | unswept |

### Dt

| function | our test file(s) | status |
|---|---|---|
| `convert_time_zone` | datatypes/timezones.jl | unswept |
| `date` | dataframe/describe.jl, datatypes/datetimes.jl, datatypes/series.jl, datatypes/strings.jl, datatypes/times.jl, expr/curried_forms.jl, expr/literals_cast.jl, expr/selectors.jl | unswept |
| `day` | datatypes/datetimes.jl, datatypes/strings.jl, expr/literals_cast.jl | unswept |
| `hour` | datatypes/datetimes.jl, datatypes/timezones.jl | unswept |
| `minute` | datatypes/datetimes.jl | unswept |
| `month` | datatypes/datetimes.jl, datatypes/strings.jl | unswept |
| `offset_by` | datatypes/datetimes.jl, expr/curried_forms.jl | unswept |
| `ordinal_day` | datatypes/datetimes.jl | unswept |
| `replace_time_zone` | datatypes/timezones.jl, misc_ffi_safety.jl | unswept |
| `second` | datatypes/datetimes.jl, datatypes/structs.jl, operations/reshape.jl | unswept |
| `strftime` | datatypes/datetimes.jl, expr/curried_forms.jl | unswept |
| `total_days` | datatypes/durations.jl | unswept |
| `total_hours` | datatypes/durations.jl | unswept |
| `total_microseconds` | datatypes/durations.jl | unswept |
| `total_milliseconds` | datatypes/durations.jl | unswept |
| `total_minutes` | datatypes/durations.jl | unswept |
| `total_nanoseconds` | datatypes/durations.jl | unswept |
| `total_seconds` | datatypes/durations.jl | unswept |
| `weekday` | datatypes/datetimes.jl | unswept |
| `year` | datatypes/datetimes.jl, datatypes/strings.jl, lazyframe/scan_parquet.jl, lazyframe/sink_ipc.jl | unswept |

### Structs

| function | our test file(s) | status |
|---|---|---|
| `field_by_index` | datatypes/structs.jl | unswept |
| `field_by_name` | datatypes/list_struct_write.jl, datatypes/structs.jl, expr/horizontal.jl, misc_ffi_safety.jl | unswept |
| `rename_fields` | datatypes/structs.jl, misc_ffi_safety.jl | unswept |

### Selectors

| function | our test file(s) | status |
|---|---|---|
| `array` | dataframe/construction.jl, dataframe/gc.jl, expr/literals_cast.jl, expr/selectors.jl, misc_ffi_safety.jl | unswept |
| `binary` | datatypes/binary.jl, datatypes/series.jl, expr/arithmetic.jl, expr/curried_forms.jl, expr/meta.jl, expr/selectors.jl, misc_ffi_safety.jl, runtests.jl | unswept |
| `boolean` | expr/arithmetic.jl, expr/selectors.jl | unswept |
| `by_dtype` | expr/selectors.jl | unswept |
| `by_index` | expr/selectors.jl | unswept |
| `by_name` | expr/selectors.jl | unswept |
| `categorical` | datatypes/series.jl, expr/selectors.jl | unswept |
| `date` | dataframe/describe.jl, datatypes/datetimes.jl, datatypes/series.jl, datatypes/strings.jl, datatypes/times.jl, expr/curried_forms.jl, expr/literals_cast.jl, expr/selectors.jl | unswept |
| `datetime` | datatypes/series.jl, datatypes/structs.jl, expr/selectors.jl, misc_ffi_safety.jl | unswept |
| `decimal` | expr/selectors.jl | unswept |
| `duration` | datatypes/datetimes.jl, datatypes/durations.jl, expr/selectors.jl, lazyframe/scan_parquet.jl, misc_ffi_safety.jl, operations/group_by_dynamic.jl | unswept |
| `ends_with` | datatypes/strings.jl, expr/curried_forms.jl, expr/selectors.jl | unswept |
| `integer` | datatypes/durations.jl, datatypes/times.jl, expr/literals_cast.jl, expr/selectors.jl, lazyframe/sink_csv.jl, operations/frame_verbs.jl | unswept |
| `list` | dataframe/gc.jl, datatypes/durations.jl, datatypes/list_struct_write.jl, datatypes/lists.jl, datatypes/times.jl, expr/lit_vector.jl, expr/null_handling.jl, expr/selectors.jl, lazyframe/scan_parquet.jl, misc_ffi_safety.jl, operations/concat.jl, operations/reshape.jl | unswept |
| `matches` | datatypes/binary.jl, datatypes/series.jl, expr/literals_cast.jl, expr/replace.jl, expr/selectors.jl, expr/when_then_otherwise.jl, operations/filter.jl, operations/frame_verbs.jl, operations/join.jl, operations/unique.jl | unswept |
| `nested` | dataframe/construction.jl, dataframe/gc.jl, datatypes/list_struct_write.jl, datatypes/lists.jl, datatypes/series.jl, datatypes/times.jl, expr/meta.jl, expr/selectors.jl, expr/when_then_otherwise.jl, lazyframe/sink_csv.jl, lazyframe/sink_ipc.jl, lazyframe/sink_parquet.jl, operations/reshape.jl | unswept |
| `numeric` | dataframe/describe.jl, datatypes/binary.jl, datatypes/series.jl, expr/meta.jl, expr/selectors.jl, lazyframe/sink_csv.jl, operations/reshape.jl | unswept |
| `signed_integer` | expr/selectors.jl | unswept |
| `starts_with` | datatypes/strings.jl, expr/curried_forms.jl, expr/selectors.jl | unswept |
| `struct_` | expr/selectors.jl | unswept |
| `temporal` | datatypes/structs.jl, expr/selectors.jl | unswept |
| `unsigned_integer` | expr/selectors.jl | unswept |
