# Julia UDFs in Polars.jl — implementation plan (C callback approach)

Status: revision 2 (review findings folded in; see §7).

## 0. Goal and scope

Let users run Julia functions inside a polars query:

| Julia API | Upstream Rust | Semantics |
|---|---|---|
| `map(f, e::Expr, more::Expr...; return_dtype=nothing)` | `Expr::map` / `Expr::map_many` | Elementwise (`FunctionOptions::elementwise()`, **without** `OPTIONAL_RE_ENTRANT`, see §1.4). `f` receives one `Series` per input and may be called on a chunk/morsel of the column. |
| `apply(f, e::Expr, more::Expr...; return_dtype=nothing)` | `Expr::apply` / `Expr::apply_many` | Groupwise (`FunctionOptions::groupwise()`): `f` sees the whole column in `select`, one call per group in `agg`. |
| `map(f, lf::LazyFrame; schema=nothing, predicate_pushdown=false, projection_pushdown=false, streamable=false)` | `LazyFrame::map` | `f(::DataFrame)::DataFrame`. Whole materialized frame by default; with `streamable=true` the streaming engine calls `f` per morsel, concurrently; with `projection_pushdown=true` `f` may see a projected input. |
| `map(f, df::DataFrame; ...)` | — | `collect ∘ map ∘ lazy`, per the eager convention. |

Out of scope for v1 (follow-ups): `map_elements` (pure-Julia per-element helper on top of `map`),
aggregation UDFs (`FunctionOptions::aggregation()` / `returns_scalar`), `return_dtype` for dtypes
`polars_value_type_t` cannot encode (List/Struct/Datetime-with-unit/Decimal), plan serialization.

Naming (open question for the user, see §7): `map` extends `Base.map` on our own types (no piracy; `Expr`/`LazyFrame` are not iterable,
so no existing behavior changes). `apply` is a new top-level export; `Lists.apply` is unexported and
unaffected. Docstrings take upstream Rust wording (CLAUDE.md), with `Note:` paragraphs for the
Julia-specific parts (thread safety, return types accepted).

## 1. Threading / GC model (the core decision)

Facts established (Julia 1.10 source, `release-1.10` branch):
- `src/jlapi.c` exports `int8_t jl_gc_safe_enter(void)` and `void jl_gc_safe_leave(int8_t)`.
- `gen_cfun_wrapper` (`codegen.cpp`) + `llvm-ptls.cpp`: a `@cfunction` entry adopts an unknown
  thread (`jl_adopt_thread`) and switches the thread to GC-unsafe, restoring the previous state on
  exit. It also sets the world age to the latest world, so `f` defined after the `Expr` is visible.

Design:
1. polars calls the Julia trampoline **directly on whatever thread it runs the UDF** (rayon pool,
   streaming executor threads, or the calling thread). No queue, no marshalling back to one task.
2. The one Julia call that *executes* a plan, `polars_lazy_frame_collect`, runs in a
   **GC-safe region**, so a GC triggered by Julia code on a polars thread can proceed while the
   calling thread is blocked in Rust. Without this: deadlock (GC waits for the calling thread,
   which waits for the UDF, which waits for GC).
   - Julia ≥ 1.12: `@ccall gc_safe=true ...`.
   - Julia 1.10/1.11: `st = @ccall jl_gc_safe_enter()::Int8; ret = ccall(...); @ccall jl_gc_safe_leave(st::Int8)::Cvoid`.
   - Arguments must be `cconvert`ed (and `GC.@preserve`d) **before** entering the safe region; only
     `unsafe_convert` + the raw ccall run inside it (same shape as GPUToolbox.jl's
     `@gcsafe_ccall`). No allocation, no dispatch, no Julia exceptions inside the region; the Rust
     side never unwinds (all these entry points are already `guard_error`-wrapped).
   - Applied **unconditionally** (not only when the plan has a UDF): the cost is two cheap calls,
     and it also stops a long `collect` from blocking GC on other Julia threads today.
3. Plan-inspection paths that only run the output-type function (`collect_schema`, `explain`,
   `show(::LazyFrame)`) never call into Julia (the output-type closure is pure Rust), so they stay
   on the generated wrappers.

