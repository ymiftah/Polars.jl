# Macro dedup sweep: reuse existing macros, add new ones, kill repeated hand-written patterns

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Status

**Not started.** Stacks on the current branch at execution time (`parity-low-hanging-tier12` @
`1cded32` as of this plan's last update — branch names in this repo turn over quickly; always
branch off whatever `HEAD` actually is when Task 0 runs, not a hardcoded name) as a new branch
`macro-dedup-sweep`.

**Goal:** Both the Rust (`c-polars/src/*.rs`) and Julia (`src/**/*.jl`) halves of this codebase have
a documented macro layer specifically built to eliminate copy-paste across near-identical
"wrap a polars operation" definitions (see `c-polars/src/expr.rs`'s 18 `macro_rules!` and
`src/macros.jl`'s 5 macros, whose header comment even has a "Not yet covered" section). A full
sweep (two parallel research agents, one per language) found: functions that duplicate a pattern
an existing macro already covers but weren't written with it; patterns that recur 3+ times with no
covering macro; and a few small non-macro simplifications the sweep surfaced along the way. This
plan closes every one of those findings in one stacked PR, split into small, independently
buildable/testable tasks — pure internal refactors, **no observable behavior change** anywhere in
this plan (confirmed per-task by the existing Rust and Julia test suites staying green, plus this
plan does not touch a single `extern "C"` function's *signature*, only its body, so no header
regen is required anywhere in this plan).

Explicitly **out of scope** (confirmed with the user): the C-enum-mirror generator idea (`types.rs`/
`value.rs`/`expr.rs`'s ~19 hand-written `#[repr(C)] enum` + `to_*` match pairs) — that one needs
cbindgen to see macro-expanded *enums*, not just functions, which is a generation-pipeline change
rather than a pure refactor, and was deliberately deferred to its own plan.

**Architecture:** No new capabilities are added anywhere in this plan — every task replaces
hand-written code with either (a) an invocation of an *existing* macro, (b) an invocation of a
*new* macro/helper this plan adds (itself built by generalizing 3+ existing hand-written call
sites), or (c) a small non-macro helper function. Every Rust task keeps every touched
`extern "C"` function's name, parameter list, and return type byte-for-byte identical — only the
function *body* changes — so `c-polars/include/polars.h` (and therefore
`src/api/generated.jl`) needs no regeneration in this plan; `python3 c-polars/check_header_drift.py`
is expected to report zero drift after every Rust task, confirming that. Every Julia task is
likewise a pure refactor of already-correct, already-tested behavior.

**Tech Stack:** Rust (`c-polars/`, `macro_rules!`), Julia (`src/`, `macro`/generated-function
metaprogramming).

## Global Constraints

- **Stable toolchain only**; run `rustup show` if unsure. Never `cargo +nightly`.
- **Check `c-polars/target/` before the very first build in Task 1.** If it is empty/missing (as it
  was when this plan was written — this checkout has never been built), the *first* `cargo build`
  is a full dependency compile and **must** use `-j 1` per CLAUDE.md (deps build at opt-level 3
  even in the dev profile; a 4-way-or-wider optimized dependency rebuild OOM-kills this machine).
  Every build after that first one is incremental (only this crate's own object files change
  task-to-task, since no task in this plan touches `Cargo.toml`/`Cargo.lock`) and should use
  **`cargo build -j 4`**. If `target/` already has content (a prior session already built it),
  `-j 4` is safe from the start.
- After every Rust build, the previously-built `.so` is stale. This plan verifies Julia-level
  behavior by invoking `julia --project=. -e 'using Pkg; Pkg.test()'` **as a fresh non-interactive
  process** after each Rust task — a fresh `julia` process always loads the current `.so`, so no
  explicit "restart" step is needed for that verification path. **Separately**, prefer the Kaimon
  shared live REPL (`kaimon-julia` skill, `ex()`) for the "exercise it live" step CLAUDE.md's
  workflow calls for, restarting it after every `cargo build` — a live Kaimon session does *not*
  pick up a rebuild on its own. If Kaimon is unavailable in your environment, the non-interactive
  `Pkg.test()` run plus one throwaway `julia --project=. -e '...'` snippet exercising the touched
  path is the fallback; note in the task's commit/PR description that live interactive exercise was
  skipped and why.
- Every Rust task's body-only refactor must be verified against the **behavior**, not just the
  shape, of the code it replaces — re-read the original hand-written body once more immediately
  before deleting it and confirm the macro expansion reproduces it exactly (argument order,
  `.clone()` placement, which namespace method is called).
- `cargo test`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check` must all pass
  after every Rust task.
- `julia --project=. -e 'using Pkg; Pkg.test()'` must report the same pass/fail/broken counts
  before and after every Julia task (get a baseline once, at the start of Task 8, before any Julia
  task begins).
- Every task ends with its own commit (small, revertable, bisectable). Do not squash across tasks.
- No behavior change means no new tests are required by this plan — the existing suites are the
  regression guard. Do not delete or weaken any existing test while touching its file.

## File Structure

Rust, touched only in `c-polars/src/`:
- `expr.rs` — most of the Rust tasks; adds `gen_impl_expr_named!`, `gen_impl_expr_dt_timeunit!`,
  `gen_impl_expr_ternary!`, `gen_impl_expr_ternary_list!`, `gen_impl_expr_ternary_str!`; migrates
  ~25 hand-written functions onto existing or new macros.
- `ffi_util.rs` — adds `read_opt_u64`.
- `dataframe.rs` — adds `gen_lazy_frame_reduce!`, `gen_lazy_frame_unary_expr_mutator!`; migrates 15
  `mem::take`-shaped mutators; extracts a `to_idx_size` helper.
- `io.rs` — extracts a `build_sink_args` helper.

Julia, touched in `src/`:
- `expr/list.jl`, `expr/string.jl` — `head`/`tail`/`shift` onto `@wrap_expr_method`.
- `expr/datetime.jl` — `strftime`/`convert_time_zone` onto `@wrap_expr_method`; curry-sibling
  cleanup onto `@curry`.
- `expr/struct.jl` — `field_by_name` onto `@wrap_expr_method`.
- `expr/statistics.jl` — `value_counts` onto `@wrap_expr_method` (plus the `String`→`AbstractString`
  footgun fix that unblocks it).
- `expr/expr.jl` — `cast_datetime`'s missing curry; `_expr_ptrs`/`_nullable_ref`/
  `_resolve_descending` adoption.
- `verbs.jl`, `reshape.jl`, `join.jl`, `io/csv.jl`, `io/parquet.jl`, `io/ipc.jl`, `group_by.jl` —
  `_enum_lookup` adoption.
- `select.jl`, `sort.jl`, `dataframe.jl` — `_expr_ptrs`/`_resolve_descending`/`_io_read` adoption.
- `io/csv.jl`, `io/json.jl`, `io/ipc.jl`, `io/parquet.jl` — `_nullable_ref`/`_nullable_str`/
  `@wrap_path_writer` adoption.
- `lazyframe.jl`, `expr/meta.jl` — `_io_read` adoption.
- `macros.jl` — adds `_expr_ptrs`, `_nullable_ref`, `_nullable_str`, `_io_read`,
  `@wrap_path_writer`, `_resolve_descending`, and a `fix2=true` option on `@curry`; updates the
  "Not yet covered" header comment to drop the items this plan closes.
- `expr/list.jl`, `expr/string.jl`, `expr/datetime.jl`, `expr/struct.jl` — a second pass (Task 19)
  migrates their 12 hand-written `Base.Fix2` curries onto `@curry ... fix2=true`.

---

## Task 0: Create the stacked branch

**Files:** none (branch only).

- [ ] **Step 1:** From a clean working tree on whatever branch is currently checked out, create and
  switch to the new branch:

```bash
git checkout -b macro-dedup-sweep
```

- [ ] **Step 2:** Confirm `git status` is clean and `git log --oneline -1` shows the same commit as
  the branch this was cut from. No commit yet — this task only creates the branch.

---

# Rust tasks

## Task 1: Reuse existing `gen_impl_expr!`/`gen_impl_expr_binary!` for 5 hand-written functions

**Files:**
- Modify: `c-polars/src/expr.rs:393-413` (`polars_expr_keep_name`, `polars_expr_to_lowercase`,
  `polars_expr_to_uppercase`), `c-polars/src/expr.rs:629-637` (`polars_expr_pearson_corr`),
  `c-polars/src/expr.rs:2711-2715` (`polars_expr_meta_undo_aliases`).

**Interfaces:** No new symbols. Every touched function keeps its exact name/signature/return type;
only the body changes to a macro invocation. Nothing downstream (Julia call sites, the header)
needs any change.

- [ ] **Step 1:** In `c-polars/src/expr.rs`, replace the three hand-written functions at lines
  393-413:

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_keep_name(expr: *const polars_expr_t) -> *const polars_expr_t {
    let aliased = (*expr).inner.clone().name().keep();
    make_expr(aliased)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_to_lowercase(
    expr: *const polars_expr_t,
) -> *const polars_expr_t {
    let aliased = (*expr).inner.clone().name().to_lowercase();
    make_expr(aliased)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_to_uppercase(
    expr: *const polars_expr_t,
) -> *const polars_expr_t {
    let aliased = (*expr).inner.clone().name().to_uppercase();
    make_expr(aliased)
}
```

with three `gen_impl_expr!` invocations, placed right after the `gen_impl_expr!` macro definition
(currently at `expr.rs:578-587`) alongside its other entries — i.e. delete the three hand-written
functions from their current location and add these lines next to the existing
`gen_impl_expr!(polars_expr_sum, Expr::sum);` block:

```rust
gen_impl_expr!(polars_expr_keep_name, |e: Expr| e.name().keep());
gen_impl_expr!(polars_expr_to_lowercase, |e: Expr| e.name().to_lowercase());
gen_impl_expr!(polars_expr_to_uppercase, |e: Expr| e.name().to_uppercase());
```

(This closure shape is already proven by the existing
`gen_impl_expr!(polars_expr_struct_json_encode, |e: Expr| e.struct_().json_encode());`-style entries
elsewhere in the file — confirm by grepping `gen_impl_expr!(polars_expr_struct_json_encode` before
you start, to see the exact precedent.)

- [ ] **Step 2:** Replace `polars_expr_pearson_corr` (`expr.rs:629-637`):

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_pearson_corr(
    a: *const polars_expr_t,
    b: *const polars_expr_t,
) -> *const polars_expr_t {
    let a = (*a).inner.clone();
    let b = (*b).inner.clone();
    make_expr(pearson_corr(a, b))
}
```

with a `gen_impl_expr_binary!` invocation placed next to its sibling entries
(`gen_impl_expr_binary!(polars_expr_arctan2, Expr::arctan2);` etc., around `expr.rs:1361`):

```rust
gen_impl_expr_binary!(polars_expr_pearson_corr, pearson_corr);
```

`pearson_corr` is already imported at the top of the file (`use polars_plan::dsl::functions::{...,
pearson_corr, ...}`), so no import change is needed. Leave `polars_expr_cov` and
`polars_expr_spearman_rank_corr` (its neighbors) untouched — both take a genuine extra scalar
argument (`ddof`/`propagate_nans`) that `gen_impl_expr_binary!` cannot express.

- [ ] **Step 3:** Replace `polars_expr_meta_undo_aliases` (`expr.rs:2711-2715`):

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_meta_undo_aliases(
    expr: *const polars_expr_t,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().meta().undo_aliases())
}
```

with, next to its neighbors in the `Meta` section of the file:

```rust
gen_impl_expr!(polars_expr_meta_undo_aliases, |e: Expr| e.meta().undo_aliases());
```

- [ ] **Step 4:** Build and verify:

```bash
cd c-polars && cargo build -j 4 && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check
python3 check_header_drift.py
```

Expect: clean build, all tests pass, clippy/fmt clean, **zero header drift** (these four functions'
signatures are byte-for-byte unchanged).

- [ ] **Step 5:** From the repo root, run the Julia suite against the freshly built `.so`:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expect: identical pass/fail/broken counts to `parity-kwarg-gaps`'s baseline (record that baseline
now if you haven't already — this is the first Rust task).

- [ ] **Step 6:** Commit:

```bash
git add c-polars/src/expr.rs
git commit -m "c-polars: reuse gen_impl_expr!/gen_impl_expr_binary! for keep_name/to_lowercase/to_uppercase/undo_aliases/pearson_corr"
```

---

## Task 2: Add `gen_impl_expr_named!`; migrate 7 name-taking functions

**Files:**
- Modify: `c-polars/src/expr.rs:313-391` (`polars_expr_alias`, `polars_expr_prefix`,
  `polars_expr_suffix`, `polars_expr_prefix_fields`, `polars_expr_suffix_fields`),
  `c-polars/src/expr.rs:2630-2641` (`polars_expr_struct_field_by_name`),
  `c-polars/src/expr.rs:2570-2582` (`polars_expr_dt_strftime`).

**Interfaces:** Produces macro `gen_impl_expr_named!` in `expr.rs`, callable by any future
single-name-argument, fallible, `Expr`-returning wrapper.

- [ ] **Step 1:** Add the new macro right after `gen_impl_expr!`'s definition (`expr.rs:578-587`):

```rust
macro_rules! gen_impl_expr_named {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            expr: *const polars_expr_t,
            name: *const u8,
            len: usize,
            out: *mut *const polars_expr_t,
        ) -> *const polars_error_t {
            guard_error(|| {
                let name = tri!(read_str(name, len));
                let result = $t((*expr).inner.clone(), name);
                *out = make_expr(result);
                std::ptr::null()
            })
        }
    };
}
```

- [ ] **Step 2:** Replace the five functions at `expr.rs:313-391`:

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_alias(
    expr: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let name = tri!(read_str(name, len));
        let aliased = (*expr).inner.clone().alias(name);
        *out = make_expr(aliased);
        std::ptr::null()
    })
}
```
...and the four analogous `polars_expr_prefix`/`polars_expr_suffix`/`polars_expr_prefix_fields`/
`polars_expr_suffix_fields` bodies, with:

```rust
gen_impl_expr_named!(polars_expr_alias, |e: Expr, name: &str| e.alias(name));
gen_impl_expr_named!(polars_expr_prefix, |e: Expr, name: &str| e.name().prefix(name));
gen_impl_expr_named!(polars_expr_suffix, |e: Expr, name: &str| e.name().suffix(name));
/// Prefixes every *field name* of a Struct-typed `expr` (not the expression's own output name --
/// contrast [`polars_expr_prefix`], which does that). Gated `#[cfg(feature = "dtype-struct")]` in
/// polars-plan, already active here (same feature the rest of the `Structs` namespace needs).
gen_impl_expr_named!(polars_expr_prefix_fields, |e: Expr, name: &str| e.name().prefix_fields(name));
/// Suffixes every *field name* of a Struct-typed `expr` (not the expression's own output name --
/// contrast [`polars_expr_suffix`], which does that). Same feature gate as
/// [`polars_expr_prefix_fields`] above.
gen_impl_expr_named!(polars_expr_suffix_fields, |e: Expr, name: &str| e.name().suffix_fields(name));
```

Keep the two doc comments (`prefix_fields`/`suffix_fields`) attached to their macro invocation line
— they carry real information (the feature gate, the "not the same as `prefix`" distinction) that
must not be lost.

- [ ] **Step 3:** Replace `polars_expr_struct_field_by_name` (`expr.rs:2630-2641`):

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_struct_field_by_name(
    a: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let name = tri!(read_str(name, len));
        *out = make_expr((*a).inner.clone().struct_().field_by_name(name));
        std::ptr::null()
    })
}
```

