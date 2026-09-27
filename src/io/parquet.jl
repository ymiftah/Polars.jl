"""
Calls `f` with a temporary `polars_cloud_options_t` handle built from `storage_options` (a null
pointer for `nothing`), destroying it afterwards.
"""
function _with_cloud_options(f, storage_options::Union{Nothing, AbstractDict{<:AbstractString, <:AbstractString}})
    if storage_options === nothing
        return f(Ptr{polars_cloud_options_t}(C_NULL))
    end
    ks = String[]
    vs = String[]
    for (k, v) in storage_options
        push!(ks, String(k))
        push!(vs, String(v))
    end
    key_names, key_ptrs, key_lens = _name_ptrs(ks)
    value_names, value_ptrs, value_lens = _name_ptrs(vs)
    handle = GC.@preserve key_names value_names begin
        out = Ref{Ptr{polars_cloud_options_t}}()
        err = polars_cloud_options_new(key_ptrs, key_lens, value_ptrs, value_lens, length(ks), out)
        polars_error(err)
        out[]
    end
    try
        return f(handle)
    finally
        polars_cloud_options_destroy(handle)
    end
end

"""
    scan_parquet(path::String;
                 n_rows::Union{Nothing,Integer}=nothing,
                 row_index_name::Union{Nothing,AbstractString}=nothing,
                 row_index_offset::Integer=0,
                 parallel::Symbol=:auto,
                 low_memory::Bool=false,
                 rechunk::Bool=false,
                 cache::Bool=true,
                 glob::Bool=true,
                 use_statistics::Bool=true,
                 allow_missing_columns::Bool=false,
                 allow_extra_columns::Bool=false,
                 include_file_paths::Union{Nothing,AbstractString}=nothing,
                 hive_partitioning::Union{Nothing,Bool}=nothing,
                 cast_policy::Union{Nothing,CastPolicy,AbstractDict}=nothing,
                 storage_options::Union{Nothing,AbstractDict{<:AbstractString,<:AbstractString}}=nothing)::LazyFrame

Create a LazyFrame directly from a parquet scan. `path` may be a file, a glob pattern, or a
directory of (optionally Hive-partitioned) files.

- `n_rows`: only scan the first `n_rows` rows.
- `row_index_name`/`row_index_offset`: if `row_index_name` is given, adds a row-index column with
  that name, starting at `row_index_offset`.
- `parallel`: how to parallelize reading — one of `:auto`, `:none`, `:columns`, `:row_groups`.
- `low_memory`: trade speed for lower peak memory use.
- `rechunk`: rechunk each file's columns into contiguous memory after reading.
- `cache`: cache the result of the scan (only relevant if reused within the same plan).
- `glob`: expand `path` as a glob pattern.
- `use_statistics`: use row-group statistics to skip reading unneeded row groups.
- `allow_missing_columns`: allow columns present in some files but not others (filled with nulls).
- `allow_extra_columns`: drop columns that are absent from the first file scanned, instead of
  raising.
- `include_file_paths`: if given, adds a column with this name containing each row's source path.
- `hive_partitioning`: force Hive-style partition-column detection on (`true`) or off (`false`);
  `nothing` (default) auto-detects.
- `cast_policy`: a [`CastPolicy`](@ref) (or a `Dict{Symbol,Bool}` of its fields) for type
  mismatches between files. `nothing` (default) raises on any mismatch.
- `storage_options`: cloud storage configuration (e.g. `"aws_region" => "us-east-1"`) for
  `s3://`, `gs://`, `az://` paths. By default the provider's environment variables and config
  files are used.

# Examples
```julia
# Default: strict mode, errors on any type mismatch
df = read_parquet("data.parquet")

# Allow specific relaxations
df = read_parquet("data.parquet"; cast_policy = CastPolicy(integer_upcast = true, float_upcast = true))

# Read Spark-written parquet (nanosecond-precision datetimes)
df = read_parquet("spark_output.parquet"; cast_policy = CastPolicy(datetime_nanoseconds_downcast = true))
```
"""
function scan_parquet(
        path;
        n_rows::Union{Nothing, Integer} = nothing,
        row_index_name::Union{Nothing, AbstractString} = nothing,
        row_index_offset::Integer = 0,
        parallel::Symbol = :auto,
        low_memory::Bool = false,
        rechunk::Bool = false,
        cache::Bool = true,
        glob::Bool = true,
        use_statistics::Bool = true,
        allow_missing_columns::Bool = false,
        allow_extra_columns::Bool = false,
        include_file_paths::Union{Nothing, AbstractString} = nothing,
        hive_partitioning::Union{Nothing, Bool} = nothing,
        cast_policy::Union{Nothing, CastPolicy, AbstractDict} = nothing,
        storage_options::Union{Nothing, AbstractDict{<:AbstractString, <:AbstractString}} = nothing
    )
    parallel_enum = parallel == :auto ? API.PolarsParquetParallelAuto :
        parallel == :none ? API.PolarsParquetParallelNone :
        parallel == :columns ? API.PolarsParquetParallelColumns :
        parallel == :row_groups ? API.PolarsParquetParallelRowGroups :
        error(
            "unknown parallel strategy $parallel, expected one of (:auto, :none, :columns, :row_groups)"
        )

    n_rows_ref = n_rows === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(n_rows))
    row_index_name_arg = row_index_name === nothing ? Ptr{UInt8}(C_NULL) : row_index_name
    row_index_name_len = row_index_name === nothing ? 0 : ncodeunits(row_index_name)
    include_file_paths_arg = include_file_paths === nothing ? Ptr{UInt8}(C_NULL) : include_file_paths
    include_file_paths_len = include_file_paths === nothing ? 0 : ncodeunits(include_file_paths)
    hive_partitioning_ref = hive_partitioning === nothing ? Ptr{Bool}(C_NULL) : Ref(hive_partitioning)

    cast_policy_ref = Ref(
        _to_api_struct(
            cast_policy === nothing ? CastPolicy() :
                cast_policy isa CastPolicy ? cast_policy :
                _dict_to_cast_policy(cast_policy)
        )
    )

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = _with_cloud_options(storage_options) do cloud_options
        GC.@preserve n_rows_ref hive_partitioning_ref cast_policy_ref begin
            polars_lazy_frame_scan_parquet(
                path, ncodeunits(path), n_rows_ref, row_index_name_arg, row_index_name_len,
                UInt32(row_index_offset), parallel_enum, low_memory, rechunk, cache, glob,
                use_statistics, allow_missing_columns, allow_extra_columns, include_file_paths_arg,
                include_file_paths_len, hive_partitioning_ref, cast_policy_ref, cloud_options, out
            )
        end
    end
    polars_error(err)
    return LazyFrame(out[])
