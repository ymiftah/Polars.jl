# Range generators + temporal constructors

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans` to execute this task-by-task. Use the
> `kaimon-julia` skill for every REPL step (never `juliaserver`/`jls`, per global Claude rules).
> After every `cargo build`, restart the Kaimon REPL before exercising anything — the `.so` is
> already mapped into a running session and won't pick up the rebuild.

## Status

**Not started.** Scoped and live-verified against `polars-plan-0.54.4`/`polars-time-0.54.4`'s
vendored source and the active feature closure (`cargo tree -e features -i polars-plan`), per
`CLAUDE.md`'s method — not against `Cargo.toml`'s comments. Continues on the current branch
(`parity-frame-verbs-horizontal-concat`), in the same vein as its recent commits (frame verbs,
horizontal concat, frame aggregations).

Closes two [`api_gap_audit.md`](api_gap_audit.md) Group 2 items: **"Ranges and generators"** and
**"Temporal constructors"**. Explicitly out of scope (own follow-up items, not attempted here):
`int_ranges`/`date_ranges`/`datetime_ranges`/`time_ranges` (the per-row "each input row produces a
list" plural forms), `arange` (a plain alias for `int_range`), `linear_space`/`linear_spaces`,
`repeat`/`ones`/`zeros`, and the `date_range(start, end, num_samples=...)` overload that omits
`interval` — each is a separate, independently-sizeable addition once this lands.

## Goal

Add `int_range`, `date_range`, `datetime_range`, `time_range` (the scalar/single-range top-level
constructors) and `datetime`, `duration`, `date`, `time`, `from_epoch` (component-wise temporal
constructors) to close the two open Group 2 families.

## Live-verified scoping

Method: grep `#[cfg(feature = ...)]` on each target's *module declaration* (not just the function
itself — a function can look ungated while its enclosing `mod` is feature-gated, which is exactly
what happened here) in
`~/.cargo/registry/src/*/polars-plan-0.54.4/src/dsl/functions/{range,temporal}.rs` and
`mod.rs`, then cross-check against the active feature set via `cargo tree -e features -i
polars-plan` run from `c-polars/`.

- **`range` feature is genuinely required and currently NOT active.**
  `polars-plan-0.54.4/src/dsl/functions/mod.rs:14` gates the entire `mod range;` behind
  `#[cfg(feature = "range")]` — `int_range`/`int_ranges` have no *further* per-function gate inside
  that file, but the module-level gate alone makes them unreachable without the feature.
  `cargo tree -e features -i polars-plan` (run from `c-polars/`) shows no `"range"` feature edge
  anywhere in the active tree. **This is the one Cargo change this plan needs** — see Task 1.
- **`dtype-date`, `dtype-datetime`, `dtype-time`, and `temporal` are all already active** (confirmed
  in the same `cargo tree` output), so once `range` is on, `date_range`/`date_ranges` (gated by
  `dtype-date`), `datetime_range`/`datetime_ranges` (gated by `dtype-datetime`), and
  `time_range`/`time_ranges` (gated by `dtype-time`) all become reachable together — one feature
  flip unlocks the whole family, matching the audit's ROI note.
- **`datetime()`/`duration()` need no Cargo change at all.** `dsl/functions/temporal.rs`'s module
  gate is `#[cfg(feature = "temporal")]` (already active); `duration()` has its own additional
  `#[cfg(feature = "dtype-duration")]` (also already active, confirmed in the facade's feature
  list). Nothing here touches `Cargo.toml`.
- **There is no top-level `date()`/`time()`/`from_epoch()` in Rust at all** — only `datetime()` and
  `duration()` exist as genuine Rust constructors. Upstream py-polars' own `pl.date`/`pl.time`/
  `pl.from_epoch` are pure-Python compositions (`pl.date(y,m,d)` ≡
  `pl.datetime(y,m,d).dt.date()`; `pl.time(h,mi,s)` ≡ `pl.datetime(1970,1,1,h,mi,s).dt.time()`;
  `from_epoch` ≡ a physical cast to `Datetime`/`Date`, scaled first for `:s`). This package already
  has `Dt.date`/`Dt.time` (extraction) and `cast_datetime`/`cast` — so these three compose entirely
  in Julia, **zero new FFI**, exactly mirroring upstream's own implementation choice (Task 7).
- **Marshalling precedents already exist for everything these need**: `polars_closed_interval_t`
  (`c-polars/src/expr.rs:703`, for `is_between`/`qcut`) is the template for a new
  `polars_closed_window_t` (same 4 variants, different Rust type — `ClosedWindow` vs
  `ClosedInterval`, so it needs its own enum, not reuse); `cast_datetime`'s tz handling
  (`c-polars/src/expr.rs:405`, `TimeZone::opt_try_new`) is the template for `datetime_range`'s
  `time_zone`; `_time_unit_enum`/`polars_time_unit_t` (`src/expr/expr.jl:192`,
  `c-polars/src/value.rs`) already exists for every `time_unit` parameter below;
  `_plain_value_type_code`/`polars_value_type_t::to_dtype` (`src/expr/expr.jl:270`,
  `c-polars/src/expr.rs:379`) already exists for `int_range`'s `dtype`; `_expr_vector`/
  `@wrap_multi_expr_function` (`src/macros.jl:482`, used by `concat_str`/`all_horizontal`) is the
  template for marshalling a fixed list of `Expr` arguments; `Base.convert(::Type{Expr}, v)`
  overloads (`src/expr/expr.jl:24-92`) are what let every constructor below accept a plain scalar
  (an `Int`, a `Date`, …) anywhere it accepts an `Expr`, matching how the rest of the DSL already
  behaves. `polars::prelude::*` (already `use`d wholesale in `c-polars/src/expr.rs:6`) already
  re-exports `ClosedWindow` and `Duration` from `polars_time` (gated on `temporal`, already active)
  — **no new Cargo dependency needed**, just new `use` items from the existing `polars_plan::dsl::
  functions::{...}` import block.
