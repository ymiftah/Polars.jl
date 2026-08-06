# Polars.jl — Project Notes for Claude

## Architecture

A thin Julia wrapper over the Rust `polars` crate via a hand-written C ABI bridge (no `jlrs`). The
stack: `src/**/*.jl` (idiomatic Julia API + Tables.jl glue, one file per concern) → the generated
1:1 `@ccall` wrappers in `src/api/generated.jl` → the `extern "C"` cdylib over opaque pointers in
`c-polars/src/*.rs` → unmodified upstream `polars` (never patched).

Guiding principle: `c-polars/` does the minimum — unwrap a pointer, call the real polars method,
rebox the result. One new symbol per capability; no generic pass-through machinery. Eager `DataFrame`
ops are `collect ∘ op ∘ lazy` in Julia, so add capabilities to the lazy path and get the eager
version free. `src/` is split by concern (mirroring py-polars) and `test/` mirrors it — put a new
verb in the file matching its *category* (a join variant in `join.jl`, not `verbs.jl`).

## C ABI conventions

**Opaque pointers + finalizers.** Every type crossing the boundary is an empty `polars_foo_t` in
Julia and a `Box`ed wrapper in Rust. The Julia `mutable struct` registers
`finalizer(polars_foo_destroy, ...)` in its inner constructor and defines
`Base.unsafe_convert(::Type{Ptr{polars_foo_t}}, x) = x.ptr` — that's the whole GC story.

**Ownership.** Constructors (`scan_parquet`, `clone`) `Box::into_raw` a fresh pointer, never consuming
their input. Mutators (`filter`, `select`, `sort`) borrow `&mut (*handle).inner` and return void — the
Julia wrapper clones first, so no caller observes it. `*_destroy` does `Box::from_raw`.

**Errors.** Fallible functions return `*const polars_error_t` (null = success), the result coming via
an out-param (`out: *mut *mut polars_foo_t`); Julia follows every such ccall with `polars_error(err)`.
A panic unwinding across `extern "C"` aborts the host process (a defined abort since Rust 1.81, not
UB — you get SIGABRT and the panic message on stderr, uncatchable from Julia), so **anything that can
fail — including parses — must use this shape, never `.unwrap()`/`.expect()`/`panic!`** (see
`plans/ffi_panic_safety.md`). Every fallible entry point is additionally wrapped in `guard_error`,
which catches an upstream panic and returns it as a `polars_error_t`; the entry points that return a
handle/`usize`/`bool` or void have no error channel and so cannot be covered — do not expose an
operation that can panic through one of those.

**Marshalling.** `Vec<Expr>` args → `*const *const polars_expr_t` + length under `GC.@preserve`
(convert incoming `String`/`Symbol` to `col(...)` first). Optional scalars → nullable pointers
(`x === nothing ? Ptr{T}(C_NULL) : Ref(T(x))`). Rust enums need a hand-written `#[repr(C)] pub enum`
mirror plus match-based conversion, passed **by value**. Strings → `(ptr, len)` pairs, i.e.
`(s, ncodeunits(s))` — **always `ncodeunits`, never `length`**, a *character* count that cuts
non-ASCII args mid-codepoint and surfaces as `incomplete utf-8 byte sequence`; this was wrong at all
24 sites once, and ASCII-only tests never catch it. Optional strings: null ptr or len 0 = `None`.
Lists of column names go through `_name_ptrs` (`src/verbs.jl`), which returns `(owned, ptrs, lens)`
— **`GC.@preserve` the returned `owned`, never the argument you passed in**: for anything but a
`Vector{String}` (a `Vector{Symbol}`, say) `owned` is a freshly converted copy that nothing else
roots, and the `Ref` allocation every call site makes before its ccall is a live GC safepoint.

**Generation pipeline — never hand-edit either end.** Rust → (cbindgen) `c-polars/include/polars.h`
→ (Clang.jl) `src/api/generated.jl`. Regenerate with `c-polars/regen_header.sh`, then
`julia --project=gen gen/generate.jl`, then `runic -i src/api/generated.jl`; if output looks wrong,
fix the Rust or `gen/generator.toml`. A symbol missing
from Rust is silently invisible to Julia, not a build error — `python3 c-polars/check_header_drift.py`
is the fast pre-check, and `--lib PATH` verifies a built library exports what the header declares
(the `artifact` CI job does this, since the `Artifacts.toml` binary is versioned separately: **any
`c-polars/` change is invisible to users until a new libpolars release is cut**).

