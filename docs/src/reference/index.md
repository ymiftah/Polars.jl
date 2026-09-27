# Reference

Every public function in Polars.jl, organized like the
[py-polars API reference](https://docs.pola.rs/api/python/stable/reference/index.html).

## Core types

- [DataFrame](@ref): the eager table type and the verbs shared with `LazyFrame`.
- [LazyFrame](@ref): `lazy`, `collect`, `collect_schema` and `LazyGroupBy`.
- [Series](@ref): a single named column.
- [Expressions](@ref): methods on `Expr`.

## Functions & selection

- [Functions](@ref): `col`, `lit`, `when`, horizontal reductions and other constructors.
- [Selectors](@ref): select columns by dtype, name, position or pattern.

## Expression namespaces

- [List](@ref expr-list): `Lists`, for List columns.
- [String](@ref expr-string): `Strings`, for String columns.
- [Datetime](@ref expr-datetime): `Dt`, for Date, Datetime and Duration columns.
- [Struct](@ref expr-struct): `Structs`, for Struct columns.
- [Meta](@ref expr-meta): `Polars.Meta`, for inspecting expressions.

## I/O, types & misc

- [Input/output](@ref): reading, writing and streaming parquet, CSV, IPC and JSON.
- [Data types](@ref): how Julia and polars types map to each other.
- [Metadata](@ref): `Polars.version()`.
- [Exceptions](@ref): `PolarsError`.