end

"""
    read_parquet(path::String; kwargs...)::DataFrame

Read a parquet file (or a directory or glob of them) into a `DataFrame`. Accepts the keywords of
[`scan_parquet`](@ref).
"""
read_parquet(path; kwargs...) = collect(scan_parquet(path; kwargs...))

function _parquet_compression_enum(compression::Symbol)
    compression == :uncompressed && return API.PolarsParquetCompressionUncompressed
    compression == :snappy && return API.PolarsParquetCompressionSnappy
    compression == :gzip && return API.PolarsParquetCompressionGzip
    compression == :brotli && return API.PolarsParquetCompressionBrotli
    compression == :zstd && return API.PolarsParquetCompressionZstd
    compression == :lz4_raw && return API.PolarsParquetCompressionLz4Raw
    return error(
        "unknown compression $compression, expected one of (:uncompressed, :snappy, :gzip, :brotli, :zstd, :lz4_raw)"
    )
end

"""
    write_parquet(io::IO, df::DataFrame;
                  compression::Symbol=:zstd,
                  compression_level::Union{Nothing,Integer}=nothing,
                  statistics::Bool=true,
                  row_group_size::Union{Nothing,Integer}=nothing,
                  data_page_size::Union{Nothing,Integer}=nothing)
    write_parquet(path::String, df::DataFrame; kwargs...)

Write a DataFrame to parquet.

- `compression`: one of `:zstd` (default), `:snappy`, `:gzip`, `:brotli`, `:lz4_raw`,
  `:uncompressed`.
- `compression_level`: for `:gzip`, `:brotli` and `:zstd` only.
- `statistics`: whether to compute and write column statistics (default `true`).
- `row_group_size`: maximum rows per row group (default: a single row group).
- `data_page_size`: maximum bytes per data page (default: polars' own default, ~1 MiB).

A `path` containing `"://"` (e.g. `"s3://bucket/out.parquet"`) is written with
[`sink_parquet`](@ref), and accepts its keywords.
"""
function write_parquet(
        io::IO, df::DataFrame;
        compression::Symbol = :zstd,
        compression_level::Union{Nothing, Integer} = nothing,
        statistics::Bool = true,
        row_group_size::Union{Nothing, Integer} = nothing,
        data_page_size::Union{Nothing, Integer} = nothing
    )
    compression_enum = _parquet_compression_enum(compression)
    compression_level_ref = compression_level === nothing ? Ptr{Int32}(C_NULL) :
        Ref(Int32(compression_level))
    row_group_size_ref = row_group_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(row_group_size))
    data_page_size_ref = data_page_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(data_page_size))

    callback = _io_callback()
    ref = Ref(io)
    err = GC.@preserve compression_level_ref row_group_size_ref data_page_size_ref begin
        polars_dataframe_write_parquet(
            df, ref, callback, compression_enum, compression_level_ref, statistics,
            row_group_size_ref, data_page_size_ref
        )
    end
    polars_error(err)
    return nothing
end
function write_parquet(p::String, df::DataFrame; kwargs...)
    occursin("://", p) && return sink_parquet(df, p; kwargs...)
    return open(io -> write_parquet(io, df; kwargs...), p, "w")