- **`Duration::try_parse` (not `Duration::parse`) is mandatory.** `polars-time-0.54.4/src/windows/
  duration.rs:162`: `parse` is `try_parse(duration).unwrap()` — a genuine panic-on-bad-input
  entry point. Per `CLAUDE.md`'s FFI panic-safety rule, every `date_range`/`datetime_range`/
  `time_range` wrapper below must call `Duration::try_parse` and propagate its `PolarsResult` via
  `tri!`, never the panicking form.
- **`Base.time` collision**: `time` is a real, exported Base function (`Base.time()::Float64`,
  wall-clock seconds). The Julia-side `time(...)` constructor in Task 7 must extend `Base.time`
  (`function Base.time(hour, ...)`), matching the precedent already set for `get`/`sort`/`tail` in
  `src/expr/expr.jl` (see the in-source note on `tail`), not shadow it with a fresh top-level
  `function time(...)` — the latter would silently be unreachable the same way `@wrap_simple_ops`
  qualifying by `isdefined(Base, f)` bites an unexported collision (`CLAUDE.md`'s own sharp-edge
  note), except here it's worse because `Base.time` **is** exported, so a naive `function time(...)`
  in the `Polars` module would be a separate, ambiguous method that plain `time(...)` after `using
  Polars` may not even resolve to. `date`/`datetime`/`duration`/`from_epoch` have no such collision
  (verified: no `Base.date`, `Base.datetime`, `Base.duration`, or `Base.from_epoch`).

## Global Constraints

- Per `CLAUDE.md`: any Cargo feature change forces a full `cargo build -j 1` (never `-j 4`) and
  invalidates every prior build artifact; do this rebuild exactly once (Task 1), not per-task.
- Every fallible new `extern "C"` fn must be wrapped in `guard_error` and use `tri!` for every
  fallible step (`Duration::try_parse`, `dtype.to_dtype()`, `time_unit.to_time_unit()`,
  `TimeZone::opt_try_new`) — never `.unwrap()`/`.expect()`/`parse()`'s panicking form.
- String args cross the FFI as `(ptr, len)` with `ncodeunits`, never `length`.
- Regenerate bindings after *each* task's Rust changes: `c-polars/regen_header.sh`, then
  `julia --project=gen gen/generate.jl`, then `runic -i src/api/generated.jl` — then restart the
  Kaimon REPL before exercising anything.
- Exercise every new function live in the REPL before writing its test (`CLAUDE.md`'s workflow
  step 3) — this suite has real coverage gaps from operations that shipped untested.
