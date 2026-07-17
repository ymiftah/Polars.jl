# c-polars review & production-hardening

## Status

**Done** (branch `review-one`, 1151 Julia tests + 7 Rust tests, not yet committed); only the
deliberately-deferred cosmetic items below remain out of scope for this branch. Reviewer comments
captured verbatim in `rev.md` (expr.rs / dataframe.rs / value.rs, rated C+ / weak-B- / B-). This
plan addresses every reviewer comment plus defects found first-hand in the files the reviewer did
not see (`io.rs`, `series.rs`, `types.rs`, `ffi_util.rs`, `lib.rs`).

Verification (re-run and confirmed after the `upsample`/doc/test-leak fixes below, independently
of the earlier pass's numbers): `cargo build -j 4` clean (0 warnings), `cargo clippy --all-targets
-D warnings` clean, `cargo fmt --check` clean, `cargo test` **7/7**, header-drift check green (256
symbols matched), Julia suite in a scratch env (`Pkg.develop(path=".")` +
`Aqua`/`Test`/`Tables`/`TimeZones`) **1151 passed / 2 broken (pre-existing) / 0 failed**. `upsample`
exercised live and adversarially post-fix (basic/stable/grouped upsample, a bad duration string, a
bad column name — both error cleanly rather than crashing), and the Time dtype path re-exercised
live (round-trip, join, sort) to confirm `dtype-time` still holds. Not yet committed.

Done:

- **P0.1** `polars_value_list_type` categorical/enum panic guard.
- **P0.2** panic guard: `guard_error` helper in `lib.rs`, applied to every query-*execution* entry
  point (`collect`, `write_parquet`, `write_ipc`, `write_csv`, `sink_parquet`, `sink_csv`,
  `sink_ipc`, `new_from_carrow`, `upsample` — the last one caught in a follow-up re-review of this
  plan, since it runs group_by/gather machinery internally, the same panic class the guard exists
  for).
- **P0.3** `n == 0` short-circuits in `read_exprs`/`read_names`/`read_bool_mask`/`read_str`
  (`slice::from_raw_parts` requires a non-null aligned ptr even for len 0).
- **P0.4** `read_bool_mask` reads bytes and normalizes (`!= 0`); enum trust boundary documented in
  the crate docs.
- **P0.5** `struct_rename_fields`: `from_utf8_unchecked` → `read_names` (validated) + out-param.
- **P1.1** `to_dtype` is now fallible; `polars_expr_cast` takes an out-param and errors instead of
  silently casting to `Unknown(Any)`.
- **P1.2** `polars_value_type` routes through a new `from_any_value` (handles the
  Categorical/Enum-panics-on-`.dtype()` hazard), which falls through to `from_dtype` for every
  other variant; `polars_series_type` calls `from_dtype` directly (it only ever has a `DataType`,
  never an `AnyValue`). `from_dtype` itself gained a Categorical/Enum → String arm, so both entry
  points now agree — the fix is the shared *table*, not a shared call path. `PolarsValueTypeTime`
  added.
- **P1.3** `to_time_unit` rejects the `PolarsTimeUnitInvalid` return-sentinel as input.
- **P1.4** `unwrap_or_default()` on UTF-8 → `read_str` + real errors (`group_by_dynamic`,
  `rolling`).
- **P1.5** `with_row_index` offset via `try_from` + clean error; `head`/`tail` clamp.
- **P1.6** `write_all` instead of `write` in `string_get`/`binary_get`; `UserIOCallback::write`
  rejects `n > buf.len()`.
- **P1.7** `struct_field_by_name`: null-handle return → out-param + error.
- **P2.1** *(decision, see below)* raw `Box::from_raw`/`mem::forget` round-trip replaced with
  `&mut (*x).inner`; convention documented in the crate docs.
- **P2.2** `new_from_carrow`'s four bare-null returns → out-param + real error messages. No
  bare-null-means-error return remains anywhere in the crate; the only loose end was
  `polars_lazy_frame_collect_schema`'s doc claiming to match `polars_dataframe_schema`'s *shape*
  when the signatures actually differ (by-value vs. out-param + error) — reworded to say it
  matches the ArrowSchema *content*, not the C signature.
- **P2.4** `*_horizontal` macro-ized; `make_lazy_frame`/`make_lazy_group_by`/`selector_by_name`
  helpers replace ~15 open-coded sites; duplicate `read_opt_str` in `expr.rs` deleted.
- **P2.5** `new_from_series` preserves Series names; `period_len == 0` documented; all three magic
  booleans now commented at their call sites — `is_in`'s `nulls_equal=false`, `implode`'s
  `maintain_order=true` (row order is always preserved, not exposed as a knob), and
  `ExplodeOptions { empty_as_null: true, keep_nulls: true }` (explode never drops a row).
- **P3 (partial)** `polars_value_type` marked `unsafe`; rayon `iter::repeat` → `std::iter::repeat_n`
  in `sort`; lifetime theater (`'a: 'b`) dropped + caller invariant documented; `_iter_struct_av`
  risk pinned in a comment; `&self` convention unified; filter TODO-as-NOTE answered; commented-out
  `str_explode` and redundant parens removed.

- **P3 (rest)** `polars_dataframe_new` deleted: it was `#[no_mangle] pub fn` (Rust ABI on an
  exported symbol — unsound to call from C), absent from the header, and referenced by nothing.
  `Strings.titlecase` now fails with an explanation instead of a bare `UndefVarError` for a symbol
  that only exists in a `--features nightly` build.
