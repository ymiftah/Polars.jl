# Batch 7 parity note: datatypes/strings.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_string.py` (2397 lines),
`test_pad.py`, `test_concat.py`, `test_strptime.py`.

Baseline: `datatypes/strings.jl` is already deep (namespace expansion, regex contains/extract,
strict vs non-strict parsing already covered). This batch's finds are a couple of untested null
edges plus three sizeable **missing functions**.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `Strings.replace` | `test_string_replace_with_nulls_10124` | source column `["S","S","S",None,"S"]` | null propagation (null source row stays null) | matches; added |
| `Strings.replace` | `test_str_replace_null_19601` | replacement value is a **column** (`col("one")`), itself containing a `null` | happy path — an untested argument shape; the null in the replacement value is irrelevant when the row's pattern doesn't match, so it never surfaces | matches (`["---","2"]`); added |
| `Strings.zfill` | `test_str_zfill_unicode_not_respected` | `["Café","345","東京",None]`, width 6 | domain edge + null propagation — zfill's width is **byte-based, not character-based** (upstream's own test name flags this as a known non-ideal-but-consistent quirk); `null` passes through unchanged | matches exactly (`["0Café","000345","東京",missing]`); added |

## Genuine gaps found (flagged, not fixed — new Rust FFI needed, out of scope)

1. **`Strings.join` (py-polars' `str.join`, an aggregating string-concat-with-separator) doesn't
   exist at all.** `test_concat.py` devotes its entire file to this one function, including
   `ignore_nulls` semantics (`null` propagates the whole result to `null` when `False`; nulls are
   skipped when `True`, even for an all-null or empty input → `""`). Not to be confused with
   `unpivot`/horizontal `concat_str` (different functions) — Step 9 territory, noted so a future
   pass doesn't conflate them.
2. **`pad_start`/`pad_end` don't exist** — only the more specific zero-padding `zfill` is wrapped.
   `test_pad.py`'s `test_str_pad_start`/`test_str_pad_end` (and their `_expr`/unicode variants)
   have no home here yet.
3. **`extract_groups` (named-capture-group regex extraction into a Struct column) doesn't exist**
   — only positional-group `extract`/`extract_all` are wrapped. `test_extract_groups*` in
   `test_string.py` covers this extensively, including the empty-pattern-returns-empty-struct edge
   (`test_extract_groups_empty`).

All three recorded in `LEDGER.md`.

## Not ported (Step 4 exclusions)

- `test_str_json_decode_25237`, `test_json_decode_*` — JSON decoding into a dtype; no
  `json_decode` binding here, separate gap not investigated this batch (already a lot found).
- `test_string_extract_groups_lazy_schema_10305` — schema-inference check tied to the missing
  `extract_groups`, not portable independent of it.
- `test_str_concat_deprecated` — exercises a *deprecated* py-polars alias (`Series.str.concat()`
  for `str.join()`); not applicable.
- `test_str_join_datetime` — `str.join` over a Datetime column (implicit string formatting);
  depends on the missing `join` function above, not portable independently.
- `test_str_pad_start_expr`/`test_str_pad_end_expr`, unicode pad variants — depend on the missing
  `pad_start`/`pad_end` above.
- `test_str_zfill_wrong_length` — asserts a negative-width `ErrorException`; would need to be
  re-checked once/if the function's signature is revisited, not meaningful to test in isolation
  against the current gap-free-of-this-specific-validation implementation without risking a false
  claim about behavior that wasn't actually exercised.
- The remaining ~2300 lines of `test_string.py` are dominated by: Categorical/Enum-dtype string ops
  (out of scope), `test_strptime.py`'s huge parametrized format-string matrix (belongs partly to
  Batch 8 alongside temporal dtypes, partly not portable as discrete fixtures), and internal
  regression tests for py-polars' own SIMD/chunking fast paths with no adversarial-value content.

## Resolved non-issues (verified before assuming a bug)

- None — every fixture checked matched on the first try, including the subtle byte-vs-character
  `zfill` width behavior.