- New Julia code goes in a new `src/expr/ranges.jl` (top-level `pl.*`-family functions don't fit
  any existing file's concern — not `Dt`, not plain `Expr` arithmetic); include it in
  `src/Polars.jl` next to `include("./expr/expr.jl")`. New tests go in `test/expr/ranges.jl`,
  included in `test/runtests.jl` next to `include("expr/horizontal.jl")`.

---

### Task 1: Enable the `range` Cargo feature and rebuild

**Files:**
- Modify: `c-polars/Cargo.toml` (the `polars = { version = "0.54.4", features = [...] }` line)

**Interfaces:**
- Produces: the `range` feature active for every later task in this plan.

- [ ] **Step 1: Add the feature**

Edit the `polars` dependency's `features` list (currently ends `..., "is_first_distinct",
"is_last_distinct"]`) to append `"range"`:

```toml
polars = { version = "0.54.4", features = ["parquet", "lazy", "performant", "trigonometry", "abs", "round_series", "strings", "regex", "dynamic_group_by", "product", "propagate_nans", "is_in", "offset_by", "string_pad", "cum_agg", "diff", "rank", "pct_change", "semi_anti_join", "cross_join", "asof_join", "log", "sign", "dtype-decimal", "replace", "pivot", "top_k", "is_unique", "random", "ipc", "interpolate", "timezones", "decompress", "dtype-time", "meta", "dtype-duration", "aws", "gcp", "azure", "rolling_window", "moment", "is_between", "rle", "cov", "ewma", "cutqcut", "list_sets", "list_count", "list_gather", "list_drop_nulls", "list_sample", "list_to_struct", "dtype-array", "concat_str", "extract_groups", "json", "is_first_distinct", "is_last_distinct", "range"] }
```

Add a one-line comment above it (matching this file's existing per-feature comment style) noting
`range` unlocks `int_range`/`date_range`/`datetime_range`/`time_range` (this plan) and that it
implies `dtype-array` (already on, so a no-op there).

- [ ] **Step 2: Full rebuild**

```bash
cd c-polars && cargo build -j 1
```

Expect several minutes (this recompiles the dependency tree at opt-level 3 per the `[profile.dev.
package."*"]` override). Do **not** use `-j 4` here (`CLAUDE.md`: a full dependency rebuild at
higher parallelism has OOM-killed this machine before).

- [ ] **Step 3: Confirm the feature is really active**

```bash
cd c-polars && cargo tree -e features -i polars-plan 2>/dev/null | grep -F '"range"'
```

Expect at least one `polars-plan feature "range"` line now (there were none before Task 1).

- [ ] **Step 4: Commit**

```bash
git add c-polars/Cargo.toml c-polars/Cargo.lock
git commit -m "Enable range Cargo feature for int_range/date_range/datetime_range/time_range"
```

---

### Task 2: `polars_closed_window_t` enum + `int_range`

**Files:**
- Modify: `c-polars/src/expr.rs` (new enum + new `extern "C"` fn)
- Modify: `c-polars/include/polars.h` (regenerated, not hand-edited)
- Modify: `src/api/generated.jl` (regenerated, not hand-edited)
- Modify: `src/expr/expr.jl` (add `int_range, date_range, datetime_range, time_range` to the
  existing `use polars_plan::dsl::functions::{...}` — wait, that's Rust; on the Julia side, no
  import changes needed, just new function definitions)
- Create: `src/expr/ranges.jl`
- Modify: `src/Polars.jl` (add `include("./expr/ranges.jl")` after `include("./expr/expr.jl")`)
- Create: `test/expr/ranges.jl`
- Modify: `test/runtests.jl` (add `include("expr/ranges.jl")` after `include("expr/horizontal.jl")`)

**Interfaces:**
- Consumes: `_time_unit_enum` (`src/expr/expr.jl:192`), `_plain_value_type_code`
  (`src/expr/expr.jl:270`), `Expr` / `polars_expr_t` / `polars_error` (from `Polars` module scope).
- Produces: `polars_closed_window_t` C enum (reused by Tasks 3-4), `int_range(start, end;
  step::Integer=1, dtype::Type=Int64)::Expr` (module `Polars`, exported).

- [ ] **Step 1: Add the Rust enum + import**

In `c-polars/src/expr.rs`, extend the existing import block (around line 11):

```rust
use polars_plan::dsl::functions::{
    all_horizontal, any_horizontal, as_struct, coalesce, concat_list, concat_str, cov,
    date_range, datetime, datetime_range, duration, int_range, max_horizontal, mean_horizontal,
    min_horizontal, pearson_corr, spearman_rank_corr, sum_horizontal, time_range, DatetimeArgs,
    DurationArgs,
};
```

Add the new enum near `polars_closed_interval_t` (around line 703):

```rust
#[repr(C)]
#[allow(dead_code)]
pub enum polars_closed_window_t {
    PolarsClosedWindowBoth,
    PolarsClosedWindowLeft,
    PolarsClosedWindowRight,
    PolarsClosedWindowNone,
}

impl polars_closed_window_t {
    fn to_closed_window(&self) -> ClosedWindow {
        match self {
            Self::PolarsClosedWindowBoth => ClosedWindow::Both,
            Self::PolarsClosedWindowLeft => ClosedWindow::Left,
            Self::PolarsClosedWindowRight => ClosedWindow::Right,
            Self::PolarsClosedWindowNone => ClosedWindow::None,
        }
    }
}
```

- [ ] **Step 2: Add `polars_expr_int_range`**

Anywhere in `c-polars/src/expr.rs` (e.g. right after the new enum):

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_int_range(
    start: *const polars_expr_t,
    end: *const polars_expr_t,
    step: i64,
    dtype: polars_value_type_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let start = (*start).inner.clone();
        let end = (*end).inner.clone();
        let dtype = tri!(dtype.to_dtype());
        *out = make_expr(int_range(start, end, step, dtype));
        std::ptr::null()
    })
}
```

- [ ] **Step 3: Regenerate bindings and rebuild**

```bash
cd c-polars && cargo build -j 4
cd c-polars && ./regen_header.sh
julia --project=gen gen/generate.jl
runic -i src/api/generated.jl
```

