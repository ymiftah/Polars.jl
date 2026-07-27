# Arrow C Data Interface conformance audit + fixes

## Status

Done. Three confirmed memory-safety defects fixed (D1-D3), four lower-severity conformance gaps
closed (D4-D7), 32 new tests added, full suite passes: 1826 passed, 0 errored, 2 broken
(pre-existing, unrelated), 1 failed (pre-existing, unrelated -- see "Pre-existing unrelated
failure" below). All three reproductions were confirmed live before and after the fix.

## Context

A review question was raised about `src/arrow/array.jl`: that `release_array!` violates the Arrow
C Data Interface by releasing children, which the spec forbids consumers from doing. That specific
concern turned out to be a false alarm -- `base_release_array` is the **producer**-side callback
(for arrays Julia builds and hands to polars), and the spec's producer contract is the opposite of
its consumer contract: producers MUST walk children and call their own release callbacks; it's
*consumers* who must not. The consumer-side paths in this codebase (`ExportedArray.release!`,
`load_series_schema`/`load_dataframe_schema`, `_read_list`) were already correctly base-structure-only.

Auditing the rest of the C Data Interface implementation against the spec
(https://arrow.apache.org/docs/format/CDataInterface.html) turned up real issues instead, found by
reading the code and then reproducing each one live in a Julia session (not inferred from reading
alone):

- **D1 (critical): use-after-free on `read_series(...; zerocopy=true)`.** `_dispatch_read`
  unconditionally released the exported buffers right after building the result, including when
  the result was a zero-copy alias of those very buffers. Reproduced: read a 5-element `Int64`
  series with `zerocopy=true`, drop the source `Series`, force-GC, churn the heap -- the borrowed
  array read back corrupted values.
- **D2 (high): `arrowtable` permanently leaked `LIVE_ARRAYS`/`LIVE_SCHEMAS` on partial
  construction failure.** Every nesting level rooted itself independently, so a throw partway
  through column construction (out-of-range `DateTime`, unsupported dtype, ...) stranded
  already-built entries with nothing left to ever release them. Reproduced: 5 failed
  `DataFrame` constructions left 5 `LIVE_ARRAYS` + 15 `LIVE_SCHEMAS` entries, surviving
  `GC.gc(true)`.
- **D3: release callbacks never set `release = NULL`,** the one MUST the spec gives any consumer
  to detect a released structure.
- **D4 (low): contradictory ownership comment** on `DataFrame(table)`'s failure path (harmless in
  practice, since `release_array!` was already idempotent).
- **D5 (low, unreachable today): `ArrowSchema`'s `metadata` keyword was marshalled as a
  NUL-terminated C string** instead of the spec's length-prefixed binary encoding. No call site
  ever passed a real value, so latent rather than live, but the keyword looked public.
- **D6 (low): no consumer site checked for a NULL release callback** before invoking it (spec:
  consumers SHOULD check). A double release would have been a segfault, not a catchable error.
- **D7 (doc gap): `DataFrame(table)` silently aliases the caller's `Vector`** for fixed-width
  numeric columns (confirmed live), undocumented.

Two spec items were explicitly checked and found already compliant, so were left alone: `flags = 0`
(the spec does not mandate `ARROW_FLAG_NULLABLE`) and buffer alignment (recommended, not required).

## Changes made

1. **Rooting model simplified to top-level-only** (`src/arrow/array.jl`, `src/arrow/schema.jl`).
   `set_private_data!` now only installs the release callback + `private_data` (every nesting
   level still needs this, since a parent's release callback invokes its children's callbacks
   directly); a new `root!` registers an object in `LIVE_ARRAYS`/`LIVE_SCHEMAS` and is called only
   on the two top-level objects, in `arrowtable`, once construction fully succeeds. Children are
   kept alive transitively through their parent's `children` field, so they were never rooted.
   `release_array!`/`release_schema!` lost their recursion entirely (previously needed because
   every level rooted itself independently -- the reason for the depth-≥2 bug fixed before this
   plan).

   **This one change fixed D2 as a side effect, more simply than originally planned.** The
   original plan called for explicit try/catch cleanup around partially-built columns in
   `arrowtable`. Once rooting is deferred to a single `root!` call after full success, that
   cleanup became unnecessary: nothing is ever registered in `LIVE_ARRAYS`/`LIVE_SCHEMAS` until
   construction has already succeeded, so a throw at any point simply leaves ordinary unreferenced
   Julia garbage. Adding the originally-planned try/catch on top would have been dead defensive
   code for a scenario the new design makes structurally impossible.

2. **D3 + producer children-walk**: `base_release_array`/`base_release_schema` now walk
   `array.children`/`schema.children`, invoking each child's own release callback (a `C_NULL`
   guard skips already-released ones), then mark both the incoming pointer and the object's own
   `carrow_array`/`carrow_schema` copy released via a new shared `_mark_released!` helper. Full
   recursive release through arbitrarily deep trees falls out for free: every object built by this
   package shares the same callback, so invoking a child's callback naturally walks *its* children
   in turn.