Audit (done in review): `polars_lazy_frame_collect` (`dataframe.rs:858`) is the only entry point
that runs a plan. The `polars_lazy_frame_sink_*` functions only build a sink plan
(`lf.sink(...)`, e.g. `io.rs:461`); Julia then runs it through `collect(...; engine=:streaming)`
(`src/io/parquet.jl:265` and siblings). Re-check when adding new entry points.

4. **No `OPTIONAL_RE_ENTRANT`.** With that flag the streaming engine runs the UDF via
   `ASYNC.spawn_blocking` (polars-stream `to_graph.rs`, `expression.rs`) on tokio's blocking pool
   (up to 512 threads, idle threads exit). Julia 1.10 never reuses a thread-table slot
   (`threading.c` `jl_init_threadtls`: `tid = jl_n_threads`), so every new blocking thread would
   permanently grow the thread table. Without the flag, UDFs run on the fixed-size rayon/executor
   pools. Nested queries inside `f` are unsupported anyway (§4 limitations).
5. Adopted threads: `Threads.threadid()` inside `f` can exceed `Threads.nthreads()`; document it.
6. Pre-existing issue this also fixes: the Arrow release callbacks (`src/arrow/`) already enter
   Julia from polars threads while the caller sits in a GC-unsafe `collect`. Mention it in the
   commit message.

## 2. Rust side (`c-polars/src/udf.rs`, new module; registered in `lib.rs`)

### 2.1 Callback types (appear in `polars.h` via cbindgen)

