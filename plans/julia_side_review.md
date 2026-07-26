# Julia-side A-grade review: fixes & hardening plan

## Status

**Done** (branch `review-one`, 2026-07-18; committed and pushed). Every item below (P0-P3) landed.
Final verification: full suite in the scratch env (`Pkg.develop(path=".")` +
Aqua/Test/Tables/TimeZones/Statistics) **1235 passed / 2 broken (pre-existing) / 0 failed**
(up from the pre-change baseline of 1151/2/0 — 84 new/updated regression tests added across the
P0-P2 fixes). Aqua fully green except the two pre-existing `broken=true` categories
(ambiguities, unbound type params — see `test/aqua.jl`'s updated comment for the one new,
benign `Expr`-vs-`WeakRef` ambiguity P2.1 introduced). `runic --check` clean on every modified
file; header-drift check green (256 symbols); no Rust files touched (this was a pure Julia-side
pass, `c-polars/` untouched throughout).

Two performance numbers measured live and worth keeping on record:
- **P1.2** (bulk string/binary reads): ~40x speedup collecting a 1M-row string column
  (0.017s bulk vs. 0.66s per-element).
- **P1.3** (cheap `columnnames`/`names`): ~19x speedup on a 1M-row, 2-column frame (0.005s vs.
  0.092s previously, since `Tables.columnnames` ran a null-count `select` over the whole frame
  just to answer "what are the names").

One deliberate scope decision, not in the original plan: **P2.4 also found and fixed a genuine
`StackOverflowError`** (not just a `MethodError`/panic) triggered by any column whose Julia
element type resolves to bare `Any` (e.g. a row-oriented `Vector{<:NamedTuple}` literal with a
`missing` value in one row and a concrete value in another, never explicitly typed
`Union{T,Missing}`) — `format(::Type{MaybeMissing{T}}) where T` self-matches when `T` solves to
`Any` (since `MaybeMissing{Any} === Any`), recursing forever. Fixed with a more-specific
`format(::Type{Any})` method that raises a clear error instead; see `src/arrow/array.jl` and the
regression test in `test/datatypes/structs.jl`.

One P3 item landed as a documented compromise rather than a full fix: `docs/make.jl` now uses
`checkdocs = :exports` (previously `:none`) and scopes the softened check to
`warnonly = [:missing_docs]` only — every other Documenter error category that the old blanket
`warnonly = true` was silencing (broken cross-refs, doctests, footnotes, ...) now fails the build
for real. `checkdocs = :exports` surfaced ~200 exported symbols whose docstring isn't pulled into
any reference page's `@docs`/`@autodocs` block — a large, pre-existing reference-page curation
gap far beyond the plan's anticipated "six join functions," and a content-authoring task for the
maintainer to prioritize deliberately rather than have auto-filled. The six `@eval`-generated
join functions (`innerjoin`/`leftjoin`/`rightjoin`/`outerjoin`/`semijoin`/`antijoin`) the plan did
call out by name now have real docstrings (`src/join.jl`).

Not done, deliberately out of scope (noted as follow-ups, not forgotten):
- Rust-side residuals tracked separately in `plans/c_polars_review_two.md`.
- Eager `group_by(::DataFrame)` wrapper and `lit(::Date)`/`cast(expr, DateTime)` (need new
  design/Rust symbols).
