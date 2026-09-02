# Close two keyword-argument gaps surfaced by the test-parity sweep: `drop`'s `strict`, joins' `maintain_order`

## Status

**Done.** Both gaps closed, live-verified, tested. Full `Pkg.test()`: 3037 passed, 0 failed, 0
errored, 2 broken (pre-existing baseline). `pre-commit run --all-files` (all four hooks, including
`cargo fmt`/`clippy` this time since Rust changed) passes clean. One `cargo build -j 4` total,
made safe by hardlink-copying the main workspace's already-built `c-polars/target/` (93GB,
`cp -al`, ~2s, zero extra disk) into this fresh worktree before building — confirmed via
`git status` that no `Cargo.toml`/`Cargo.lock` change occurred, so the hardlinked dependency
artifacts stayed valid and only `c-polars` itself needed rebuilding (5.85s).

**Live-verified actual behavior** (Step 7): `drop(df, ["a","nonexistent"]; strict=false)` drops
`"a"` and silently ignores `"nonexistent"`, keeping the rest; `strict=true`/omitted still raises.
`crossjoin(a, b; maintain_order=:left)`/`:none`/`:left_right` give left-major order
(`(0,0),(0,1),(1,0),(1,1),...`); `:right`/`:right_left` give right-major order
(`(0,0),(1,0),(2,0),(0,1),...`) — matching upstream's exact iteration pattern from
`test_cross_join_maintain_order_24663`. `innerjoin(c, d, col("k"); maintain_order=:left)` on
`c.k=[1,2,3]`/`d.k=[3,2,1]` returns rows in `c`'s key order (`1,2,3`) with `d`'s matching values
correctly reordered (`z,y,x`), not `d`'s row order. `join_asof(...; maintain_order=:left)` doesn't
crash and returns the same values as the equivalent unordered call (asof already preserves the
left frame's order by construction, so this is an API-surface/no-crash check, matching how
`nulls_equal` is exercised on `join_asof` elsewhere in this file).

## Goal

Two gaps recorded during the batch 10/11 test-parity sweep (`plans/parity/api_gap_audit.md` Group
6 "Missing keyword arguments"), both genuine thin-wrapper gaps (the underlying Rust already
supports the option; only the FFI/Julia surface is missing it):

1. **`drop(df, columns)` has no `strict` keyword.** `LazyFrame::drop(self, columns: Selector)`
   takes a `Selector::ByName { names, strict }`; `polars_lazy_frame_drop` already builds this via
   `selector_by_name(names, true)` (`c-polars/src/ffi_util.rs`) but hardcodes `strict: true`, with
   no FFI parameter to control it. `rename` already has this exact kwarg (`strict::Bool=true`,
   `src/join.jl`... `src/verbs.jl`) — `drop` should match.
2. **No join variant threads `maintain_order`.** `JoinArgs` (real polars, `polars-ops-0.54.4`) has
   `pub maintain_order: MaintainOrderJoin` (`enum { None, Left, Right, LeftRight, RightLeft }`),
   an ungated field on the same struct whose other fields (`suffix`/`coalesce`/`validation`/
   `nulls_equal`) are already fully threaded through `polars_lazy_frame_join` /
   `polars_lazy_frame_join_asof` (`c-polars/src/dataframe.rs`) and `src/join.jl`'s shared `_join`
   helper. Confirmed live in the batch-11 sweep: `crossjoin(a,b; maintain_order=:left)` is a plain
   `MethodError`, not a runtime rejection.

Both are ungated (no `#[cfg(feature = ...)]` on the relevant struct fields or `Selector` type —
verified against the vendored `polars-ops-0.54.4`/`polars-plan-0.54.4` source), so **no
`Cargo.toml` change** is needed, matching this repo's existing "close it now, cheaply" precedent
for `group_by`/`unique`/`sort`'s own `maintain_order` (already closed).

## Architecture

Standard "adding a wrapped operation" workflow (`CLAUDE.md`): extend two existing `extern "C"`
functions (`polars_lazy_frame_drop`, `polars_lazy_frame_join`) plus one more
(`polars_lazy_frame_join_asof`) with a new parameter each, regenerate header + bindings **once**
(not per-function — batch both Rust changes before regenerating), one `cargo build -j 4`
(incremental — no `Cargo.toml`/`Cargo.lock` change, so this must not trigger a full dependency
rebuild; abort and re-check if it does), then thread the new parameter through the corresponding
Julia call sites.

**Deliberately excluded from this PR** (found while researching, not attempted here — see
`api_gap_audit.md`'s Group 11 batch notes for detail on why each is a bigger lift than "add a
kwarg"):
- `Meta`'s missing `is_scalar`/`is_known_length`/`is_row_separable`/`is_length_preserving`/`eq`
  (batch 14) — these are missing *methods*, not a missing kwarg on an existing one; each needs its
  own FFI symbol.
- `nth`'s missing multi-argument form (batch 14) — an argument-shape change, not a kwarg addition.
- Frame-level `sample`/`DataFrame.sample()` (batch 14) — an entirely new function, not a kwarg on
  an existing one.
- `Expr.eq_missing`/`ne_missing`/`hash` (batch 12) — missing methods, not kwargs.

## File structure

| File | Responsibility |
|---|---|
| `c-polars/src/ffi_util.rs` | `selector_by_name`'s existing `strict: bool` param already exists — no change needed there, only at the call site |
| `c-polars/src/dataframe.rs` | `polars_lazy_frame_drop` (+`strict` param), `polars_lazy_frame_join` / `polars_lazy_frame_join_asof` (+`maintain_order` param) |
| `c-polars/src/types.rs` | new `polars_maintain_order_join_t` enum + `to_maintain_order_join()`, mirroring `polars_join_coalesce_t` exactly |
| `src/verbs.jl` | `drop`'s new `strict::Bool=true` kwarg |
| `src/join.jl` | `_join`'s new `maintain_order::Symbol=:none` kwarg (flows automatically into `innerjoin`/`leftjoin`/`rightjoin`/`outerjoin`/`semijoin`/`antijoin` via their existing `kwargs...` passthrough); `crossjoin` and `join_asof` need it added explicitly since they don't forward generic `kwargs...` |
| `test/operations/frame_verbs.jl` | `drop`'s `strict=false` test |
| `test/operations/join.jl` | `maintain_order` tests across a representative join + `crossjoin` + `join_asof` |
| `docs/src/reference/dataframe.md`, `docs/src/reference/join.md` (or wherever joins are documented) | docstring updates already inline; confirm `@docs` blocks don't need new entries (no new function names, just new kwargs on existing ones) |

- [x] **Step 1: Add `strict` to `polars_lazy_frame_drop`** (`c-polars/src/dataframe.rs`)
- [x] **Step 2: Add `polars_maintain_order_join_t` + conversion** (`c-polars/src/types.rs`)
- [x] **Step 3: Add `maintain_order` to `polars_lazy_frame_join` and `polars_lazy_frame_join_asof`** (`c-polars/src/dataframe.rs`)
- [x] **Step 4: Regenerate header + bindings, one `cargo build -j 4`**
- [x] **Step 5: Thread `strict` through `drop` in `src/verbs.jl`**
- [x] **Step 6: Thread `maintain_order` through `_join`/`crossjoin`/`join_asof` in `src/join.jl`**
- [x] **Step 7: Exercise all of it live, record actual values**
- [x] **Step 8: Write tests**
- [x] **Step 9: `pre-commit run --all-files` (this PR DOES touch Rust, so `cargo fmt`/`clippy` apply this time), full `Pkg.test()`, commit, push, open PR**
