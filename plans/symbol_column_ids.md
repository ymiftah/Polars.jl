# Accept `Symbol` column identifiers everywhere `String` ones are accepted

## Status

**Done (Steps 0–3; Step 4 docstrings deferred to a separate docs task, per user request).**
`ColId` is now used consistently across `src/verbs.jl`, `src/expr/expr.jl`, `src/join.jl`, and
`src/reshape.jl`; the `with_row_index` bug from Step 0 is fixed and pinned with a regression test.
Full suite: 2385 total (2383 pass, 2 broken — pre-existing, unrelated), 0 failures. One unrelated
issue was found and resolved along the way: the local `c-polars/target/debug/libpolars.so` was
stale (built before the checked-in `dataframe.rs`), which made `explode` crash the whole process
on *any* input, Symbol or String — not a code bug, fixed by rebuilding.

## Motivation

`col("x")`/`_as_expr` already treat `String` and `Symbol` as equivalent column references (`Expr`
literals go through `col`, which has a `Symbol` method). Several verbs that take column names
*directly* as `String`/`Vector{String}` (not as `Expr`s) don't yet accept `Symbol`/`Vector{Symbol}`
counterparts, which is an inconsistent, easy-to-hit surprise for callers who use `Symbol`s
elsewhere in the same call chain (e.g. `select(df, :x)` works but
`with_row_index(df, :idx)` doesn't).

## Step 0 — fix the pre-existing bug before building on it

`src/verbs.jl`'s `with_row_index` accepts `name::T where T<:Union{String,Symbol}` but passes
`name` straight into `ncodeunits(name)` and to the ccall. **`Base.ncodeunits` has no method for
`Symbol`** (confirmed: `ncodeunits(:x)` throws `MethodError`), so
`with_row_index(df, :idx)` currently crashes. Every sibling verb in the same diff
(`unique`/`drop`/`rename`/`drop_nulls`) avoids this because they route through `_name_ptrs`, which
does `String.(names)` before ever calling `ncodeunits`. Fix by converting at the top of the
function (`name = String(name)`) rather than deep in the ccall call — same shape as `col(name::Symbol) = col(String(name))` in `src/expr/expr.jl`.

## Step 1 — consolidate on the `ColId` alias

`ColId = Union{String, Symbol}` (`src/Polars.jl`) is currently unused outside its own
definition — every call site still spells out `Union{String,Symbol}`/`T <: Union{String,Symbol}`
inline (`src/expr/expr.jl`'s `col`/`over`/`sort_by`, `src/verbs.jl`'s new methods). Before adding
more call sites, replace those inline spellings with `ColId` so there's one name to grep for and
one place to widen later (e.g. if `AbstractString` should be accepted too). Also collapse
`_name_ptrs`'s two methods (`Vector{String}` and `Vector{Symbol}`) into one
`_name_ptrs(names::Vector{<:ColId}) = _name_ptrs(String.(names))`-style single entry point, or
keep two methods but have the `Vector{String}` one stay the zero-copy fast path — either is fine,
just make the `Symbol` path share the fast path's pointer-building code instead of duplicating it.

## Step 2 — close the remaining gaps

Grep confirms every other file with raw `String`/`Vector{String}` *column-identifier* parameters
(as opposed to file paths, which should stay `String`-only):

- **`src/join.jl`** — `join_asof`'s `by_left::Vector{String}`/`by_right::Vector{String}` kwargs
  (all 3 methods: the 3-arg `on` shorthand, the `DataFrame` method, the `LazyFrame` method). `on`/
  `on_a`/`on_b` already go through `_as_expr` and accept `Symbol` today — only `by_left`/`by_right`
  need loosening to `Vector{<:ColId}`, then passed through the (now-consolidated) `_name_ptrs`.
- **`src/reshape.jl`**:
  - `explode`'s `columns::Vector{String}` (both methods)
  - `unpivot`'s `index::Vector{String}` and `on::Vector{String}` kwarg (both methods)
  - `unnest`'s `columns::Vector{String}` (both methods)
  - `upsample`'s `time_column::String` and `by::Vector{String}` kwarg
  - `Base.transpose`'s `new_col_names::Union{Nothing,Vector{String}}` — lower priority, these are
    *new* names being created rather than existing-column references, but should still accept
    `Symbol` for consistency with everything else taking a name list
  - `pivot`'s `on`/`index`/`values` **already accept `Symbol`** incidentally (`on isa
    AbstractVector ? String.(on) : [String(on)]` converts either type) — no change needed, just
    worth a one-line docstring mention so it's not assumed unsupported.
- **`src/dataframe.jl`** — already `Symbol`-native (`getindex(df, s::String) = getindex(df,
  Symbol(s))`); no change needed, just confirms the direction of conversion should generally be
  "convert `String`→whatever the ccall/internal boundary wants", mirrored at each new site.

For each function above: widen the signature to `Vector{<:ColId}`/`ColId`, convert to `String`
(or `Vector{String}`) at the top via `String.(...)`/`String(...)` before any `ncodeunits`/ccall
use — do not rely on `Symbol` auto-converting through `Ptr{UInt8}` implicitly the way it does for
direct ccall args (see Step 0 — it does auto-convert for the ccall itself, but not for
`ncodeunits`, so convert once, up front, rather than relying on that partial support).

## Step 3 — tests

`test/operations/select_with_columns.jl` already has a `"Symbol column references (Julia-side
P2.4)"` testset for `_as_expr`-backed verbs (`select`/`with_columns`/`over`/`sort_by`). Add the
equivalent coverage for every verb touched in Steps 0–2, in the matching `test/<category>/*.jl`
file per this repo's file-layout convention (`test/operations/frame_verbs.jl` for
`drop`/`rename`/`drop_nulls`/`with_row_index`, `test/operations/unique.jl` for `unique`,
`test/operations/join.jl` for `join_asof`, `test/operations/reshape.jl` or wherever
`explode`/`unpivot`/`unnest`/`upsample`/`transpose` currently live). At minimum: one call per
touched function using `Symbol` args, asserting identical output to the equivalent `String` call.
Include `with_row_index(df, :idx)` explicitly, to pin the Step 0 fix as a regression test.

## Step 4 — docs

None of the touched functions' docstrings currently mention `Symbol` support. Once Steps 0–3 land,
do a pass updating the docstrings (mirroring `col`'s `Union{String,Symbol}` doc line) so the
generated API reference reflects the new signatures — low cost, do it in the same commit as each
function's code change rather than as a separate sweep.

## Out of scope

- `src/io/*.jl` path arguments (`scan_parquet`, `write_csv`, ...) — these are file paths, not
  column identifiers; no change.
- Widening beyond `Union{String,Symbol}` to generic `AbstractString` — not requested, and this
  package already uses concrete `String` at FFI boundaries deliberately (see `ncodeunits` usage
  patterns in CLAUDE.md); keep `ColId` exactly `Union{String,Symbol}` unless a concrete need for
  `SubString`/`AbstractString` shows up.
