# Utilities

Miscellaneous functions for introspection and display.

```@setup utils
using Polars
```

## Version

`version()` — returns the polars version (as a `VersionNumber`) the C ABI was built against.

```julia
Polars.version()  # => v"0.20.0" or similar
```

## Schema inspection

`schema(df::DataFrame)` — implements the Tables.jl interface method, returning a `Tables.Schema` with column names and types. Unlike `collect_schema` on a lazy frame, this refines column types using actual null counts from the materialized data.

```@example utils
df = DataFrame((; x = [1, 2, missing], y = ["a", "b", "c"]))
import Tables
Tables.schema(df)
```

## Summary statistics: `describe`

`describe(df; percentiles=[0.25, 0.5, 0.75])` computes per-column summary statistics, returning
one row per statistic (`"count"`, `"null_count"`, `"mean"`, `"std"`, `"min"`, one row per
`percentiles` entry, `"max"`) and one column per column of `df` (plus a leading `"statistic"`
column). Every value is stringified, since a single output column otherwise couldn't coherently
hold both e.g. a count (integer) and a mean (float). `mean`/`std`/percentile rows are `missing`
for non-numeric columns; `min`/`max` are `missing` for columns with no natural ordering (e.g.
`List`/`Struct`).

```@example utils
describe(df)
```

## Display

- `size(df::DataFrame)` returns `(nrows, ncols)`.
- `Base.summary(df::DataFrame)` returns a one-line summary (e.g., "3×2 DataFrame").
- `Base.show(io::IO, df::DataFrame)` renders the full table with PrettyTables formatting.

All display is automatic in REPL/Pluto.jl; no explicit call needed.
