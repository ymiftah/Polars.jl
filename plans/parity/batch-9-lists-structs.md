# Batch 9 parity note: datatypes/lists.jl, structs.jl, list_struct_write.jl (+ operations/reshape.jl)

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `operations/namespaces/list/test_list.py`
(`namespaces_test_list.py`, 1447 lines), `operations/namespaces/list/test_set_operations.py`
(`test_set_operations.py`), `operations/namespaces/list/test_unique.py` (`list_test_unique.py`),
`operations/namespaces/test_struct.py` (`namespaces_test_struct.py`, 182 lines),
`datatypes/test_list.py` (`datatypes_test_list.py`, 910 lines), `datatypes/test_struct.py`
(`datatypes_test_struct.py`, 1932 lines), `operations/test_explode.py` (`operations_test_explode.py`,
697 lines).

**Fetch-loop naming collision, corrected before reading:** the first fetch loop used
`basename("$f")` to name local files, which collapsed `operations/namespaces/list/test_list.py`
and `datatypes/test_list.py` onto the same local `test_list.py` (second fetch silently overwrote
the first), and likewise for `operations/namespaces/test_struct.py` vs. `datatypes/test_struct.py`.
All four were re-fetched under distinct names before any fixture was ported; nothing below was
sourced from the clobbered files.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `Lists.get` | `test_list_arr_get`/`test_list_arr_get_null_on_oob` | negative index (`-1` = last, `-3` on a 3-elem list = first, out-of-range negative + `null_on_oob=true` -> `missing`) | domain edge / non-default parameter | matches; added |
| `Lists.get` | (same, null-index case) | index itself is `missing` -> result `missing` (not an out-of-bounds error) | null propagation | matches; added |
| `Lists.get` | `test_list_get_with_null` | whole-row-null list (the list itself is `missing`, not an element within it) + `null_on_oob=true` -> `missing` | null propagation, domain edge | matches; added |
| `Lists.sum` | `test_list_sum_and_dtypes` (Booleans section) | `Bool` lists sum to `[1,2,2,3]` (physical `UInt32` on our side, values agree) | non-default dtype | matches; added |
| `Lists.mean` | `test_list_mean` | whole-row-null list -> `missing` (distinct from a list containing a null element) | null propagation | matches; added |
| `Lists.min`/`Lists.max` | `test_list_min_max_13978` | whole-row-null list -> `missing` for both | null propagation | matches; added |
| `Lists.unique` | `test_list_unique_boolean_22753` | heavily-null `Bool` lists collapse to a single `missing` in the unique set (`[missing,missing,missing,false]` -> `{missing,false}`, not one `missing` per input null) | domain edge | matches (compared as a `Set` per row, since `unique`'s order isn't guaranteed here, unlike upstream's `list.sort()`-normalized comparison -- we have no `Lists.sort`, see gaps below); added |
| `Structs.field_by_index` | `test_field_by_index_18732` | negative index (`-1` = last field, matching Python's `struct[-1]`) | non-default parameter | matches; added |
| `Structs.field_by_index` | `test_field_by_index_18732` | out-of-range index (`5` on a 2-field struct) -> `PolarsError`, not a process abort | **Step 5 priority: wrong-input abort-safety check** | raises cleanly; added |
| `explode` (`operations/reshape.jl`) | `test_explode_params` | empty list row + whole-row-null list row, mixed in one frame | domain edge, null propagation | matches upstream's `empty_as_null=True` branch (our only behavior, see gap below); added |
| `explode` (`operations/reshape.jl`) | `test_explode_invalid_element_count` | exploding two list columns with mismatched per-row element counts -> `PolarsError`, not a silent wrong zip | **Step 5 priority: wrong-input abort-safety check** | raises cleanly; added |

Also live-verified as already-correct, no test added (already covered by existing fixtures or not
worth a dedicated assertion): `unnest` on a non-`Struct` column already raises `PolarsError`
cleanly (`test/operations/reshape.jl`'s existing "unnesting a non-struct-typed column also errors
cleanly" case covers `test_unnest_raises_on_non_struct_23654`); `Lists.lengths` on a whole-null-row
list already returns `missing` per its own docstring, matching `test_list_lengths`'s `when/then`
case.

## Cross-file placement note

`test_explode.py`'s fixtures landed in `test/operations/reshape.jl`, not
`test/datatypes/lists.jl`, per `CLAUDE.md`'s "put tests in the file matching its category"
rule -- `explode` is implemented in `src/reshape.jl`, so its tests belong with `unpivot`/`pivot`/
`unnest`/`transpose` there, even though the sweep ledger's grep-derived skeleton assigns
`test_explode.py` to this batch's row. Same class of ledger/reality mismatch already noted for
`Dt.truncate`/`Dt.round` in Batch 8's note.

## Genuine API gaps found (flagged, not fixed -- consistent with Batch 1/6's precedent of recording
rather than implementing new FFI surface during a test-porting pass)

**`Lists` namespace is missing a large fraction of upstream's `list` namespace.** Confirmed absent
from `src/expr/list.jl` (whole file read, 15 functions total: `lengths`, `max`, `min`, `arg_max`,
`arg_min`, `sum`, `mean`, `reverse`, `unique`, `unique_stable`, `first`, `last`, `head`, `get`,
`contains`). Missing, in rough order of how often upstream tests exercise them: `all`/`any`
(boolean reduction), `std`/`median`, `count_matches`, `n_unique`, `sort`, `shift`, `diff`,
`sample`, `join`, `concat`, `slice`, `gather`, `to_struct`, `to_array`, `filter`, `eval`, `item`.
Each is its own FFI symbol upstream (`ListNameSpace::all`, etc.) -- this is sized like a dedicated
API-gap batch (comparable to the `api-wave*` branches), not something to absorb into a test-porting
pass.

**List set operations (`list.set_union`/`set_intersection`/`set_difference`/
`set_symmetric_difference`) have no binding at all** -- confirmed via `test_set_operations.py`'s
entire content (9 tests, all exercising these four methods) and a `src/expr/list.jl` grep for
`set_`. A second, smaller gap of the same shape as the bullet above.

**`explode`/`flatten` don't expose upstream's `empty_as_null`/`keep_nulls` kwargs.** Confirmed live
(see the ported fixture above): our fixed behavior matches upstream's `empty_as_null=True` branch.
This is no longer a cosmetic default in current upstream -- `test_explode_empty_as_null_deprecation`
shows *every* call site now emits a `DeprecationWarning` without an explicit `empty_as_null` value,
meaning upstream is mid-migration toward requiring it explicitly. `src/reshape.jl`'s `explode` and
`src/expr/expr.jl`'s `flatten` (the expr-level equivalent) both take no such option.

**`Structs` namespace lacks `with_fields`/`json_encode`.** `namespaces_test_struct.py`'s
`test_struct_field`/`test_struct_json_encode*` exercise `struct.with_fields` (apply expressions to
selected fields in place) and `struct.json_encode` (struct -> JSON string) -- neither exists in
`src/expr/struct.jl` (3 functions total: `field_by_name`, `field_by_index`, `rename_fields`).

## Not ported (Step 4 exclusions)

- The overwhelming majority of `datatypes/test_list.py` (56 tests) and `datatypes/test_struct.py`
  (~100 tests) -- internal dtype/schema/categorical/serialization/pickle regression tests
  (`test_list_recursive_categorical_cast`, `test_struct_categorical_5843`, ZFS
  (zero-field-struct) serialization round-trips, Arrow/pandas interop, `hypothesis`-parametrized
  cases like `test_explode_parametric`). None have a clean assertion path against our thin FFI
  wrapper and none exercise a function we actually bind.
- `test_list.py`'s temporal-dtype parametrization (`test_list_agg_temporal`, over `min`/`max`/
  `mean`/`median`) -- would need `Lists.median` (see gap above) to port faithfully; the
  non-temporal min/max/mean cases are already covered by this batch's and the existing fixtures.
- `namespaces_test_list.py`'s `test_list_gather*`, `test_list_slice*`, `test_list_shift`,
  `test_list_sample*`, `test_list_join`, `test_list_concat`, `test_list_to_struct*`,
  `test_list_count_match*`, `test_list_n_unique`, `test_list_filter*`, `test_list_eval*`,
  `test_list_to_array*` -- all exercise functions from the "genuine API gaps" list above; nothing
  to assert against on our side.
- `test_set_operations.py` in full -- entirely gated on the missing set-operation functions above.
- `namespaces_test_struct.py`'s `test_map_fields`/`test_prefix_suffix_fields` -- these are
  `name.map_fields`/`name.prefix_fields`/`name.suffix_fields`, which belong to the `Naming`
  submodule (`expr/naming.jl`, Batch 14's file), not `Structs` -- out of this batch's scope, not a
  gap specific to this batch.
- `operations_test_explode.py`'s remaining ~30 tests -- almost every one pins a specific
  `empty_as_null`/`keep_nulls` combination we can't select (see gap above); the two ported fixtures
  above are the subset whose expected values happen to match our one fixed behavior
  (`empty_as_null=True`, keep_nulls implicitly true).
- `test_list_contains_invalid_datatype` -- exercises `pl.Array` dtype (fixed-size list), which this
  wrapper doesn't support as a distinct dtype from `List`; not applicable.

## Resolved non-issues (verified before assuming a bug)

- `Lists.get`'s negative-index and null-index handling were unverified assumptions going in --
  live-checked against upstream's exact fixtures before writing any assertion; both already match
  upstream's Python semantics with zero source changes needed.
- `Structs.field_by_index`'s out-of-range and negative-index paths were checked against a process
  abort specifically (Step 5 priority) before writing the "raises cleanly" assertion -- confirmed
  `PolarsError`, not a crash, on both the existing FFI implementation.
