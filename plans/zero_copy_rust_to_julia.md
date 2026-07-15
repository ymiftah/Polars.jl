# Zero-copy / bulk column transfer Rust → Julia (Arrow C Data Interface)

## Status

Done. Branch: `zero-copy-rust-to-julia` (off `scan-parquet`). Full test suite: 705 passed, 3 broken
(pre-existing, unrelated), 0 failed -- 26 new tests added in `test/datatypes/series.jl` covering
numeric (null/no-null), Bool, Date/DateTime, empty series, sliced/offset series, true zero-copy
(including post-GC lifetime), double-release idempotency, and the String/List fallback path.

Implemented exactly as designed below: `polars_series_export_carray` in
[c-polars/src/series.rs](../c-polars/src/series.rs), header + `@ccall` wrapper, and the new
[src/arrow/read.jl](../src/arrow/read.jl) with `ExportedArray`/`release!` and `read_series`. Wired
into `Base.collect(::Series)`/`Base.Vector(::Series)` (bulk-copy default; `zerocopy=true` opt-in via
`read_series` directly, exported). All live-verification steps in the Verification section below
were run against a real build (not just `cargo build` succeeding) and passed, including the
double-release and offset/slice edge cases flagged during design review.

## Context

Data movement across the Polars.jl FFI boundary is currently **asymmetric**:

- **Julia → Rust (write): already zero-copy and complete.** `arrowtable`/`arrowvector`
  ([src/arrow/array.jl](../src/arrow/array.jl)) build Arrow buffers once and hand raw pointers to
  `polars_dataframe_new_from_carrow` → `ffi::import_array_from_c`
  ([c-polars/src/lib.rs:172-200](../c-polars/src/lib.rs#L172-L200)) with a release-callback ownership
  transfer. No per-element copy.
- **Rust → Julia (read): NOT zero-copy.** There is no Arrow *array* export — only schema export
  (`polars_series_schema`, [c-polars/src/series.rs:30-34](../c-polars/src/series.rs#L30-L34)). Reading
  values goes through per-index scalar getters (`polars_series_get_*`,
  [c-polars/src/series.rs:74-105](../c-polars/src/series.rs#L74-L105)), so `collect(::Series)` /
  Tables.jl materialization costs **O(n) ccalls** (plus a boxed alloc per non-primitive value).

This plan adds the missing read direction so `to`/`from` are both zero-copy (or at least bulk,
zero-ccall). It mirrors the write path in reverse: the Rust-side `export_array_to_c` (the exact
counterpart of the already-used `import_array_from_c`) exists in `polars-arrow` but is currently
unused. The one genuinely new piece is **lifetime management in the opposite direction** —
Rust/Arrow-owned buffers must outlive the Julia array wrapping them, handled via a deferred,
idempotent release finalizer (see Memory safety section below).

## Scope (initial)

Three tiers, by type, chosen so each is correct and safe:

| Type category (Arrow `format`) | Path | Copy? |
|---|---|---|
| Fixed-width numeric `c C s S i I l L e f g`, **no nulls** | `unsafe_wrap(own=false)` + lifetime keeper | **true zero-copy** (opt-in) |
| Fixed-width numeric, **with nulls** | bulk read buffer, splice `missing` per validity bit | one Julia-side pass, **0 ccalls** |
| Temporal `tdD`/`ts*`/`tD*`, Bool `b` | bulk read int/bitmap buffer + vectorized transform to `Date`/`DateTime`/`Period`/`Bool` | one pass, **0 ccalls** |
| `String u/U/vu`, `List +l`, `Struct +s`, `Binary z`, dictionary | **fall back to existing per-element `getindex`** | unchanged |

String/List/Struct are deferred: their Arrow layout (offset+bytes / nested children / view encoding)
doesn't map onto a Julia `Vector` without a materialization pass anyway, and correct multi-compat
handling is a larger follow-up. The fallback keeps them working exactly as today.

## Changes

### 1. Rust — export a Series' single Arrow chunk (`c-polars/src/series.rs`)

Add, next to `polars_series_schema` (return-by-value, same style):

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_series_export_carray(series: *mut polars_series_t) -> ArrowArray {
    assert!(!series.is_null());
    let s = (*series).inner.rechunk();            // collapse to 1 chunk (no-op if already 1)
    ffi::export_array_to_c(s.chunks()[0].to_boxed()) // ArrayRef(Arc) -> Box<dyn Array>, Arc-cheap
}
```

- `rechunk()` (polars-core `SeriesTrait::rechunk`/`chunks`/`n_chunks`) guarantees one chunk, so we
  never need the N-chunk `ArrowArrayStream` design.
- `export_array_to_c` takes ownership of a `Box<dyn Array>`; internally `align_to_c_data_interface`
  boxes/leaks the (Arc-backed) buffers and installs the `release` callback that drops them. The
  exported `ArrowArray` is therefore **self-contained** — the original `Series`/rechunked temporary
  can drop; buffers stay alive via the Arc refcount held in the exported array's private data.
- The matching schema is the **existing** `polars_series_schema`; its logical type (via
  `parse_format`) is all the Julia side needs to interpret the physical buffers for the in-scope
  types.

### 2. Header + API wrapper

- `c-polars/include/polars.h`: add `ArrowArray polars_series_export_carray(struct polars_series_t *series);`
  next to the `polars_series_schema` prototype.
- [src/api/series.jl](../src/api/series.jl): add, mirroring the `polars_series_schema` wrapper:
  ```julia
  function polars_series_export_carray(series)
      return @ccall libpolars.polars_series_export_carray(series::Ptr{polars_series_t})::ArrowArray
  end
  ```
  No new opaque type or `@cenum` — reuses the `ArrowArray`/`ArrowSchema` C structs already defined in
  [src/api/types.jl:16-39](../src/api/types.jl#L16-L39).

### 3. Julia — the read consumer (new file `src/arrow/read.jl`, included from `Polars.jl`)

Reuses `parse_format` and the `CArrowArray`/`CArrowSchema` aliases already in `src/arrow/`.

**Lifetime keeper (the new, opposite-direction piece).** Because Rust now owns the memory, wrap the
exported struct so its `release` callback fires exactly once — whether eagerly (copy paths) or on GC
(zero-copy path). Release is made **idempotent** via a flag to prevent a double-free (see Memory
safety section):

```julia
mutable struct ExportedArray
    carray::CArrowArray
    released::Bool
    function ExportedArray(carray)          # construct immediately after export; nothing fallible between
        h = new(carray, false)
        finalizer(release!, h)
        return h
    end
end

function release!(h::ExportedArray)
    h.released && return                     # idempotent: safe under eager-release + finalizer
    h.released = true
    ref = Ref(h.carray)
    @ccall $(h.carray.release)(ref::Ptr{CArrowArray})::Cvoid
    return
end
```

This is the mirror of the write path's `LIVE_ARRAYS` + `base_release_array`
([src/arrow/array.jl:134-173](../src/arrow/array.jl#L134-L173)) and reuses the same
"call the C struct's `release` via a `Ref`" idiom already used to consume Rust-produced schemas in
`load_series_schema` ([src/arrow/schema.jl:140-147](../src/arrow/schema.jl#L140-L147)) — the difference
is the release is **deferred** to GC (zero-copy) or called eagerly (copy paths), always through the
single idempotent `release!`.

**Core reader** `read_series(series::Series)`:
1. `schema = polars_series_schema(series); fmt = unsafe_string(schema.format)`; release schema
   immediately (independent of the array).
2. Branch on `fmt`. For **unsupported** fmts return `nothing` (caller falls back to per-element).
3. `h = ExportedArray(polars_series_export_carray(series))`; `ca = h.carray`.
   `bufs = unsafe_wrap(Array, ca.buffers, ca.n_buffers)` (a `Vector{Ptr{Cvoid}}`), so
   `bufs[1]` = validity (or `C_NULL`), `bufs[2]` = data.
4. **Default (safe): bulk copy.** For numeric/temporal/Bool, allocate a Julia-owned `Vector` and
   copy the buffer in one pass (`unsafe_copyto!` for contiguous numerics; validity-aware splice of
   `missing` when `ca.null_count > 0`, reusing the bit-test logic mirroring `isvalid`/`ValidityMap`,
   [src/arrow/array.jl:45-49](../src/arrow/array.jl#L45-L49); vectorized epoch/bit transform for
   temporal/Bool, the inverse of the write-side encoders at
   [src/arrow/array.jl:233-246](../src/arrow/array.jl#L233-L246)). Then `release!(h)` **eagerly** — the
   data is copied, Rust memory can go. **0 ccalls**, Julia owns the result (safe to mutate). This is
   the default path.
5. **Opt-in: true zero-copy** (numeric, `ca.null_count == 0`, caller explicitly requests it):
   ```julia
   T = <physical type from fmt>
   data = Ptr{T}(bufs[2]) + ca.offset * sizeof(T)          # honor offset; assert in-bounds
   arr = unsafe_wrap(Array, data, ca.length; own = false)  # own=false is mandatory (Rust owns)
   finalizer(_ -> (h; nothing), arr)   # closure keeps h alive until arr is GC'd → then release! runs
   return arr
   ```
   The finalizer closure captures `h`, so the Rust buffers live exactly as long as `arr` is
   reachable; when `arr` dies, `h` dies, `h`'s finalizer calls `release!`. **The result aliases
   Rust-owned memory and must be treated as read-only** (see Memory safety section) — this is why it
   is opt-in, not the default.

### 4. Wire into materialization (minimal, non-breaking)

Keep `Tables.getcolumn`/`Base.getindex` returning the lazy `Series` (broad callers rely on it), but
route bulk materialization through the new path:

- `Base.collect(s::Series)` and `Base.Vector(s::Series)` → `read_series(s)` in **bulk-copy** mode
  (safe, Julia-owned result), falling back to the current `AbstractVector` default (per-element
  `getindex`) when `read_series` returns `nothing` (unsupported type). The true zero-copy path is a
  separate opt-in entry point (e.g. `read_series(s; zerocopy=true)` / a documented function), never
  the `collect`/`Vector` default — because its result aliases Rust memory.
- Optionally a `DataFrame` convenience (`Base.collect(df)` / `columntable`) that maps the bulk reader
  over `df[name]` for each column — biggest end-user win for pulling a whole frame into native Julia.

Per-element `getindex` in [src/series.jl](../src/series.jl) stays as-is (scalar access + fallback).

## Memory safety & GC (explicit)

Reviewed hazards and how the design handles each:

- **Double-release (would be a double-free):** eager release in the copy paths *and* the finalizer
  both call release. Neutralized by the `released` flag making `release!` idempotent — release runs
  exactly once regardless of path.
- **`own = false` is mandatory:** the zero-copy `unsafe_wrap` must not own the buffer; with
  `own = true` Julia's GC would `free()` Rust-allocated memory (heap corruption / double-free vs. the
  release callback). Asserted, not optional.
- **Aliased mutation of the source Series:** the zero-copy `Vector` aliases the Arrow buffer, which
  (since `rechunk` is a no-op that Arc-shares an already-single chunk) can be the *live* Series' own
  data. A `Vector` is mutable, so writing to it would corrupt polars. Handled by making zero-copy
  **opt-in + documented read-only**; the default `collect`/`Vector` path copies and is freely mutable.
- **Leak window:** the exported `ArrowArray` is owned by the caller the moment Rust returns it; wrap
  it in `ExportedArray` (which registers the release finalizer) as the very next step with nothing
  fallible in between, mirroring the write path's documented "must not fail" region
  ([src/arrow/array.jl:332-336](../src/arrow/array.jl#L332-L336)).
- **GC ownership conflict — none:** with `own=false`, the only Julia-managed object is the small
  `ExportedArray` keeper; Julia's GC never touches the Rust buffers, so there is no competing
  ownership. Rust frees them exactly once via the release callback.
- **Running release from a finalizer thread — safe:** the release callback is pure Rust
  deallocation; it does not call back into Julia, allocate, or touch the runtime (unlike a UDF
  callback would), and Arc refcounting is atomic. Safe to run at a GC safepoint on any thread.
- **offset / bounds:** honor `ca.offset` and assert `offset + length` fits the buffer (normally
  `offset == 0` post-`rechunk`, but Arrow permits a sliced chunk).

## Verification (end-to-end, per CLAUDE.md workflow step 7)

Build stable, then **restart the Kaimon REPL** (the `.so` is mmapped; a rebuild is invisible to a
live session) before testing:

```
cd c-polars && cargo build      # stable toolchain (rust-toolchain pinned)
```

Then in a fresh session:
1. **Correctness vs. old path**: for `Int64`/`Float64`/`Int32` columns (with and without `missing`),
   assert `collect(df[:x]) == [df[:x][i] for i in 1:length(df[:x])]` (bulk vs. per-element agree).
2. **True zero-copy proof**: for a no-null numeric column, confirm the returned `Vector`'s
   `pointer(arr)` lies inside the exported buffer (not a fresh Julia alloc), and that mutating polars
   isn't possible (immutable) — i.e. it aliases Rust memory.
3. **Lifetime/GC safety**: drop the `Series`/`DataFrame`, `GC.gc()` several times while holding only
   the wrapped `arr`, read all elements — must not crash or corrupt (proves the keeper holds the
   buffer). Then drop `arr`, `GC.gc()` — release runs without error.
   - **Double-release**: exercise a copy-path column (with nulls) — it eager-releases; then force
     GC so the finalizer also fires. Must not crash (proves `release!` idempotency). A loop of
     thousands of `collect`s + `GC.gc()` should show no growth/crash (no leak, no double-free).
4. **Temporal + Bool**: round-trip a `Date`/`DateTime`/`Bool` column, compare to per-element.
5. **Fallback**: a `String`/`List`/`Struct` column still materializes correctly (via per-element).
6. Add tests under `test/dataframe/` (or `test/series/`) using `write_temp_parquet`/fixtures per
   CLAUDE.md step 8; include the null, temporal, and fallback cases.

## Out of scope (follow-ups)

- Zero-copy / bulk **String, List, Struct, Binary** reads (needs compat-level-aware offset/view and
  nested-child handling).
- Multi-chunk streaming export without `rechunk` (only needed if `rechunk`'s copy cost matters).