with, at the same location:

```rust
gen_impl_expr_named!(polars_expr_struct_field_by_name, |e: Expr, name: &str| e.struct_().field_by_name(name));
```

- [ ] **Step 4:** Replace `polars_expr_dt_strftime` (`expr.rs:2570-2582`):

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_dt_strftime(
    expr: *const polars_expr_t,
    format: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let format = tri!(read_str(format, len));
        let result = (*expr).inner.clone().dt().strftime(format);
        *out = make_expr(result);
        std::ptr::null()
    })
}
```

with:

```rust
gen_impl_expr_named!(polars_expr_dt_strftime, |e: Expr, format: &str| e.dt().strftime(format));
```

- [ ] **Step 5:** Build, test, clippy, fmt, header-drift check (same commands as Task 1 Step 4),
  then run the Julia suite (Task 1 Step 5). Expect identical results.

- [ ] **Step 6:** Commit:

```bash
git add c-polars/src/expr.rs
git commit -m "c-polars: add gen_impl_expr_named!, migrate alias/prefix/suffix/prefix_fields/suffix_fields/struct_field_by_name/dt_strftime"
```

---

## Task 3: Add `gen_impl_expr_dt_timeunit!`; migrate 3 TimeUnit-enum functions

**Files:**
- Modify: `c-polars/src/expr.rs:2469-2515` (`polars_expr_dt_timestamp`,
  `polars_expr_dt_cast_time_unit`, `polars_expr_dt_with_time_unit`).

**Interfaces:** Produces macro `gen_impl_expr_dt_timeunit!` in `expr.rs`.

- [ ] **Step 1:** Add the macro near `gen_impl_expr_dt!`'s definition (`expr.rs:2345-2353`):

```rust
/// Like `gen_impl_expr_dt!`, but for the sub-family that takes a `polars_time_unit_t` and must
/// convert it fallibly (`to_time_unit` rejects an out-of-range enum value rather than panicking
/// across the FFI boundary -- see the doc comment on `polars_expr_dt_timestamp` before this
/// macro replaced it).
macro_rules! gen_impl_expr_dt_timeunit {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            expr: *const polars_expr_t,
            unit: polars_time_unit_t,
            out: *mut *const polars_expr_t,
        ) -> *const polars_error_t {
            guard_error(|| {
                let unit = tri!(unit.to_time_unit());
                let result = $t((*expr).inner.clone(), unit);
                *out = make_expr(result);
                std::ptr::null()
            })
        }
    };
}
```

- [ ] **Step 2:** Replace the three functions at `expr.rs:2469-2515`:

```rust
/// Fallible since `polars_time_unit_t` mirrors a Julia-side `@cenum` and must reject an
/// out-of-range value rather than let `to_time_unit` panic across the FFI boundary.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_dt_timestamp(
    expr: *const polars_expr_t,
    unit: polars_time_unit_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let unit = tri!(unit.to_time_unit());
        let result = (*expr).inner.clone().dt().timestamp(unit);
        *out = make_expr(result);
        std::ptr::null()
    })
}
```
...and the analogous `cast_time_unit`/`with_time_unit` bodies, with:

```rust
gen_impl_expr_dt_timeunit!(polars_expr_dt_timestamp, |e: Expr, unit| e.dt().timestamp(unit));
/// Changes the underlying `TimeUnit` and rescales the data accordingly (e.g. `:ms` -> `:ns`
/// multiplies by 1e6). Compare [`polars_expr_dt_with_time_unit`], which relabels without rescaling.
gen_impl_expr_dt_timeunit!(polars_expr_dt_cast_time_unit, |e: Expr, unit| e.dt().cast_time_unit(unit));
/// Relabels the underlying `TimeUnit` without touching the data (e.g. reinterpreting `:ms` values
/// as `:ns` without rescaling). Compare [`polars_expr_dt_cast_time_unit`], which rescales.
gen_impl_expr_dt_timeunit!(polars_expr_dt_with_time_unit, |e: Expr, unit| e.dt().with_time_unit(unit));
```

Leave `polars_expr_dt_combine` (`expr.rs:2519-2536`) untouched — it takes a second `Expr` argument
(`time`) in addition to the `TimeUnit`, a shape this macro doesn't cover and isn't worth
generalizing for a single call site.

- [ ] **Step 3:** Build/test/clippy/fmt/header-drift, then Julia suite (same as Task 1).

- [ ] **Step 4:** Commit:

```bash
git add c-polars/src/expr.rs
git commit -m "c-polars: add gen_impl_expr_dt_timeunit!, migrate dt_timestamp/dt_cast_time_unit/dt_with_time_unit"
```

---

## Task 4: Add ternary macros; migrate 6 functions

**Files:**
- Modify: `c-polars/src/expr.rs:1125-1135` (`polars_expr_clip`), `c-polars/src/expr.rs:1143-1153`
  (`polars_expr_replace`), `c-polars/src/expr.rs:1377-1386` (`polars_expr_extend_constant`),
  `c-polars/src/expr.rs:1879-1891` (`polars_expr_list_slice`), `c-polars/src/expr.rs:1907-1919`
  (`polars_expr_list_gather_every`), `c-polars/src/expr.rs:2157-2168` (`polars_expr_str_slice`).

**Interfaces:** Produces macros `gen_impl_expr_ternary!`, `gen_impl_expr_ternary_list!`,
`gen_impl_expr_ternary_str!` in `expr.rs` — no ternary-arity macro existed before this task.

- [ ] **Step 1:** Add the three macros next to `gen_impl_expr_binary!`'s definition
  (`expr.rs:1283-1296`):

```rust
macro_rules! gen_impl_expr_ternary {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            b: *const polars_expr_t,
            c: *const polars_expr_t,
        ) -> *const polars_expr_t {
            let a = &(*a).inner;
            let b = &(*b).inner;
            let c = &(*c).inner;
            make_expr($t(a.clone(), b.clone(), c.clone()))
        }
    };
}

macro_rules! gen_impl_expr_ternary_list {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            b: *const polars_expr_t,
            c: *const polars_expr_t,
        ) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().list(), (*b).inner.clone(), (*c).inner.clone());
            make_expr(expr)
        }
    };
}

macro_rules! gen_impl_expr_ternary_str {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            b: *const polars_expr_t,
            c: *const polars_expr_t,
        ) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().str(), (*b).inner.clone(), (*c).inner.clone());
            make_expr(expr)
        }
    };
}
```

- [ ] **Step 2:** Replace `polars_expr_clip` (`expr.rs:1125-1135`):

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_clip(
    expr: *const polars_expr_t,
    min: *const polars_expr_t,
    max: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let min = (*min).inner.clone();
    let max = (*max).inner.clone();
    make_expr(expr.clip(min, max))
}
```

with:

```rust
gen_impl_expr_ternary!(polars_expr_clip, |e: Expr, min: Expr, max: Expr| e.clip(min, max));
```

- [ ] **Step 3:** Replace `polars_expr_replace` (`expr.rs:1143-1153`) with:

```rust
gen_impl_expr_ternary!(polars_expr_replace, |e: Expr, old: Expr, new: Expr| e.replace(old, new));
```

(Leave `polars_expr_replace_strict`, its 4-argument neighbor, untouched — it takes a 4th `default`
argument this ternary macro doesn't cover.)

- [ ] **Step 4:** Replace `polars_expr_extend_constant` (`expr.rs:1377-1386`) with, keeping its
  existing doc comment:

```rust
/// Infallible -- `Expr::extend_constant` only builds a plan node.
gen_impl_expr_ternary!(polars_expr_extend_constant, |e: Expr, value: Expr, n: Expr| e.extend_constant(value, n));
```

- [ ] **Step 5:** Replace `polars_expr_list_slice` (`expr.rs:1879-1891`) with:

```rust
gen_impl_expr_ternary_list!(polars_expr_list_slice, |l: ListNameSpace, offset: Expr, length: Expr| l.slice(offset, length));
```

- [ ] **Step 6:** Replace `polars_expr_list_gather_every` (`expr.rs:1907-1919`) with:

```rust
gen_impl_expr_ternary_list!(polars_expr_list_gather_every, |l: ListNameSpace, n: Expr, offset: Expr| l.gather_every(n, offset));
```

- [ ] **Step 7:** Replace `polars_expr_str_slice` (`expr.rs:2157-2168`) with:

```rust
gen_impl_expr_ternary_str!(polars_expr_str_slice, |s: StringNameSpace, offset: Expr, length: Expr| s.slice(offset, length));
```

- [ ] **Step 8:** Build/test/clippy/fmt/header-drift, then Julia suite.

- [ ] **Step 9:** Commit:

```bash
git add c-polars/src/expr.rs
git commit -m "c-polars: add ternary gen_impl_expr* macros, migrate clip/replace/extend_constant/list_slice/list_gather_every/str_slice"
```

---

## Task 5: Add `read_opt_u64`; migrate 5 nullable-seed call sites

**Files:**
- Modify: `c-polars/src/ffi_util.rs` (add `read_opt_u64`), `c-polars/src/expr.rs:1388-1397`
  (`polars_expr_shuffle`), `c-polars/src/expr.rs:1515-1526` (`polars_expr_sample_n`),
  `c-polars/src/expr.rs:1529-1540` (`polars_expr_sample_frac`), `c-polars/src/expr.rs:1936-1950`
  (`polars_expr_list_sample_n`), `c-polars/src/expr.rs:1953-1968`
  (`polars_expr_list_sample_fraction`).

**Interfaces:** Produces `pub(crate) unsafe fn read_opt_u64(ptr: *const u64) -> Option<u64>` in
`ffi_util.rs`, imported the same way `read_opt_str`/`read_str` already are at the top of `expr.rs`.

- [ ] **Step 1:** Add to `ffi_util.rs`, right after `read_f64_array` (line 96):

```rust
/// Reads an optional scalar behind a nullable pointer: `ptr.is_null()` means `None`, otherwise
/// `Some(*ptr)` -- the shared convention for an optional scalar argument (as opposed to an
/// optional string, see `read_opt_str` above), e.g. `Expr::shuffle`'s `seed`.
pub(crate) unsafe fn read_opt_u64(ptr: *const u64) -> Option<u64> {
    if ptr.is_null() { None } else { Some(*ptr) }
}
```

- [ ] **Step 2:** Add `read_opt_u64` to `expr.rs`'s `ffi_util::{...}` import list (currently at
  `expr.rs:21-24`).

