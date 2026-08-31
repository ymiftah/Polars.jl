# Tier 1 + Tier 2 low-hanging parity closure

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans` to execute this task-by-task.
> **Kaimon is unavailable this session** (`kaimon` MCP server: ConnectionRefused). The global rule
> says use Kaimon for Julia; with it down, use `julia --project=. -e '...'` via Bash instead. That
> also removes the "restart the REPL after `cargo build`" step — each `julia` invocation is a fresh
> process that maps the freshly built `.so`.

## Status

**Task 1 done** (frame-level `limit`/`Base.reverse`/`null_count`/`Base.count`/`fill_nan`/`explain`/
`cache`); Tasks 2-5 not started. Branch `parity-low-hanging-tier12`, stacked on
`parity-frame-verbs-horizontal-concat` (PR #46).

Derived from a fresh triage of every file in `plans/parity/`, with each candidate's `#[cfg(feature
= ...)]` gate re-verified against the vendored `polars-*-0.54.4` source and `c-polars/Cargo.toml`'s
actual feature list rather than trusting the audit text (several entries are stale). Scope is
deliberately **everything that needs no Cargo feature change**.

**Explicitly out of scope**, each for a stated reason rather than by omission:

- `int_range`/`date_range`/`datetime_range`/`time_range`, `arg_sort_by`, `arg_where`, `is_close` —
  all need a Cargo feature (`range`, `arg_where`, `is_close`). `arange` goes with them: it is a
  plain alias for `int_range`, so it cannot exist before `int_range` does.
- `mode`, `unique_counts`, `search_sorted`, `hist`, `peak_min`/`peak_max`, `repeat_by`, the
  `bitwise_*` reductions — same, each behind its own feature (verified: `mode` at
  `polars-plan-0.54.4/src/dsl/mod.rs:1095`, `unique_counts` at 1555).
- `fold`/`reduce`/`cum_fold`/`cum_reduce` — ungated in Rust, but they take a Rust closure. They are
  [`api_gap_audit.md`](api_gap_audit.md) Group 9 callback work, not thin wrappers.
- `join_where` — `LazyFrame::join_where` is ungated in `polars-lazy-0.54.4/src/frame/mod.rs:2303`,
  so a shim would compile cleanly and then hit the `iejoin`-gated execution path at runtime. This is
  exactly `CLAUDE.md`'s "a clean `cargo build` is never evidence a path is safe" hazard; do not add
  it here.

## Goal

Close the no-Cargo-change remainder of [`api_gap_audit.md`](api_gap_audit.md)'s Groups 2, 3, 4 and
6: seven frame-level verbs, eleven `Expr` methods, two top-level functions, `Dt.to_string`, and the
component-wise temporal constructors.

## Architecture

Every item follows `CLAUDE.md`'s existing "Workflow: adding a wrapped operation" unchanged: a Rust
`extern "C"` shim in the matching `c-polars/src/*.rs`, regenerate header + bindings, one Julia
entry point in the category-matching `src/` file, live-verify, then tests under the matching
`test/<category>/`. Most `Expr` items are one-line `gen_impl_expr*!` macro invocations on both
sides — `src/macros.jl`'s header comment is the authoritative guide to which macro to pick.

**Tech stack:** Rust (`c-polars`, stable toolchain), cbindgen + Clang.jl generation pipeline,
Julia 1.10+.

**Spec:** [`api_gap_audit.md`](api_gap_audit.md) (Groups 2, 3, 4, 6) plus
[`range_temporal_constructors.md`](range_temporal_constructors.md), whose Tasks 6 and 7 are lifted
into this plan verbatim as Task 4 — they were always independent of that plan's `range` Cargo flip.

## Global Constraints

- **No `Cargo.toml` change in this PR.** Every function below was verified reachable under the
  features `c-polars/Cargo.toml` already enables. Anything that turns out to need a new feature is
  dropped from the PR and recorded in `api_gap_audit.md`'s Group 10, not added.
- **Never hand-edit `c-polars/include/polars.h` or `src/api/generated.jl`.** Regenerate:
  `c-polars/regen_header.sh`, then `julia --project=gen gen/generate.jl`, then
  `runic -i src/api/generated.jl`.
- **`cargo build -j 4`** only. No dependency rebuild is expected (no `Cargo.toml`/`Cargo.lock`
  change); if one starts anyway, kill it and re-run with `-j 1`.
- **Strings cross the ABI as `(ptr, ncodeunits(s))`** — never `length(s)`.
- **Anything that can fail returns `*const polars_error_t`** with the result via an out-param, and
  is wrapped in `guard_error`. A panic across `extern "C"` aborts the Julia process.
- **Exercise every new function live before writing its test.** A clean `cargo build` is not
  evidence a path works.
- **Run `pre-commit run --all-files` before every commit** — it runs runic, `cargo fmt`, clippy and
  clang-format, and CI fails on all four.
- Base-name collisions: `count`, `reverse`, `reshape`, `time` are **exported** `Base` names and must
  be defined as `Base.count` / `Base.reverse` / `Base.reshape` / `Base.time` methods. `shuffle`,
  `dot`, `entropy`, `arctan2`, `to_physical`, `lower_bound`, `upper_bound`, `arg_unique`,
  `escape_regex`, `extend_constant`, `format`, `limit`, `cache`, `explain`, `null_count`,
  `concat_arr`, `date`, `from_epoch`, `datetime`, `duration` are free (verified with `isdefined`).

## File structure

| File | Responsibility | Task |
|---|---|---|
| `c-polars/src/dataframe.rs` | frame-level `extern "C"` shims | 1 |
| `c-polars/src/expr.rs` | all `Expr`-level shims | 2, 3, 4 |
| `src/verbs.jl` | frame-level `limit`/`reverse`/`fill_nan`/`null_count`/`count` | 1 |
| `src/lazyframe.jl` | `explain`/`cache` (plan-level, not a data verb) | 1 |
| `src/expr/expr.jl` | the eleven `Expr` methods; top-level `format`/`concat_arr` | 2, 3 |
| `src/expr/string.jl` | `Strings.escape_regex` | 2 |
| `src/expr/datetime.jl` | `Dt.to_string` | 3 |
| `src/expr/ranges.jl` (new) | `datetime`/`duration`/`date`/`time`/`from_epoch` | 4 |
| `test/operations/frame_verbs.jl` | Task 1 tests | 1 |
| `test/expr/math.jl`, `test/expr/selection.jl` | Task 2 tests | 2 |
| `test/expr/ranges.jl` (new) | Task 4 tests | 4 |
| `docs/src/reference/{expressions,dataframe,expr-datetime,functions}.md` | `@docs` entries | each |

`src/expr/ranges.jl` is named to match what
[`range_temporal_constructors.md`](range_temporal_constructors.md) Task 2 expects, so the follow-up
`range` PR appends to it rather than moving anything.

---

### Task 1: Frame-level verbs

Closes most of [`api_gap_audit.md`](api_gap_audit.md) Group 6's "Row/column selection" and
"Whole-frame computation" rows. All seven upstream methods are ungated in
`polars-lazy-0.54.4/src/frame/mod.rs` (`limit` 1824, `reverse` 375, `fill_nan` 454, `null_count`
1662, `count` 1939, `explain` 245, `cache` 463) — verified, no `#[cfg]` on any of them.

**Files:**
- Modify: `c-polars/src/dataframe.rs` (append after `polars_lazy_frame_quantile`, ~line 807)
- Modify: `src/verbs.jl`, `src/lazyframe.jl`
- Modify: `docs/src/reference/dataframe.md`
- Test: `test/operations/frame_verbs.jl`

**Interfaces:**
- Consumes: `polars_lazy_frame_t`, `guard_error`, `_io_callback()` (`src/Polars.jl`), the existing
  `_frame_sum!` pattern in `src/verbs.jl:269-273`.
- Produces: `limit(df, n)`, `Base.reverse(df)`, `fill_nan(df, value)`, `null_count(df)`,
  `Base.count(df)`, `explain(df; optimized=true)::String`, `cache(df)` — each with a `LazyFrame`
  and a `DataFrame` method except `explain`, which is `LazyFrame`-only (matching upstream).

- [x] **Step 1: Add the five void-mutator shims to `c-polars/src/dataframe.rs`**

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_reverse(df: *mut polars_lazy_frame_t) {
    let df = &mut (*df).inner;
    // See the `mem::take` comment on `polars_lazy_frame_sort` above.
    *df = std::mem::take(df).reverse();
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_null_count(df: *mut polars_lazy_frame_t) {
    let df = &mut (*df).inner;
    *df = std::mem::take(df).null_count();
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_count(df: *mut polars_lazy_frame_t) {
    let df = &mut (*df).inner;
    *df = std::mem::take(df).count();
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_cache(df: *mut polars_lazy_frame_t) {
    let df = &mut (*df).inner;
    *df = std::mem::take(df).cache();
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_fill_nan(
    df: *mut polars_lazy_frame_t,
    value: *const polars_expr_t,
) {
    let value = (*value).inner.clone();
    let df = &mut (*df).inner;
    *df = std::mem::take(df).fill_nan(value);
}
```

- [x] **Step 2: Add `polars_lazy_frame_explain`**

`explain` returns a `String`, so it uses the `IOCallback` shape that `polars_dataframe_show`
(`c-polars/src/dataframe.rs:331`) already uses — copy that function's structure exactly, including
the `use std::fmt::Write` it relies on.

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_explain(
    df: *mut polars_lazy_frame_t,
    optimized: bool,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    guard_error(|| {
        let df = (*df).inner.clone();
        let text = match df.explain(optimized) {
            Ok(text) => text,
            Err(err) => return make_error(err),
        };
        let mut w = UserIOCallback(callback, user);
        if let Err(err) = write!(w, "{text}") {
            return make_error(err);
        }
        std::ptr::null()
    })
}
```

- [x] **Step 3: Regenerate and build**

```bash
c-polars/regen_header.sh
julia --project=gen gen/generate.jl
runic -i src/api/generated.jl
python3 c-polars/check_header_drift.py
cd c-polars && cargo build -j 4 && cd ..
```

Expected: `check_header_drift.py` clean; build finishes without a dependency rebuild.

- [x] **Step 4: Add the Julia entry points to `src/verbs.jl`**

Follow the `_frame_sum!` shape at `src/verbs.jl:269-273` exactly (clone for the `LazyFrame` method,
`lazy(df)` + `collect` for the `DataFrame` one).

```julia
"""
    limit(df::LazyFrame, n::Integer)::LazyFrame
    limit(df::DataFrame, n::Integer)::DataFrame

The first `n` rows of `df`. A plain alias for [`head`](@ref), matching upstream polars, which
defines `limit` as an alias for the same reason.
"""
limit(df::LazyFrame, n::Integer) = head(df, n)
limit(df::DataFrame, n::Integer) = head(df, n)

export limit

"""
    Base.reverse(df::LazyFrame)::LazyFrame
    Base.reverse(df::DataFrame)::DataFrame

Reverses the row order of `df`.
"""
Base.reverse(df::LazyFrame) = _frame_reverse!(clone(df))
Base.reverse(df::DataFrame) = _frame_reverse!(lazy(df)) |> collect
function _frame_reverse!(df::LazyFrame)
    API.polars_lazy_frame_reverse(df)
    return df
end

"""
    null_count(df::LazyFrame)::LazyFrame
    null_count(df::DataFrame)::DataFrame

The number of `null` values in every column of `df`, as a single-row frame with the same column
names. The per-column expression form is [`null_count(::Polars.Expr)`](@ref).
"""
null_count(df::LazyFrame) = _frame_null_count!(clone(df))
null_count(df::DataFrame) = _frame_null_count!(lazy(df)) |> collect
function _frame_null_count!(df::LazyFrame)
    API.polars_lazy_frame_null_count(df)
    return df
end

"""
    Base.count(df::LazyFrame)::LazyFrame
    Base.count(df::DataFrame)::DataFrame

The number of rows in every column of `df`, as a single-row frame with the same column names.
Counts `null`s, unlike the per-column [`Polars.count`](@ref).
"""
Base.count(df::LazyFrame) = _frame_count!(clone(df))
Base.count(df::DataFrame) = _frame_count!(lazy(df)) |> collect
function _frame_count!(df::LazyFrame)
    API.polars_lazy_frame_count(df)
    return df
end

"""
    fill_nan(df::LazyFrame, value)::LazyFrame
    fill_nan(df::DataFrame, value)::DataFrame

Replaces every `NaN` in every float column of `df` with `value` (an expression or a plain scalar).
The `null`-replacing counterpart is [`fill_null`](@ref).
"""
fill_nan(df::LazyFrame, value) = _frame_fill_nan!(clone(df), convert(Expr, value))
fill_nan(df::DataFrame, value) = _frame_fill_nan!(lazy(df), convert(Expr, value)) |> collect
function _frame_fill_nan!(df::LazyFrame, value::Expr)
    API.polars_lazy_frame_fill_nan(df, value)
    return df
end

export null_count, fill_nan
```

`null_count` and `fill_nan` already exist as `Expr` methods; these are added methods on the same
generic functions, so **do not** re-`export` a name that `src/expr/` already exports — check with
`grep -rn "export.*null_count\|export.*fill_nan" src/` first and drop it from the `export` line
above if it is already there.

- [x] **Step 5: Add `explain`/`cache` to `src/lazyframe.jl`**

```julia
"""
    explain(df::LazyFrame; optimized::Bool=true)::String

Renders `df`'s query plan as text. With `optimized=true` (the default) this is the plan polars will
actually execute, after predicate/projection pushdown and the other optimizer passes; with
`optimized=false` it is the plan exactly as built.
"""
function explain(df::LazyFrame; optimized::Bool = true)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = API.polars_lazy_frame_explain(df, optimized, io, callback)
    polars_error(err)
    return String(take!(io[]))
end

"""
    cache(df::LazyFrame)::LazyFrame

Marks `df`'s subtree for caching, so a plan that consumes it more than once evaluates it once.
Advisory: it changes evaluation strategy, never results.
"""
function cache(df::LazyFrame)
    out = clone(df)
    API.polars_lazy_frame_cache(out)
    return out
end

export explain, cache
```

- [x] **Step 6: Exercise all seven live**

```bash
julia --project=. -e '
using Polars
df = DataFrame((; a=[1.0, NaN, 3.0, missing], b=[10, 20, 30, 40]))
println(limit(df, 2))
println(reverse(df))
println(null_count(df))
println(count(df))
println(fill_nan(df, 0.0))
println(explain(lazy(df)))
println(collect(cache(lazy(df))))
'
```

Expected: `null_count` gives `a=1, b=0`; `count` gives `a=4, b=4`; `fill_nan` replaces only the
`NaN`, leaving the `missing` alone; `explain` prints a plan containing `DF ["a", "b"]`.
**Record the actual output** — the tests assert on it.

**Actual (live-verified) output, and one correction to this plan's expectation:**
`null_count` gives `a=1, b=0` as expected. **`count` gives `a=3, b=4`, not `a=4, b=4`** — upstream
`LazyFrame::count()` counts *non-null* values per column (same semantics as the per-`Expr`
`count`), not the row count including nulls; confirmed with a fully-`missing` 3-row column, which
reports `count == 0`. The plan's expected value here was wrong; the shipped docstring documents the
actual behavior instead. `fill_nan(df, 0.0)` gives `[1.0, 0.0, 3.0, missing]` for `a` (the `NaN`
became `0.0`, the `missing` stayed `missing`) and leaves `b` untouched. `explain(lazy(df))` on this
trivial single-scan plan prints `DF ["a", "b"]; PROJECT */2 COLUMNS` for both `optimized=true` and
`optimized=false` (no difference on a plan with nothing to push down); a filtered-then-selected
plan does differ (`FILTER`+projection-trimmed `DF [...]; PROJECT["a"] 1/3 COLUMNS` when optimized,
vs. a `SELECT` wrapper preserving `PROJECT */3 COLUMNS` when not) -- see the test for the exact
strings. `reverse(reverse(df)) == df` holds. `cache(lazy(df)) |> collect` reproduces `df` exactly.

- [x] **Step 7: Write tests in `test/operations/frame_verbs.jl`**

Follow the file's existing `@testset` style. Cover, per function: the happy path; that
`null_count`/`count` disagree on a column containing `missing` (that is the whole point of having
both); that `fill_nan` leaves `missing` untouched while replacing `NaN` (they are different things
here and upstream); that `limit(df, n)` with `n` greater than the row count returns everything; that
`reverse` round-trips (`reverse(reverse(df)) == df`); that `explain(lazy(df); optimized=false)`
differs from the optimized plan for a filtered frame (proof the flag is threaded, not ignored); and
that `cache` is result-preserving. Assert on the values recorded in Step 6, not on guesses.

- [x] **Step 8: Add docs entries**

Add `limit`, `null_count`, `fill_nan`, `explain`, `cache` to the `@docs` block in
`docs/src/reference/dataframe.md` that already lists the frame verbs. `Base.reverse` and
`Base.count` go in as `Base.reverse` / `Base.count` (the qualified form, matching how
`Base.replace`/`Base.coalesce` are already listed in `docs/src/reference/expressions.md`).
**Any `[`x`](@ref)` you write in a docstring must have its binding in some `@docs` block** or the
docs CI job fails with `Cannot resolve @ref` — that exact failure just cost a CI round on PR #46.

- [x] **Step 9: Verify and commit**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
pre-commit run --all-files
git add -A && git commit -m "Add frame-level limit/reverse/fill_nan/null_count/count/explain/cache"
```

