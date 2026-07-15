# Limitations

Known gaps and sharp edges in Polars.jl worth skimming before you hit them.

## I/O limitations

- ~~List and Struct columns cannot be constructed from Julia arrays.~~ **Resolved.**
  `DataFrame(table)` now accepts `Vector{<:Vector{T}}` (including the nullable
  `Vector{Union{Missing,Vector{T}}}` case) for List columns and `Vector{<:NamedTuple}` for Struct
  columns, alongside the scalar/fixed-width types it already supported
  (`Vector{Int}`, `Vector{String}`, `Vector{Date}`, `Vector{DateTime}`, etc.). See the examples in
  [Structs](@ref).

## Date/time limitations

- ~~`Series{Datetime{Res}}`/`Series{Duration{Res}}` don't support `collect()` or broadcasting.~~
  **Resolved.** Datetime and Duration columns now report their real, plain `Dates.DateTime`/
  `Dates.Period` `eltype` (there was never a genuine need for the internal wrapper types this used
  to report — the actual resolution is re-derived at runtime from the underlying polars value
  regardless), so `collect`, `copy`, and broadcasts all work directly. No workaround needed
  anymore.

## Expression/function limitations

- **`Strings.titlecase` is broken.** The upstream polars function requires an internal "nightly" Cargo feature that this package deliberately doesn't enable (see Build environment in the project notes). The binding exists but will error at runtime.

- **`Base.lt(expr1, expr2)` needs explicit qualification.** It collides with an unexported `Base`
  name. Use `Base.lt(col("x"), lit(2))` instead of `col("x") < lit(2)` (or use `.>` and flip the
  operands). The product aggregation used to have the same problem (`Base.product`) but has since
  been renamed to `prod`, an exported Base name — plain `prod(col("x"))` now works with no
  qualification.

- **`Base.tail(df, n)` and `Base.rename(df, existing, new)` also need explicit qualification**,
  for the same reason as `lt` above — bare `tail(df, 2)` / `rename(df, ...)` raise
  `UndefVarError`. `unique`, `drop`, `drop_nulls`, `with_row_index`, `explode`, `unpivot`, and
  `pivot` do **not** have this problem and can be called bare. See [Manipulation](@ref).

## Feature coverage

- Some polars capabilities are behind Cargo features that aren't enabled by default (see `c-polars/Cargo.toml`). If you hit a "activate 'X' feature" panic message, the feature needs to be added there and `c-polars/` rebuilt.

- The test suite has gaps — some operations have shipped with zero automated test coverage. Verify new operations end-to-end in a live session before assuming they work.

## Performance notes

- Eager `DataFrame` operations (via `collect ∘ op ∘ lazy`) are not as query-optimized as operations built directly on lazy frames — the optimizer only sees the outer `lazy()` call and the final `collect`, not the intermediate steps. For performance-critical workflows, construct the full query on `LazyFrame` before collecting.