- [ ] **Step 3:** In each of the 5 call sites, replace the inline
  `let seed = if seed.is_null() { None } else { Some(*seed) };` line with
  `let seed = read_opt_u64(seed);` — e.g. `polars_expr_shuffle` (`expr.rs:1388-1397`) becomes:

```rust
/// Infallible -- `Expr::shuffle` only builds a plan node. `seed` null means "draw one from the OS".
#[no_mangle]
pub unsafe extern "C" fn polars_expr_shuffle(
    expr: *const polars_expr_t,
    seed: *const u64,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let seed = read_opt_u64(seed);
    make_expr(expr.shuffle(seed))
}
```

Apply the identical one-line substitution at `polars_expr_sample_n` (`expr.rs:1515-1526`),
`polars_expr_sample_frac` (`expr.rs:1529-1540`), `polars_expr_list_sample_n` (`expr.rs:1936-1950`),
`polars_expr_list_sample_fraction` (`expr.rs:1953-1968`). Nothing else in any of these 5 functions
changes.

- [ ] **Step 4:** Build/test/clippy/fmt/header-drift, then Julia suite.

- [ ] **Step 5:** Commit:

```bash
git add c-polars/src/ffi_util.rs c-polars/src/expr.rs
git commit -m "c-polars: add read_opt_u64, dedup the nullable-seed pattern across shuffle/sample_n/sample_frac/list_sample_n/list_sample_fraction"
```

---

## Task 6: Add `gen_lazy_frame_reduce!`/`gen_lazy_frame_unary_expr_mutator!`; migrate 15 mutators

**Files:**
- Modify: `c-polars/src/dataframe.rs:625-648` (`filter`, `fill_null`), `dataframe.rs:757-846`
  (`sum`/`mean`/`min`/`max`/`median`/`std`/`var`/`reverse`/`null_count`/`count`/`cache`/`fill_nan`).

**Interfaces:** Produces macros `gen_lazy_frame_reduce!`, `gen_lazy_frame_unary_expr_mutator!` in
`dataframe.rs`.

- [ ] **Step 1:** Add both macros right before `polars_lazy_frame_with_columns`
  (`dataframe.rs:600`), preserving the existing `mem::take` rationale comment that currently sits
  above `polars_lazy_frame_sort` (do not delete that original comment — it's still the canonical
  explanation these macros' own doc comments should point back to):

```rust
/// A void `LazyFrame` mutator taking one further `*const polars_expr_t` argument, cloned and
/// passed to the underlying method by value -- the shape `filter`/`fill_null`/`fill_nan` share.
/// See the `mem::take` comment on `polars_lazy_frame_sort` above for why this mutates through
/// `mem::take` rather than threading a return value.
macro_rules! gen_lazy_frame_unary_expr_mutator {
    ($n: ident, $t: ident, $arg: ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(df: *mut polars_lazy_frame_t, $arg: *const polars_expr_t) {
            let $arg = (*$arg).inner.clone();
            let df = &mut (*df).inner;
            *df = std::mem::take(df).$t($arg);
        }
    };
}

/// A void, argument-free (beyond `df` and any trailing primitive args like `ddof`) `LazyFrame`
/// reduction -- the shape `sum`/`mean`/`min`/`max`/`median`/`std`/`var`/`reverse`/`null_count`/
/// `count`/`cache` share. See the `mem::take` comment on `polars_lazy_frame_sort` above.
macro_rules! gen_lazy_frame_reduce {
    ($n: ident, $t: ident $(, $arg: ident : $ty: ty)*) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(df: *mut polars_lazy_frame_t $(, $arg: $ty)*) {
            let df = &mut (*df).inner;
            *df = std::mem::take(df).$t($($arg),*);
        }
    };
}
```

- [ ] **Step 2:** Replace `polars_lazy_frame_filter` (`dataframe.rs:624-635`) and
  `polars_lazy_frame_fill_null` (`dataframe.rs:637-648`):

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_filter(
    df: *mut polars_lazy_frame_t,
    expr: *const polars_expr_t,
) {
    let predicate = (*expr).inner.clone();
    let df = &mut (*df).inner;
    *df = std::mem::take(df).filter(predicate);
}
```

with (note the macro's generated variable name must match the parameter name for cbindgen header
stability — `filter` keeps `expr`, `fill_null` keeps `fill_value`):

```rust
gen_lazy_frame_unary_expr_mutator!(polars_lazy_frame_filter, filter, expr);
/// Fills every `null` value across all columns of `df` with `fill_value` (an expression, typically
/// a `lit`). Distinct from `polars_expr_fill_null` (per-expression, inside `select`/`with_columns`).
gen_lazy_frame_unary_expr_mutator!(polars_lazy_frame_fill_null, fill_null, fill_value);
```

- [ ] **Step 3:** Replace the 9 zero-arg reductions at `dataframe.rs:756-834`
  (`polars_lazy_frame_sum`, `_mean`, `_min`, `_max`, `_median`, `_reverse`, `_null_count`,
  `_count`, `_cache`) — e.g. `polars_lazy_frame_sum`:

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_sum(df: *mut polars_lazy_frame_t) {
    let df = &mut (*df).inner;
    *df = std::mem::take(df).sum();
}
```

becomes, keeping the existing block doc comment (currently at `dataframe.rs:747-755`) attached to
the first entry in the new block:

```rust
/// Whole-frame reductions -- `LazyFrame::sum`/`mean`/`min`/`max`/`median`/`std`/`var`/`quantile`
/// (`polars-lazy-0.54.4/src/frame/mod.rs`) are genuine methods on the Rust `LazyFrame` itself, not
/// something this crate composes from `with_columns` + a wildcard selector: unlike the naive
/// `select(lf, wildcard.sum())` composition, they are null-tolerant per column rather than
/// erroring the whole frame on the first unsupported dtype (e.g. a `String` column sums to `None`,
/// per each method's own doc comment) -- verified live before choosing this shape over the
/// wildcard one. Aggregated columns keep their original names. All eight are infallible plan-build
/// operations (validated at `collect`, not here), so -- like `polars_lazy_frame_sort`/`slice`
/// above -- they mutate through `mem::take` and return void rather than threading an error out.
gen_lazy_frame_reduce!(polars_lazy_frame_sum, sum);
gen_lazy_frame_reduce!(polars_lazy_frame_mean, mean);
gen_lazy_frame_reduce!(polars_lazy_frame_min, min);
gen_lazy_frame_reduce!(polars_lazy_frame_max, max);
gen_lazy_frame_reduce!(polars_lazy_frame_median, median);
gen_lazy_frame_reduce!(polars_lazy_frame_std, std, ddof: u8);
gen_lazy_frame_reduce!(polars_lazy_frame_var, var, ddof: u8);
gen_lazy_frame_reduce!(polars_lazy_frame_reverse, reverse);
gen_lazy_frame_reduce!(polars_lazy_frame_null_count, null_count);
gen_lazy_frame_reduce!(polars_lazy_frame_count, count);
gen_lazy_frame_reduce!(polars_lazy_frame_cache, cache);
```

(`polars_lazy_frame_std`/`_var`, currently at `dataframe.rs:787-796`, fold into this same block —
the macro's `$($arg: $ty)*` repetition handles the extra `ddof: u8` uniformly. Leave
`polars_lazy_frame_quantile`, `dataframe.rs:798-807`, untouched — it takes an `Expr` plus an enum,
a shape neither macro covers and not worth generalizing for one call site.)

- [ ] **Step 4:** Replace `polars_lazy_frame_fill_nan` (`dataframe.rs:837-846`) with:

```rust
gen_lazy_frame_unary_expr_mutator!(polars_lazy_frame_fill_nan, fill_nan, value);
```

- [ ] **Step 5:** Build/test/clippy/fmt/header-drift — **pay special attention here**: confirm
  `check_header_drift.py` reports zero drift, since a mismatched `$arg` name between the macro
  invocation and the original hand-written parameter name would otherwise silently rename a
  parameter in the generated header (harmless functionally, since C ABI matching is positional, but
  worth catching). Then Julia suite.

- [ ] **Step 6:** Commit:

```bash
git add c-polars/src/dataframe.rs
git commit -m "c-polars: add gen_lazy_frame_reduce!/gen_lazy_frame_unary_expr_mutator!, migrate 15 mem::take-shaped LazyFrame mutators"
```

---

## Task 7: Small Rust helper extractions (`to_idx_size`, `build_sink_args`, generic `read_array`)

**Files:**
- Modify: `c-polars/src/dataframe.rs:684,706,1393,1400` (`to_idx_size` call sites — line numbers
  shift after Task 6; locate by the `n.min(IdxSize::MAX as usize) as IdxSize` text instead),
  `c-polars/src/io.rs:466-471,539-548,685-690,723-728,753-758` (`build_sink_args` call sites),
  `c-polars/src/ffi_util.rs:81-96` (`read_i64_array`/`read_f64_array`).

- [ ] **Step 1:** In `dataframe.rs`, add near the top (module-level, after the `use` block):

```rust
/// Clamps a `usize` row count into polars' `IdxSize` -- the shared "don't overflow IdxSize"
/// conversion every row-count-taking FFI entry point needs.
fn to_idx_size(n: usize) -> IdxSize {
    n.min(IdxSize::MAX as usize) as IdxSize
}
```

Replace each of the 4 occurrences of `n.min(IdxSize::MAX as usize) as IdxSize` (in `slice`,
`top_or_bottom_k`, `head`, `tail` — grep for the exact text since Task 6 shifted line numbers) with
`to_idx_size(n)` (substituting the right local variable name for `n` at each site — `len` in
`slice`, `k` in `top_or_bottom_k`, etc.).

- [ ] **Step 2:** In `io.rs`, add near `build_csv_writer_options`/`build_ipc_writer_options`
  (`io.rs:559,613`):

```rust
/// Builds the `UnifiedSinkArgs` shared by every `sink_*` entry point (`mkdir`/`maintain_order`
/// passed through, `cloud_options` wrapped in `Arc` if present, everything else defaulted).
fn build_sink_args(
    mkdir: bool,
    maintain_order: bool,
    cloud_options: Option<CloudOptions>,
) -> UnifiedSinkArgs {
    UnifiedSinkArgs {
        mkdir,
        maintain_order,
        cloud_options: cloud_options.map(Arc::new),
        ..Default::default()
    }
}
```

Replace the 5 occurrences of the `UnifiedSinkArgs { mkdir: ..., maintain_order, cloud_options:
cloud_options.map(Arc::new), ..Default::default() }` literal (`sink_parquet`,
`sink_parquet_partitioned`, `sink_csv`, `sink_ipc`, `sink_ndjson`) with
`build_sink_args(mkdir, maintain_order, cloud_options)` — for `sink_parquet_partitioned`
specifically, that's `build_sink_args(false, maintain_order, cloud_options)`, preserving its
existing comment explaining why `mkdir` is hardcoded `false` there.

- [ ] **Step 3:** In `ffi_util.rs`, replace `read_i64_array` and `read_f64_array` (currently two
  byte-identical functions modulo element type, `ffi_util.rs:81-96`) with one generic function:

```rust
/// Reads an `n`-element array supplied by the caller (e.g. `Selector::ByIndex`'s column indices,
/// or `cut`/`qcut`'s `breaks`/`probs`, passed by value rather than as `Expr`s). `n == 0`
/// short-circuits (see `read_names` for why).
pub(crate) unsafe fn read_array<T: Copy>(ptr: *const T, n: usize) -> Vec<T> {
    if n == 0 {
        return Vec::new();
    }
    std::slice::from_raw_parts(ptr, n).to_vec()
}
```

Update every call site (`grep -rn "read_i64_array\|read_f64_array" c-polars/src/`) to call
`read_array::<i64>(ptr, n)`/`read_array::<f64>(ptr, n)` respectively (or just `read_array(ptr, n)`
if the surrounding context lets type inference resolve `T`), and update the `ffi_util::{...}`
import lists at each call site's top-of-file `use` block to import `read_array` instead of the two
old names.

- [ ] **Step 4:** Build/test/clippy/fmt/header-drift, then Julia suite.

- [ ] **Step 5:** Commit:

```bash
git add c-polars/src/dataframe.rs c-polars/src/io.rs c-polars/src/ffi_util.rs
git commit -m "c-polars: extract to_idx_size/build_sink_args helpers, unify read_i64_array/read_f64_array into generic read_array"
```

---

# Bridge: Task 8 — confirm the Rust half is fully green before starting Julia tasks

**Files:** none (verification only).

- [ ] **Step 1:** From repo root:

```bash
cd c-polars && cargo build -j 4 && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check
python3 check_header_drift.py
cd .. && julia --project=. -e 'using Pkg; Pkg.test()'
```

Record the exact pass/fail/broken counts from this run — this is the baseline every remaining task
in this plan (all Julia-only) must match exactly.

- [ ] **Step 2:** If Kaimon is available, restart the shared REPL now (`manage_repl` with
  `command="restart"`) so it picks up every Rust change from Tasks 1-7 in one go, and spot-check one
  touched path per task live (e.g. `col("x") |> Dt.strftime("%Y")`, `clip(col("x"), 0, 10)`,
  `col("x") |> Structs.field_by_name("f")`, `df |> Base.sort(...)` for the `mem::take` mutators).
  If Kaimon is unavailable, note that in the task notes and rely on Step 1's `Pkg.test()` run plus
  spot-checking via one-off `julia --project=. -e '...'` snippets instead.

No commit for this task (nothing changes).

---

# Julia tasks

## Task 9: `list.jl`/`string.jl` — `head`/`tail`/`shift` onto `@wrap_expr_method`

**Files:**
- Modify: `src/expr/list.jl:33-72` (`head`, `tail`, `shift`), `src/expr/string.jl:32-52` (`head`,
  `tail`).

**Interfaces:** No new symbols; keeps every existing `Base.Fix2` curry line (`head(n) =
Base.Fix2(head, convert(Expr, n))` etc.) exactly as-is — only the *primal* function body/docstring
generation changes from hand-written to macro-generated.

- [ ] **Step 1:** In `src/expr/list.jl`, replace:

```julia
"""
    head(expr::Polars.Expr, n::Polars.Expr)::Polars.Expr

First `n` elements of each list in `expr` (fewer if the list is shorter than `n`).
"""
function head(a::Expr, b::Expr)
    out = API.polars_expr_list_head(a, b)
    return Expr(out)
end
```

with:

```julia
@wrap_expr_method head(expr::Expr, n::Expr) polars_expr_list_head "First `n` elements of each list in `expr` (fewer if the list is shorter than `n`)."
```

Keep the `head(n) = Base.Fix2(head, convert(Expr, n))` line and its docstring immediately below,
unchanged. Apply the identical transformation to `tail` (lines 50-59, `API.polars_expr_list_tail`)
and `shift` (lines 62-71, `API.polars_expr_list_shift`), each keeping its own existing
`Base.Fix2` curry line unchanged. Keep the existing "pulled out of `@wrap_simple_ops` because of
the `head`/`Polars.head` collision" comment above the block — it's still accurate (the fix here is
switching *which* macro is used, not un-pulling these from the block).

