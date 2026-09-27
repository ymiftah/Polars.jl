"""
    PartitionByKey(base_path::AbstractString;
                   by,
                   include_key::Bool=true,
                   max_rows_per_file::Union{Nothing,Integer}=nothing,
                   approximate_bytes_per_file::Union{Nothing,Integer}=nothing)

Partition by the values of `by`, for [`sink_parquet`](@ref): one file per distinct key under
Hive-style directories (e.g. `base_path/year=2024/month=1/00000000.parquet`). Pass it in place of
a path.

- `by`: column names or elementwise expressions.
- `include_key`: also write the key columns into the files.
- `max_rows_per_file`, `approximate_bytes_per_file`: split a partition over several files.
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
    keys = by isa AbstractVector ? _expr_vector(by) : Expr[_as_expr(by)]
    isempty(keys) && error("PartitionByKey requires at least one partition key in `by`")
    return PartitionByKey(
        String(base_path), keys, include_key,
        max_rows_per_file === nothing ? nothing : Int(max_rows_per_file),
        approximate_bytes_per_file === nothing ? nothing : Int(approximate_bytes_per_file)
    )
end
