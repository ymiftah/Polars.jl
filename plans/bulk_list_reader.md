# Bulk List-column reader (breaking: `Vector{Vector{T}}`, not `Series{T}`)

## Status

Done. List columns with a leaf (non-nested, non-Struct, non-dictionary) child dtype now bulk-read
in one pass instead of one `Series` allocation per row. `collect(list_series)` / `getindex`
element type changed from `Series{T}` to plain `Vector{T}` (breaking, pre-1.0). Benchmark, 100k
rows, random 1-5-element sublists: bulk **~12-18ms** vs the old per-element path (still reachable,
now only as the nested/Struct/dictionary fallback) **~588ms** — **~35-49x**. Full suite **1544
passed / 2 broken (pre-existing) / 0 failed**. `cargo build/clippy/fmt/test`, header drift
(unchanged — pure Julia-side, no Rust/header/ABI change), and docs build all clean.

## Context

Flagged in round four's review (`plans/review_four_fixes.md`, P1.2) as the single biggest
remaining read-path cost: each row of a List column materialized as an independently-allocated
`polars_series_t` (via `polars_value_list_get`), each paying its own schema fetch + `length` +
`null_count` ccalls on top. The original P1.2 investigation found the naive "slice the exported
carray's offsets buffer into `Vector{Vector{T}}`" sketch was incompatible with the *existing*
type contract (`collect` returned `Vector{Series{T}}`) and would silently break the eltype
contract if implemented without a deliberate decision. Presented as a choice (keep `Series{T}`,
needing a new Rust bulk-export function to only cut ccall *count*, not per-row allocation; or
break to `Vector{Vector{T}}`, zero-ccall, consistent with how Struct already materializes as a
plain `NamedTuple` not a `Series`) — the breaking option was chosen (smaller test surface than
expected, more consistent design, and acceptable pre-1.0).

## Design

**Scope boundary (deliberate):** bulk-reads `List<leaf>` where `leaf` is any already-bulk-readable
format (numeric/bool/string/binary/date/time/duration/datetime). Falls back to the existing
per-element path for List-of-List (nested), List-of-Struct, and dictionary-encoded (Categorical)
list elements. A fully general recursive bulk reader would need a dual-tree walk (the schema tree,
for child format strings, in lockstep with the array tree, for buffers) — assessed as
disproportionate complexity/risk for the rarer nested case; the common case (the vast majority of
real List columns) gets the full win.

**Mechanism** (`src/arrow/read.jl`):
- Every leaf reader (`_read_numeric`/`_read_bool`/`_read_view`/`_read_offset`/`_read_transformed`)
  was refactored to take a raw `(ca::CArrowArray, bufs::Vector)` view instead of an
  `ExportedArray`, with the `release!` call moved *out* to the top-level caller. This is what
  makes recursion possible: a List's child array is a *borrowed* view into the parent's own
  exported carray (per the Arrow C Data Interface, only the top-level array's `release` is ever
  called by the consumer — it recursively frees the whole tree), so the leaf readers must be
  callable without themselves trying to release anything.
- `_read_list(series, fmt)`: fetches the schema once (only for List columns — the common
  scalar/string/etc. columns still never re-fetch schema, preserving round four's P1 optimization)
  to read the child's format string; bails out to `nothing` for nested/Struct/dictionary children;
  otherwise exports the carray once, materializes the *entire* child column once via the leaf
  dispatcher, then slices per-row sub-vectors out of it by copying (each row must be its own
  independently-owned `Vector`, never a `SubArray`, so this is inherently a copy even though the
  child materialization itself can be a single bulk pass).
- **Type-correctness subtlety, caught during implementation, not in the original design:**
  `parse_format` (schema-only, can't know actual data) always conservatively declares a leaf
  child type as `Union{ChildT, Missing}`. If `_read_list` derived its row-vector element type from
  the *actual* materialized child data's `eltype` (narrower, `ChildT`, whenever that specific
  child column happens to have zero real nulls), the result would violate `Series{T}`'s declared
  `eltype` — and Julia `Vector` is invariant, so `Vector{ChildT}` is not a subtype of
  `Vector{Union{ChildT,Missing}}`, an actual type-contract violation, not just an imprecision.
  Fixed by deriving the element type from `parse_format(child_schema)` (the authoritative source,
  called while the schema is still alive) and widening the materialized child data to match via
  `convert` if it came back narrower — a real one-time copy, paid once per column.
- `getindex`/`load_value` updated for consistency: `Base.getindex`'s dispatch constraint swapped
  `MaybeMissing{Series}` for `MaybeMissing{Vector}` (also subsuming the already-listed
  `MaybeMissing{Vector{UInt8}}` binary case); `load_value(::Value{V}) where {V<:Vector}` replaces
  the old `Value{S} where {S<:Series}` method, materializing via `collect(Series(...))` and
  returning the plain `Vector` — deliberately *not* widened (matching the prior design's own
  precision level for the per-element path, which was never guaranteed to match the declared
  `eltype` exactly either).
- `parse_format`'s `+l`/`+L` arm (`src/arrow/schema.jl`) changed from `MaybeMissing{Series{T}}`
  to `MaybeMissing{Vector{T}}`.

**Two real bugs caught by live testing, not by reasoning alone:**
1. `unsafe_load(ca.children, 1)` gives a `Ptr{CArrowArray}` (one level of pointer indirection
   remains) — needs a *second* `unsafe_load` to get the actual struct value. Got this right for
   the schema-side child but initially missed it for the array-side child; surfaced immediately
   as a `MethodError` (not silent wrong-memory-read) on the first live test.
2. A pre-existing test (`test/expr/curried_forms.jl`, `Strings.extract_all` — which also produces
   a List column) and a direct unit test calling the old 3-arg `_read_offset(T, OffT, h)`
   signature (`test/misc_ffi_safety.jl`) both broke and needed updating; neither was caught by the
   initial grep sweep for `isa Series` (case/qualification variance) or for leaf-reader call
   sites, only by running the full suite.

## Tests

`test/datatypes/series.jl`: rewrote the load-bearing "fallback to per-element for unsupported
types" testset (was pinning the old `Series{T}` contract) into two testsets — bulk-vs-per-element
agreement for a leaf-child List (incl. the exact declared/widened eltype), and the
nested-list/Struct-in-list fallback path (confirming both still produce correct results via
`load_value`'s recursion through `collect(Series(...))`). Added empty-column, sliced-series
(`ca.offset != 0`), and string-child cases. `test/datatypes/list_struct_write.jl`: simplified
now-redundant `collect(getindex(...))` to plain `getindex(...)` (List elements are already
materialized `Vector`s) and added bulk-vs-value assertions. Fixed the two broken call sites above.

## Verification

Live-exercised (before writing any test): basic Int64 list, null rows, null elements within
non-null rows, empty list column, string-element list, sliced list series, nested list-of-list
(fallback), list-of-struct (fallback, including field access), `DataFrame ==`/`hash` through list
columns, an `implode`-produced (query-result, not Julia-written) list. Full suite 1544/2/0 (no
Rust/header changes, so no regen needed). Benchmark recorded above.