- [ ] **Step 2:** In `src/expr/string.jl`, apply the identical transformation to `head`
  (lines 32-41, `API.polars_expr_str_head`) and `tail` (lines 43-52, `API.polars_expr_str_tail`),
  keeping the shared `head(n) = Base.Fix2(...)`/`tail(n) = Base.Fix2(...)` lines at 72-73 unchanged.

- [ ] **Step 3:** Verify:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expect: identical counts to the Task 8 baseline.

- [ ] **Step 4:** Commit:

```bash
git add src/expr/list.jl src/expr/string.jl
git commit -m "Julia: reuse @wrap_expr_method for Lists/Strings head/tail/shift"
```

---

## Task 10: `datetime.jl`/`struct.jl` — `strftime`/`convert_time_zone`/`field_by_name` onto `@wrap_expr_method`

**Files:**
- Modify: `src/expr/datetime.jl:37-56` (`strftime`), `src/expr/datetime.jl:254-280`
  (`convert_time_zone`), `src/expr/struct.jl:4-16` (`field_by_name`).

- [ ] **Step 1:** In `src/expr/datetime.jl`, replace:

```julia
"""
    strftime(expr::Polars.Expr, format::String)::Polars.Expr

Formats a Date/Datetime/Duration/Time expression using a `chrono`-style format string
(e.g. `"%Y-%m-%d"`).
"""
function strftime(expr::Expr, format::AbstractString)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_dt_strftime(expr, format, ncodeunits(format), out)
    polars_error(err)
    return Expr(out[])
end
```

with:

```julia
@wrap_expr_method strftime(expr::Expr, format::AbstractString) polars_expr_dt_strftime "Formats a Date/Datetime/Duration/Time expression using a `chrono`-style format string (e.g. `\"%Y-%m-%d\"`)."
```

Keep `strftime(format::AbstractString) = Base.Fix2(strftime, format)` and `export strftime`
immediately below, unchanged (`to_string`'s hand-written alias further down, which calls
`strftime(expr, format)`, needs no change — it calls the public function, not the internal body).

- [ ] **Step 2:** Apply the identical transformation to `convert_time_zone` (lines 266-271,
  `API.polars_expr_dt_convert_time_zone`):

```julia
@wrap_expr_method convert_time_zone(expr::Expr, tz::AbstractString) polars_expr_dt_convert_time_zone "Re-labels a Datetime expression's instant into a different IANA time zone `tz` (e.g. `\"America/New_York\"`) -- the underlying instant is unchanged, only the display/interpretation changes. Compare [`replace_time_zone`](@ref), which does the opposite (preserves the wall-clock value, changes the instant).\n\n!!! note\n    Reading the *result* back into Julia (e.g. via `df[:col]`) needs `TimeZones.jl` loaded (`using TimeZones`) -- a naive read otherwise errors with an explanatory message."
```

Keep `convert_time_zone(tz::AbstractString) = Base.Fix2(convert_time_zone, tz)` and
`export convert_time_zone` unchanged.

- [ ] **Step 3:** In `src/expr/struct.jl`, replace:

```julia
"""
    field_by_name(expr::Polars.Expr, name::String)::Polars.Expr
    field_by_name(name::String)::Base.Fix2{typeof(field_by_name), String}

Returns a new expression corresponding to values of the selected field.
"""
function field_by_name(expr, name)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_struct_field_by_name(expr, name, ncodeunits(name), out)
    polars_error(err)
    return Expr(out[])
end
field_by_name(name) = Base.Fix2(field_by_name, name)
```

with (note the original was untyped `function field_by_name(expr, name)`; `@wrap_expr_method`
requires the leading argument to be literally `expr::Expr`, so this also tightens the signature —
confirm every call site already passes a genuine `Expr`, which `Structs.field_by_name` always did
per its own docstring):

```julia
@wrap_expr_method field_by_name(expr::Expr, name::AbstractString) polars_expr_struct_field_by_name "Returns a new expression corresponding to values of the selected field."
field_by_name(name) = Base.Fix2(field_by_name, name)
```

- [ ] **Step 4:** `julia --project=. -e 'using Pkg; Pkg.test()'` — expect the Task 8 baseline.

- [ ] **Step 5:** Commit:

```bash
git add src/expr/datetime.jl src/expr/struct.jl
git commit -m "Julia: reuse @wrap_expr_method for Dt.strftime/Dt.convert_time_zone/Structs.field_by_name"
```

---

## Task 11: `statistics.jl` — `value_counts` onto `@wrap_expr_method`

**Files:**
- Modify: `src/expr/statistics.jl:144-164` (`value_counts`).

This is the one reuse candidate with a real footgun: `_marshal_arg` in `macros.jl` matches an
argument's type annotation by the *exact* `Symbol` `:AbstractString` — a `name::String` annotation
would silently skip the `(ptr, ncodeunits)` marshalling and produce a wrong-arity ccall. Fix the
type annotation as part of this migration, not separately.

- [ ] **Step 1:** Replace:

```julia
"""
    value_counts(expr::Polars.Expr; sort::Bool=false, parallel::Bool=false, name::String="count",
                 normalize::Bool=false)::Polars.Expr

Counts the occurrences of each unique value in `expr`, returning a `Struct` column mapping value
to count (field `name`, default `"count"`). If `sort` is `true`, results are sorted by count
descending. If `normalize` is `true`, counts become fractions of the total instead.
"""
function value_counts(
        expr::Expr; sort::Bool = false, parallel::Bool = false, name::String = "count",
        normalize::Bool = false
    )
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_value_counts(expr, sort, parallel, name, ncodeunits(name), normalize, out)
    polars_error(err)
    return Expr(out[])
end

@curry value_counts(; sort::Bool = false, parallel::Bool = false, name::String = "count", normalize::Bool = false)
```

with:

```julia
@wrap_expr_method value_counts(expr::Expr; sort::Bool = false, parallel::Bool = false, name::AbstractString = "count", normalize::Bool = false) polars_expr_value_counts "Counts the occurrences of each unique value in `expr`, returning a `Struct` column mapping value to count (field `name`, default `\"count\"`). If `sort` is `true`, results are sorted by count descending. If `normalize` is `true`, counts become fractions of the total instead."

@curry value_counts(; sort::Bool = false, parallel::Bool = false, name::AbstractString = "count", normalize::Bool = false)
```

Note the keyword-argument order in the generated ccall follows *declaration* order of the keyword
parameters, which here matches the original hand-written ccall's `sort, parallel, name,
ncodeunits(name), normalize` order — double check this against `_gen_expr_parts`'s behavior
(kwparams processed in the order they appear in the signature) before trusting it blindly; if the
generated arity/order assertion in `_resolve_fallible` fails at `] test`/build time, it will name
exactly what it expected, so a mismatch here is a loud compile-time error, not a silent bug.

- [ ] **Step 2:** `julia --project=. -e 'using Pkg; Pkg.test()'` — expect the Task 8 baseline.
  Specifically re-run any `value_counts` test with a non-default `name` keyword to confirm the
  `AbstractString` marshalling path is actually exercised, not just the `"count"` default.

- [ ] **Step 3:** Commit:

```bash
git add src/expr/statistics.jl
git commit -m "Julia: reuse @wrap_expr_method for value_counts, fix its String->AbstractString marshalling footgun"
```

---

## Task 12: `datetime.jl`/`expr.jl` — curry-sibling cleanup onto `@curry`; add `cast_datetime`'s missing curry

**Files:**
- Modify: `src/expr/datetime.jl:117-122` (`cast_time_unit`), `src/expr/datetime.jl:141-146`
  (`with_time_unit`), `src/expr/datetime.jl:164-169` (`combine`), `src/expr/datetime.jl:315-326`
  (`replace_time_zone`), `src/expr/expr.jl:361-410ish` (`cast_datetime`, near `cast_duration`).

- [ ] **Step 1:** In `src/expr/datetime.jl`, replace the hand-written curry:

```julia
"""
    cast_time_unit(; time_unit::Symbol)::Base.Callable

Curried form of [`cast_time_unit`](@ref) for use with `|>`.
"""
cast_time_unit(; time_unit::Symbol) = expr -> cast_time_unit(expr; time_unit)
```

with:

```julia
@curry cast_time_unit(; time_unit::Symbol)
```

Apply the identical substitution to `with_time_unit` (`@curry with_time_unit(; time_unit::Symbol)`)
and `combine` (`@curry combine(time::Expr; time_unit::Symbol = :us)`) — verify `@curry`'s generated
docstring header (`_gen_expr_doc`... actually `@curry`'s own docstring template, "Curried form of
[`f`](@ref) for use with `|>`.") matches what's being deleted closely enough that no information is
lost; if a hand-written curry's docstring carries any extra prose beyond that boilerplate line,
keep it as a suffix in a manual `Docs.@doc` call rather than silently dropping it (check all three
before assuming they're boilerplate-only — `combine`'s currently is, per the file content already
read for this plan).

- [ ] **Step 2:** Replace `replace_time_zone`'s hand-written curry (`datetime.jl:315-326`):

```julia
"""
    replace_time_zone(tz::Union{Nothing,String} = nothing; ambiguous::String = "raise",
                       non_existent::Symbol = :raise)::Base.Callable

Curried form of [`replace_time_zone`](@ref) for use with `|>`.
"""
function replace_time_zone(
        tz::Union{Nothing, AbstractString} = nothing;
        ambiguous::AbstractString = "raise", non_existent::Symbol = :raise
    )
    return expr -> replace_time_zone(expr, tz; ambiguous, non_existent)