end
"""
    sink_parquet(lf::LazyFrame, path::String;
                 compression::Symbol=:zstd,
                 compression_level::Union{Nothing,Integer}=nothing,
                 statistics::Bool=true,
                 row_group_size::Union{Nothing,Integer}=nothing,
                 data_page_size::Union{Nothing,Integer}=nothing,
                 mkdir::Bool=false,
                 maintain_order::Bool=true)
    sink_parquet(df::DataFrame, path::String; kwargs...)

Stream the results of the query to a parquet file, without materializing the full result in
memory.

Accepts the same `compression`/`compression_level`/`statistics`/`row_group_size`/`data_page_size`
keywords as [`write_parquet`](@ref), plus:
- `mkdir`: create missing parent directories (default `false`).
- `maintain_order`: preserve row order through the streaming pipeline (default `true`).
- `storage_options`: cloud storage configuration (e.g. `"aws_region" => "us-east-1"`) for
  `s3://`, `gs://`, `az://` paths. By default the provider's environment variables and config
  files are used.
"""
sink_parquet(df::DataFrame, path::String; kwargs...) = sink_parquet(lazy(df), path; kwargs...)
function sink_parquet(
        lf::LazyFrame, path::String;
        compression::Symbol = :zstd,
        compression_level::Union{Nothing, Integer} = nothing,
        statistics::Bool = true,
        row_group_size::Union{Nothing, Integer} = nothing,
        data_page_size::Union{Nothing, Integer} = nothing,
        mkdir::Bool = false,
        maintain_order::Bool = true,
        storage_options::Union{Nothing, AbstractDict{<:AbstractString, <:AbstractString}} = nothing
    )
    compression_enum = _parquet_compression_enum(compression)
    compression_level_ref = compression_level === nothing ? Ptr{Int32}(C_NULL) :
        Ref(Int32(compression_level))
    row_group_size_ref = row_group_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(row_group_size))
    data_page_size_ref = data_page_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(data_page_size))

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = _with_cloud_options(storage_options) do cloud_options
        GC.@preserve compression_level_ref row_group_size_ref data_page_size_ref begin
            polars_lazy_frame_sink_parquet(
                lf, path, ncodeunits(path), compression_enum, compression_level_ref, statistics,
                row_group_size_ref, data_page_size_ref, mkdir, maintain_order,
                cloud_options, out
            )
        end
    end
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end

"""
    sink_parquet(lf::LazyFrame, target::PartitionByKey;
                 compression::Symbol=:zstd,
                 compression_level::Union{Nothing,Integer}=nothing,
                 statistics::Bool=true,
                 row_group_size::Union{Nothing,Integer}=nothing,
                 data_page_size::Union{Nothing,Integer}=nothing,
                 maintain_order::Bool=true)
    sink_parquet(df::DataFrame, target::PartitionByKey; kwargs...)

Stream the results of the query to a Hive-partitioned directory of parquet files (see
[`PartitionByKey`](@ref)). Accepts the keywords of the single-file method except `mkdir`
(directories are always created).
"""
sink_parquet(df::DataFrame, target::PartitionByKey; kwargs...) = sink_parquet(lazy(df), target; kwargs...)
function sink_parquet(
        lf::LazyFrame, target::PartitionByKey;
        compression::Symbol = :zstd,
        compression_level::Union{Nothing, Integer} = nothing,
        statistics::Bool = true,
        row_group_size::Union{Nothing, Integer} = nothing,
        data_page_size::Union{Nothing, Integer} = nothing,
        maintain_order::Bool = true,
        storage_options::Union{Nothing, AbstractDict{<:AbstractString, <:AbstractString}} = nothing
    )
    compression_enum = _parquet_compression_enum(compression)
    compression_level_ref = compression_level === nothing ? Ptr{Int32}(C_NULL) :
        Ref(Int32(compression_level))
    row_group_size_ref = row_group_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(row_group_size))
    data_page_size_ref = data_page_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(data_page_size))
    max_rows_ref = target.max_rows_per_file === nothing ? Ptr{UInt64}(C_NULL) :
        Ref(UInt64(target.max_rows_per_file))
    approx_bytes_ref = target.approximate_bytes_per_file === nothing ? Ptr{UInt64}(C_NULL) :
        Ref(UInt64(target.approximate_bytes_per_file))
    keys = target.by

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = _with_cloud_options(storage_options) do cloud_options
        GC.@preserve keys compression_level_ref row_group_size_ref data_page_size_ref max_rows_ref approx_bytes_ref begin
            key_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in keys]
            polars_lazy_frame_sink_parquet_partitioned(
                lf, target.base_path, ncodeunits(target.base_path), key_ptrs, length(key_ptrs),
                target.include_key, max_rows_ref, approx_bytes_ref, compression_enum,
                compression_level_ref, statistics, row_group_size_ref, data_page_size_ref,
                maintain_order, cloud_options, out
            )
        end
    end
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end
