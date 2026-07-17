# c-polars second-pass review (post-hardening residuals)

## Status

**Done** (branch `review-one`, all 7 items below fixed; not yet committed). Findings from a full
re-review of `c-polars/` after the `review-one` hardening branch (see `plans/c_polars_hardening.md`,
whose work this review confirms: memory management is sound, every `rev.md` item verified fixed or
deliberately deferred). The items below were the *residuals* that pass missed — mostly latent-UB
consistency gaps against the crate's own `ffi_util` conventions. No live bugs were reachable from
the current Julia layer, so this branch is a hardening pass rather than a bug-fix pass.

Verification: `cargo build -j 4` clean (0 warnings), `cargo clippy --all-targets -- -D warnings`
clean, `cargo fmt --check` clean, `cargo test` **10/10** (7 pre-existing + 3 new: item 7's
`read_bool_mask_normalizes_non_0_1_bytes`, `read_opt_str_null_or_zero_len_is_none`,
`read_opt_str_rejects_invalid_utf8`), header-drift check green (256 symbols matched). Item 6's
header change (`polars_value_string_get`/`polars_value_binary_get`'s `user` param `*mut c_void` →
`*const c_void`) regenerated via `julia --project=gen gen/generate.jl` + `runic -i`; produces no
visible diff in `src/api/generated.jl` since Julia's `Ptr{Cvoid}` doesn't encode C `const`. Live
Julia suite in a scratch env (`Pkg.develop(path=".")` + `Aqua`/`Test`/`Tables`/`TimeZones`)
**1151 passed / 2 broken (pre-existing) / 0 failed**. Touched paths adversarially re-exercised live:
`col("café")` select+collect (item 2's non-ASCII path), `unpivot` with and without
`variable_name`/`value_name` (item 2's inlined-`read_opt_str` site), `show` on a frame (item 4's
new `guard_error` wrap), `collect_schema` (item 4's other wrap), `with_row_index`, and
`polars_dataframe_new_from_series` called directly at `nseries == 0` with a null pointer (item 1 —
no idiomatic Julia caller exists for this FFI entry point, so it was exercised via the generated
binding directly; returns a clean empty `(0, 0)` frame, no crash).

## Review verdict (what was checked, what held up)

- **Handle lifecycle**: `Box::into_raw`/`from_raw` symmetric per type; `*_destroy` fns are the
  only consumers; in-place mutators go through `&mut (*h).inner` wholesale replacement. No leak
  or double-free path found.
- **Borrowing values**: `polars_value_t<'a>` wraps a borrowing `AnyValue<'a>`; safe because the
  Julia `Value` struct roots its parent (`src/value.jl` `parent::Union{Series, Value}`), and
  `polars_value_struct_get` documents the caller invariant.
- **Panic safety**: `guard_error` covers execution entry points; `tests.rs` exercises the guard,
  the `n == 0` slice guards, and an end-to-end select/collect through the C ABI.
- **Enum boundary**: all `#[repr(C)]` mirrors use exhaustive matches; trust boundary documented
  in `lib.rs`; drift checker + clippy `-D warnings` + fmt + `cargo test` wired into CI.

## Fixes (ranked)

### 1. Unguarded `from_raw_parts` in `polars_dataframe_new_from_series` — latent UB
`c-polars/src/dataframe.rs:97`. The only remaining caller-controlled array read without the
`n == 0` short-circuit that `read_exprs`/`read_names`/`read_bool_mask` all have (null/dangling
ptr + len 0 violates `slice::from_raw_parts`'s contract). Guard `nseries == 0` → empty
`Vec<Column>`. Note: no idiomatic Julia caller today (only the generated binding) — fix anyway,
it's exported API.

### 2. ~17 string sites bypass `read_str`/`read_opt_str` — consistency + latent UB
Same latent null+0 hazard, plus these sites skip the helpers the crate built for exactly this:
- `expr.rs`: `literal_utf8` (69), `col` (86), `alias` (226), `prefix` (242), `suffix` (258),
  `value_counts` (540), `dt_convert_time_zone` (1087), `dt_strftime` (1137)
- `dataframe.rs`: `dataframe_get` (260), `upsample` time_column/every (303, 308),
  `with_row_index` (798), `pivot` separator (930); `unpivot` (870–885) hand-rolls
  `read_opt_str` inline twice
- `io.rs`: all six path reads (132, 207, 282, 347, 481, 541)

Mechanical swap to `read_str` (required) / `read_opt_str` (unpivot's optional names). No ABI or
header change.

### 3. `unwrap_single()` panic path in `polars_lazy_frame_collect`
`c-polars/src/dataframe.rs:463`. `QueryResult::unwrap_single()` is a bare `panic!()` on the
`Multiple` variant (polars-core `query_result.rs`). `guard_error` already downgrades it to a
catchable "internal panic" error, but match on `QueryResult` and return a real
`make_error("query produced multiple frames; expected a single result")` instead.

### 4. `guard_error` coverage gaps
`polars_dataframe_show` (`dataframe.rs:240`) and `polars_lazy_frame_collect_schema`
(`dataframe.rs:476`) are the only execution-adjacent paths not wrapped while every
`write_*`/`sink_*`/`collect`/`upsample` peer is. Wrap both.

### 5. Stale TODO + missing borrowed-pointer docs
- `c-polars/src/types.rs:5` — `// TODO: investigate what the lifetime implies.` is answered by
  the `# Safety` doc on `polars_value_struct_get` (`value.rs:390`). Replace the TODO with a doc
  comment on `polars_value_t` stating the borrow contract (borrows from parent; caller keeps
  parent alive; Julia roots it via `Value.parent`).
- `polars_series_name` (`series.rs:76`) and `polars_error_message` (`lib.rs:101`) return
  borrowed pointers with no lifetime doc — `polars_value_time_zone` even cites
  `polars_series_name` as the convention's reference. One-line docs on both.

### 6. Small consistency polish
- `series.rs:17` — `polars_series_type` lacks the `assert!(!series.is_null())` its siblings have.
- `dataframe.rs:324` — `upsample` open-codes `Box::into_raw(Box::new(...))`; use `make_dataframe`.
- `value.rs:300, 376` — `string_get`/`binary_get` take `user: *mut c_void` where every other
  callback site takes `*const c_void`. Align to `*const` → 2 prototypes in `include/polars.h`
  change → regenerate `src/api/generated.jl`.

### 7. Test additions (`c-polars/src/tests.rs`)
- `read_bool_mask` normalizes non-0/1 bytes (e.g. byte `2` → `true`) — the one `ffi_util` guard
  with no test.
- `read_opt_str`: null/0 → `None`; invalid UTF-8 → error.

### Not doing (already logged as deferred in c_polars_hardening.md — unchanged)
`*const` → `*mut` on owned-pointer returns (incl. `make_expr`), `polars_expr_nth`'s needless
out-param, `write_csv` options struct, typed error model, `#[expect(dead_code)]`.

### Observation only (report, don't change without a separate decision)
`.github/workflows/Tests.yml` triggers on `push: branches: [main]` only — PR branches never run
the clippy/drift/test gates; they fire post-merge.

## Verification (per CLAUDE.md step 7)

1. `cd c-polars && cargo build -j 4` (stable toolchain; job cap — 16-way OOMs this machine).
2. `cargo test`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`.
3. `python3 c-polars/check_header_drift.py`.
4. Item 6 header change: `julia --project=gen gen/generate.jl` + `runic -i src/api/generated.jl`,
   confirm `git diff` on generated.jl is only the two `void *`-constness prototypes.
5. Restart the Kaimon REPL (a live session never picks up a rebuilt `.so`), then live-exercise a
   touched path end-to-end (`col("café")` select+collect, `unpivot` with/without names,
   `show` on a frame) and run the Julia suite in a scratch env
   (`Pkg.develop(path=".")` + `Aqua`/`Test`/`Tables`/`TimeZones`).
6. Flip `## Status` to **Done** with final test counts.