Restart the Kaimon REPL (per this plan's header note).

- [ ] **Step 4: Write `src/expr/ranges.jl`**

```julia
"""
    int_range(start, end; step::Integer=1, dtype::Type=Int64)::Polars.Expr

Generates a column of consecutive integers from `start` (inclusive) to `end` (exclusive), spaced
by `step`. `start`/`end` may be plain values or `Expr`s (see [`Base.convert`](@ref) overloads on
`Expr`). `dtype` must be one of the plain integer dtypes accepted by [`cast`](@ref) (`Int8`
through `Int64`/`UInt8` through `UInt64`) -- anything else raises, mirroring `cast`'s own
`_plain_value_type_code` restriction.
"""
function int_range(start, end_; step::Integer = 1, dtype::Type = Int64)
    start = convert(Expr, start)
    end_ = convert(Expr, end_)
    value_type = _plain_value_type_code(dtype)
    value_type === nothing && error("could not use $dtype as an int_range dtype")
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_int_range(start, end_, Int64(step), value_type, out)
    polars_error(err)
    return Expr(out[])
end

export int_range
```

Note the second positional arg is named `end_` (not `end`, a reserved word in Julia).

- [ ] **Step 5: Wire up includes**

In `src/Polars.jl`, add right after `include("./expr/expr.jl")`:

```julia
include("./expr/ranges.jl")
```

- [ ] **Step 6: Exercise live in the Kaimon REPL**

```julia
using Polars
select(DataFrame((; x=[1])), alias(int_range(0, 5), "r"))[:r]  # expect [0,1,2,3,4]
select(DataFrame((; x=[1])), alias(int_range(0, 10; step=2, dtype=Int32), "r"))[:r]  # [0,2,4,6,8], Int32
```

Confirm no panic/abort for a few dtype/step combinations (negative step, `UInt8` overflow of the
requested range, etc.) before moving on — this is the live-verification `CLAUDE.md` requires for
a freshly-enabled Cargo feature, not just a clean build.

- [ ] **Step 7: Write the failing test, then make it pass**

`test/expr/ranges.jl`:

```julia
@testset "int_range" begin
    df = DataFrame((; x = [1]))

    r = select(df, alias(int_range(0, 5), "r"))
    @test r[:r] == [0, 1, 2, 3, 4]

    r2 = select(df, alias(int_range(0, 10; step = 2, dtype = Int32), "r"))
    @test r2[:r] == Int32[0, 2, 4, 6, 8]
    @test eltype(r2[:r]) == Int32

    r3 = select(df, alias(int_range(5, 0; step = -1), "r"))
    @test r3[:r] == [5, 4, 3, 2, 1]
end
```

In `test/runtests.jl`, add right after `include("expr/horizontal.jl")`:

```julia
include("expr/ranges.jl")
```

Run:

```bash
julia --project=test -e 'using Pkg; Pkg.test()'
```

Expect the new `int_range` testset to pass and nothing else to regress.

- [ ] **Step 8: Commit**

```bash
git add c-polars/src/expr.rs c-polars/include/polars.h src/api/generated.jl src/expr/ranges.jl src/Polars.jl test/expr/ranges.jl test/runtests.jl
git commit -m "Add int_range"
```

---

### Task 3: `date_range`

**Files:**
- Modify: `c-polars/src/expr.rs`, `c-polars/include/polars.h` (regenerated), `src/api/generated.jl`
  (regenerated), `src/expr/ranges.jl`, `test/expr/ranges.jl`

**Interfaces:**
- Consumes: `polars_closed_window_t`/`to_closed_window` (Task 2), `read_str` (`ffi_util.rs`),
  `Duration::try_parse` (`polars_time`, already in scope via `polars::prelude::*`).
- Produces: `date_range(start, end; interval::AbstractString, closed::Symbol=:both)::Expr`.

- [ ] **Step 1: Add `polars_expr_date_range`**

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_date_range(
    start: *const polars_expr_t,
    end: *const polars_expr_t,
    interval: *const u8,
    interval_len: usize,
    closed: polars_closed_window_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let start = (*start).inner.clone();
        let end = (*end).inner.clone();
        let interval = tri!(read_str(interval, interval_len));
        let interval = tri!(Duration::try_parse(interval.as_str()));
        let closed = closed.to_closed_window();
        let expr = tri!(date_range(Some(start), Some(end), Some(interval), None, closed));
        *out = make_expr(expr);
        std::ptr::null()
    })
}
```

If `read_str` returns a type without `.as_str()` (check its signature in `ffi_util.rs` if the
compiler complains), pass it directly — `PlSmallStr` derefs to `&str` in most call positions.

- [ ] **Step 2: Regenerate + rebuild + restart REPL**

Same three commands as Task 2 Step 3, plus REPL restart.

- [ ] **Step 3: Add the Julia wrapper**

Append to `src/expr/ranges.jl`:

```julia
const _CLOSED_WINDOW = Dict(
    :both => API.PolarsClosedWindowBoth,
    :left => API.PolarsClosedWindowLeft,
    :right => API.PolarsClosedWindowRight,
    :none => API.PolarsClosedWindowNone,
)

function _closed_window_enum(closed::Symbol)
    haskey(_CLOSED_WINDOW, closed) || error("unknown closed $closed, expected one of (:both, :left, :right, :none)")
    return _CLOSED_WINDOW[closed]
end

"""
    date_range(start, end; interval::AbstractString, closed::Symbol=:both)::Polars.Expr

Generates a column of `Date`s from `start` to `end` (inclusive/exclusive per `closed`), stepping
by `interval` (a polars interval string, e.g. `"1d"`, `"1w"` -- must consist of whole days, matching
upstream's own restriction for a `Date`-typed range). `start`/`end` may be plain `Date`s or `Expr`s.
"""
function date_range(start, end_; interval::AbstractString, closed::Symbol = :both)
    start = convert(Expr, start)
    end_ = convert(Expr, end_)
    closed_enum = _closed_window_enum(closed)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_date_range(start, end_, interval, ncodeunits(interval), closed_enum, out)
    polars_error(err)
    return Expr(out[])
end

