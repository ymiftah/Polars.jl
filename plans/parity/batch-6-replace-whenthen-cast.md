# Batch 6 parity note: expr/replace.jl, expr/when_then_otherwise.jl, expr/literals_cast.jl, expr/lit_vector.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_replace.py`,
`test_replace_strict.py`, `test_cast.py`, `test_when_then.py`, `test_lit.py`, `test_literal.py`.

Baseline: these files are already deep (prior gap-closure work covers most `convert(Expr,...)`
overloads, temporal literals, chained `when`). This batch's finds are mostly untested edges of
already-wrapped functions, plus one confirmed-correct-but-untested domain behavior for `cast`.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `replace_strict` | `test_replace_strict_mapping_null_not_specified` | `[1,2,2,None,None]`, mapping `{1:10,2:20}` (no null key) | null propagation (unmapped null passes through as null, not an error) | matches (`[10,20,20,missing,missing]`); added |
| `replace_strict` | `test_replace_strict_mapping_null_specified` | same fixture, mapping includes a `missing → 0` entry | null-as-mapping-key (null itself is a valid `old` value) | matches (`[10,20,20,0,0]`); added |
| `replace_strict` | `test_replace_strict_incomplete_mapping_null_raises` | incomplete mapping, input contains `missing` | wrong-input raises cleanly (Step 5) | matches (`PolarsError`); added |
| `replace` | `test_replace_old_new_many_to_one` | `old=[2,3]` (a list), `new=9` (a single scalar, broadcasting) | happy path — an untested argument shape (multi-value `old`, single-value `new`) | matches (`[1,9,9,9]`); added |
| `replace` | `test_replace_old_new_mismatched_lengths` | `old` length 3, `new` length 2 (neither 1 nor matching) | wrong-input raises cleanly (Step 5) | matches (`PolarsError`); added |
| `cast` | `test_cast_int` | `Int8(-1) → UInt8`, `UInt8(5) → UInt8` (no-op) | domain edge — our `cast` is non-strict by construction (`CastOptions::NonStrict`, confirmed from the vendored `polars-plan` source), so **overflow returns `missing`, not an error or silent wraparound** | matches (`[missing, 0x05]`); added, and this specific behavior (overflow-to-null under the default/only cast mode) had zero coverage before |

## Confirmed non-issue (already-correct, already-intentional, just re-verified)

`when(cond, then, otherwise)` **requires** `otherwise` — there is no way to omit it and get an
implicit `null`, unlike py-polars' `pl.when(cond).then(v)` with no `.otherwise(...)`
(`test_when_then_implicit_none`). This is not a new finding: the existing "explicit missing as
otherwise" testset in `test/expr/when_then_otherwise.jl` already documents this as a deliberate
design choice (`otherwise` has no default) with `when(cond, then, missing)` as the equivalent.
Re-verified the reasoning still holds; nothing to add.

## Genuine gap found (flagged, not fixed — new Rust FFI/API surface needed)

**No `strict` cast option is exposed at all.** `cast(expr, dtype)` always uses `CastOptions::NonStrict`
(confirmed from the vendored `polars-plan` crate — the free `cast()` function used by
`polars_expr_cast`, as opposed to `Expr::cast()`/`Expr::strict_cast()`'s own distinction). Upstream
`test_strict_cast_int` exercises the `strict=True` raise-on-overflow path extensively; there's no
way to reach that from Polars.jl today. Recorded in `LEDGER.md`.

## Not ported (Step 4 exclusions)

- `test_replace_enum*`, `test_replace_cat_to_cat`, `test_replace_strict_str_to_cat`,
  `test_replace_strict_enum_to_new_enum` — Categorical/Enum dtype; out of this sweep's scope.
- `test_replace_int_to_str_with_null` — asserts a dtype-conversion `InvalidOperationError`
  (mapping to a `str` value can't encode back into an `Int16` column); not a null-handling case,
  a dtype-shape one with no clean equivalent here.
- `test_replace_return_dtype_deprecated`, `test_replace_default_deprecated` — exercise a
  *deprecated* py-polars kwarg path; not applicable.
- `test_when_then_empty_list_5547`, `test_list_zip_with_logical_type`,
  `test_when_then_else_struct_18961`, `test_struct_when_then_broadcasting_combinations_19122` —
  List/Struct-dtype `when`/`then` values; belongs to Batch 9.
- `test_object_when_then_4702`, `test_comp_categorical_lit_dtype`,
  `test_comp_incompatible_enum_dtype` — Object/Categorical/Enum dtype, out of scope.
- `test_when_then_supertype_*`, `test_when_then_to_decimal_18375`,
  `test_type_coercion_when_then_otherwise_2806` — dtype-supertype-coercion assertions, no clean
  dtype-introspection API to assert against (same reasoning as prior batches).
- `test_cast.py`'s temporal-cast tests (`test_cast_date_to_time`, `test_cast_time_to_date`,
  `test_err_on_time_datetime_cast`, `test_string_datetime*`) — belong to Batch 8 (temporal).
  `test_cast_decimal_*`, `test_cast_array_to_different_width`, `test_invalid_inner_type_cast_list`,
  `test_list_uint8_to_bytes` — Decimal/Array/List-dtype casts, out of scope here.
- `test_lit.py`/`test_literal.py` — skimmed; dominated by numpy-array/pandas-Series literal
  construction (not applicable) and dtype-inference-matrix parametrization already covered by the
  existing "literal convert overloads" testset's per-type sweep.

## Resolved non-issues (verified before assuming a bug)

- None beyond the `when`/`otherwise` re-confirmation above, which was already correctly documented.