```rust
/// Called by polars to run a Julia UDF on `n` input series. Writes a new, owned series to `out`
/// and returns null, or returns an owned error.
pub type polars_udf_series_call_t = unsafe extern "C" fn(
    ctx: *const c_void,
    inputs: *const *mut polars_series_t, // n owned handles; callee takes ownership
    n: usize,
    out: *mut *mut polars_series_t,
) -> *const polars_error_t;

pub type polars_udf_frame_call_t = unsafe extern "C" fn(
    ctx: *const c_void,
    input: *mut polars_dataframe_t,      // owned; callee takes ownership
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t;

```
There is **no release callback**: no Julia code runs when polars drops a UDF (drops happen in
finalizers, on tokio threads, and during Rust teardown after Julia's `atexit`). Julia instead holds
a Rust handle to the shared wrapper and polls whether polars still references it (§2.2).

Ownership convention: Rust hands Julia freshly boxed handles (`make_series` / `make_dataframe`),
Julia wraps them in `Series`/`DataFrame` with finalizers. Julia returns an owned handle created with
a new `polars_series_clone` / `polars_dataframe_clone` (so Rust never reads a handle whose Julia
owner may be finalized concurrently on another thread).

### 2.2 The shared wrapper

```rust
struct JuliaUdf { ctx: *const c_void }
unsafe impl Send for JuliaUdf {}
unsafe impl Sync for JuliaUdf {}

/// Julia's reference to a UDF: an `Arc` clone of the one captured by the polars closure.
pub struct polars_udf_t { inner: Arc<JuliaUdf> }   // `impl Opaque`, destroyed by polars_udf_destroy
```
The polars closure(s) capture an `Arc<JuliaUdf>`; the constructor also returns a `polars_udf_t`
holding another clone. `polars_udf_is_shared(h) -> bool` (`Arc::strong_count > 1`, infallible)
tells Julia whether any plan still references the UDF.

### 2.3 New entry points

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_expr_map_julia(
    exprs: *const *const polars_expr_t, n: usize,   // n >= 1; first is `self`, rest are arguments
    ctx: *const c_void,
    call: polars_udf_series_call_t,
    groupwise: bool,                                // false: map/map_many, true: apply/apply_many
    return_dtype: polars_value_type_t,
    has_return_dtype: bool,                          // false: output dtype = first input's dtype
    out: *mut *mut polars_expr_t,
    out_udf: *mut *mut polars_udf_t,
) -> *const polars_error_t

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_map_julia(
    lf: *const polars_lazy_frame_t,
    ctx: *const c_void,
    call: polars_udf_frame_call_t,
    schema_names: *const *const u8, schema_name_lens: *const usize,
    schema_types: *const polars_value_type_t, schema_n: usize,
    has_schema: bool,                                // false: output schema = input schema
    predicate_pushdown: bool, projection_pushdown: bool, streamable: bool,
    out: *mut *mut polars_lazy_frame_t,
    out_udf: *mut *mut polars_udf_t,
) -> *const polars_error_t

#[no_mangle] pub unsafe extern "C" fn polars_udf_is_shared(h: *const polars_udf_t) -> bool
#[no_mangle] pub unsafe extern "C" fn polars_udf_destroy(h: *mut polars_udf_t)
#[no_mangle] pub unsafe extern "C" fn polars_series_clone(s: *const polars_series_t) -> *mut polars_series_t
#[no_mangle] pub unsafe extern "C" fn polars_dataframe_clone(df: *const polars_dataframe_t) -> *mut polars_dataframe_t
#[no_mangle] pub unsafe extern "C" fn polars_error_new(msg: *const u8, len: usize) -> *const polars_error_t
```
- All fallible ones wrapped in `guard_error`. `polars_error_new` returns `*const polars_error_t`,
  so it is wrapped too (the signature decides). Add `udf.rs` to `check_panic_guards.py`'s
  hardcoded `FILES` list (or switch it to a glob, as `check_header_drift.py` does).
- `polars_error_new` uses `String::from_utf8_lossy`. The clones are `Arc` bumps and cannot panic;
  handle-returning signatures are fine for them.
- On an error return `out_udf` is left null; Julia then drops its registry entry immediately.
- Use `Opaque::into_handle` / the existing destroy helpers (`types.rs`), not raw `Box::from_raw`.
- `return_dtype` decode: `polars_value_type_t::to_dtype` (already fallible for unencodable types) →
  error if `has_return_dtype` and it fails.

### 2.4 Closure bodies

Expr UDF (built like upstream `map_with_fmt_str`/`map_many` but constructing
`Expr::AnonymousFunction { input, function: new_column_udf(BaseColumnUdf::new(f, dt)), options,
fmt_str: "julia_udf" }` directly so the options can be chosen):

```text
f(cols: &mut [Column]) -> PolarsResult<Column>:
  name  = cols[0].name().clone()
  ptrs  = cols.iter().map(|c| make_series(c.as_materialized_series().clone())).collect::<Vec<_>>()
  let mut res = null
  err = (call)(udf.ctx, ptrs.as_ptr(), ptrs.len(), &mut res)
  // ownership of ptrs has passed to Julia regardless of outcome
  if !err.is_null() { msg = take message; polars_error_destroy(err); return Err(ComputeError(msg)) }
  if res.is_null()  { return Err(ComputeError("Julia UDF returned no series")) }
  s = *Box::from_raw(res)  → Series
  expected = return_dtype or cols[0].dtype()   // always checked, declared or not
  if s.dtype() != expected: Err(SchemaMismatch("Julia UDF returned {}, expected {}; pass return_dtype"))
  Ok(s.with_name(name).into_column())

dt(_schema, fields) -> PolarsResult<Field>:
  Field::new(fields[0].name().clone(), return_dtype.unwrap_or(fields[0].dtype().clone()))
```
- The output-type closure never calls Julia (it runs during planning, possibly from
  `collect_schema` outside a GC-safe region).
- Renaming to the first input's name keeps the declared field name and the actual column name in
  agreement.
- The check is unconditional because polars trusts the resolved dtype: in a groupwise `apply` it
  builds list results with `collect_ca_with_dtype(dtype.implode())` (polars-expr `apply.rs`), so an
  unexpected dtype would fail inside rayon.
- Length validation for the elementwise case is polars' own `check_lengths` (on by default).
- No `catch_unwind` needed around `call`: the Julia trampoline never unwinds (see §3.3). A panic in
  our own closure code is already turned into an error by upstream/`guard_error` at the boundary
  where the query was started.

LazyFrame UDF: `lf.clone().map(move |df| ..., optimizations, schema, Some("julia_udf"))`, same
error/ownership handling, `schema` = `None` (input schema) or a fixed `Arc<dyn UdfSchema>` built from
the `(name, dtype)` list. Check the returned frame's schema against the declared one, or, when
none is declared, against the **runtime** input frame's schema captured in the closure (with
projection pushdown or streaming morsels this differs from the plan-time schema); error on
mismatch. Verify the exact
`AllowedOptimizations` (`OptFlags`) constructor names against polars-lazy 0.55.2 at implementation
time.

### 2.5 Rust unit tests (`tests.rs`)

Drive the full Rust path with a Rust `extern "C" fn` standing in for Julia:
- identity/transform callback over `collect` on in-memory and streaming engines;
- callback returning an error → `collect` error carries the message;
- callback returning null → error, no crash;
- declared dtype mismatch → `SchemaMismatch` error;
- `polars_udf_is_shared` true while an `Expr`/`LazyFrame` (or a clone) references the UDF, false
  once all are dropped; `out_udf` null when construction fails (bad `return_dtype`);
- `apply` in `group_by().agg()` calls the callback once per group.

## 3. Julia side (`src/udf.jl`, included after `expr/expr.jl` and `lazyframe.jl`)

### 3.1 Handle and registry

```julia
mutable struct _UDF
    f::Any
    handle::Ptr{polars_udf_t}   # set after construction; C_NULL until then
end

const LIVE_UDFS = IdDict{_UDF, Nothing}()   # roots every UDF Rust may still call
const LIVE_UDFS_LOCK = ReentrantLock()
```
- `ctx = pointer_from_objref(udf)`; the trampoline recovers it with `unsafe_pointer_to_objref(ctx)`
  — lock-free, no allocation on the hot path.
- Sweep under `LIVE_UDFS_LOCK`, from normal code only (at every registration and before every
  `collect`): for each entry, if `!polars_udf_is_shared(handle)`, call `polars_udf_destroy` and
  delete it. Nothing runs on the Rust drop path, so finalizers and foreign threads never touch
  this registry.

### 3.2 Callback pointers

Follow `_io_callback()` (`src/Polars.jl:31`): a function returning `@cfunction(...)`, evaluated at
call time (the package has no `__init__`): `_udf_series_call()`, `_udf_frame_call()`.

### 3.3 Trampoline (series flavor; frame flavor is analogous)

```julia
function _udf_series_trampoline(ctx::Ptr{Cvoid}, inputs::Ptr{Ptr{polars_series_t}}, n::Csize_t,
                                out::Ptr{Ptr{polars_series_t}})::Ptr{polars_error_t}
    try
        udf = unsafe_pointer_to_objref(ctx)::_UDF
        args = [Series(unsafe_load(inputs, i)) for i in 1:n]    # takes ownership
        res = _as_series(udf.f(args...), args[1])               # Series, or AbstractVector → Series
        GC.@preserve res unsafe_store!(out, API.polars_series_clone(res))
        return Ptr{polars_error_t}(C_NULL)
    catch e
        return _udf_error(e, catch_backtrace())
    end
end
```
- Everything is inside `try`: an exception escaping a `@cfunction` into Rust is UB / an abort.
  Includes `InterruptException`, `StackOverflowError`, errors in `Series(ptr)`.
- Ownership edge: if `Series(ptr)` throws for input *k*, inputs *k+1..n* are never wrapped → leak.
  Wrap all handles first in a loop that destroys the remaining raw pointers on failure
  (`Series(ptr)` already destroys its own on failure).
- `_as_series`: `Series` passes through; `AbstractVector` → `Series(name(input1), v)`; anything
  else → `ArgumentError`.
- **Arrow release lock.** `Series(name, v)` is a zero-copy Arrow import whose release callback
  (`release_array!`, `src/arrow/array.jl:160`) takes `LIVE_ARRAYS_LOCK`, a `ReentrantLock`. UDFs
  produce many concurrent releases from adopted threads and finalizers; a contended `lock` inside
  a finalizer throws ("task switch not allowed from inside gc finalizer") and would escape a
  `@cfunction` into Rust. Prerequisite change: move `LIVE_ARRAYS`/`LIVE_SCHEMAS` to the same
  scheme (release sets an atomic flag, sweep deferred to normal code) or guard them with a
  `Threads.SpinLock` over a non-allocating critical section. Land this before the UDF work.
- Frame flavor: `DataFrame(ptr)` in; `f` may return a `DataFrame` or any Tables.jl table
  (`DataFrame(table)`); out via `polars_dataframe_clone`.

### 3.4 Preserving the user's exception

`_udf_error(e, bt)`:
- stores `(e, bt)` in `UDF_ERRORS::Dict{Int, Tuple{Any, Any}}` keyed by an atomic counter `id`,
  under a `Threads.SpinLock` (a contended `ReentrantLock` would yield, letting the adopted thread's
  scheduler run unrelated tasks while a polars worker stalls);
- returns `polars_error_new("\0julia-udf-error:$id\0 " * sprint(showerror, e))` — the NUL-delimited
  marker cannot come from a normal exception message.

`polars_error` (in `src/Polars.jl`) checks the message for the marker; if found and
the id is still in `UDF_ERRORS`, pops it and throws `UDFError(e, bt, message)` (new exported
exception type, `showerror` prints the original exception with its backtrace, then the polars
context). polars may wrap the message with context, so match anywhere in it. Bound `UDF_ERRORS`
(drop the oldest beyond ~64 entries): polars can swallow some errors (e.g. only the first failing
morsel is reported), so unclaimed entries must not accumulate.

### 3.5 Public functions

```julia
function Base.map(f, e::Expr, more::Expr...; return_dtype = nothing)  # also accepts col names via _as_expr
function apply(f, e::Expr, more::Expr...; return_dtype = nothing)
function Base.map(f, lf::LazyFrame; schema = nothing, predicate_pushdown = false,
                  projection_pushdown = false, streamable = false)
Base.map(f, df::DataFrame; kw...) = collect(map(f, lazy(df); kw...))
```
- `return_dtype`: Julia type → `_plain_value_type_code` (existing); unsupported types error in
  Julia before any Rust call. `schema`: `Pair`s or a `NamedTuple` of name ⇒ Julia type.
- Registration order: create `_UDF`, insert into `LIVE_UDFS`, then call Rust (which, per §2.3, now
  owns the release obligation on every path).
- Check `map(f, ::Expr)` does not collide with anything reachable via broadcasting on `Expr`
  (e.g. `f.(col("x"))` must keep its current meaning, if any).

### 3.6 GC-safe query calls (`src/api/gcsafe.jl`)

- Macro `@gcsafe_ccall` implementing §1.2 (version-switched).
- One hand-written `_gcsafe_polars_lazy_frame_collect` with the same signature as the generated
  wrapper; `Base.collect(::LazyFrame)` (`src/lazyframe.jl`) calls it. Sinks already go through
  `collect`.
- Drift guard: a test that parses `src/api/generated.jl` for `polars_lazy_frame_collect` and
  asserts the hand-written argument/return types match (generated.jl stays generator-owned).

## 4. Tests (Julia) — `test/expr/udf.jl`, `test/lazyframe/udf.jl`, add to `runtests.jl`

Behavior:
- `map` elementwise: `x .* 2` via `map(s -> read_series(s) .* 2, col("x"))`, both engines, eager
  and lazy; multi-input `map(+, col("a"), col("b"))` style; returning a `Vector` vs a `Series`.
- `apply` in `select` sees the whole column (e.g. `s .- mean(s)`); in `group_by().agg()` one call
  per group (count calls with an `Atomic`).
- `return_dtype`: declared Float64 honored in `collect_schema`; mismatch → error.
- `map(f, ::LazyFrame)` with and without `schema`; schema mismatch → error; eager form.
- Output keeps the input column's name; `alias` after `map` works.

Failure modes (the reason this design exists):
- `f` throws → `UDFError` carrying the original exception type and backtrace; the process survives;
  a second query afterwards works.
- `f` calls `GC.gc()` and allocates heavily, on the streaming engine with many morsels
  (`POLARS_MAX_THREADS` > 1) → completes (the deadlock regression test). Run with a timeout wrapper.
- `f` runs on the calling thread (small frame, in-memory engine) → no hang.
- `f` does task-switching work (`println`, `lock`, `sleep(0)`) on a polars thread → completes.
- Closure lifetime: create `Expr`, drop Julia refs to `f`, `GC.gc()`, then `collect` → works;
  after dropping the `Expr` and `GC.gc()` twice + a new registration, `LIVE_UDFS` is empty.
- Construction error (bad `return_dtype`) → no `LIVE_UDFS` leak.
- UTF-8 exception messages round-trip.
- `apply` on an empty frame: polars calls `f` once with a zero-length, all-null input to infer the
  dtype (polars-expr `apply.rs`) — test and document.
- A non-trivial `f` whose first call compiles on a polars thread (~2 MiB Rust stack): no stack
  overflow.
- `f` yields while `Threads.@spawn` tasks are runnable → completes, no stalled workers.
- A `select` with two UDF expressions (run in parallel).
- Interaction with `test/dataframe/gc.jl` assertions (`LIVE_ARRAYS` empty) — UDF tests must not
  leave Arrow exports rooted.

Docs build: new `docs/src/reference/udf.md` (or sections in expressions/lazyframe pages) with
`@docs` for `map`, `apply`, `UDFError`; `limitations.md` gains, stated once:
- `f` may run concurrently on several threads and must be thread-safe;
- plans containing a Julia UDF cannot be serialized;
- `return_dtype`/`schema` limited to the dtypes `polars_value_type_t` encodes;
- per-call overhead (a handle round-trip per chunk/group) — prefer native expressions;
- do not run a polars query from inside `f` (nested execution on the polars pool; see §6).

## 5. Delivery

0. Prerequisite PR: GC-safe `collect` + the `LIVE_ARRAYS` release-lock change (§3.3). Both fix
   pre-existing hazards and are useful without UDFs.
1. Rust: `udf.rs`, clones, `polars_error_new`, `check_panic_guards.py` file list, tests; `cargo fmt`, `cargo test`,
   `check_panic_guards.py`, regenerate header + bindings (`regen_header.sh`, `gen/generate.jl`,
   `runic`), `check_header_drift.py`.
2. Julia: `udf.jl`, exports, docs, tests.
3. Needs a libpolars release before users see it (`Cargo.toml` version bump → Release workflow →
   `Artifacts.toml` PR). Until then the Julia code must fail clearly if the loaded library lacks
   `polars_expr_map_julia` (`dlsym` check at first use → "requires libpolars ≥ X").

## 6. Open risks to verify live

- Nested query inside `f` (a `collect` on a polars worker thread): possible pool deadlock or
  re-entrancy issues → test; if it hangs, document as unsupported (§4 limitation).
- Contended `ReentrantLock` on an adopted foreign thread (only on the error path, §3.4).
- Without `OPTIONAL_RE_ENTRANT`, confirm the streaming engine still runs `map` UDFs in parallel on
  its executor threads (and does not fall back to a single thread or the in-memory engine).
- Streaming engine + `apply` (groupwise): confirm it falls back correctly rather than splitting.

## 7. Review log (revision 2)

Adopted from the review: no `OPTIONAL_RE_ENTRANT` (thread-slot growth on 1.10); no release
callback (Rust handle + `polars_udf_is_shared` sweep); only `collect` executes plans; unconditional
dtype check; runtime-schema check for `LazyFrame` UDFs; `LIVE_ARRAYS` release lock as a
prerequisite; SpinLock for `UDF_ERRORS`; `check_panic_guards.py` file list; `guard_error` on
`polars_error_new`; no `__init__`; NUL-delimited error marker; extra tests.

Open for the user: naming. `map(f, col("x"))` reads as a per-element map in Julia, but `f`
receives a whole `Series`; `map(f, df)` would read as a row map. Option A: Rust names
(`map`/`apply`, extending `Base.map`). Option B: py-polars names (`map_batches`, `map_groups`, and
`map_batches` on `LazyFrame`/`DataFrame`), which avoid the per-element reading and leave room for
a later `map_elements`. Recommendation: B.