export date_range
```

- [ ] **Step 4: Exercise live**

```julia
using Polars, Dates
select(DataFrame((; x=[1])), alias(date_range(Date(2024,1,1), Date(2024,1,5); interval="1d"), "r"))[:r]
```

Expect `[Date(2024,1,1), ..., Date(2024,1,5)]` (5 values, `:both` closed by default). Also try
`closed=:left` (4 values, drops the end) and an invalid interval string (e.g. `"1h"` — should raise
a `PolarsError` about whole days, not crash the process — confirming `guard_error`/`tri!` actually
catches it).

- [ ] **Step 5: Write the failing test, then make it pass**

```julia
@testset "date_range" begin
    df = DataFrame((; x = [1]))

    r = select(df, alias(date_range(Date(2024, 1, 1), Date(2024, 1, 5); interval = "1d"), "r"))
    @test r[:r] == [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3), Date(2024, 1, 4), Date(2024, 1, 5)]

    r2 = select(df, alias(date_range(Date(2024, 1, 1), Date(2024, 1, 5); interval = "1d", closed = :left), "r"))
    @test r2[:r] == [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3), Date(2024, 1, 4)]

    @test_throws Polars.PolarsError date_range(Date(2024, 1, 1), Date(2024, 1, 5); interval = "1h")
end
```

- [ ] **Step 6: Commit**

```bash
git add c-polars/src/expr.rs c-polars/include/polars.h src/api/generated.jl src/expr/ranges.jl test/expr/ranges.jl
git commit -m "Add date_range"
```

---

### Task 4: `datetime_range`

**Files:** same shape as Task 3.

**Interfaces:**
- Consumes: `polars_closed_window_t` (Task 2), `polars_time_unit_t`/`_time_unit_enum`
  (pre-existing), `TimeZone::opt_try_new` (already used by `cast_datetime`).
- Produces: `datetime_range(start, end; interval::AbstractString, closed::Symbol=:both,
  time_unit::Symbol=:us, time_zone::Union{Nothing,AbstractString}=nothing)::Expr`.

- [ ] **Step 1: Add `polars_expr_datetime_range`**

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_datetime_range(
    start: *const polars_expr_t,
    end: *const polars_expr_t,
    interval: *const u8,
    interval_len: usize,
    closed: polars_closed_window_t,
    time_unit: polars_time_unit_t,
    tz: *const u8,
    tz_len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let start = (*start).inner.clone();
        let end = (*end).inner.clone();
        let interval = tri!(read_str(interval, interval_len));
        let interval = tri!(Duration::try_parse(interval.as_str()));
        let closed = closed.to_closed_window();
        let time_unit = tri!(time_unit.to_time_unit());
        let tz = tri!(read_opt_str(tz, tz_len));
        let time_zone = tri!(TimeZone::opt_try_new(tz));
        let expr = tri!(datetime_range(
            Some(start), Some(end), Some(interval), None, closed, Some(time_unit), time_zone
        ));
        *out = make_expr(expr);
        std::ptr::null()
    })
}
```

- [ ] **Step 2: Regenerate + rebuild + restart REPL** (same as before).

- [ ] **Step 3: Julia wrapper** — append to `src/expr/ranges.jl`:

```julia
"""
    datetime_range(start, end; interval::AbstractString, closed::Symbol=:both,
                   time_unit::Symbol=:us, time_zone::Union{Nothing,AbstractString}=nothing)::Polars.Expr

Generates a column of `DateTime`s from `start` to `end`, stepping by `interval` (a polars interval
string, e.g. `"1h30m"`). `start`/`end` may be plain `DateTime`s or `Expr`s.
"""
function datetime_range(
        start, end_; interval::AbstractString, closed::Symbol = :both,
        time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing
    )
    start = convert(Expr, start)
    end_ = convert(Expr, end_)
    closed_enum = _closed_window_enum(closed)
    unit_enum = _time_unit_enum(time_unit)
    tz = time_zone === nothing ? "" : String(time_zone)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_datetime_range(
        start, end_, interval, ncodeunits(interval), closed_enum, unit_enum, tz, ncodeunits(tz), out
    )
    polars_error(err)
    return Expr(out[])
end

export datetime_range
```

- [ ] **Step 4: Exercise live**, including a `time_zone="UTC"` case and a sub-day `interval`
  (e.g. `"6h"`) to confirm both the tz and non-whole-day-interval paths (illegal for `date_range`,
  legal here) work.

- [ ] **Step 5: Write the failing test, then make it pass** in `test/expr/ranges.jl`:

```julia
@testset "datetime_range" begin
    df = DataFrame((; x = [1]))

    r = select(
        df,
        alias(datetime_range(DateTime(2024, 1, 1, 0), DateTime(2024, 1, 1, 12); interval = "6h"), "r")
    )
    @test r[:r] == [DateTime(2024, 1, 1, 0), DateTime(2024, 1, 1, 6), DateTime(2024, 1, 1, 12)]
end
```

Add a timezone-aware case using this suite's existing `ZonedDateTime`/`TimeZones.jl` extension
fixture pattern (see `test/datatypes/timezones.jl` for how tz-aware columns are asserted elsewhere
in this suite) rather than inventing a new one.

- [ ] **Step 6: Commit.**

---

### Task 5: `time_range`

**Files:** same shape as Task 3, minus tz.

**Interfaces:**
- Consumes: `polars_closed_window_t` (Task 2).
- Produces: `time_range(start, end; interval::AbstractString, closed::Symbol=:both)::Expr`.