- **P4** `c-polars/check_header_drift.py` + a CI step: every exported Rust symbol must appear in
  `include/polars.h` and vice versa (`#[cfg]`-gated symbols exempted and reported). Feature-panic
  re-audit done, see below. **Rust smoke test** added (`c-polars/src/tests.rs`, 7 cases covering
  the panic guard, the null-ptr/`n==0` slice guards, `to_dtype` fallibility, `read_str` UTF-8
  validation, an end-to-end col→select→collect through the C ABI, and a write callback) plus a
  `rust` CI job running `clippy --all-targets -D warnings`, `fmt --check`, and `cargo test`.
  **Callback thread-safety** invariant recorded on `UserIOCallback` (it is `!Send` by design; the
  callback reaches into the Julia GC heap and must stay on the calling thread -- sinks write to
  paths, not callbacks, precisely so no `Send` writer is ever needed).

Plus, found while executing (not in the original plan):

- **Julia-side byte-vs-char length bug — systemic, 24 sites.** Every FFI string argument passed
  `length(s)` (a *character* count) where the ABI wants a *byte* length, so any non-ASCII string
  was truncated mid-value. Pre-existing on `main` and unrelated to the reviewer's Rust comments,
  but the same defect class one layer up. It hit essentially the whole public API: `col`, `alias`,
  `lit(::String)`, `prefix`/`suffix`, `df[:col]`, every `scan_*`/`sink_*`/`write_*` **path**,
  `with_row_index` name, `unpivot` variable/value names, `pivot` separator, `upsample`
  time_column/every, `replace_time_zone`/`convert_time_zone` tz, `str_to_date`/`str_to_datetime`
  format, `value_counts` name, and the two `Structs` entry points. `col("café")` simply did not
  work. All now `ncodeunits`, matching what the newer `io/`/`group_by`/`join` code already did.
  Note the arrow *data* path was always correct (`sizeof`/`codeunits`), which is why non-ASCII
  data worked while non-ASCII *names* did not — and why tests never caught it.
- **`dtype-time` was not enabled.** Not implied by polars' defaults: `dtype-slim` (in `default`) is
  date+datetime+duration only, and `temporal` pulls `polars-time` without it. polars-core/-io/-lazy/
  -expr get it transitively but **polars-ops does not**, which compiles out its
  `take_chunked_unchecked` Time arm and falls through to `_ => unreachable!()` — a process abort on
  any gather (join/gather) over a Time column. Now enabled explicitly on `polars` and `polars-ops`.

### Feature-panic re-audit (P4)

`grep -rhoE "activate '?[a-z0-9_-]+'? feature" ~/.cargo/registry/src/*/polars-*-0.54.4/src/` yields
seven features whose absence turns into a runtime `panic!`:

| Feature | Status |
|---|---|
| `decompress`, `product`, `propagate_nans`, `round_series`, `timezones` | enabled |
| `dtype-time` | **enabled by this branch** (see above) |
| `binary_encoding` | not enabled, **unreachable**: gates `hex_decode`/`base64_decode` in polars-ops' string namespace; c-polars wraps no encode/decode op |
| `dtype-i128` | not enabled, **unreachable**: an `.expect()` on `DynLiteralValue::Int(i128)` in polars-plan's `lit.rs`; c-polars never constructs an i128 and Julia has no `Int128` literal path |

### Deliberately deferred (cosmetic / additive, no bug behind them)

These are the reviewer's remaining *style* points. None fixes a bug; each carries real
regenerate-and-retest surface, so they are logged rather than done on this branch:

- **P2.3 — options struct for `write_csv`'s 19 params** (and `sink_csv`/`scan_csv`). A `#[repr(C)]`
  struct across the boundary is pure ergonomics; `build_csv_writer_options` already consolidates the
  sink path. High churn, real struct-layout risk, zero behaviour change.