end
```

with:

```julia
@curry replace_time_zone(tz::Union{Nothing, AbstractString} = nothing; ambiguous::AbstractString = "raise", non_existent::Symbol = :raise)
```

- [ ] **Step 3:** In `src/expr/expr.jl`, near `cast_duration`'s existing `@curry cast_duration(;
  time_unit::Symbol = :us)` line, add the currently-missing curry for `cast_datetime`:

```julia
@curry cast_datetime(; time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing)
```

placed immediately after `cast_datetime`'s own function definition (mirroring where
`cast_duration`'s curry sits relative to its primal — locate both by searching for `function
cast_datetime` and `function cast_duration` in `src/expr/expr.jl`).

- [ ] **Step 4:** `julia --project=. -e 'using Pkg; Pkg.test()'`. `cast_datetime`'s curry is new
  behavior surface (previously `cast_datetime(; time_unit, time_zone) |> ...` piping did not exist)
  — search `test/` for existing `cast_duration`-curry tests (e.g. `test/expr/` or wherever temporal
  constructors are tested) and add one analogous `cast_datetime` curry test if none exists, since
  this is the one part of this task that is not a pure refactor of already-tested behavior. Keep
  it minimal — one `col("x") |> cast_datetime(time_unit=:ms)`-shaped assertion is enough.

- [ ] **Step 5:** Commit:

```bash
git add src/expr/datetime.jl src/expr/expr.jl test/
git commit -m "Julia: reuse @curry for cast_time_unit/with_time_unit/combine/replace_time_zone curry siblings, add cast_datetime's missing curry"
```

---

## Task 13: `_enum_lookup` adoption across 8 files

**Files:**
- Modify: `src/verbs.jl:34-44` (`Base.unique`'s `keep_enum`), `src/reshape.jl:121-127` (`pivot`'s
  `naming_enum`), `src/join.jl:1-18` (`_join_coalesce_enum`, `_join_validation_enum`),
  `src/io/csv.jl:1-18` (`_quote_style_enum`, `_csv_compression_enum`), `src/io/parquet.jl:155-165`
  (`_parquet_compression_enum`), `src/io/ipc.jl` (`_ipc_compression_enum`), `src/group_by.jl:94-114`
  (`group_by_dynamic`'s `label_cenum`/`closed_cenum`/`start_by_cenum`) and `src/group_by.jl:169-173`
  (`rolling`'s `closed_cenum`).

`_enum_lookup(sym::Symbol, label::AbstractString, mapping::Pair{Symbol}...)` already exists in
`macros.jl:103-109` and is already used consistently inside `src/expr/`; this task is pure
adoption in the files outside `src/expr/` that never picked it up, plus `group_by.jl`'s three enum
chains (found during this plan's own research, not the original two-agent sweep — same pattern,
same fix).

- [ ] **Step 1:** In `src/verbs.jl`, replace:

```julia
    keep_enum = if keep == :first
        API.PolarsUniqueKeepFirst
    elseif keep == :last
        API.PolarsUniqueKeepLast
    elseif keep == :none
        API.PolarsUniqueKeepNone
    elseif keep == :any
        API.PolarsUniqueKeepAny
    else
        error("unknown keep strategy $keep, expected one of (:first, :last, :none, :any)")
    end
```

with:

```julia
    keep_enum = _enum_lookup(
        keep, "keep strategy",
        :first => API.PolarsUniqueKeepFirst, :last => API.PolarsUniqueKeepLast,
        :none => API.PolarsUniqueKeepNone, :any => API.PolarsUniqueKeepAny,
    )
```

- [ ] **Step 2:** In `src/reshape.jl`, replace `pivot`'s `naming_enum` chain (lines 121-127) with:

```julia
    naming_enum = _enum_lookup(
        column_naming, "column_naming",
        :auto => API.PolarsPivotColumnNamingAuto, :combine => API.PolarsPivotColumnNamingCombine,
    )
```

- [ ] **Step 3:** In `src/join.jl`, replace both standalone functions (lines 1-18):

```julia
function _join_coalesce_enum(coalesce::Symbol)
    coalesce == :join_specific && return API.PolarsJoinCoalesceJoinSpecific
    coalesce == :coalesce_columns && return API.PolarsJoinCoalesceCoalesceColumns
    coalesce == :keep_columns && return API.PolarsJoinCoalesceKeepColumns
    return error(
        "unknown coalesce $coalesce, expected one of (:join_specific, :coalesce_columns, :keep_columns)"
    )
end

function _join_validation_enum(validate::Symbol)
    validate == :many_to_many && return API.PolarsJoinValidationManyToMany
    validate == :many_to_one && return API.PolarsJoinValidationManyToOne
    validate == :one_to_many && return API.PolarsJoinValidationOneToMany
    validate == :one_to_one && return API.PolarsJoinValidationOneToOne
    return error(
        "unknown validate $validate, expected one of (:many_to_many, :many_to_one, :one_to_many, :one_to_one)"
    )
end
```

with:

```julia
_join_coalesce_enum(coalesce::Symbol) = _enum_lookup(
    coalesce, "coalesce",
    :join_specific => API.PolarsJoinCoalesceJoinSpecific,
    :coalesce_columns => API.PolarsJoinCoalesceCoalesceColumns,
    :keep_columns => API.PolarsJoinCoalesceKeepColumns,
)

_join_validation_enum(validate::Symbol) = _enum_lookup(
    validate, "validate",
    :many_to_many => API.PolarsJoinValidationManyToMany,
    :many_to_one => API.PolarsJoinValidationManyToOne,
    :one_to_many => API.PolarsJoinValidationOneToMany,
    :one_to_one => API.PolarsJoinValidationOneToOne,
)
```

(Both functions' *names* and call sites stay identical — only their bodies collapse to one
`_enum_lookup` call each.)

- [ ] **Step 4:** In `src/io/csv.jl`, replace `_quote_style_enum`/`_csv_compression_enum`
  (lines 1-18) with the same one-line-body pattern:

```julia
_quote_style_enum(quote_style::Symbol) = _enum_lookup(
    quote_style, "quote_style",
    :necessary => API.PolarsQuoteStyleNecessary, :always => API.PolarsQuoteStyleAlways,
    :non_numeric => API.PolarsQuoteStyleNonNumeric, :never => API.PolarsQuoteStyleNever,
)

_csv_compression_enum(compression::Symbol) = _enum_lookup(
    compression, "compression",
    :uncompressed => API.PolarsCsvCompressionUncompressed, :gzip => API.PolarsCsvCompressionGzip,
    :zstd => API.PolarsCsvCompressionZstd,
)
```

- [ ] **Step 5:** In `src/io/parquet.jl`, replace `_parquet_compression_enum` (lines 155-165) with:

```julia
_parquet_compression_enum(compression::Symbol) = _enum_lookup(
    compression, "compression",
    :uncompressed => API.PolarsParquetCompressionUncompressed,
    :snappy => API.PolarsParquetCompressionSnappy, :gzip => API.PolarsParquetCompressionGzip,
    :brotli => API.PolarsParquetCompressionBrotli, :zstd => API.PolarsParquetCompressionZstd,
    :lz4_raw => API.PolarsParquetCompressionLz4Raw,
)
```

- [ ] **Step 6:** In `src/io/ipc.jl`, replace `_ipc_compression_enum` (near the top of the file)
  with:

```julia
_ipc_compression_enum(compression::Symbol) = _enum_lookup(
    compression, "compression",
    :uncompressed => API.PolarsIpcCompressionUncompressed, :lz4 => API.PolarsIpcCompressionLz4,
    :zstd => API.PolarsIpcCompressionZstd,
)
```

- [ ] **Step 7:** In `src/group_by.jl`, replace `group_by_dynamic`'s three ternary chains
  (lines 94-114):

```julia
    label_cenum = label === :left ? API.PolarsLabelLeft :
        label === :right ? API.PolarsLabelRight :
        label === :data_point ? API.PolarsLabelDataPoint :
        error("invalid label $label, expected :left, :right, or :data_point")

    closed_cenum = closed === :left ? API.PolarsClosedWindowLeft :
        closed === :right ? API.PolarsClosedWindowRight :
        closed === :both ? API.PolarsClosedWindowBoth :
        closed === :none ? API.PolarsClosedWindowNone :
        error("invalid closed $closed, expected :left, :right, :both, or :none")

    start_by_cenum = start_by === :window_bound ? API.PolarsStartByWindowBound :
        start_by === :data_point ? API.PolarsStartByDataPoint :
        start_by === :monday ? API.PolarsStartByMonday :
        start_by === :tuesday ? API.PolarsStartByTuesday :
        start_by === :wednesday ? API.PolarsStartByWednesday :
        start_by === :thursday ? API.PolarsStartByThursday :
        start_by === :friday ? API.PolarsStartByFriday :
        start_by === :saturday ? API.PolarsStartBySaturday :
        start_by === :sunday ? API.PolarsStartBySunday :
        error("invalid start_by $start_by")
```

with:

```julia
    label_cenum = _enum_lookup(
        label, "label",
        :left => API.PolarsLabelLeft, :right => API.PolarsLabelRight,
        :data_point => API.PolarsLabelDataPoint,
    )

    closed_cenum = _enum_lookup(
        closed, "closed",
        :left => API.PolarsClosedWindowLeft, :right => API.PolarsClosedWindowRight,
        :both => API.PolarsClosedWindowBoth, :none => API.PolarsClosedWindowNone,
    )

    start_by_cenum = _enum_lookup(
        start_by, "start_by",
        :window_bound => API.PolarsStartByWindowBound, :data_point => API.PolarsStartByDataPoint,
        :monday => API.PolarsStartByMonday, :tuesday => API.PolarsStartByTuesday,
        :wednesday => API.PolarsStartByWednesday, :thursday => API.PolarsStartByThursday,
        :friday => API.PolarsStartByFriday, :saturday => API.PolarsStartBySaturday,
        :sunday => API.PolarsStartBySunday,
    )
```

and `rolling`'s single `closed_cenum` chain (lines 169-173, identical shape to
`group_by_dynamic`'s `closed_cenum` above) with the same `_enum_lookup(closed, "closed", ...)`
call. Note `_enum_lookup`'s auto-generated error message (`"unknown $label $sym, expected one of
($valid)"`) reads slightly differently from each of these hand-written ones (`"invalid $label
$sym, expected ..."`, `"unknown $label $sym, expected one of (...)"`) — this is an intentional
minor wording normalization, not a bug; if any existing test asserts on the exact error string,
update that assertion to match `_enum_lookup`'s wording (search `test/` for `"invalid label"`,
`"invalid closed"`, `"invalid start_by"`, `"unknown keep strategy"`, etc. before assuming none do).

