# Reference

A complete manual covering every public function in Polars.jl, organized by type — mirroring the
structure of the [py-polars API reference](https://docs.pola.rs/api/python/stable/reference/index.html).
Use this once you know roughly what you're looking for; for a guided introduction, start with the
tutorials instead.

## Core types

- [DataFrame](@ref) — the eager, columnar table type, and every verb that operates on it (`select`,
  `filter`, `sort`, `group_by`/`agg`, joins, reshaping, ...) — shared with `LazyFrame`.
- [LazyFrame](@ref) — the lazy, query-plan type: `lazy`, `collect`, `collect_schema`, and
  `LazyGroupBy`.
- [Series](@ref) — a single named column.
- [Expressions](@ref) — `Expr`, the building block of every query: aggregation, boolean, math,
  manipulation, naming, and casting functions.

## Functions & selection

- [Functions](@ref) — top-level expression constructors: `col`, `lit`, `when`, and horizontal
  (row-wise) reductions.
- [Selectors](@ref) — select columns by dtype, name, position, or pattern instead of one `col(...)`
  at a time.

## Expression namespaces

- [List](@ref expr-list) — the `Lists` namespace, for list-typed columns.
- [String](@ref expr-string) — the `Strings` namespace, for `String`-typed columns.
- [Datetime](@ref expr-datetime) — the `Dt` namespace, for `Date`/`Datetime`/`Duration` columns.
- [Struct](@ref expr-struct) — the `Structs` namespace, for struct-typed columns.
- [Meta](@ref expr-meta) — the `Polars.Meta` namespace, for inspecting an expression tree itself.

## I/O, types & misc

- [Input/output](@ref) — reading, writing, and streaming parquet/CSV/IPC files.
- [Data types](@ref) — the Julia↔polars dtype mapping and nullability convention.
- [Metadata](@ref) — `Polars.version()`.
- [Exceptions](@ref) — `PolarsError`, the single exception type every fallible operation raises.
