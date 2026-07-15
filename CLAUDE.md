# Polars.jl — Project Notes for Claude

## Architecture & philosophy

A thin Julia wrapper over the Rust `polars` crate, built as a hand-written C ABI bridge rather than
a deep binding (no `jlrs`, no attempt to expose polars' full Rust type system to Julia):

```
src/*.jl, src/{expr,arrow,io}/*.jl   idiomatic Julia API, Tables.jl integration (one file
        │  @ccall                    per concern -- see "Where things live" below)
src/api/*.jl                        thin, ~1:1 per-symbol ccall wrappers (mirrors the Rust file
        │                            split below almost exactly)
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

### Where things live (`src/`)

`src/` is split by concern, modeled on py-polars' own `src/polars` layout (one directory per root
type, one file per accessor namespace, `io/` split by format):

| Path | Contents |
|---|---|
| `src/Polars.jl` | Module setup only: imports, shared types (`MaybeMissing`, `PhysicalDType`), the `include()` sequence, `version()`/`polars_error()`, the final `export` list |
| `src/dataframe.jl` | `struct DataFrame`, constructor, `size`/`getindex`/`unsafe_convert`, `Base.show`, `Tables.jl` schema/interface glue |
| `src/lazyframe.jl` | `struct LazyFrame`, `lazy()`, `collect()`, `clone()`, `collect_schema()` |
| `src/group_by.jl` | `struct LazyGroupBy`, `group_by`/`groupby`, `agg`, `group_by_dynamic`, `rolling` |
| `src/select.jl` | `select`, `with_columns`, `head`, `tail`, `filter` |
| `src/verbs.jl` | `unique`, `drop`, `rename`, `drop_nulls`, `with_row_index`, `concat` |
| `src/join.jl` | `innerjoin`/`leftjoin`/`rightjoin`/`outerjoin`/`semijoin`/`antijoin`/`crossjoin`, `join_asof` |
| `src/reshape.jl` | `explode`, `unpivot`, `pivot`, `upsample` |
| `src/sort.jl` | `Base.sort` (both `LazyFrame`/`DataFrame`) |
| `src/describe.jl` | `describe()` |
| `src/series.jl` | `struct Series`, `getindex` across dtypes, `name()` |
| `src/value.jl` | `struct Value`, `load_value` methods (materializing a scalar/nested value) |
| `src/io/{parquet,csv,ipc}.jl` | `scan_*`/`read_*`/`write_*`/`sink_*` per format |
| `src/arrow/schema.jl` | Arrow C Data Interface schema side: `parse_format`, `load_series_schema`/`load_dataframe_schema`, the `_tz_aware_datetime_type` extension hook |
| `src/arrow/array.jl` | Arrow C Data Interface array side: `ValidityMap`, `arrowvector` (Julia `Vector` → `ArrowArray`, one method per dtype incl. `List`/`Struct`), `arrowtable` |
| `src/expr/expr.jl` | Core `struct Expr`, operators, `@generate_expr_fns`-generated ops, everything not in a namespace submodule below (still the largest file — matches py-polars' own pattern of one big "core" file per root type even after splitting out namespaces) |
| `src/expr/{list,string,datetime,struct}.jl` | The `Lists`/`Strings`/`Dt`/`Structs` namespace submodules |
| `src/api/API.jl` | `module API`; just `include()`s the files below + the final auto-export loop |
| `src/api/types.jl` | All `@cenum` blocks, opaque `polars_*_t` handle structs, `ArrowSchema`/`ArrowArray` C-interop structs, `IOCallback`, libpolars local-dev-build resolution |
| `src/api/{dataframe,expr,series,value}.jl` | `@ccall` wrappers, split along the *same* boundaries as the Rust files below (`dataframe.jl` covers `lib.rs`'s `DataFrame`+`LazyFrame`+`LazyGroupBy` functions) |

When adding a new verb, put it in the file matching its *category* above, not wherever's
convenient — e.g. a new join variant goes in `src/join.jl`, not `src/verbs.jl`. `test/` mirrors
this by *concern* too (`test/operations/join.jl`, `test/lazyframe/scan_parquet.jl`, etc.) — see the
workflow section below.

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
API that panics. **This has bitten us for real, twice:** `polars_series_get` used to `.unwrap()` on
an out-of-bounds index (crashed the whole process on e.g. `s[999]` for any `Series` whose element
type isn't numeric/bool), and `polars_dataframe_show` used to `.expect()` on a write-callback
failure — both fixed by converting to the out-param + error-pointer shape (see
`plans/ffi_panic_safety.md`).

**Missing Cargo features are a live version of this danger, not just a hypothetical.** Several
polars-core/-expr functions (`Series::product`, nan-propagating min/max, others) compile to a bare
`panic!("activate 'X' feature")` when their feature isn't enabled — calling them crashes the whole
Julia process, not a catchable Julia error. Before wrapping or exercising a function for the first
time, scan for these across the vendored crates and cross-check against `c-polars/Cargo.toml`'s
feature list: `grep -rn "activate .* feature" ~/.cargo/registry/src/*/polars-*-<version>/src/`.
**This isn't limited to that literal panic macro either** — `sink_csv(...; compression=:gzip)` once
crashed the whole process because the `polars` crate doesn't enable `polars-io`'s `decompress`
feature by default (even though `polars-io` itself defaults it on for standalone use — the `polars`
crate's own `Cargo.toml` disables `polars-io`'s defaults and cherry-picks features explicitly). This
kind of bug **compiles fine and only crashes at runtime**, so a clean `cargo build` is never
sufficient evidence a new code path is safe — always exercise it live (see workflow step 7) before
considering it done, especially anything touching a compression/codec option.

**Passing collections/strings across the boundary:**
- `Vec<Expr>`-shaped args (used by `select`, `filter`, `group_by`, `agg`, `sort`, and any future
  operation taking a column-expression list) are passed as `*const *const polars_expr_t` + a
  length, built on the Julia side under `GC.@preserve` from a `Vector{Expr}`. Convert incoming
  `String`s to `col(...)` before building the pointer array so callers can pass either.
- Strings (paths, duration literals, column names) are passed as `(ptr: Ptr{UInt8}, len: Csize_t)`
  pairs — a plain Julia `String` auto-converts, so just pass `(s, length(s))` / `(s, ncodeunits(s))`.
  *Optional* strings follow the same shape with a null-ptr-or-zero-len-means-`None` convention
  (`read_opt_str` on the Rust side) — e.g. `row_index_name`, `include_file_paths`.
- Optional scalars generally cross as nullable pointers (`*const T`, null = `None`) — e.g.
  `polars_expr_sample_n`'s `seed: *const u64`, marshalled on the Julia side as
  `seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))` under `GC.@preserve`.
- Rust enums crossing the boundary need a hand-defined `#[repr(C)] pub enum polars_foo_t { ... }`
  mirror plus match-based to/from conversion against the real polars enum (there is no derive for
  this). C enums are passed/returned **by value**, never by pointer. Mirror this with a
  `@cenum polars_foo_t::UInt32 begin ... end` block in `src/api/types.jl` (variants numbered from 0
  in declaration order).

**The header and bindings are hand-maintained, not generated.** `c-polars/build.rs` can regenerate
`include/polars.h` via `cbindgen` (opt-in, see below), but this repo's actual working convention is
to hand-edit both the header and the `@ccall` wrappers directly when adding a symbol — always add
the header prototype and the `src/api/*.jl` wrapper by hand, matching the style of neighboring
entries. (A Clang.jl-based generator for the Julia bindings side used to live in `gen/`; it was
removed — it only produced a single flat ccall file, not our per-category `src/api/` split, needed
its own toolchain warmed up per run, and every real bug found in this codebase has been a runtime
behavior issue no binding generator would have caught anyway — see the panic-safety notes above.)

## Package extensions (optional weak dependencies)

Some functionality needs a heavy optional dependency that most users shouldn't be forced to
install — timezone-aware `Datetime` materialization needs `TimeZones.jl`'s `ZonedDateTime`, for
instance. Pattern (see `ext/PolarsTimeZonesExt.jl`, `Project.toml`'s `[weakdeps]`/`[extensions]`):

- The core package ships **everything that doesn't need the optional dependency's types**
  unconditionally — e.g. `Dt.replace_time_zone`/`Dt.convert_time_zone` just pass timezone name
  strings across the FFI boundary and work with no extension loaded at all.
- The one place that *would* need the optional type (materializing a tz-aware value into a Julia
  `ZonedDateTime`) is guarded by an extension hook that **errors with a clear "load X.jl" message**
  by default, and is overridden once the user does `using TimeZones`.
- **The hook itself must be a zero-method stub, not a function with a default-case method.**
  Julia's package extension mechanism forbids an extension from *redefining* an existing
  same-signature method during precompilation (`"Method overwriting is not permitted during
  Module precompilation"`) — only *adding* a genuinely new method is allowed there. The working
  pattern (`_tz_aware_datetime_type`/`_resolve_tz_aware_datetime_type` in `src/arrow/schema.jl`):
  the public-facing function has real logic and catches `MethodError` from calling a *second*,
  deliberately empty function (`function _resolve_tz_aware_datetime_type end` — zero methods,
  declared but never implemented in core); the extension adds the first-ever method for that
  second function. This sidesteps the precompilation restriction entirely since there's no
  existing method to conflict with.
- Verify both paths live in a scratch environment that actually has the optional package added
  (`Pkg.develop(path=".")` + `Pkg.add("TimeZones")`) — the default `--project=.` session won't
  load the extension at all, so "does it error without TimeZones" and "does it work with
  TimeZones" need two different environments to test.

## Workflow: adding a new wrapped polars operation

1. **Check whether it needs a new type at all.** Many polars operations return/consume types this
   package already wraps (`LazyFrame`, `LazyGroupBy`, `Expr`) — confirm this first so you don't
   build unnecessary new pointer/finalizer plumbing.
2. **Check the Cargo feature is enabled.** `c-polars/Cargo.toml`'s `polars` dependency only enables
   a subset of upstream features; some polars capabilities are behind a Cargo feature flag that
   isn't on by default here and needs adding to the `features = [...]` list. Remember this
   includes transitive-crate defaults the `polars` crate itself disables (see the `decompress`
   example above) — not just capabilities that panic outright.
3. **Write the Rust `extern "C"` function** in the appropriate `c-polars/src/*.rs` file, following
   the ownership/error/enum conventions above and the style of the nearest existing function for
   the same category (constructor vs. mutator vs. destructor).
4. **Hand-add the header prototype** to `c-polars/include/polars.h`, matching the cbindgen output
   style of neighboring declarations.
5. **Hand-add the `@ccall` wrapper** to the matching `src/api/*.jl` file (see "Where things live"
   above — same category split as the Rust source files), and a matching `@cenum` block in
   `src/api/types.jl` if a new enum was introduced.
6. **Write the idiomatic Julia entry point** in the `src/*.jl`/`src/{expr,arrow,io}/*.jl` file
   matching its category (see "Where things live" above), reusing the marshalling patterns above,
   and add it to `src/Polars.jl`'s `export` list (or the relevant namespace submodule's own
   `export`, for `Lists`/`Strings`/`Dt`/`Structs`).
7. **Build** (`cd c-polars && cargo build` — stable toolchain, see below) and verify end-to-end
   through a live Julia session before writing tests: construct the smallest input that exercises
   the new path, run it, and inspect the actual result — this repo's existing test suite has gaps
   (whole operations have shipped with zero coverage before), so don't assume something works
   because it compiles. **A clean build is not sufficient evidence of safety** — see the
   `decompress`/panic notes above; exercise every new option combination live, not just the happy
   path, especially anything touching compression/codecs or directory/multi-file scanning.
8. **Add a test** under the matching `test/<category>/*.jl` file (`dataframe/`, `lazyframe/`,
   `operations/`, `expr/`, `datatypes/` — mirrors py-polars' layout; `test/runtests.jl` just
   `include`s them all). Reuse `test/fixtures.jl`'s sample-data builders where the shape fits.
   There are no committed data fixtures — tests that need parquet/file input generate it on the
   fly (e.g. via `write_parquet` into a `mktempdir()`, see `write_temp_parquet` in fixtures.jl).
9. **Persist any multi-step implementation plan in-repo** under `plans/` (not only the ephemeral
   `~/.claude/plans/` scratch file) so a future session can pick it up. Give it a `## Status` line
   at the top and update it to `Done` (with the final test count) once landed — several plans in
   this repo follow that convention and it's the fastest way to answer "is X finished?" later.

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

**Running the test suite needs a scratch environment, not `--project=test` or `Pkg.test()`.**
Create one with `Pkg.develop(path=".")` plus `Pkg.add(["Aqua", "Test", "Tables", "TimeZones"])`
(TimeZones is needed to exercise the `PolarsTimeZonesExt` extension — see above), then
`JULIA_PROJECT=<scratch env> julia -e 'include("test/runtests.jl")'`.

## Known sharp edges

- **`@generate_expr_fns` (in `src/expr/expr.jl`) qualifies by `isdefined(Base, fname)`, not
  `isexported`** — if the Rust method name happens to match a Base binding that exists but isn't
  exported (e.g. `Expr::product` collided with an internal, unexported `Base.product`), the
  generated wrapper silently becomes unreachable: it's defined as `Base.product(expr)`, but since
  `product` was never exported from Base, plain `product(expr)` throws `UndefVarError` in a normal
  session (unlike, say, `sum`/`diff`, which collide with *exported* Base names and work unqualified
  with no extra effort). If a generated wrapper seems to vanish, check `isdefined(Base, :fname)`
  and `Base.isexported(Base, :fname)` both. The fix (see `prod` in `src/expr/expr.jl`) is to pull
  that one item out of the `@generate_expr_fns` block and hand-write it under the *exported* Base
  name instead (`prod`, not `product`) — same pattern already used for `std`/`var`/`quantile`/`rank`
  (extra args the macro's plain shape can't express).
- **CSV scanning has no `hive_partitioning` option, unlike parquet/IPC** — not a scope choice, a
  real gap in upstream: `polars_lazy::frame::LazyCsvReader` (the builder `scan_csv` uses)
  hardcodes `hive_options: HiveOptions::new_disabled()` internally and doesn't expose a way to
  override it. Fixing this would mean bypassing the builder entirely.
- **`allow_missing_columns` (parquet/CSV/IPC scan options) only covers files *missing* a column
  present in the reference schema, not files with an *extra* column beyond it** — that's a
  separate `ExtraColumnsPolicy` this wrapper doesn't expose. The reference schema is whichever
  file/fragment gets scanned first; ordering matters when testing this.