Expected: full suite passes, all four hooks pass.

---

### Task 2: Eleven `Expr` methods

Closes most of [`api_gap_audit.md`](api_gap_audit.md) Group 3. Gates verified in
`polars-plan-0.54.4/src/dsl/`: `arctan2` needs `trigonometry` (enabled), `entropy` needs `log`
(enabled), `escape_regex` needs `regex` (enabled), `reshape` needs `dtype-array` (enabled),
`shuffle` needs `random` (enabled, via `mod random` at `dsl/mod.rs:37`); `dot`, `arg_unique`,
`extend_constant`, `to_physical`, `lower_bound`, `upper_bound` are ungated.

**Files:**
- Modify: `c-polars/src/expr.rs`, `src/expr/expr.jl`, `src/expr/string.jl`
- Modify: `docs/src/reference/expressions.md`, `docs/src/reference/expr-string.md`
- Test: `test/expr/math.jl`, `test/expr/selection.jl`

**Interfaces:**
- Consumes: `gen_impl_expr!`, `gen_impl_expr_binary!`, `gen_impl_expr_str!` (Rust,
  `c-polars/src/expr.rs:460/1160/1837`); `@wrap_simple_ops`, `@wrap_expr_method`, `@curry`
  (Julia, `src/macros.jl`).