- Closing the ~200-symbol `checkdocs` gap (see above).
- Optional PrecompileTools TTFX workload (explicitly optional in the original plan).
- `_name_ptrs`-based `Vector{String}`-only APIs (`drop`, `unique`, `rename`, `explode`, `unpivot`,
  `pivot`, `join_asof`'s `by_left`/`by_right`) were **not** widened to accept `Symbol` — only the
  `Expr`-accepting verbs (`select`/`filter`/`group_by`/`sort`/`join`/`over`/`sort_by`, the ones
  users actually reach for with `:col`-style references) were, via the new `_as_expr` helper.

---

## P0 — Correctness bugs

### 0.1 `tail`/`rename` are unreachable for users
`Base.tail` (`src/select.jl:82`) and `Base.rename` (`src/verbs.jl:62`) extend **unexported**
Base bindings (verified: `Base.isexported` is false for both), so plain `tail(df)` /
`rename(df, ...)` throw `UndefVarError`. This is the exact `product` trap already documented in
CLAUDE.md. Fix like `head`: define package-local `tail` and `rename` functions (delete the
`Base.` qualification), add both to the export list. Add tests calling them **unqualified**.

### 0.2 Fixed-size-list schema parse throws `TypeError`
`src/arrow/schema.jl:130`: `@assert schema.n_children` asserts on an `Int64` → `TypeError` for
any Array-dtype column. Fix to `== 1`. Then exercise the path live: if `Series{NTuple{N,T}}`
still can't materialize (no `getindex` method, no `load_value`), replace the `NTuple` mapping
with a clear "Array dtype not supported" error instead of a type that lies.

### 0.3 GC-unsafe string pointers in `group_by_dynamic`/`rolling`
`src/group_by.jl:106-127` and `:161-177` pass `pointer(every)`/`pointer(period)`/
`pointer(offset)` to the FFI while those strings are **not** in the `GC.@preserve` list — the
strings are dead after their last use and can be collected mid-argument-evaluation. Add them to
the preserve list (`GC.@preserve index_expr group_by every period offset begin`).

### 0.4 `_write_callback` len type is `Cuint`, C typedef says `uintptr_t`
All 5 `@cfunction(_write_callback, Cssize_t, (Any, Ptr{Cchar}, Cuint))` sites (`src/value.jl`
×2, `src/io/parquet.jl`, `src/io/csv.jl`, `src/io/ipc.jl`) truncate the 64-bit `len` to 32
bits. Fix to `Csize_t`, and deduplicate: define the callback pointer once next to
`_write_callback` in `src/Polars.jl` (`_io_callback() = @cfunction(...)`) so the signature
can't drift again.

### 0.5 Binary columns' eltype omits `Missing`
`src/arrow/schema.jl:68-70`: `"z"/"Z"/"vz"` return bare `Vector{UInt8}` (strings correctly
return `MaybeMissing{String}`). A binary column with nulls gets `Series{Vector{UInt8}}` whose
`getindex` returns `missing` — violates the `AbstractVector` eltype contract. Wrap in
`MaybeMissing{...}`. Extend `test/datatypes/binary.jl` with a nulls-present case.

### 0.6 `LIVE_SCHEMAS`/`LIVE_ARRAYS` leak nested children + are unsynchronized
`release_schema!` (`src/arrow/schema.jl:196`) and `release_array!` (`src/arrow/array.jl:135`)
delete only one nesting level; every constructor level registers itself, so depth-≥2 children
(struct-of-struct, list-of-list, list-of-struct) stay rooted forever. Make both recursive. Also
add a `ReentrantLock` guarding all insert/delete on both `IdDict`s — the release callbacks are
invoked by Rust on whatever thread drops the array (adopted foreign threads race the main
thread otherwise).

### 0.7 String/binary/list write-path offsets can overflow silently
`src/arrow/array.jl:258-333`: `UInt32` offsets for `"u"`/`"z"` (>4 GiB column data wraps
`cumsum!` silently → corrupt data) and `Int32` offsets for `"+l"`. Switch the declared formats
to the large variants — `"U"`, `"Z"`, `"+L"` — with `Int64` offsets (polars' native list is
i64-offset anyway; verify import accepts, then the limit disappears entirely).

### 0.8 `Project.toml` compat contradiction
`Dates = "1.11.0"` with `julia = "1.10"` — resolution fails on Julia 1.10 (its Dates is
1.10.0). Fix to `Dates = "1.10, 1.11, 1.12"`. Add `Statistics` (same compat) for P2.2.

### 0.9 Temporal `load_value` methods miss the null guard
`load_value(::Value{<:Dates.Period})`, `(::Value{DateTime})`, `(::Value{Date})`,
`(::Value{Dates.Time})` in `src/value.jl:100-148` lack the
`polars_value_type(value) == PolarsValueTypeNull && return missing` guard every other loader
has. Reachable via struct fields holding null datetimes (the Series-level null check doesn't
cover struct-field access, `src/value.jl:75-98`). Verify live with a struct-with-null-datetime
column, then add the guard + test.

---

## P1 — Performance

### 1.1 Static dispatch for scalar reads
`src/series.jl:40-58` and `src/value.jl:25-38` compute
`getproperty(API, Symbol("polars_series_get_", ...))` at **runtime per element** — dynamic
lookup + uninferable call on every `getindex`. Replace with compile-time mapping, one trivially
inlined method per type: `_series_getter(::Type{Float64}) = API.polars_series_get_f64` etc.
(and `_value_getter(...)`).

### 1.2 Bulk string/binary reads (biggest user-visible win)
`read_series` (`src/arrow/read.jl:79`) has no string path, so string columns materialize
per-element: 3 FFI calls + an `IOBuffer` allocation **per value**. Add `"vu"` (Utf8View — what
polars exports) plus `"u"`/`"U"` classic-offset handling to `read_series`, building
`Vector{String}` / `Vector{Union{String,Missing}}` in one pass; same for `"z"/"vz"/"Z"` binary.
Pure Julia, no Rust change: parse the view buffer (16-byte views, ≤12-byte payloads inline,
longer ones as `(buffer_index, offset)` into the variadic data buffers; the last buffer is the
variadic-sizes array per the Arrow C spec). Test: nulls, empty strings, >12-byte strings,
non-ASCII, and a sliced series (`ca.offset != 0`). Benchmark before/after with a ~1M-row
string column in the REPL and record the numbers here.

### 1.3 Stop running a query to answer `Tables.columnnames`
`src/dataframe.jl:91-118`: `schema(df)` executes a null-count `select` per call, and
`Tables.columnnames`/`Tables.getcolumn(df, idx)` call it. Make `columnnames` (and a new
`Base.names(df)::Vector{String}`) read only the Arrow schema
(`load_dataframe_schema(API.polars_dataframe_schema(df))` — cheap, no query). Keep the
null-count refinement in `Tables.schema(df)` itself, documented as data-dependent.

### 1.4 Small cleanups
- `Base.copy(s::Series) = collect(s)` so generic consumers hit the bulk path.
- Precompute the `fieldoffset` in the two `unsafe_convert` methods (`src/arrow/schema.jl:257`,
  `src/arrow/array.jl:212`) as consts.
- Remove redundant `Base.eltype(::Series{T})` method; simplify `MaybeMissing` to
  `Union{T, Missing}` (`src/Polars.jl:5` — currently a redundant nested union).

---

## P2 — API design (breaking → 0.2.0)

### 2.1 Drop `Expr <: Number`
`src/expr/expr.jl:8`. Remove the supertype and `promote_rule`; keep all
`convert(::Type{Expr}, x)` methods (currying/`lit` use them). Add an `@eval` loop defining
explicit mixed-type methods for `+ - * / ^ == != < <= > >= & |`:
`Base.op(a::Expr, b::Expr)`, `Base.op(a::Expr, b)` / `Base.op(a, b::Expr)` via
`convert(Expr, ...)`. Delete the `isless`/`isequal` methods (contract breakers; `==` stays —
it *is* the DSL; document that `Expr`s aren't `Dict` keys / sortable). Watch `^`
(`literal_pow` with integer literals — add `Base.:^(::Expr, ::Integer)`). Re-run the whole
`expr/` test suite; try flipping Aqua `ambiguities` to non-broken afterwards.

### 2.2 Extend `Statistics` instead of exporting clashing names
Move `mean`/`median` out of the `@generate_expr_fns` block, and `std`/`var`/`quantile` from
hand-written locals, onto `Statistics.mean(::Expr)` etc. Re-export those five names from
Polars so `mean(col("x"))` still works without `using Statistics`. **Cost**: the curried forms
`std(; ddof)`, `var(; ddof)`, `quantile(q; method)` cannot live on Statistics generics without
type piracy — drop them and document the `x -> std(x; ddof=2)` alternative (update
`test/expr/curried_forms.jl`, docs).

### 2.3 A real exception type
`struct PolarsError <: Exception; message::String; end` + `Base.showerror`; `polars_error`
(`src/Polars.jl:48`) throws it instead of `Base.error`. Export it. Update any
`@test_throws ErrorException` in tests.

### 2.4 Export & namespace hygiene
- Consolidate the scattered `export` statements (`src/expr/expr.jl` has ~10) into the single
  list in `src/Polars.jl:83`, or at minimum audit for gaps: add `tail`, `rename`,
  `drop_nulls`, `nth`, `PolarsError`. Don't export `name` (clash-prone) — keep `Polars.name`
  documented, add `Base.names(df)`.
- Fix the `"unknow schema format"` typo (`src/arrow/schema.jl:137`).
- Factor the 8× repeated `map(ex -> ex isa String ? col(ex) : ex, ...)` into `_as_expr(x)`,
  and accept `Symbol` as well as `String` for column references throughout (Julia idiom:
  `select(df, :a)`).
- Optional: Julia ≥1.11 `public` declarations for supported-but-unexported API
  (`read_series`, `name`, `clone`).

### 2.5 `show` polish
Move the PrettyTables output to `Base.show(io, ::MIME"text/plain", df)`; make 2-arg
`show(io, df)` compact (`"5×2 Polars.DataFrame"`). Add simple `show` methods for `LazyFrame`
and `LazyGroupBy` (currently raw pointer dumps).

---

## P3 — CI, docs, packaging

- **CI triggers**: add `pull_request` (currently push-to-`main` only — PRs are untested!);
  Julia matrix `["1.10", "1"]`; add Swatinem/rust-cache for the cargo build; enable coverage +
  Codecov upload.
- **Docs gates**: `checkdocs = :exports` and drop `warnonly = true` in `docs/make.jl`. Add
  docstrings for the six `@eval`-generated join functions (`src/join.jl:19-34`) and any other
  exported symbol Documenter flags.
- **test/Project.toml**: add `Statistics`.
- Optional final polish: a small PrecompileTools workload (build DataFrame → select →
  collect) to cut TTFX.

Out of scope: Rust-side residuals (tracked in `plans/c_polars_review_two.md`); eager
`group_by(::DataFrame)` wrapper and `lit(::Date)`/`cast(expr, DateTime)` (need design/Rust
symbols — follow-ups).

---

## Verification

1. No Rust changes planned → no rebuild needed; run everything through Kaimon's live REPL.
2. Per-fix live checks: unqualified `tail(df)`/`rename(...)`; binary column with nulls
   (`eltype` includes `Missing`); struct field holding a null datetime; string bulk read vs
   old per-element results (equality on a mixed column: nulls/empty/long/`"café"`), including
   a sliced series; `collect` of a >2-element Utf8View column round-trips.
3. GC fix (0.3) is by-inspection; add a `GC.gc()` call inside the `group_by_dynamic` test with
   dynamically-constructed duration strings as a smoke check.
4. Overflow fix (0.7): after switching to Int64 offsets, round-trip a list/string column and
   confirm polars imports `"U"`/`"+L"` formats.
5. Full suite in a scratch env per CLAUDE.md (`Pkg.develop(path=".")` +
   Aqua/Test/Tables/TimeZones/Statistics), expect ≥1151 passing + new tests; Aqua green
   (attempt un-breaking `ambiguities`).
6. Docs build clean locally with the new gates: `julia --project=docs docs/make.jl`.
7. Record the string-column benchmark (1.2) before/after numbers in this Status section.
