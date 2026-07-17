# Reference

A topic-organized manual covering every public function in Polars.jl. Use this once you know
roughly what you're looking for — for a guided introduction, start with the tutorials instead.

- [Structures](@ref) — the core wrapper types: `DataFrame`, `Series`, `LazyFrame`, `LazyGroupBy`, `Expr`
- [Laziness](@ref) — `lazy`, `collect`, `collect_schema`, and the eager/lazy relationship
- [Manipulation](@ref) — `select`, `filter`, `sort`, `group_by`/`agg`, joins, `concat`, and more
- [Expressions](@ref) — `col`, `lit`, `alias`, aggregation/math functions, windowing, and more
- [Lists](@ref) — the `Lists` namespace, for list-typed columns
- [Strings](@ref) — the `Strings` namespace, for `String`-typed columns
- [Date & Time](@ref) — the `Dt` namespace, for `Date`/`Datetime` columns
- [Structs](@ref) — the `Structs` namespace, for struct-typed columns
- [I/O](@ref) — reading, writing, and streaming parquet/CSV/IPC files
- [Utilities](@ref) — `version`, `schema`, and display customization