## Build environment

**Cargo features are a live crash hazard.** With a feature off, many polars functions compile to
`panic!("activate 'X' feature")` — or worse, fall through a `#[cfg]`-gated match to `unreachable!()`
with no greppable string — aborting the whole Julia process uncatchably. Before wrapping something
new, grep `"activate .* feature"` under
`~/.cargo/registry/src/*/polars-*-<version>/src/` and check per-crate reality with
`cargo tree -e features -i <crate>`: a feature on the `polars` facade is not that feature on each
sub-crate (`dtype-time` reached everything *except* polars-ops; `sink_csv` gzip crashed because
`polars` disables `polars-io`'s default `decompress`). **A clean `cargo build` is never evidence a
path is safe — exercise every option combination live.**

- **`cargo build -j 4`** normally; **`-j 1` for any full dependency rebuild** (fresh clone,
  `Cargo.toml`/`Cargo.lock` change) — deps build at opt-level 3 even in the dev profile, and a 16- or
  even 4-way optimized rebuild OOM-kills this machine, taking the VS Code host down with it.
- **Stable toolchain only** (`c-polars/rust-toolchain`): `polars-ops`' `build.rs` sniffs for nightly
  rustc *by version string* and opts into unstable stdlib internals that break without warning —
  invisible to `cargo tree -e features`. `regen_header.sh` therefore sets `RUSTC_BOOTSTRAP=1` on
  stable to unlock `-Zunpretty=expanded` (cbindgen can't see the ~48% of the FFI surface that's
  macro-generated); **do not "fix" that with `cargo +nightly`** — it re-arms the hazard.
- **A running Julia session doesn't pick up a rebuild** — the `.so` is already mapped. Restart the
  REPL (Kaimon `manage_repl` `command="restart"`) after every `cargo build`.
- Tests: `test/Project.toml` carries all deps, so `Pkg.test()` / `julia-runtest` works directly.

## Workflow: adding a wrapped operation

1. Check the existing wrapped types suffice (usually yes — don't build new plumbing) and the Cargo
   feature is enabled; then write the Rust `extern "C"` fn in the right `c-polars/src/*.rs` and
   regenerate the header and bindings.
2. Write the Julia entry point in the category-matching file; export it (or from the
   `Lists`/`Strings`/`Dt`/`Structs` submodule).
3. Build, restart the REPL, and **exercise it live before writing tests** — this suite has real
   coverage gaps; whole operations have shipped untested.
4. Add tests under the matching `test/<category>/`, reusing `test/fixtures.jl` builders (no committed
   data fixtures — generate parquet/CSV into a `mktempdir()`). Persist any multi-step plan under
   `plans/` with a `## Status` line, set to `Done` once landed.

## Known sharp edges

- **`@generate_expr_fns` qualifies by `isdefined(Base, f)`, not `isexported`** — colliding with an
  unexported Base name (e.g. `product`) makes the wrapper unreachable via `UndefVarError`; hand-write
  it under the exported name (`prod`), as `std`/`var`/`quantile`/`rank` already are. It also passes
  args in source order, so an op whose polars arg order differs from its Base binding must be
  hand-written — `log` silently computed the reverse of `log(base, x)`.
- **A package extension hook must be a zero-method stub** (`ext/Polars*Ext.jl`) — Julia forbids an
  extension from *redefining* a method during precompilation, only adding one. Pattern in
  `src/arrow/schema.jl`: the public function holds the logic and catches `MethodError` from a second,
  empty function (`function _resolve_tz_aware_datetime_type end`) the extension supplies the first
  method for. Everything not needing the optional type ships unconditionally.
- **No `hive_partitioning` for CSV scans** — upstream `LazyCsvReader` hardcodes it disabled.
- **`allow_missing_columns` covers missing columns only, not extra ones** (that's a separate
  `ExtraColumnsPolicy` we don't expose). The reference schema is whichever file is scanned first.
- **No handle is thread-safe** — they're unsynchronized pointer wrappers; the `LIVE_*_LOCK`s only
  guard Arrow release-callback bookkeeping. See "Concurrency" in `docs/src/limitations.md`.