- [ ] **Step 8:** `_enum_lookup` is defined in `macros.jl`, which every one of these files already
  has implicit access to (all `include`d directly into the top-level `Polars` module scope, per
  `macros.jl`'s own docstring already citing this fact) — no new `using`/import needed anywhere
  in this task. Confirm this holds by building; a missing binding would be a loud `UndefVarError`
  at load time, not a silent failure.

- [ ] **Step 9:** `julia --project=. -e 'using Pkg; Pkg.test()'` — expect the Task 8 baseline
  (modulo any error-message-wording test updates from Step 7).

- [ ] **Step 10:** Commit:

```bash
git add src/verbs.jl src/reshape.jl src/join.jl src/io/csv.jl src/io/parquet.jl src/io/ipc.jl src/group_by.jl test/
git commit -m "Julia: adopt _enum_lookup in verbs/reshape/join/csv/parquet/ipc/group_by, replacing hand-rolled enum chains"
```

---

## Task 14: Add `_expr_ptrs`; migrate the `Vector{Expr}`-to-`GC.@preserve`d-`Ptr`-array sites

**Files:**
- Modify: `src/macros.jl` (add `_expr_ptrs`), `src/select.jl:1-9,50-57`, `src/group_by.jl:35-42,
  50-57`, `src/sort.jl:57-83,114-134`, `src/join.jl:38-51`, `src/expr/struct.jl:56-63`,
  `src/expr/expr.jl:1142-1158,1168-1184,1204-1212,1235-1244,1264-1271`, `src/dataframe.jl` (Series
  ptrs site), `src/verbs.jl:173-179,187-195`.

**Interfaces:** Produces `_expr_ptrs(exprs::Vector{Expr}) -> (owned::Vector{Expr},
ptrs::Vector{Ptr{polars_expr_t}})` in `macros.jl`, next to `_name_ptrs` (whose docstring it mirrors
in spirit — same "the returned owner, not your argument, is what you preserve" contract).

- [ ] **Step 1:** Add to `macros.jl`, immediately after `_enum_lookup`'s definition:

```julia
"""
    _expr_ptrs(exprs::Vector{Expr}) -> (owned::Vector{Expr}, ptrs::Vector{Ptr{polars_expr_t}})

Builds the `(owned, ptrs)` pair for passing a `Vector{Expr}` across the C ABI -- mirrors
[`_name_ptrs`](@ref) for `Vector{String}`. `owned === exprs` always (an `Expr` already owns a
handle rather than needing conversion, unlike `_name_ptrs`'s `Vector{Symbol}` case), kept as a
separate return purely so both helpers share the same `owned, ptrs = _thing_ptrs(...)` calling
convention and the same "preserve `owned`, not your original argument" discipline. `ptrs` is what
goes into the ccall alongside `length(ptrs)`.
"""
_expr_ptrs(exprs::Vector{Expr}) = (exprs, Ptr{polars_expr_t}[e.ptr for e in exprs])
```

- [ ] **Step 2:** In `src/select.jl`, replace `_select!` (lines 2-9):

```julia
function _select!(df::LazyFrame, exprs::Vector)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        polars_lazy_frame_select(df, exprs_ptrs, length(exprs_ptrs))
    end
    return df
end
```

with:

```julia
function _select!(df::LazyFrame, exprs::Vector)
    owned, ptrs = _expr_ptrs(_expr_vector(exprs))
    GC.@preserve owned begin
        polars_lazy_frame_select(df, ptrs, length(ptrs))
    end
    return df
end
```

Apply the identical transformation to `_with_columns!` (lines 51-57, calling
`polars_lazy_frame_with_columns`).

- [ ] **Step 3:** In `src/group_by.jl`, apply the identical transformation to `groupby`
  (lines 35-42, calling `polars_lazy_frame_group_by(df, exprs_ptrs, length(exprs_ptrs),
  maintain_order)` — note the extra `maintain_order` trailing arg carries through unchanged) and
  `agg` (lines 50-57, calling `polars_lazy_group_by_agg`).

- [ ] **Step 4:** In `src/sort.jl`, apply it to `_sort!` (lines 72-80,
  `API.polars_lazy_frame_sort(df, exprs_ptrs, nexprs, descending, nulls_last, maintain_order)`) and
  `_top_or_bottom_k!` (lines 126-131, the `f(df, k, exprs_ptrs, nexprs, descending,
  maintain_order)` call where `f` is `API.polars_lazy_frame_bottom_k`/`_top_k`) — in both cases only
  the `GC.@preserve exprs begin ... exprs_ptrs = Ptr{polars_expr_t}[...] ... end` shape changes to
  `owned, exprs_ptrs = _expr_ptrs(exprs); GC.@preserve owned begin ... end`; the surrounding
  `descending`/`nulls_last`/`maintain_order` logic (which Task 17 also touches) is untouched by
  this task.

- [ ] **Step 5:** In `src/join.jl`'s `_join` (lines 38-45), apply it to *both* `exprs_a_ptr` and
  `exprs_b_ptr`:

```julia
    owned_a, exprs_a_ptr = _expr_ptrs(exprs_a)
    owned_b, exprs_b_ptr = _expr_ptrs(exprs_b)
    GC.@preserve owned_a owned_b begin
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_join(
            a, b,
            exprs_a_ptr, length(exprs_a_ptr),
            exprs_b_ptr, length(exprs_b_ptr),
            how, suffix_arg, suffix_len, coalesce_enum, validate_enum, nulls_equal,
            Ptr{Int64}(C_NULL), Ptr{Csize_t}(C_NULL), out,
        )
        polars_error(err)
    end
```

- [ ] **Step 6:** In `src/expr/struct.jl`'s `with_fields` (lines 56-63), apply it (note this one
  currently calls `API.polars_expr_struct_with_fields(expr, ptrs, length(ptrs))` directly — an
  infallible call, not through `Ref{Ptr{polars_expr_t}}()`/`polars_error`, so keep that infallible
  shape, only swap the ptr-building):

```julia
function with_fields(expr::Expr, fields::Expr...)
    owned, ptrs = _expr_ptrs(collect(Expr, fields))
    GC.@preserve owned begin
        out = API.polars_expr_struct_with_fields(expr, ptrs, length(ptrs))
    end
    return Expr(out)
end
```

- [ ] **Step 7:** In `src/expr/expr.jl`, apply it to `top_k_by`/`bottom_k_by` (the `by_ptrs =
  Ptr{polars_expr_t}[e.ptr for e in by]` lines inside each, ~1142-1158/1168-1184 — leave the
  `descending` resolution above untouched here, Task 17 handles that separately), `Base.coalesce`
  (~1204-1212, the `ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]` line), `concat_str`
  (~1235-1244), and `format` (~1264-1271) — each following the same `owned, ptrs = _expr_ptrs(...)`
  substitution inside its existing `GC.@preserve` block (renaming the preserved variable from
  `exprs`/`by` to `owned` at each site, and dropping the separate `ptrs = Ptr{...}[...]` line).

- [ ] **Step 8:** In `src/dataframe.jl`, locate the `Series`-vector ptr-building site (grep
  `Ptr{polars_series_t}\[` in `src/dataframe.jl`) and apply the analogous transformation using a
  `Series`-typed sibling — add a second method to `_expr_ptrs` rather than a new function name,
  since the shape is identical modulo pointer type:

```julia
_expr_ptrs(series::Vector{Series}) = (series, Ptr{polars_series_t}[s.ptr for s in series])
```

(Despite the name, `_expr_ptrs` is being used here as "the generic `_thing_ptrs` helper for any
`polars_*_t`-wrapping Julia type with a `.ptr` field" — if this reads awkwardly once you're looking
at both call sites side by side, renaming it to `_handle_ptrs` throughout Steps 1-8 is a reasonable
judgment call; make it before committing, not after, so the name is consistent everywhere in one
commit.)

- [ ] **Step 9:** In `src/verbs.jl`, apply the `LazyFrame`-typed variant (a third method, same
  reasoning as Step 8) to `concat` (lines 173-179) and the `Series`-typed variant (reusing Step 8's
  method) to `hstack` (lines 187-195).

- [ ] **Step 10:** `julia --project=. -e 'using Pkg; Pkg.test()'` — expect the Task 8 baseline. This
  is the largest single-task diff in this plan (11 call sites across 8 files); if anything regresses,
  bisect by reverting one file's hunk at a time rather than the whole commit.

- [ ] **Step 11:** Commit:

```bash
git add src/macros.jl src/select.jl src/group_by.jl src/sort.jl src/join.jl src/expr/struct.jl src/expr/expr.jl src/dataframe.jl src/verbs.jl
git commit -m "Julia: add _expr_ptrs (mirroring _name_ptrs), dedup the Vector{Expr}/Series/LazyFrame-to-GC.@preserve'd-ptr-array pattern across 11 call sites"
```

---

## Task 15: Add `_nullable_ref`/`_nullable_str`; migrate the nullable-scalar/string dances

**Files:**
- Modify: `src/macros.jl` (add both helpers; update the "Not yet covered" header comment),
  `src/expr/statistics.jl:177,198`, `src/expr/list.jl:106,122`, `src/expr/expr.jl:604,757,1064,
  1082`, `src/io/csv.jl:100-110,189-199,260-270`, `src/io/json.jl:58-63`, `src/io/parquet.jl:117-
  122,201-202,258-259,311-312`, `src/io/ipc.jl:60-65,113-114,158-159`.

- [ ] **Step 1:** Add to `macros.jl`, right after `_expr_ptrs`:

```julia
"""
    _nullable_ref(x, ::Type{T}) where T -> Union{Ptr{T}, Ref{T}}

`x === nothing` yields the null pointer `Ptr{T}(C_NULL)`; otherwise `Ref(T(x))`. The `Ref` this
returns is a fresh local allocation and must be kept alive across the ccall that consumes it via
`GC.@preserve` *at the call site* -- exactly as if you had written the ternary by hand -- since a
`Ref` allocated before a ccall and only reachable through the ccall's own converted argument is a
live GC safepoint (see CLAUDE.md's marshalling section).
"""
_nullable_ref(x, ::Type{T}) where {T} = x === nothing ? Ptr{T}(C_NULL) : Ref(T(x))

"""
    _nullable_str(s::Union{Nothing,AbstractString}) -> (ptr, len::Int)

`s === nothing` yields `(Ptr{UInt8}(C_NULL), 0)`; otherwise `(s, ncodeunits(s))` -- the `(ptr, len)`
pair the C ABI expects for an optional string. Returns the string `s` itself (not a materialized
pointer) as the first element, exactly as every existing hand-written call site already did, so it
continues to rely on `ccall`'s own automatic rooting of a directly-passed `String` argument for the
duration of the call -- no additional `GC.@preserve` is needed for the string half specifically
(only for any *other* `Ref`s built alongside it, per [`_nullable_ref`](@ref) above).
"""
_nullable_str(s::Union{Nothing, AbstractString}) = s === nothing ? (Ptr{UInt8}(C_NULL), 0) : (s, ncodeunits(s))
```

- [ ] **Step 2:** In `src/expr/statistics.jl` and `src/expr/list.jl`, replace each
  `x === nothing ? Ptr{T}(C_NULL) : Ref(T(x))` occurrence (4 sites:
  `statistics.jl:177,198`, `list.jl:106,122` — all `seed`-shaped) with
  `_nullable_ref(x, T)`, e.g. `list.jl:106`:

```julia
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
```

becomes

```julia
    seed_ref = _nullable_ref(seed, UInt64)
```

The surrounding `GC.@preserve seed_ref ... end` block is untouched — `seed_ref` still needs
preserving, exactly as documented in `_nullable_ref`'s own docstring above.

- [ ] **Step 3:** In `src/expr/expr.jl`, apply the identical substitution at the 4 remaining
  `Ref(T(x))`-vs-`Ptr{T}(C_NULL)` sites (`expr.jl:604,757,1064,1082` — locate by grepping
  `=== nothing \? Ptr{` in that file, since exact surrounding variable names differ per site).

- [ ] **Step 4:** In `src/io/csv.jl`, `src/io/json.jl`, `src/io/parquet.jl`, `src/io/ipc.jl`,
  replace each paired
  `x_arg = x === nothing ? Ptr{UInt8}(C_NULL) : x; x_len = x === nothing ? 0 : ncodeunits(x)` with
  a single `_nullable_str` call, e.g. `io/csv.jl:189-190`:

```julia
    null_value_arg = null_value === nothing ? Ptr{UInt8}(C_NULL) : null_value
    null_value_len = null_value === nothing ? 0 : ncodeunits(null_value)
```

becomes

```julia
    null_value_arg, null_value_len = _nullable_str(null_value)
```