3. **D1 fix** (`src/arrow/read.jl`): added `ExportedArray.borrowed::Bool`, set by `_read_numeric`'s
   zero-copy branch; `_dispatch_read` now gates the eager release on `h.borrowed`.

   **A second, more subtle bug surfaced while fixing this and required its own fix.** The
   zero-copy branch's existing keepalive mechanism --
   `finalizer(_ -> (keepalive; nothing), arr)`, matching `plans/zero_copy_rust_to_julia.md`'s
   original design -- turned out not to reliably keep `keepalive` alive as long as `arr` is
   reachable. Verified with an isolated, Polars-independent repro (`Owner`/`arr` example): the
   owner's own finalizer fires *before* `arr` becomes unreachable, even though the closure
   captures it. The likely cause: `(keepalive; nothing)` references `keepalive` and immediately
   discards the value, so the compiler is free to (and does) treat the capture as dead code and
   elide it -- referencing a variable with no observable effect on the closure's behavior is not
   enough to force retention. Fixed by replacing the closure-capture idiom with an explicit
   strong-reference table (`LIVE_BORROWED_ARRAYS`, same pattern as `LIVE_ARRAYS`/`LIVE_SCHEMAS`):
   `_read_numeric`'s zero-copy branch roots `keepalive` there before returning `arr`, and `arr`'s
   finalizer unroots it and calls `release!` explicitly. Confirmed via the same isolated repro
   before trusting it against the real FFI path.

4. **D4**: rewrote the misleading comment in `DataFrame(table)` (`src/dataframe.jl`) to reflect
   that Rust takes ownership of `array` unconditionally (by-value ccall) and already releases
   synchronously on the failure path (per the Rust-side doc comment and `guard_error`'s closure
   semantics) -- the Julia-side `release_array!` in the `catch` is a defensive, idempotent unroot,
   not a required one. Also marks the Julia-side `array` copy released right after the ccall
   returns, since it's a stale, moved-from copy on both paths.

5. **D5**: `ArrowSchema`'s `metadata` keyword now accepts `nothing` or an ordered `key => value`
   collection, encoded by a new `_encode_metadata` into the spec's binary layout; a plain string
   is rejected with a clear error. The struct field was retyped from `Union{Nothing,String}` to
   `Union{Nothing,Vector{UInt8}}` to hold the encoded bytes (which back the `Cstring`-typed C
   field's pointer, same lifetime requirement as `format`/`name`).

6. **D6**: added `_release_or_throw` (throws instead of invoking a `C_NULL` function pointer) and
   routed all four consumer release sites through it
   (`ExportedArray.release!`, `_read_list`, `load_series_schema`, `load_dataframe_schema`).

   **A `GC.@preserve` bug surfaced while making this change and was fixed in the same pass.**
   Splitting `@ccall $(release)(ref::Ptr{T})::Cvoid` into "compute the pointer, then call a
   separate function" breaks `@ccall`'s automatic preservation of its own arguments -- the `Ref`
   backing an isbits value can be freed/reused before the deferred call runs, since a bare `Ptr`
   carries no GC-rootedness. Reproduced live (a misaligned-pointer abort inside polars-arrow's
   `c_release_array`), fixed by wrapping each call site in explicit `GC.@preserve`.

7. **D7**: documented the write-side aliasing in `docs/src/developer.md` (which columns alias vs.
   copy) and a one-line cross-reference in `docs/src/limitations.md`.

## Tests added

- `test/datatypes/series.jl`: strengthened the existing "true zero-copy opt-in" test to force full
  GC + heap churn between dropping the source and re-checking the borrowed array -- the original
  single non-forced `GC.gc()` would not reliably have caught D1.
- `test/dataframe/gc.jl`: new testset covering three distinct construction-failure shapes
  (out-of-range `DateTime`, bare-`Any` column, unsupported dtype), asserting
  `LIVE_ARRAYS`/`LIVE_SCHEMAS` are empty afterward.
- `test/misc_ffi_safety.jl`: new testset building a 2-level `ArrowSchema`/`ArrowArray` tree
  directly, invoking the top-level release callback, and asserting both levels get
  `release == C_NULL` and that a second release throws via `_release_or_throw`; new testset
  round-tripping `ArrowSchema` metadata (rejection of a plain string, byte-level decode of the
  encoded form, and an end-to-end `polars_dataframe_new_from_carrow` call carrying non-empty
  metadata).

## Pre-existing unrelated failure

The suite's single failure (`Stale dependencies` under `Aqua`, flagging `BenchmarkTools`) predates
this work -- `Project.toml` had an uncommitted change (visible in `git status` at the start of this
session) adding `BenchmarkTools` as a dependency that isn't `using`d anywhere in `src/`. Left
untouched; out of scope for this plan.

## Verification performed

- Each of the three confirmed defects was reproduced live *before* the fix and confirmed fixed
  *after*, including under heavier stress than the original repro (full `GC.gc(true)` cycles,
  ~1M-element heap churn between drop and check, 10 failed constructions of two different shapes).
- Full suite in a scratch environment (`Pkg.develop(path=".")` +
  `Pkg.add(["Aqua","Test","Tables","TimeZones"])`): 1826 passed, 1 failed (pre-existing, see
  above), 0 errored, 2 broken (pre-existing).
- `python3 c-polars/check_header_drift.py`: clean (no Rust/header changes in this plan).
- `runic -i` over every touched `src/`/`test/` file.
