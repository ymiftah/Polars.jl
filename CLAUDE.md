# Polars.jl — Project Notes for Claude

## Architecture & philosophy

A thin Julia wrapper over the Rust `polars` crate, built as a hand-written C ABI bridge rather than
a deep binding (no `jlrs`, no attempt to expose polars' full Rust type system to Julia):

```
src/Polars.jl, src/expr.jl, ...   idiomatic Julia API, Tables.jl integration
        │  @ccall
src/API.jl                        thin, ~1:1 per-symbol ccall wrappers
        │
c-polars/src/lib.rs, expr.rs, series.rs, value.rs   extern "C" cdylib over opaque pointers
        │
polars / polars-lazy / polars-core / ...   unmodified upstream crate — never patched
```

Guiding principle: the C ABI layer (`c-polars/`) does the minimum possible — unwrap a pointer, call
the real polars method, rebox the result. All actual query logic lives in upstream polars. Prefer
extending this thin layer with one new function per new capability over building generic
pass-through machinery; the existing symbol-per-operation style is intentional and keeps each
addition small and auditable.

Eager `DataFrame` operations are generally implemented as `collect ∘ op ∘ lazy` on the Julia side —
check whether a new capability can be added purely to the lazy path (`LazyFrame`/`LazyGroupBy`) and
get the eager equivalent for free, rather than writing separate eager and lazy C ABI functions.

## How the C ABI is leveraged

**Opaque pointers + Julia finalizers.** Every polars type crossing the boundary
(`DataFrame`, `LazyFrame`, `LazyGroupBy`, `Expr`, `Series`, `Value`) is an empty opaque struct on
the Julia side (`polars_foo_t`) and a `Box`-allocated real-type wrapper on the Rust side
(`struct polars_foo_t { inner: RealPolarsType }`). Julia wraps the raw pointer in a
`mutable struct` that registers `finalizer(polars_foo_destroy, ...)` in its inner constructor and
defines `Base.unsafe_convert(::Type{Ptr{polars_foo_t}}, x) = x.ptr` so it can be passed directly to
`@ccall`. This is the whole memory-management story — get this right for any new type and GC is
handled for free.

**Ownership conventions on the Rust side:**
- Functions that *construct a new* object (`scan_parquet`, `group_by`, `clone`) do
  `Box::into_raw(Box::new(...))` and return a fresh pointer; the input, if any, is only
  read/cloned, never consumed.
- Functions that *mutate in place* (`filter`, `select`, `with_columns`, `sort`) reclaim ownership
  via `Box::from_raw`, mutate `.inner`, then `std::mem::forget` to hand the same pointer back
  without dropping it.
- Every `*_destroy` function does `Box::from_raw(...)` and lets it drop.

**Error handling.** Fallible functions return `*const polars_error_t` (null = success); the actual
result comes back through an out-parameter (`out: *mut *mut polars_foo_t`). `make_error(err)` boxes
a stringified error. On the Julia side, every fallible ccall is immediately followed by
`polars_error(err)`, which unwraps null-vs-message and raises via `Base.error()`. Follow this
convention for anything that can fail — including type conversions/parses (e.g. duration strings)
that would otherwise need to panic; a Rust panic unwinding across `extern "C"` is UB, so any
fallible parse *must* go through this out-param + error-pointer convention instead of an
API that panics.

**Missing Cargo features are a live version of this danger, not just a hypothetical.** Several
polars-core/-expr functions (`Series::product`, nan-propagating min/max, others) compile to a bare
`panic!("activate 'X' feature")` when their feature isn't enabled — calling them crashes the whole
Julia process, not a catchable Julia error. Before wrapping or exercising a function for the first
time, scan for these across the vendored crates and cross-check against `c-polars/Cargo.toml`'s
feature list: `grep -rn "activate .* feature" ~/.cargo/registry/src/*/polars-*-<version>/src/`.

**Passing collections/strings across the boundary:**
- `Vec<Expr>`-shaped args (used by `select`, `filter`, `group_by`, `agg`, `sort`, and any future
  operation taking a column-expression list) are passed as `*const *const polars_expr_t` + a
  length, built on the Julia side under `GC.@preserve` from a `Vector{Expr}`. Convert incoming
  `String`s to `col(...)` before building the pointer array so callers can pass either.
- Strings (paths, duration literals, column names) are passed as `(ptr: Ptr{UInt8}, len: Csize_t)`
  pairs — a plain Julia `String` auto-converts, so just pass `(s, length(s))` / `(s, ncodeunits(s))`.
- Rust enums crossing the boundary need a hand-defined `#[repr(C)] pub enum polars_foo_t { ... }`
  mirror plus match-based to/from conversion against the real polars enum (there is no derive for
  this). C enums are passed/returned **by value**, never by pointer. Mirror this with a
  `@cenum polars_foo_t::UInt32 begin ... end` block on the Julia side (variants numbered from 0 in
  declaration order).

**The header and generated bindings are hand-maintained in practice, not auto-synced.**
`c-polars/build.rs` can regenerate `include/polars.h` via `cbindgen`, and `gen/generate.jl` can
regenerate `src/API.jl` from that header via Clang.jl — but both pipelines are fragile
(cbindgen's macro-expansion step needs a cooperating nightly toolchain; Clang.jl needs its own
setup) and this repo's actual working convention is to hand-edit both files directly when adding a
symbol. Don't invest in getting the generation pipelines working as a prerequisite to adding a
function — hand-add the header prototype and the `@ccall` wrapper, matching the style of
neighboring entries.

## Workflow: adding a new wrapped polars operation

1. **Check whether it needs a new type at all.** Many polars operations return/consume types this
   package already wraps (`LazyFrame`, `LazyGroupBy`, `Expr`) — confirm this first so you don't
   build unnecessary new pointer/finalizer plumbing.
2. **Check the Cargo feature is enabled.** `c-polars/Cargo.toml`'s `polars` dependency only enables
   a subset of upstream features; some polars capabilities are behind a Cargo feature flag that
   isn't on by default here and needs adding to the `features = [...]` list.
3. **Write the Rust `extern "C"` function** in the appropriate `c-polars/src/*.rs` file, following
   the ownership/error/enum conventions above and the style of the nearest existing function for
   the same category (constructor vs. mutator vs. destructor).
4. **Hand-add the header prototype** to `c-polars/include/polars.h`, matching the cbindgen output
   style of neighboring declarations.
5. **Hand-add the `@ccall` wrapper** to `src/API.jl`, matching the style of neighboring wrappers
   (and a matching `@cenum` block if a new enum was introduced).
6. **Write the idiomatic Julia entry point** in `src/Polars.jl` (or `src/expr.jl` for expression
   builders), reusing the marshalling patterns above, and add it to the `export` list.
7. **Build** (`cd c-polars && cargo build` — stable toolchain, see below) and verify end-to-end
   through a live Julia session before writing tests: construct the smallest input that exercises
   the new path, run it, and inspect the actual result — this repo's existing test suite has gaps
   (whole operations have shipped with zero coverage before), so don't assume something works
   because it compiles.
8. **Add a test** under the matching `test/<category>/*.jl` file (`dataframe/`, `lazyframe/`,
   `operations/`, `expr/`, `datatypes/` — mirrors py-polars' layout; `test/runtests.jl` just
   `include`s them all). Reuse `test/fixtures.jl`'s sample-data builders where the shape fits.
   There are no committed data fixtures — tests that need parquet/file input generate it on the
   fly (e.g. via `write_parquet` into a `mktempdir()`, see `write_temp_parquet` in fixtures.jl).
9. **Persist any multi-step implementation plan in-repo** under `plans/` (not only the ephemeral
   `~/.claude/plans/` scratch file) so a future session can pick it up.

## Build environment

**Build `c-polars` with the stable Rust toolchain**, not nightly — `c-polars/rust-toolchain` is
pinned to `stable` deliberately. A polars dependency (`polars-ops`) auto-detects a nightly rustc via
its own `build.rs` and unconditionally opts into a nightly-only internal code path that depends on
unstable standard-library internals; those internals are churned by the Rust project without
warning, and this has broken the build under nightly before. Note this is invisible to
`cargo tree -e features` — it's injected by a `build.rs`, not a normal Cargo feature edge — so don't
trust `cargo tree` alone if you suspect a phantom feature is active.

Header regeneration via `cbindgen` (which does need nightly + a working `cargo expand`) is opt-in
via `CBINDGEN_GENERATE=1`; default builds skip it entirely (see "hand-maintained" note above).

**A running Julia session does not pick up a `cargo build` rebuild** — the native `.so` is already
mapped in; re-running `using Polars` is a no-op. Restart the session (Kaimon: `manage_repl` with
`command="restart"`) after every `c-polars` rebuild before testing the change.

## Known sharp edges

- **`src/arrow.jl` has no write-side support for List or Struct columns.** `DataFrame(table)` can't
  construct a column from `Vector{Vector{T}}` or `Vector{<:NamedTuple}` — only scalar/fixed-width
  types, `String`, `Date`, `DateTime` have an `arrowvector` method. List data can still be obtained
  via `implode`/`group_by`; Struct data currently has no pure-Julia construction path at all.
- **`Series{Datetime{Res}}`/`Series{Duration{Res}}` don't support `collect()` or broadcasting** —
  the declared `eltype` is the internal wrapper type, but `getindex` returns a plain
  `Dates.DateTime`/`Period`, so the generic `Base.collect` path throws `MethodError`. Use direct
  indexing (`s[i]`) or `isequal` comparisons instead.
- **`@generate_expr_fns` qualifies by `isdefined(Base, fname)`, not `isexported`** — if the Rust
  method name happens to match a Base binding that exists but isn't exported (e.g. `Expr::product`
  collided with an internal, unexported `Base.product`), the generated wrapper silently becomes
  unreachable: it's defined as `Base.product(expr)`, but since `product` was never exported from
  Base, plain `product(expr)` throws `UndefVarError` in a normal session (unlike, say, `sum`/`diff`,
  which collide with *exported* Base names and work unqualified with no extra effort). If a
  generated wrapper seems to vanish, check `isdefined(Base, :fname)` and `Base.isexported(Base,
  :fname)` both. The fix (see `prod` in [expr.jl](src/expr.jl)) is to pull that one item out of the
  `@generate_expr_fns` block and hand-write it under the *exported* Base name instead (`prod`, not
  `product`) — same pattern already used for `std`/`var`/`quantile`/`rank` (extra args the macro's
  plain shape can't express).