Apply this to every one of the ~25 paired occurrences across the 4 files listed above (`null_value`,
`line_terminator`, `date_format`, `time_format`, `datetime_format` in both `write_csv` and
`sink_csv` in `csv.jl`; `row_index_name`, `include_file_paths` repeated across `scan_parquet`/
`scan_ipc`/`scan_ndjson`; etc.) — grep `=== nothing \? Ptr{UInt8}\(C_NULL\)` across `src/io/` to
enumerate every remaining site exhaustively before considering this step done, since the exact
variable names differ per call site and this list is illustrative, not necessarily exhaustive.
Where `_nullable_ref` also applies in the same function (e.g. `compression_level_ref`,
`row_group_size_ref`, `float_precision_ref`, `n_rows_ref`, `hive_partitioning_ref`,
`infer_schema_length_ref` — all the `Ptr{T}(C_NULL) : Ref(T(x))` shape), apply Step 1's
`_nullable_ref` helper there too, in the same pass over each file.

- [ ] **Step 5:** Update `macros.jl`'s "## Not yet covered" header comment (currently
  `macros.jl:80-92`): remove the first bullet ("the nullable-scalar shape...") and the reference to
  `sample_n`/`sample_frac`/`fill_null` in it, since `_nullable_ref`/`_nullable_str` now cover it —
  replace that bullet with a short note pointing at the new helpers instead, e.g.:

```
#   - the nullable-scalar/nullable-string shapes are now covered by `_nullable_ref`/`_nullable_str`
#     -- reach for those directly rather than restating the `x === nothing ? Ptr{T}(C_NULL) : ...`
#     ternary by hand.
```

- [ ] **Step 6:** `julia --project=. -e 'using Pkg; Pkg.test()'` — expect the Task 8 baseline. This
  touches every scan/write/sink entry point in `src/io/`, so run the io-specific test files
  individually first if the full suite is slow to iterate on (`test/dataframe/io.jl`,
  `test/lazyframe/scan_parquet.jl`, `test/lazyframe/sink_parquet.jl`, `test/lazyframe/sink_csv.jl`,
  `test/lazyframe/sink_ipc.jl`, and their siblings under `test/io/` if any — check
  `test/runtests.jl`'s `include(...)` list for the exact set).

- [ ] **Step 7:** Commit:

```bash
git add src/macros.jl src/expr/statistics.jl src/expr/list.jl src/expr/expr.jl src/io/csv.jl src/io/json.jl src/io/parquet.jl src/io/ipc.jl
git commit -m "Julia: add _nullable_ref/_nullable_str, dedup the nullable-scalar/nullable-string dance across ~30 call sites"
```

---

## Task 16: Add `_io_read`; migrate the "materialize a Rust-written buffer" sites

**Files:**
- Modify: `src/macros.jl` (add `_io_read`), `src/dataframe.jl:138-144` (`native_repr`),
  `src/lazyframe.jl:98-104` (`explain`), `src/value.jl:59-81` (`load_value` String/`Vector{UInt8}`
  methods), `src/expr/meta.jl:21-28` (`output_name`), `src/expr/meta.jl` (`root_names`,
  `_tree_format`).

- [ ] **Step 1:** Add to `macros.jl`, right after `_nullable_str`:

```julia
"""
    _io_read(f) -> Vector{UInt8}

Calls `f(io::Ref{IOBuffer}, callback)` -- expected to invoke one `API.polars_*` ccall taking `io`
and `callback` as its trailing two arguments and returning a `*const polars_error_t`-shaped `err`
-- checks that `err` via [`polars_error`](@ref), and returns the bytes `f` wrote into `io[]`.
Shared by every FFI site that streams bytes back into a *fresh* Julia value (contrast
`write_csv`/`write_parquet`, which stream into a caller-supplied `io`, and so build their own
`_io_callback()`/`Ref(io)` pair directly rather than through this helper).
"""
function _io_read(f)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = f(io, callback)
    polars_error(err)
    return take!(io[])
end
```

- [ ] **Step 2:** In `src/dataframe.jl`, replace `native_repr` (lines 138-144):

```julia
function native_repr(df::DataFrame)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = API.polars_dataframe_show(df, io, callback)
    polars_error(err)
    return String(take!(io[]))
end
```

with:

```julia
native_repr(df::DataFrame) = String(_io_read((io, cb) -> API.polars_dataframe_show(df, io, cb)))
```

- [ ] **Step 3:** In `src/lazyframe.jl`, replace `explain` (lines 98-104) with:

```julia
explain(df::LazyFrame; optimized::Bool = true) =
    String(_io_read((io, cb) -> API.polars_lazy_frame_explain(df, optimized, io, cb)))
```

- [ ] **Step 4:** In `src/value.jl`, replace:

```julia
function load_value(value::Value{String})
    polars_value_type(value) == PolarsValueTypeNull && return missing

    io = Ref(IOBuffer())
    callback = _io_callback()

    err = polars_value_string_get(value, io, callback)
    polars_error(err)

    return String(take!(io[]))
end

function load_value(value::Value{Vector{UInt8}})
    polars_value_type(value) == PolarsValueTypeNull && return missing

    io = Ref(IOBuffer())
    callback = _io_callback()

    err = polars_value_binary_get(value, io, callback)
    polars_error(err)

    return take!(io[])
end
```

with:

```julia
function load_value(value::Value{String})
    polars_value_type(value) == PolarsValueTypeNull && return missing
    return String(_io_read((io, cb) -> polars_value_string_get(value, io, cb)))
end

function load_value(value::Value{Vector{UInt8}})
    polars_value_type(value) == PolarsValueTypeNull && return missing
    return _io_read((io, cb) -> polars_value_binary_get(value, io, cb))
end
```

- [ ] **Step 5:** In `src/expr/meta.jl`, replace `output_name` (lines 21-28):

```julia
function output_name(expr)
    expr = _as_expr(expr)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = API.polars_expr_meta_output_name(expr, io, callback)
    polars_error(err)
    return String(take!(io[]))
end
```

with:

```julia
function output_name(expr)
    expr = _as_expr(expr)
    return String(_io_read((io, cb) -> API.polars_expr_meta_output_name(expr, io, cb)))
end
```

Apply the same shape to `_tree_format` (used by both `tree_format`/`show_graph`) — replace:

```julia
function _tree_format(expr, display_as_dot::Bool)
    expr = _as_expr(expr)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = API.polars_expr_meta_tree_format(expr, display_as_dot, io, callback)
    polars_error(err)
    return String(take!(io[]))
end
```

with:

```julia
function _tree_format(expr, display_as_dot::Bool)
    expr = _as_expr(expr)
    return String(_io_read((io, cb) -> API.polars_expr_meta_tree_format(expr, display_as_dot, io, cb)))
end
```

For `root_names` (the per-element loop variant), keep the loop structure but replace its
per-iteration `io`/`callback`/`err`/`polars_error` block with a call to `_io_read`:

```julia
function root_names(expr)
    expr = _as_expr(expr)
    # `n` is `Csize_t` (unsigned): `n - 1` at `n == 0` (a real case -- e.g. a bare literal) would
    # wrap around instead of underflowing to a negative, turning `0:(n - 1)` into a giant nonempty
    # range instead of the intended empty one. Convert to a signed `Int` first.
    n = Int(API.polars_expr_meta_root_names_len(expr))
    callback = _io_callback()
    names = Vector{String}(undef, n)
    for i in 0:(n - 1)
        io = Ref(IOBuffer())
        err = API.polars_expr_meta_root_names_get(expr, i, io, callback)
        polars_error(err)
        names[i + 1] = String(take!(io[]))
    end
    return names
end
```

becomes:

```julia
function root_names(expr)
    expr = _as_expr(expr)
    # `n` is `Csize_t` (unsigned): `n - 1` at `n == 0` (a real case -- e.g. a bare literal) would
    # wrap around instead of underflowing to a negative, turning `0:(n - 1)` into a giant nonempty
    # range instead of the intended empty one. Convert to a signed `Int` first.
    n = Int(API.polars_expr_meta_root_names_len(expr))
    names = Vector{String}(undef, n)
    for i in 0:(n - 1)
        names[i + 1] = String(_io_read((io, cb) -> API.polars_expr_meta_root_names_get(expr, i, io, cb)))
    end
    return names
end
```

(`_io_read` builds a fresh `callback = _io_callback()` every loop iteration here, where the
original built it once outside the loop — a `@cfunction` pointer is cheap and stateless to
rebuild, so this is a non-issue functionally, but note it as a minor efficiency regression if
`root_names` is ever called on an expression with very many root columns; not worth a special case
for this plan.)

- [ ] **Step 6:** `julia --project=. -e 'using Pkg; Pkg.test()'` — expect the Task 8 baseline.

- [ ] **Step 7:** Commit:

```bash
git add src/macros.jl src/dataframe.jl src/lazyframe.jl src/value.jl src/expr/meta.jl
git commit -m "Julia: add _io_read, dedup the IOBuffer-materialization pattern across native_repr/explain/load_value/Meta.output_name/Meta.root_names/Meta._tree_format"
```

---

## Task 17: Add `@wrap_path_writer`; migrate 4 of the 5 `path::String`-sibling writers

**Files:**
- Modify: `src/macros.jl` (add `@wrap_path_writer`), `src/io/csv.jl:215-218` (`write_csv`),
  `src/io/ipc.jl:126-129` (`write_ipc`), `src/io/json.jl:105-108,126-129` (`write_json`,
  `write_ndjson`).

`write_parquet`'s `path::String` sibling (`io/parquet.jl:215-218`) stays hand-written — it routes a
cloud-URI path to `sink_parquet` instead of erroring, the one genuinely asymmetric case; do not
touch it in this task.

- [ ] **Step 1:** Add to `macros.jl`, right after `_io_read`:

```julia
"""
    @wrap_path_writer fname errmsg

**Use this when** an `fname(io::IO, df::DataFrame; kwargs...)` primal already exists and a
`path::String` local-file sibling is all that's missing. Generates:

    fname(p::String, df::DataFrame; kwargs...) = begin
        occursin("://", p) && error(errmsg)
        open(io -> fname(io, df; kwargs...), p, "w")
    end

Not a fit for `write_parquet`, whose `path::String` sibling *routes* a `"://"` path to
`sink_parquet` instead of erroring -- the one asymmetric case, which stays hand-written.
"""
macro wrap_path_writer(fname, errmsg)
    return esc(
        quote
            function $fname(p::String, df::DataFrame; kwargs...)
                occursin("://", p) && error($errmsg)
                return open(io -> $fname(io, df; kwargs...), p, "w")
            end
        end
    )
end
```

- [ ] **Step 2:** In `src/io/csv.jl`, replace:

```julia
function write_csv(p::String, df::DataFrame; kwargs...)
    occursin("://", p) && error("write_csv writes local files; use sink_csv for cloud URIs")
    return open(io -> write_csv(io, df; kwargs...), p, "w")
end
```

with:

```julia
@wrap_path_writer write_csv "write_csv writes local files; use sink_csv for cloud URIs"
```

- [ ] **Step 3:** In `src/io/ipc.jl`, replace the analogous `write_ipc(p::String, ...)` (lines
  126-129) with:

```julia
@wrap_path_writer write_ipc "write_ipc writes local files; use sink_ipc for cloud URIs"
```

- [ ] **Step 4:** In `src/io/json.jl`, replace `write_json(p::String, ...)` (lines 105-108) with:

```julia
@wrap_path_writer write_json "write_json writes local files only; there is no cloud sink for plain JSON"
```

and `write_ndjson(p::String, ...)` (lines 126-129) with:

```julia
@wrap_path_writer write_ndjson "write_ndjson writes local files; use sink_ndjson for cloud URIs"
```

- [ ] **Step 5:** `julia --project=. -e 'using Pkg; Pkg.test()'` — expect the Task 8 baseline;
  specifically confirm the existing tests that assert on a cloud-URI path raising each of these
  four exact error messages still pass unchanged (the macro reproduces the messages verbatim).

- [ ] **Step 6:** Commit:

```bash
git add src/macros.jl src/io/csv.jl src/io/ipc.jl src/io/json.jl
git commit -m "Julia: add @wrap_path_writer, dedup the path::String local-file-writer sibling for write_csv/write_ipc/write_json/write_ndjson"
```

---

## Task 18: Add `_resolve_descending`; migrate the `rev`-to-`descending`-vector sites

**Files:**
- Modify: `src/macros.jl` (add `_resolve_descending`), `src/sort.jl:57-68` (`_sort!`),
  `src/sort.jl:114-122` (`_top_or_bottom_k!`), `src/expr/expr.jl:1141-1152` (`top_k_by`),
  `src/expr/expr.jl:1167-1177` (`bottom_k_by`).

- [ ] **Step 1:** Add to `macros.jl`, right after `@wrap_path_writer`:

```julia
"""
    _resolve_descending(rev, n::Integer, prefix::AbstractString) -> Vector{Bool}

Broadcasts a bare `rev::Bool` to `n` copies, or validates an already-`Vector` `rev` has exactly `n`
entries -- one per `\$prefix expression` (`prefix` is e.g. `"sort"`/`"key"`/`"by"`). Raises an
`ArgumentError` naming `prefix` if the lengths disagree -- a real exception, not an `@assert`: this
validates caller-supplied input, which the Julia manual says assertions (removable, "this cannot
happen") must not be used for.
"""
function _resolve_descending(rev, n::Integer, prefix::AbstractString)
    descending = rev isa Bool ? fill(rev, n) : rev
    length(descending) == n || throw(
        ArgumentError(
            "rev must have one entry per $prefix expression (got $n $prefix expressions and " *
                "$(length(descending)) rev)"
        )
    )
    return descending
end
```

Note this normalizes the exact wording of `_sort!`/`_top_or_bottom_k!`'s current messages (which
say plain "expressions" in the count clause, e.g. `"got $nexprs expressions"`) to match
`top_k_by`/`bottom_k_by`'s more informative style (`"got $n_by by expressions"`) — an intentional
minor wording normalization for consistency, not a behavior bug. If any test asserts the exact old
`_sort!`/`_top_or_bottom_k!` wording, update it in this task (search `test/` for `"one entry per
sort expression"`/`"one entry per key expression"` before assuming none do).