- Produces: `arctan2(a, b)`, `dot(a, b)`, `entropy(expr; base=ℯ, normalize=true)`,
  `arg_unique(expr)`, `to_physical(expr)`, `lower_bound(expr)`, `upper_bound(expr)`,
  `extend_constant(expr, value, n)`, `shuffle(expr; seed=nothing)`, `Base.reshape(expr, dims...)`,
  `Strings.escape_regex(expr)`.

- [x] **Step 1: Add the macro-driven shims to `c-polars/src/expr.rs`**

Append the no-argument ones next to the existing `gen_impl_expr!` block (~line 962), the binary ones
next to the `gen_impl_expr_binary!` block (~line 1175), and the string one next to the
`gen_impl_expr_str!` block (~line 1847):

```rust
gen_impl_expr!(polars_expr_arg_unique, Expr::arg_unique);
gen_impl_expr!(polars_expr_to_physical, Expr::to_physical);
gen_impl_expr!(polars_expr_lower_bound, Expr::lower_bound);
gen_impl_expr!(polars_expr_upper_bound, Expr::upper_bound);

gen_impl_expr_binary!(polars_expr_arctan2, Expr::arctan2);
gen_impl_expr_binary!(polars_expr_dot, Expr::dot);

gen_impl_expr_str!(polars_expr_str_escape_regex, StringNameSpace::escape_regex);
```