- [ ] **Step 1: Add `polars_expr_time_range`** (infallible upstream except for the `Duration`
  parse, unlike `date_range`/`datetime_range` which also return `PolarsResult`):

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_time_range(
    start: *const polars_expr_t,
    end: *const polars_expr_t,
    interval: *const u8,
    interval_len: usize,
    closed: polars_closed_window_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let start = (*start).inner.clone();
        let end = (*end).inner.clone();
        let interval = tri!(read_str(interval, interval_len));
        let interval = tri!(Duration::try_parse(interval.as_str()));
        let closed = closed.to_closed_window();
        *out = make_expr(time_range(start, end, interval, closed));
        std::ptr::null()
    })
}
```

- [ ] **Step 2: Regenerate + rebuild + restart REPL.**

- [ ] **Step 3: Julia wrapper** — append to `src/expr/ranges.jl`:

```julia
"""
    time_range(start, end; interval::AbstractString, closed::Symbol=:both)::Polars.Expr

Generates a column of `Dates.Time`s from `start` to `end`, stepping by `interval`.
"""
function time_range(start, end_; interval::AbstractString, closed::Symbol = :both)
    start = convert(Expr, start)
    end_ = convert(Expr, end_)
    closed_enum = _closed_window_enum(closed)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_time_range(start, end_, interval, ncodeunits(interval), closed_enum, out)
    polars_error(err)
    return Expr(out[])
end

export time_range
```

- [ ] **Step 4: Exercise live, then write the failing test and make it pass**:

```julia
@testset "time_range" begin
    df = DataFrame((; x = [1]))
    r = select(df, alias(time_range(Dates.Time(9, 0), Dates.Time(10, 0); interval = "30m"), "r"))
    @test r[:r] == [Dates.Time(9, 0), Dates.Time(9, 30), Dates.Time(10, 0)]
end
```

- [ ] **Step 5: Commit.**

---

### Task 6: `datetime()` and `duration()` constructors

No Cargo change (see scoping notes). Both take a fixed set of `Expr` components — mirrors
`@wrap_multi_expr_function`'s marshalling but with named, non-variadic arguments, so hand-write
rather than force it through that macro.

**Files:**
- Modify: `c-polars/src/expr.rs`, regenerated header/bindings, `src/expr/ranges.jl`,
  `test/expr/ranges.jl`.

**Interfaces:**
- Consumes: `DatetimeArgs`/`DurationArgs`/`datetime`/`duration` (already added to the Task 2 import
  block), `polars_time_unit_t`, `TimeZone::opt_try_new`.
- Produces: `datetime(year, month, day; hour=0, minute=0, second=0, microsecond=0,
  time_unit::Symbol=:us, time_zone=nothing, ambiguous::AbstractString="raise")::Expr`,
  `duration(; weeks=0, days=0, hours=0, minutes=0, seconds=0, milliseconds=0, microseconds=0,
  nanoseconds=0, time_unit::Symbol=:us)::Expr`.

- [ ] **Step 1: Add `polars_expr_datetime`**

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_datetime(
    year: *const polars_expr_t,
    month: *const polars_expr_t,
    day: *const polars_expr_t,
    hour: *const polars_expr_t,
    minute: *const polars_expr_t,
    second: *const polars_expr_t,
    microsecond: *const polars_expr_t,
    time_unit: polars_time_unit_t,
    tz: *const u8,
    tz_len: usize,
    ambiguous: *const u8,
    ambiguous_len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let time_unit = tri!(time_unit.to_time_unit());
        let tz = tri!(read_opt_str(tz, tz_len));
        let time_zone = tri!(TimeZone::opt_try_new(tz));
        let ambiguous = tri!(read_str(ambiguous, ambiguous_len));
        let args = DatetimeArgs {
            year: (*year).inner.clone(),
            month: (*month).inner.clone(),
            day: (*day).inner.clone(),
            hour: (*hour).inner.clone(),
            minute: (*minute).inner.clone(),
            second: (*second).inner.clone(),
            microsecond: (*microsecond).inner.clone(),
            time_unit,
            time_zone,
            ambiguous: ambiguous.to_string().lit(),
        };
        *out = make_expr(datetime(args));
        std::ptr::null()
    })
}
```

`.lit()` needs the `Literal` trait in scope, already imported (`use polars_plan::prelude::
Literal;`). If `.lit()` doesn't resolve for `String` directly, check that trait's actual impl
target in `polars_plan::dsl` and adjust (this is a normal compile-fix, not a design question).