- **P2.6 — typed error model** (`polars_error_kind_t` + accessor). Additive and safe, but
  speculative: nothing on the Julia side consumes an error *kind* today (everything raises on the
  message via `polars_error`). Worth doing when a caller actually needs to branch on error type.
- **P3 — `*const` → `*mut` for owned-pointer returns** (~68 sites). The reviewer's point that `*mut`
  is "more honest" about ownership is fair, but the codebase is uniformly `*const` and it works; the
  change would ripple through the header, `generated.jl`, and every Julia `Ptr{...}` site for
  expressiveness alone.
- **P3 — blanket `#[allow(dead_code)]` → `#[expect]`** on the FFI enums. Marginal (catches a
  hypothetical future dead variant); `#[expect(dead_code)]` on enums only ever constructed via the
  `#[repr(C)]`-from-C path is finicky to keep satisfied.

Everything else in the plan is done.

## Decisions taken

- **P1.8 (`new_from_carrow` arrow-array leak) — WITHDRAWN, not a bug.** The original plan claimed
  the by-value `carray` leaks when `import_field_from_c` fails. It does not: polars-arrow's
  `impl Drop for ArrowArray` (`ffi/array.rs:59`) invokes the `release` callback, and `carray` is an
  owned local, so every early return drops → releases it. On the success path it is moved into
  `import_array_from_c`, which takes it by value. The ownership reasoning is now written into the
  function's `# Safety` doc so the next reader doesn't re-derive it. The *real* defect at those
  sites was the four diagnostic-free null returns (P2.2), which is fixed.
- **P2.1 — keep the in-place mutator convention** (`select`/`with_columns`/`sort`/`filter`/`head`/
  `tail` mutate and return void) rather than converting everything to out-param-clone. The
  reviewer's aliasing concern is handled one layer up: Julia's `select(df) = _select!(clone(df), …)`
  clones first, so no caller observes the mutation, and each mutator replaces `inner` wholesale so
  clones never alias. The raw-pointer round-trip (the part that *was* indefensible) is gone, and the
  convention is now stated in the crate docs.
- **Null-handle policy — documented, not enforced.** The reviewer's expr.rs hazard #1 ("null means
  optional in three places, UB everywhere else, nothing documents which") is now answered in
  `lib.rs`'s crate docs rather than closed with a runtime check: handles are non-null unless a
  function's own doc says otherwise (`replace_strict`'s `default`, `sample_n`/`sample_frac`'s
  `seed`), and the scattered `assert!(!x.is_null())` sites are a best-effort debug trap, not a
  checked contract — most sites have no check at all, and even where present, a failed assert
  still aborts the process across `extern "C"` rather than raising a catchable error. Adding a
  real check to every dereference site would be a much larger change than this branch's scope;
  documenting the existing (unenforced) convention is the cheap, honest close-out.
- **Time dtype — full end-to-end support** (rather than classifier-only). Note this is a coverage
  gap, not the silent-wrongness the rest of P1 fixes: a Time column errored cleanly before
  (`parse_format`: "unknow schema format"). Touches: `polars_value_time_get`, the enum variant,
  `parse_format` (`tts`/`ttm`/`ttu`/`ttn`), `read.jl` (time64 zero-copy/bulk), `arrowvector` +
  `format(::Type{Dates.Time})` (write path), `load_value(Value{Dates.Time})`, and the Julia `cast`
  branch. `Dates.value(t)` is the total nanoseconds; `Dates.Nanosecond(t)` is the 0-999 component
  accessor — do not confuse them.

## Out of scope (log as follow-ups)

- Wider `cast` ABI carrying temporal unit/tz + decimal precision/scale, so `cast(col, DateTime)` /
  `cast(col, Duration)` / Decimal become expressible (today `to_dtype` errors for them).
- Exposing remaining hardcoded knobs beyond asof tolerance (concat union strategy, `to_datetime`
  tz/ambiguous).
- CSV `hive_partitioning` (known upstream gap, already in `CLAUDE.md`).

## Verification (per CLAUDE.md step 7)

1. `cd c-polars && cargo build -j 4` — **cap the job count**: a 16-way parallel polars build OOMs
   this machine (~9 GB available), which is what killed an earlier session mid-refactor.
2. Restart the Kaimon REPL after every rebuild (a live session does not pick up a new `.so`).
3. Exercise every fixed path live and adversarially — see the P0/P1 list above; a clean `cargo
   build` is never sufficient evidence (CLAUDE.md).
4. `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`.
5. Julia suite in a scratch env (`Pkg.develop(path=".")` + `Pkg.add(["Aqua","Test","Tables",
   "TimeZones"])`).
6. Regenerate `src/api/generated.jl` after any header edit (`julia --project=gen gen/generate.jl`)
   and `runic -i` it.