- [ ] **Step 2:** In `src/sort.jl`, replace `_sort!`'s validation block (lines 58-68):

```julia
    nexprs = length(exprs)
    descending = rev isa Bool ? fill(rev, nexprs) : rev
    # A real exception, not an `@assert`: this validates a user-supplied argument, which the Julia
    # manual explicitly says assertions (removable, and semantically "this cannot happen") must
    # not be used for.
    length(descending) == nexprs || throw(
        ArgumentError(
            "rev must have one entry per sort expression (got $nexprs expressions and " *
                "$(length(descending)) rev)"
        )
    )
```

with:

```julia
    nexprs = length(exprs)
    descending = _resolve_descending(rev, nexprs, "sort")
```

Apply the identical substitution to `_top_or_bottom_k!` (lines 115-122, prefix `"key"`).

- [ ] **Step 3:** In `src/expr/expr.jl`, apply the identical substitution to `top_k_by`
  (lines 1146-1152, prefix `"by"`) and `bottom_k_by` (lines 1172-1177, prefix `"by"`).

- [ ] **Step 4:** `julia --project=. -e 'using Pkg; Pkg.test()'` — expect the Task 8 baseline
  (modulo any error-message-wording test updates from Step 1).

- [ ] **Step 5:** Commit:

```bash
git add src/macros.jl src/sort.jl src/expr/expr.jl
git commit -m "Julia: add _resolve_descending, dedup the rev-to-descending-vector broadcast+validate pattern across sort/top_k_by/bottom_k_by"
```

---

## Task 19: Add `@curry`'s `fix2=true` option; migrate the 12 hand-written `Base.Fix2` curries

**Files:**
- Modify: `src/macros.jl` (`@curry`'s definition, lines 165-206), `src/expr/list.jl:48,60,72,134`
  (`head`, `tail`, `shift`, `count_matches`), `src/expr/string.jl:72-73` (`head`, `tail`),
  `src/expr/datetime.jl:55,75,278` (`strftime`, `to_string`, `convert_time_zone` — line numbers as
  of before Task 10/12 touched this file; re-locate by function name since those tasks shifted
  lines), `src/expr/struct.jl:16,28,45` (`field_by_name`, `field_by_index`, `rename_fields`).

Every other single-required-positional-argument, no-keywords function in the codebase already uses
`@curry` (a closure) for its curried form; these 12 are hand-written `Base.Fix2` instead, purely
because `@curry` cannot produce one. This task teaches it to, then migrates all 12 — restoring the
same "one macro, one convention" property this whole plan is about, for the one shape it didn't
cover yet.

**Interfaces:** `@curry`'s public macro syntax gains an optional trailing option:
`@curry f(x) fix2=true` (or `@curry f(x::Expr) fix2=true` for the `convert(Expr, ·)` case) instead
of `@curry f(x)`. Every existing `@curry f(...)` call site in the codebase (~40 of them) must keep
working unchanged — `fix2` is opt-in, defaulting to `false` (today's closure behavior).

- [ ] **Step 1:** In `src/macros.jl`, modify `@curry`'s signature and body (lines 165-206) to accept
  an optional `fix2 = true` trailing option and, when set, emit a `Base.Fix2` instead of a closure:

```julia
macro curry(sig, opts...)
    @assert sig isa Base.Expr && sig.head === :call "@curry expects a call signature, e.g. `@curry f(x; y=1)`"
    fix2 = false
    for opt in opts
        @assert opt isa Base.Expr && opt.head === :(=) && opt.args[1] === :fix2 "@curry: unknown option $opt (the only option is `fix2 = true`)"
        fix2 = opt.args[2] === true
    end
    fname = sig.args[1]
    posarg_decls, posarg_forwards = Any[], Any[]
    kwarg_decls, kwarg_forwards = Any[], Any[]
    for a in sig.args[2:end]
        if a isa Base.Expr && a.head === :parameters
            for kw in a.args
                decl, name, forward = _curry_arg(kw)
                push!(kwarg_decls, decl)
                push!(kwarg_forwards, forward === name ? name : Base.Expr(:kw, name, forward))
            end
        else
            decl, _, forward = _curry_arg(a)
            push!(posarg_decls, decl)
            push!(posarg_forwards, forward)
        end
    end

    curry_sig_args = Any[fname]
    isempty(kwarg_decls) || push!(curry_sig_args, Base.Expr(:parameters, kwarg_decls...))
    append!(curry_sig_args, posarg_decls)
    curry_sig = Base.Expr(:call, curry_sig_args...)

    if fix2
        @assert isempty(kwarg_decls) && length(posarg_decls) == 1 "@curry: fix2 = true only applies to a single required positional argument and no keywords"
        curry_def = Base.Expr(:(=), curry_sig, Base.Expr(:call, :(Base.Fix2), fname, posarg_forwards[1]))
        return_type = "Base.Fix2{typeof($fname)}"
    else
        call_args = Any[fname, :expr]
        append!(call_args, posarg_forwards)
        call_expr = Base.Expr(:call, call_args...)
        isempty(kwarg_forwards) || insert!(call_expr.args, 2, Base.Expr(:parameters, kwarg_forwards...))
        curry_def = Base.Expr(:(=), curry_sig, Base.Expr(:->, :expr, Base.Expr(:block, call_expr)))
        return_type = "Base.Callable"
    end

    docstring = """
        $(curry_sig)::$return_type

    Curried form of [`$fname`](@ref) for use with `|>`.
    """
    return esc(
        quote
            Docs.@doc $docstring $curry_sig
            $curry_def
        end
    )
end
```

Update `@curry`'s own docstring (immediately above the macro, lines 137-164) to document the
`fix2=true` option in one added paragraph, mirroring how `@wrap_simple_ops`'s docstring documents
its own `curried = true` option.

- [ ] **Step 2:** In `src/expr/list.jl`, replace:

```julia
head(n) = Base.Fix2(head, convert(Expr, n))
```

with:

```julia
@curry head(n::Expr) fix2 = true
```

(the `::Expr` annotation reproduces the existing `convert(Expr, n)` forwarding via `_curry_arg`'s
existing rule — verify the expansion matches by comparing generated code, e.g. with
`@macroexpand @curry head(n::Expr) fix2 = true`, against the exact line being deleted, before
moving on). Apply the identical transformation to `tail` (line 60), `shift` (line 72,
`@curry shift(n::Expr) fix2 = true`), and `count_matches` (line 134,
`@curry count_matches(element::Expr) fix2 = true`).

- [ ] **Step 3:** In `src/expr/string.jl`, replace `head(n) = Base.Fix2(head, convert(Expr, n))`
  and `tail(n) = Base.Fix2(tail, convert(Expr, n))` (lines 72-73) with
  `@curry head(n::Expr) fix2 = true` / `@curry tail(n::Expr) fix2 = true`.

- [ ] **Step 4:** In `src/expr/datetime.jl` (after Tasks 10/12's edits — locate by function name,
  not the line numbers above), replace `strftime(format::AbstractString) = Base.Fix2(strftime,
  format)` with `@curry strftime(format::AbstractString) fix2 = true` (no `::Expr` involved here,
  so `_curry_arg`'s fallback rule forwards `format` unconverted, matching exactly); replace
  `to_string(format::AbstractString) = Base.Fix2(to_string, format)` with
  `@curry to_string(format::AbstractString) fix2 = true`; replace
  `convert_time_zone(tz::AbstractString) = Base.Fix2(convert_time_zone, tz)` with
  `@curry convert_time_zone(tz::AbstractString) fix2 = true`.

- [ ] **Step 5:** In `src/expr/struct.jl`, replace `field_by_name(name) = Base.Fix2(field_by_name,
  name)` with `@curry field_by_name(name) fix2 = true`; `field_by_index(fieldidx) =
  Base.Fix2(field_by_index, fieldidx)` with `@curry field_by_index(fieldidx) fix2 = true`;
  `rename_fields(new_names) = Base.Fix2(rename_fields, new_names)` with
  `@curry rename_fields(new_names) fix2 = true`.

- [ ] **Step 6:** `julia --project=. -e 'using Pkg; Pkg.test()'` — expect the Task 8 baseline. This
  is the one task in this plan that modifies a macro used by ~40 *other* call sites elsewhere in
  the codebase (every plain `@curry f(...)` invocation, unrelated to this task's 12 targets) —
  those must all still expand identically, since `fix2` defaults to `false` and the non-`fix2`
  branch is untouched logic, just re-indented under the new `if`. If anything regresses outside the
  12 files this task touches, that is the first place to look.

- [ ] **Step 7:** Commit:

```bash
git add src/macros.jl src/expr/list.jl src/expr/string.jl src/expr/datetime.jl src/expr/struct.jl
git commit -m "Julia: teach @curry a fix2=true option, migrate the 12 hand-written Base.Fix2 curries onto it"
```

---

## Task 20: Final verification and plan close-out

**Files:** none (verification + this plan file's own `## Status` line).

- [ ] **Step 1:** Full clean-room verification from the repo root:

```bash
cd c-polars && cargo build -j 4 && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check
python3 check_header_drift.py
cd .. && julia --project=. -e 'using Pkg; Pkg.test()'
```

Confirm: zero header drift (every task in this plan kept every touched signature identical), and
Julia test counts identical to the Task 8 baseline (plus the one new `cast_datetime` curry test
added in Task 12, if that ran clean).

- [ ] **Step 2:** If Kaimon is available, restart the shared REPL and spend a few minutes
  adversarially re-exercising a sample of touched paths end-to-end (not exhaustively — the test
  suite already covers correctness; this is a sanity pass for anything a unit test might not catch,
  e.g. printing a curried function at the REPL, chaining `|>` pipelines through the newly-macro'd
  `head`/`tail`/`strftime`/`value_counts`, writing then reading back a CSV/parquet/IPC file through
  the now-macro'd path-writer siblings).

- [ ] **Step 3:** Update this plan's `## Status` line to **Done**, naming the final commit range and
  test counts, mirroring the convention in `plans/c_polars_review_two.md`'s own `## Status` section
  (skim that file for the exact phrasing style before writing this one).

```bash
git add plans/macro_dedup_sweep.md
git commit -m "plans: mark macro_dedup_sweep Done"
```

- [ ] **Step 4:** Report back to the user: this branch (`macro-dedup-sweep`) is ready to open as a
  PR stacked on `parity-kwarg-gaps`, per the user's own instruction to "create another PR to stack,
  addressing all these" — do not push or open the PR without a separate explicit go-ahead, per this
  session's standing instruction to confirm before any action visible to others (a push, a PR).