- [ ] **Step 2: Add `polars_expr_duration`**

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_duration(
    weeks: *const polars_expr_t,
    days: *const polars_expr_t,
    hours: *const polars_expr_t,
    minutes: *const polars_expr_t,
    seconds: *const polars_expr_t,
    milliseconds: *const polars_expr_t,
    microseconds: *const polars_expr_t,
    nanoseconds: *const polars_expr_t,
    time_unit: polars_time_unit_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let time_unit = tri!(time_unit.to_time_unit());
        let args = DurationArgs {
            weeks: (*weeks).inner.clone(),
            days: (*days).inner.clone(),
            hours: (*hours).inner.clone(),
            minutes: (*minutes).inner.clone(),
            seconds: (*seconds).inner.clone(),
            milliseconds: (*milliseconds).inner.clone(),
            microseconds: (*microseconds).inner.clone(),
            nanoseconds: (*nanoseconds).inner.clone(),
            time_unit,
        };
        *out = make_expr(duration(args));
        std::ptr::null()
    })
}
```

- [ ] **Step 3: Regenerate + rebuild + restart REPL.**

- [ ] **Step 4: Julia wrappers** — append to `src/expr/ranges.jl`:

```julia
"""
    datetime(year, month, day; hour=0, minute=0, second=0, microsecond=0,
             time_unit::Symbol=:us, time_zone::Union{Nothing,AbstractString}=nothing,
             ambiguous::AbstractString="raise")::Polars.Expr

Constructs a `DateTime` column from component expressions (or plain scalars). Distinct from
[`cast_datetime`](@ref), which reinterprets/casts an existing value rather than building one from
parts. `ambiguous` controls how a local time that occurs twice (a DST fall-back) resolves -- same
values as [`Dt.replace_time_zone`](@ref)'s `ambiguous`.
"""
function datetime(
        year, month, day; hour = 0, minute = 0, second = 0, microsecond = 0,
        time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing,
        ambiguous::AbstractString = "raise"
    )
    year = convert(Expr, year)
    month = convert(Expr, month)
    day = convert(Expr, day)
    hour = convert(Expr, hour)
    minute = convert(Expr, minute)
    second = convert(Expr, second)
    microsecond = convert(Expr, microsecond)
    unit_enum = _time_unit_enum(time_unit)
    tz = time_zone === nothing ? "" : String(time_zone)
    ambiguous = String(ambiguous)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_datetime(
        year, month, day, hour, minute, second, microsecond, unit_enum,
        tz, ncodeunits(tz), ambiguous, ncodeunits(ambiguous), out
    )
    polars_error(err)
    return Expr(out[])
end

export datetime

"""
    duration(; weeks=0, days=0, hours=0, minutes=0, seconds=0, milliseconds=0, microseconds=0,
              nanoseconds=0, time_unit::Symbol=:us)::Polars.Expr

Constructs a `Duration` column from component expressions (or plain scalars), each may be
negative. Distinct from [`cast_duration`](@ref), which reinterprets/casts an existing value.
"""
function duration(;
        weeks = 0, days = 0, hours = 0, minutes = 0, seconds = 0,
        milliseconds = 0, microseconds = 0, nanoseconds = 0, time_unit::Symbol = :us
    )
    weeks = convert(Expr, weeks)
    days = convert(Expr, days)
    hours = convert(Expr, hours)
    minutes = convert(Expr, minutes)
    seconds = convert(Expr, seconds)
    milliseconds = convert(Expr, milliseconds)
    microseconds = convert(Expr, microseconds)
    nanoseconds = convert(Expr, nanoseconds)
    unit_enum = _time_unit_enum(time_unit)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_duration(
        weeks, days, hours, minutes, seconds, milliseconds, microseconds, nanoseconds, unit_enum, out
    )
    polars_error(err)
    return Expr(out[])
end

export duration
```

- [ ] **Step 5: Exercise live**

```julia
using Polars, Dates
select(DataFrame((; x=[1])), alias(datetime(2024, 1, col("x")), "r"))[:r]  # per-row day-of-month from a column
select(DataFrame((; x=[1])), alias(duration(; days=1, hours=2), "r"))[:r]
```

Confirm the all-literal fast path (`DatetimeArgs::as_literal`/`DurationArgs::as_literal` upstream)
doesn't do anything surprising when every arg is a plain scalar vs. when one is a real column
expression (both should produce correct, differently-shaped results — one broadcasts a scalar
literal, the other varies per row).

- [ ] **Step 6: Write the failing tests, then make them pass**:

```julia
@testset "datetime constructor" begin
    df = DataFrame((; d = [1, 2, 3]))
    r = select(df, alias(datetime(2024, 1, col("d")), "r"))
    @test r[:r] == [DateTime(2024, 1, 1), DateTime(2024, 1, 2), DateTime(2024, 1, 3)]

    r2 = select(df, alias(datetime(2024, 1, 1; hour = 12, minute = 30), "r"))
    @test r2[:r] == fill(DateTime(2024, 1, 1, 12, 30), 3)
end

@testset "duration constructor" begin
    df = DataFrame((; x = [1]))
    r = select(df, alias(duration(; days = 1, hours = 2), "r"))
    @test r[:r] == [Dates.Hour(26)]  # or whatever this suite's Duration-column comparison idiom is -- check test/datatypes/durations.jl
end
```

Check `test/datatypes/durations.jl` for how this suite already asserts `Duration`-typed column
values (likely a `Dates.Period` comparison, not a raw integer) and match that idiom instead of
guessing.

- [ ] **Step 7: Commit.**

---

### Task 7: `date`, `time`, `from_epoch` (pure Julia, zero new FFI)

**Files:**
- Modify: `src/expr/ranges.jl`, `test/expr/ranges.jl`

**Interfaces:**
- Consumes: `datetime` (Task 6), `Dt.date`/`Dt.time` (pre-existing extraction, `src/expr/
  datetime.jl`), `cast`/`cast_datetime` (pre-existing, `src/expr/expr.jl`).
- Produces: `date(year, month, day)::Expr`, `Base.time(hour, minute=0, second=0,
  microsecond=0)::Expr` (extends `Base.time`, exported), `from_epoch(expr::Expr,
  time_unit::Symbol=:s)::Expr`.

- [ ] **Step 1: Implement, appending to `src/expr/ranges.jl`**

```julia
"""
    date(year, month, day)::Polars.Expr

Constructs a `Date` column from component expressions (or plain scalars). Composes
[`datetime`](@ref) + [`Dt.date`](@ref) (this package has no separate Rust-side `Date` constructor
-- neither does upstream py-polars, whose own `pl.date` does the same composition in Python).
"""
date(year, month, day) = Dt.date(datetime(year, month, day))