`Expr::arctan2(self, x)` is `self.arctan2(x)` where `self` is the **y** argument — upstream
`pl.arctan2(y, x)` has the same order, so the generated `arctan2(a, b)` means `arctan2(y, x)`. Say
so in the docstring.

- [x] **Step 2: Add the four hand-written shims to `c-polars/src/expr.rs`**

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_entropy(
    expr: *const polars_expr_t,
    base: f64,
    normalize: bool,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    make_expr(expr.entropy(base, normalize))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_extend_constant(
    expr: *const polars_expr_t,
    value: *const polars_expr_t,
    n: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let value = (*value).inner.clone();
    let n = (*n).inner.clone();
    make_expr(expr.extend_constant(value, n))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_shuffle(
    expr: *const polars_expr_t,
    seed: *const u64,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let seed = if seed.is_null() { None } else { Some(*seed) };
    make_expr(expr.shuffle(seed))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_reshape(
    expr: *const polars_expr_t,
    dims: *const i64,
    n_dims: usize,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let dims = std::slice::from_raw_parts(dims, n_dims);
    make_expr(expr.reshape(dims))
}
```

None of these four can fail (they only build a plan node), so they return a handle directly with no
error channel — matching every other `polars_expr_*` builder in this file. If `cargo build` reveals
any of them returns a `PolarsResult`, switch that one to the `out`-param + `guard_error` shape used
by `polars_expr_concat_str` (`c-polars/src/expr.rs:222`) instead.

- [x] **Step 3: Regenerate and build**

```bash
c-polars/regen_header.sh
julia --project=gen gen/generate.jl
runic -i src/api/generated.jl
python3 c-polars/check_header_drift.py
cd c-polars && cargo build -j 4 && cd ..
```

- [x] **Step 4: Add the block-DSL entries to `src/expr/expr.jl`**

Inside the existing `@wrap_simple_ops begin ... end` block (the one containing
`gen_impl_expr!(polars_expr_arctan, ...)` around line 497):

```julia
    gen_impl_expr!(polars_expr_arg_unique, Expr::arg_unique, "The row indices of the first occurrence of each distinct value of `expr`, in order of first appearance.")
    gen_impl_expr!(polars_expr_to_physical, Expr::to_physical, "The physical (storage) representation of `expr` -- e.g. a `Date` becomes its `Int32` days-since-epoch, a `Categorical` its `UInt32` index. Leaves already-physical dtypes unchanged.")
    gen_impl_expr!(polars_expr_lower_bound, Expr::lower_bound, "A single-row column holding the smallest value `expr`'s dtype can represent.")
    gen_impl_expr!(polars_expr_upper_bound, Expr::upper_bound, "A single-row column holding the largest value `expr`'s dtype can represent.")
    gen_impl_expr_binary!(polars_expr_arctan2, Expr::arctan2, "Two-argument inverse tangent: `arctan2(y, x)` is the angle in radians between the positive x-axis and the point `(x, y)`, using both signs to pick the correct quadrant. Note the `y`-then-`x` argument order, matching upstream polars and C's `atan2`.")
    gen_impl_expr_binary!(polars_expr_dot, Expr::dot, "The dot product of two columns: the sum of their elementwise product, as a single row.")
```

And in `src/expr/string.jl`'s `@wrap_simple_ops` block inside the `Strings` submodule:

```julia
    gen_impl_expr_str!(polars_expr_str_escape_regex, StringNameSpace::escape_regex, "Escapes every regex metacharacter in each string, so the result matches itself literally when used as a pattern.")
```

- [x] **Step 5: Hand-write the four remaining Julia entry points in `src/expr/expr.jl`**

```julia
"""
    entropy(expr::Polars.Expr; base::Real=ℯ, normalize::Bool=true)::Polars.Expr
    entropy(; base::Real=ℯ, normalize::Bool=true)

The Shannon entropy of `expr`'s value distribution, as a single row. `base` is the logarithm base
(`ℯ` for nats, `2` for bits); `normalize=true` normalizes the counts into probabilities first.

!!! note "Has a curried form"
    The keyword-only method above, for `|>` pipelines.
"""
function entropy(expr::Expr; base::Real = ℯ, normalize::Bool = true)
    return Expr(API.polars_expr_entropy(expr, Float64(base), normalize))
end
@curry entropy(; base::Real = ℯ, normalize::Bool = true)

"""
    extend_constant(expr::Polars.Expr, value, n)::Polars.Expr

Appends `n` copies of `value` to the end of `expr`. `value` and `n` may be expressions or plain
scalars; `value` may be `missing`, which appends nulls.
"""
function extend_constant(expr::Expr, value, n)
    return Expr(
        API.polars_expr_extend_constant(expr, convert(Expr, value), convert(Expr, n)),
    )
end

"""
    shuffle(expr::Polars.Expr; seed::Union{Nothing,Integer}=nothing)::Polars.Expr

Randomly permutes `expr`'s values. `seed` makes the permutation reproducible; `nothing` (the
default) draws a fresh seed from the OS each call.
"""
function shuffle(expr::Expr; seed::Union{Nothing, Integer} = nothing)
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
    out = GC.@preserve seed_ref API.polars_expr_shuffle(expr, seed_ref)
    return Expr(out)
end

"""
    Base.reshape(expr::Polars.Expr, dims::Integer...)::Polars.Expr

Reshapes `expr` into an `Array`-dtype column of the given dimensions. A single `-1` in `dims` is
inferred from the length. Extends `Base.reshape` rather than shadowing it, the same way
`Base.get`/`Base.sort`/`Base.tail` are extended elsewhere in this file.
"""
function Base.reshape(expr::Expr, dims::Integer...)
    dims_vec = Int64[Int64(d) for d in dims]
    out = GC.@preserve dims_vec API.polars_expr_reshape(expr, pointer(dims_vec), length(dims_vec))
    return Expr(out)
end

export entropy, extend_constant, shuffle, arctan2, dot, arg_unique, to_physical,
    lower_bound, upper_bound
```

Copy the `seed_ref` shape from `sample_n` in this same file — the `Ref` **must** stay inside
`GC.@preserve` across the ccall. Check whether `@wrap_simple_ops` already exports the names it
generates before adding them to that `export` line; if it does, drop the duplicates.

- [x] **Step 6: Exercise all eleven live**

```bash
julia --project=. -e '
using Polars
df = DataFrame((; x=[1.0, 2.0, 3.0, 4.0], y=[1, 1, 2, 2], s=["a.b", "c*d"]))
println(select(df, arctan2(col("x"), lit(1.0)) |> alias("at2")))
println(select(df, dot(col("x"), col("x")) |> alias("dot")))
println(select(df, entropy(col("y")) |> alias("e")))
println(select(df, arg_unique(col("y")) |> alias("au")))
println(select(df, to_physical(col("y")) |> alias("phys")))
println(select(df, lower_bound(col("y")) |> alias("lb"), upper_bound(col("y")) |> alias("ub")))
println(select(df, extend_constant(col("y"), 0, 2) |> alias("ext")))
println(select(df, shuffle(col("x"); seed=42) |> alias("sh")))
println(select(df, Strings.escape_regex(col("s")) |> alias("esc")))
println(collect_schema(select(lazy(df), reshape(col("x"), 2, 2) |> alias("r"))))
'
```

Expected: `dot` is `30.0`; `escape_regex` gives `["a\\.b", "c\\*d"]`; `shuffle` with a fixed seed is
stable across runs (run it twice and compare). **`reshape` and any Array-dtype result may not
materialize into Julia** — Group 5 of the audit records that Array columns can be created but not
operated on. If `collect` on the reshaped frame errors, that is expected: assert on
`collect_schema` instead and note the limitation in the docstring. Record actual outputs.

**Actual (live-verified) output, and two corrections to this plan's expectation:**
`arctan2`/`dot`/`entropy`/`arg_unique`/`to_physical`/`lower_bound`/`upper_bound`/`extend_constant`/
`shuffle`/`escape_regex` all matched the plan's shape (values recorded in `test/expr/math.jl`,
`test/expr/selection.jl`, `test/datatypes/strings.jl`): `dot(x, x)` on `[1,2,3,4]` is `30.0`;
`entropy([1,1,2,2])` is `1.3296613488547582` (natural log, normalized); `arg_unique([1,1,2,2])` is
`UInt32[0, 2]`; `to_physical` on a `Date` column gives days-since-epoch as `Int32`;
`lower_bound`/`upper_bound` on an `Int64` column give `typemin`/`typemax(Int64)`; `escape_regex`
gives `["a\\.b", "c\\*d"]` and round-trips through `Strings.contains`; `shuffle(; seed=42)` is
stable across two calls and preserves the input multiset (never asserted on a specific
permutation, per instructions). `arctan2(lit(1.0), lit(-1.0))` is `3π/4 ≈ 2.356194490192345`,
confirming the quadrant behavior the plan called out (`atan(1.0/-1.0)` is the wrong `-π/4`).

**Correction 1 — the plan's premise about `-1` inference was incomplete.** `Expr::reshape`'s `-1`
placeholder is inferred **only when it is the first dimension** — `reshape(col("x"), -1, 2)` works,
but `reshape(col("x"), 2, -1)` raises `PolarsError("can only infer the first dimension")`. Verified
live; not previously documented anywhere in this repo.

**Correction 2 — the Array-dtype limitation is deeper than "collect may error, fall back to
`collect_schema`".** Live-verified: `select(lazy(df), reshape(...))` (building the plan) succeeds,
and `collect(lf)` on it **also succeeds** (returns a `DataFrame` handle). The failure is not in
`collect` at all — it's in anything that resolves the Arrow schema of an `Array`-dtype column
afterward: `collect_schema(lf)`, `Polars.schema(df)`, and indexing a collected `DataFrame` with an
`Array` column (`df[:col]`) all raise a plain Julia `ErrorException` (not `PolarsError`) from
`src/arrow/schema.jl:136`'s `parse_format`, which doesn't recognize the fixed-size-list Arrow
format (`"+w:N"`). The docstring and tests were written against this corrected understanding
rather than the plan's original "assert on `collect_schema` instead" suggestion, since
`collect_schema` turned out not to be the working fallback either — `explain` is.

- [x] **Step 7: Write tests**

`arctan2`, `dot`, `entropy`, `lower_bound`, `upper_bound`, `to_physical` → `test/expr/math.jl`.
`arg_unique`, `extend_constant`, `shuffle`, `reshape` → `test/expr/selection.jl`.
`Strings.escape_regex` → the existing string testset in `test/datatypes/strings.jl`.

Per function assert: the happy-path value recorded in Step 6; null propagation (add a `missing` to
the fixture and pin what comes back); and for `arctan2` the quadrant behavior that distinguishes it
from plain `arctan` — `arctan2(lit(1.0), lit(-1.0))` is `3π/4`, whereas `arctan(1.0/-1.0)` is
`-π/4`. For `shuffle`, assert that two calls with the same `seed` agree and that the multiset of
values is preserved — never assert a specific permutation without having run it. For
`escape_regex`, assert the escaped output actually matches literally via
`Strings.contains(col("s"), Strings.escape_regex(col("s")))`.

- [x] **Step 8: Add docs entries**

Add all eleven to the `@docs` blocks: the ten `Expr` ones to `docs/src/reference/expressions.md`
(`Base.reshape` in qualified form), `escape_regex` to `docs/src/reference/expr-string.md`. Every
`@ref` used in a new docstring must resolve.

- [x] **Step 9: Verify and commit**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
pre-commit run --all-files
git add -A && git commit -m "Add Expr arctan2/dot/entropy/arg_unique/to_physical/bounds/extend_constant/shuffle/reshape and Strings.escape_regex"
```

---

### Task 3: Top-level `format`, `concat_arr`, and `Dt.to_string`

Closes [`api_gap_audit.md`](api_gap_audit.md) Group 2's "String and list combination" remainder and
the last non-Cargo-gated Group 4 `Dt` item. `format_str` and `concat_arr` are ungated in
`polars-plan-0.54.4/src/dsl/functions/concat.rs` (lines 21 and 120, and `mod concat` at
`dsl/functions/mod.rs:8` carries no `#[cfg]`); `DateLikeNameSpace::to_string` is ungated at
`dsl/dt.rs:25` under the already-enabled `temporal` module gate.

**Files:**
- Modify: `c-polars/src/expr.rs`, `src/expr/expr.jl`, `src/expr/datetime.jl`
- Modify: `docs/src/reference/functions.md`, `docs/src/reference/expr-datetime.md`
- Test: `test/expr/horizontal.jl`, `test/datatypes/datetimes.jl`

**Interfaces:**
- Consumes: `read_exprs`, `read_str`, `make_expr`, `guard_error`, `tri!` — all used by
  `polars_expr_concat_str` (`c-polars/src/expr.rs:222`), which is the template for both new
  free functions.
- Produces: `format(fmt::AbstractString, args...)::Expr`, `concat_arr(exprs...)::Expr`,
  `Dt.to_string(expr, format)::Expr`.

- [ ] **Step 1: Add the two free-function shims to `c-polars/src/expr.rs`**

Both `format_str` and `concat_arr` return `PolarsResult<Expr>`, so both need the fallible shape.
Add `format_str` and `concat_arr` to the `polars_plan::dsl` import that already brings in
`concat_str`.

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_format(
    fmt: *const u8,
    fmt_len: usize,
    exprs: *const *const polars_expr_t,
    n: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let fmt = tri!(read_str(fmt, fmt_len));
        let exprs = read_exprs(exprs, n);
        match format_str(fmt, &exprs) {
            Ok(expr) => {
                *out = make_expr(expr);
                std::ptr::null()
            },
            Err(err) => make_error(err),
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_concat_arr(
    exprs: *const *const polars_expr_t,
    n: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let exprs = read_exprs(exprs, n);
        match concat_arr(exprs) {
            Ok(expr) => {
                *out = make_expr(expr);
                std::ptr::null()
            },
            Err(err) => make_error(err),
        }
    })
}
```

- [ ] **Step 2: Add `Dt.to_string` to `c-polars/src/expr.rs`**

It takes a `&str`, so it is not a `gen_impl_expr_dt!` one-liner. Put it next to the other
hand-written `polars_expr_dt_*` functions.

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_dt_to_string(
    expr: *const polars_expr_t,
    format: *const u8,
    format_len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let format = tri!(read_str(format, format_len));
        *out = make_expr((*expr).inner.clone().dt().to_string(format));
        std::ptr::null()
    })
}
```

- [ ] **Step 3: Regenerate and build** (same four commands as Task 1 Step 3)

- [ ] **Step 4: Add the Julia entry points**

In `src/expr/expr.jl`, next to `concat_str` (~line 1155). **`format` collides with the internal
`format(T)` in `src/arrow/array.jl:90`**, which maps a Julia type to an Arrow format string. They
are the same generic function in module `Polars`. The new method is `format(::AbstractString,
args...)`, which is strictly more specific than the untyped `format(T)` fallback for every call
with a `String` first argument, so dispatch is unambiguous — but **run `test/aqua.jl` and the arrow
tests specifically** to confirm no new ambiguity, and if Aqua flags one, rename the internal
function to `_arrow_format` (it is unexported; `grep -rn "format(" src/arrow/ src/dataframe.jl` for
its call sites) rather than compromising the public name.

Both bodies are `concat_str`'s marshalling (`src/expr/expr.jl:1164-1176`) with the separator
arguments removed — `_expr_vector`, then `GC.@preserve` around the pointer vector, then
`polars_error`. Note `ncodeunits(fmt)`, never `length(fmt)`.

```julia
"""
    format(fmt::AbstractString, args...)::Polars.Expr

Formats `args` into `fmt`, where each `{}` placeholder consumes one argument in order (expressions
or plain scalars). The number of `{}` placeholders must equal the number of `args`, or a
`PolarsError` is raised. The row-wise counterpart of `Base.string` over several columns; see also
[`concat_str`](@ref), which joins with a fixed separator instead of a template.
"""
function format(fmt::AbstractString, args...)
    exprs = _expr_vector(args)
    fmt = String(fmt)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_format(fmt, ncodeunits(fmt), ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

"""
    concat_arr(exprs...)::Polars.Expr

Combines `exprs` row-wise into a fixed-size `Array` column, one element per input expression. The
`Array`-dtype counterpart of [`concat_list`](@ref); all inputs must share a dtype.
"""
function concat_arr(exprs...)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_concat_arr(ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

export format, concat_arr
```

Note the argument order in the generated binding: `polars_expr_format` takes `(fmt, fmt_len, ptrs,
n, out)` because that is the order the Rust shim in Step 1 declares. If you change one, change both.

In `src/expr/datetime.jl`, inside the `Dt` submodule, use `@wrap_expr_method`:

```julia
@wrap_expr_method to_string(expr::Expr, format::AbstractString) polars_expr_dt_to_string "Formats each `Date`/`Datetime`/`Time` value as a string using the chrono `format` string (e.g. `\"%Y-%m-%d\"`)."
```

- [ ] **Step 5: Exercise live**

```bash
julia --project=. -e '
using Polars, Dates
df = DataFrame((; name=["a","b"], age=[1,2], d=[Date(2024,1,15), Date(2024,6,30)]))
println(select(df, format("{} is {}", col("name"), col("age")) |> alias("f")))
println(select(df, Dt.to_string(col("d"), "%Y/%m/%d") |> alias("s")))
println(collect_schema(select(lazy(df), concat_arr(col("age"), col("age")) |> alias("arr"))))
'
```

Expected: `format` gives `["a is 1", "b is 2"]`; `to_string` gives `["2024/01/15", "2024/06/30"]`.
As in Task 2, `concat_arr` produces an `Array` column that may not materialize — if `collect`
errors, assert on `collect_schema` and document it. Also verify the error path: `format("{}", ...)`
with a mismatched placeholder count must raise `PolarsError`, not abort the process.

- [ ] **Step 6: Write tests**

`format` and `concat_arr` → `test/expr/horizontal.jl` (where `concat_str`/`concat_list` are
already tested; mirror those testsets). `Dt.to_string` → `test/datatypes/datetimes.jl`.

Cover: the happy path values from Step 5; a `missing` in an argument (upstream propagates it into
the formatted string as the literal `null` — pin whatever actually happens); the mismatched
`{}`-count `PolarsError`; a non-ASCII `fmt` string (this is the `ncodeunits`-vs-`length` bug class
CLAUDE.md flags — `format("héllo {}", col("age"))` must not produce
`incomplete utf-8 byte sequence`); and for `Dt.to_string`, a non-ASCII format string for the same
reason plus a `Time` and a `Datetime` input, not only `Date`.

- [ ] **Step 7: Add docs entries and commit**

Add `format`/`concat_arr` to `docs/src/reference/functions.md` and `Dt.to_string` to
`docs/src/reference/expr-datetime.md`.

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
pre-commit run --all-files
git add -A && git commit -m "Add top-level format/concat_arr and Dt.to_string"
```

---

### Task 4: Temporal constructors

**This task is [`range_temporal_constructors.md`](range_temporal_constructors.md)'s Task 6 and
Task 7, executed verbatim.** Read those two sections in that file and follow their steps exactly —
they are already fully specified, live-verified against `polars-plan-0.54.4/src/dsl/functions/
temporal.rs`, and independent of that plan's `range` Cargo flip (Task 1 there), which is **not**
part of this PR.

Three deltas from what those sections assume, because they are being lifted out of their original
sequence:

1. **`src/expr/ranges.jl` does not exist yet** — that plan's Task 2 creates it. Create it in this
   task instead: a new file with the standard module preamble copied from `src/expr/statistics.jl`,
   `include`d from `src/Polars.jl` next to the other `expr/` includes, with `test/expr/ranges.jl`
   `include`d from `test/runtests.jl` next to the other `expr/` tests.
2. **The `polars_plan::dsl` import block that Task 2 there adds does not exist** — add
   `DatetimeArgs`, `DurationArgs`, `datetime` and `duration` to `c-polars/src/expr.rs`'s existing
   `polars_plan` import yourself.
3. **`Base.time` collision confirmed**: `time` is an exported `Base` name, so Task 7's
   `Base.time(hour, minute, second, microsecond)` form is correct as written — do not change it to a
   bare `time`.

After finishing, update
[`range_temporal_constructors.md`](range_temporal_constructors.md)'s `## Status` to record that its
Tasks 6 and 7 landed here, so the follow-up `range` PR starts from Task 1 and skips them.

- [ ] **Step 1: Create `src/expr/ranges.jl` and wire it into `src/Polars.jl` and `test/runtests.jl`**
- [ ] **Step 2: Execute `range_temporal_constructors.md` Task 6, all steps** (`datetime`, `duration`)
- [ ] **Step 3: Execute `range_temporal_constructors.md` Task 7, all steps** (`date`, `Base.time`, `from_epoch`)
- [ ] **Step 4: Add all five to `docs/src/reference/functions.md`'s `@docs` block**
- [ ] **Step 5: Update `range_temporal_constructors.md`'s `## Status`**
- [ ] **Step 6: Verify and commit**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
pre-commit run --all-files
git add -A && git commit -m "Add datetime/duration constructors and date/time/from_epoch"
```

---

### Task 5: Audit closure and PR

**Files:**
- Modify: `plans/parity/api_gap_audit.md`, `plans/parity/tier12_low_hanging_parity.md`

- [ ] **Step 1: Update `api_gap_audit.md`**

Add a dated entry to its `## Status` section in the same voice as the existing ones (what closed,
what it cost, what was learned), and strike through each closed item at its own Group entry with
`~~...~~ **Closed**` plus a `(see [Status](#status))` cross-reference — matching exactly how the
previous closures are recorded there. Do not delete the original text.

- [ ] **Step 2: Set this plan's `## Status` to `Done`**

- [ ] **Step 3: Full verification**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
pre-commit run --all-files
julia --project=docs -e 'include("docs/make.jl")'
```

All three must pass. The docs build is the one CI job that a missing `@docs` entry breaks, and it is
not covered by `pre-commit`.

- [ ] **Step 4: Push and open the PR, stacked on #46**

```bash
git push -u origin parity-low-hanging-tier12
gh pr create --base parity-frame-verbs-horizontal-concat \
  --title "Close the no-Cargo-change parity gaps (frame verbs, Expr methods, temporal constructors)" \
  --body "..."
```

The PR body should list every function added, state that no Cargo feature changed (so no new
`libpolars` release is required), and link the follow-up: the `range` feature flip covering
`int_range`/`date_range`/`datetime_range`/`time_range`/`arg_sort_by`/`arg_where`/`is_close`.
