"""
    PartitionByKey(base_path::AbstractString;
                   by,
                   include_key::Bool=true,
                   max_rows_per_file::Union{Nothing,Integer}=nothing,
                   approximate_bytes_per_file::Union{Nothing,Integer}=nothing)

A Hive-style partitioning scheme for [`sink_parquet`](@ref): rather than a single output file,
writes one file per distinct combination of `by`'s values, under directories named
`key=value/` beneath `base_path` (e.g. `base_path/year=2024/month=1/00000000.parquet`).

- `by`: the partition key(s) -- a column name (`String`/`Symbol`), an [`Expr`](@ref) (e.g. a
  derived key such as `Dt.year(col("d")) |> alias("year")`), or a vector of either. Must be
  non-empty, and each key expression must be elementwise (no aggregations).
- `include_key`: whether the partition key column(s) are also written into each file's contents,
  in addition to being encoded in the directory name (default `true`).
- `max_rows_per_file`/`approximate_bytes_per_file`: if given, splits a single partition's output
  across multiple numbered files (`00000000.parquet`, `00000001.parquet`, ...) once it would
  otherwise exceed this many rows / approximate bytes. `nothing` (default) means unlimited --
  exactly one file per partition.

Passed as the `path` argument to [`sink_parquet`](@ref) in place of a plain path string.
"""
struct PartitionByKey
    base_path::String
    by::Vector{Expr}
    include_key::Bool
    max_rows_per_file::Union{Nothing, Int}
    approximate_bytes_per_file::Union{Nothing, Int}
end

function PartitionByKey(
        base_path::AbstractString;
        by,
        include_key::Bool = true,
        max_rows_per_file::Union{Nothing, Integer} = nothing,
        approximate_bytes_per_file::Union{Nothing, Integer} = nothing
    )
    keys = by isa AbstractVector ? map(_as_expr, by) : [_as_expr(by)]
    isempty(keys) && error("PartitionByKey requires at least one partition key in `by`")
    return PartitionByKey(
        String(base_path), convert(Vector{Expr}, keys), include_key,
        max_rows_per_file === nothing ? nothing : Int(max_rows_per_file),
        approximate_bytes_per_file === nothing ? nothing : Int(approximate_bytes_per_file)
    )
end