export date

"""
    time(hour, minute=0, second=0, microsecond=0)::Polars.Expr

Constructs a `Dates.Time` column from component expressions (or plain scalars). Extends
`Base.time` (which takes no arguments and returns wall-clock seconds) rather than shadowing it --
same precedent as this package's `Base.get`/`Base.sort`/`Base.tail` extensions in
`src/expr/expr.jl`.
"""
Base.time(hour, minute = 0, second = 0, microsecond = 0) =
    Dt.time(datetime(1970, 1, 1; hour, minute, second, microsecond))

export time

"""
    from_epoch(expr::Polars.Expr, time_unit::Symbol=:s)::Polars.Expr

Interprets `expr` (an integer column) as a count of `time_unit`s since the Unix epoch and
constructs the corresponding `Date`/`DateTime` column -- the inverse of [`Dt.epoch`](@ref), whose
own scaling logic for `:s`/`:d` this mirrors. One of `:ns`, `:us`, `:ms` (direct physical cast to
`Datetime`), `:s` (scaled to `:ms` first -- `Datetime` has no seconds-resolution variant), or `:d`
(cast to `Date`, whose physical representation is already days-since-epoch).
"""
function from_epoch(expr::Expr, time_unit::Symbol = :s)
    if time_unit in (:ns, :us, :ms)
        return cast_datetime(expr; time_unit)
    elseif time_unit == :s
        return cast_datetime(expr * convert(Expr, 1_000); time_unit = :ms)
    elseif time_unit == :d
        return cast(expr, Date)
    else
        error("unknown time_unit $time_unit, expected one of (:ns, :us, :ms, :s, :d)")
    end
end

export from_epoch
```

- [ ] **Step 2: Exercise live**

```julia
using Polars, Dates
select(DataFrame((; x=[1])), alias(date(2024, 1, col("x")), "r"))[:r]
select(DataFrame((; x=[1])), alias(time(9, 30), "r"))[:r]
select(DataFrame((; e=[0, 86400, 172800])), alias(from_epoch(col("e"); ), "r"))[:r]  # :s default
```

Watch specifically for the `Base.time(hour, ...)` method actually being reachable as bare `time(9,
30)` after `using Polars` in a fresh session (not just inside this module) -- this is the exact
failure mode the collision note above warns about.

- [ ] **Step 3: Write the failing tests, then make them pass**:

```julia
@testset "date constructor" begin
    df = DataFrame((; d = [1, 2, 3]))
    r = select(df, alias(date(2024, 1, col("d")), "r"))
    @test r[:r] == [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3)]
end

@testset "time constructor" begin
    df = DataFrame((; x = [1]))
    r = select(df, alias(time(9, 30), "r"))
    @test r[:r] == [Dates.Time(9, 30)]
end

@testset "from_epoch" begin
    df = DataFrame((; e = [0, 86400, 172800]))

    r = select(df, alias(from_epoch(col("e")), "r"))  # :s default
    @test r[:r] == [DateTime(1970, 1, 1), DateTime(1970, 1, 2), DateTime(1970, 1, 3)]

    r2 = select(df, alias(from_epoch(col("e"); time_unit = :d), "r"))
    @test r2[:r] == [Date(1970, 1, 1), Date(1970, 1, 3), Date(1970, 1, 5)]
end
```

- [ ] **Step 4: Commit.**

---

### Task 8: Docs and audit closure

**Files:**
- Modify: `plans/parity/api_gap_audit.md` (mark both Group 2 items closed, in its established
  `~~strikethrough~~ **Closed** (see [Status](#status))` style, plus a new `## Status` bullet)
- Modify: `plans/parity/range_temporal_constructors.md` (this file) — flip `## Status` to `Done`
- Check: `docs/src/limitations.md` for any range/temporal-adjacent claim this closes (skim only —
  none expected, since nothing here changes a documented limitation).

- [ ] **Step 1**: In `api_gap_audit.md`'s `## Status` section, add a bullet describing what landed
  (mirroring the existing bullets' style — name the new functions, the one Cargo feature change,
  and the explicitly out-of-scope follow-ups from this plan's own header).

- [ ] **Step 2**: Strike the two Group 2 entries (`**Ranges and generators**` and `**Temporal
  constructors**`) per the file's own `~~...~~ **Closed**` convention.

- [ ] **Step 3**: Run the full suite once more (`julia --project=test -e 'using Pkg; Pkg.test()'`)
  to confirm nothing regressed across all 7 tasks together, then commit the doc updates.

```bash
git add plans/parity/api_gap_audit.md plans/parity/range_temporal_constructors.md
git commit -m "Close Group 2 range/temporal-constructor gaps in the parity audit"
```
