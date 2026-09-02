"""
Builds a temporary `polars_cloud_options_t` handle from `storage_options` (`nothing` becomes a
null pointer), invokes `f` with the raw handle, and always destroys the handle afterward -- unlike
every other opaque handle in this package (`DataFrame`/`LazyFrame`/`Series`/`Expr`/`Value`), this
one is never exposed to the caller, so its whole lifetime is scoped to one ccall and no persistent
Julia wrapper struct with a finalizer is needed.
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

Lazily scans a parquet file, glob pattern, or directory of (optionally Hive-partitioned) parquet
files, without reading it into memory.

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
- `allow_extra_columns`: allow columns present in a scanned file but absent from the reference
  schema (the first file scanned) to be silently dropped, rather than raising. The converse of
  `allow_missing_columns`. Only available here — `scan_csv`/`scan_ipc` have no equivalent, see
  [Limitations](@ref).
- `include_file_paths`: if given, adds a column with this name containing each row's source path.
- `hive_partitioning`: force Hive-style partition-column detection on (`true`) or off (`false`);
  `nothing` (default) auto-detects.
- `cast_policy`: a [`CastPolicy`](@ref) (or `Dict{Symbol,Bool}` with the same field names) controlling
  how type mismatches during the scan are handled. `nothing` (default) uses polars' strict
  `ERROR_ON_MISMATCH` behavior — see [`CastPolicy`](@ref) for the available relaxations.
- `storage_options`: a `Dict` of cloud object-store configuration keys/values (e.g.
  `"aws_access_key_id"`, `"aws_endpoint_url"`, `"aws_region"`) for accessing cloud paths
  (`s3://`, `gs://`, `az://`, ...). Omitting it (`nothing`, the default) falls back to the
  provider's standard environment variables / config files (e.g. `~/.aws/credentials`).

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

    n_rows_ref = _nullable_ref(n_rows, Csize_t)
    row_index_name_arg, row_index_name_len = _nullable_str(row_index_name)
    include_file_paths_arg, include_file_paths_len = _nullable_str(include_file_paths)
    hive_partitioning_ref = _nullable_ref(hive_partitioning, Bool)

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

Reads a dataframe stored in a parquet file, or a directory/glob of parquet files. Accepts the same
keyword options as [`scan_parquet`](@ref) (`n_rows`, `row_index_name`, `hive_partitioning`, etc).
"""
read_parquet(path; kwargs...) = collect(scan_parquet(path; kwargs...))

_parquet_compression_enum(compression::Symbol) = _enum_lookup(
    compression, "compression",
    :uncompressed => API.PolarsParquetCompressionUncompressed,
    :snappy => API.PolarsParquetCompressionSnappy, :gzip => API.PolarsParquetCompressionGzip,
    :brotli => API.PolarsParquetCompressionBrotli, :zstd => API.PolarsParquetCompressionZstd,
    :lz4_raw => API.PolarsParquetCompressionLz4Raw,
)

"""
    write_parquet(io::IO, df::DataFrame;
                  compression::Symbol=:zstd,
                  compression_level::Union{Nothing,Integer}=nothing,
                  statistics::Bool=true,
                  row_group_size::Union{Nothing,Integer}=nothing,
                  data_page_size::Union{Nothing,Integer}=nothing)
    write_parquet(path::String, df::DataFrame; kwargs...)

Writes a dataframe to a parquet file provided as an `IO`.

- `compression`: one of `:zstd` (default), `:snappy`, `:gzip`, `:brotli`, `:lz4_raw`,
  `:uncompressed`.
- `compression_level`: tunes the chosen algorithm's compression level. Only valid for
  `:gzip`/`:brotli`/`:zstd` — an error for the others.
- `statistics`: whether to compute and write column statistics (default `true`).
- `row_group_size`: maximum rows per row group (default: a single row group).
- `data_page_size`: maximum bytes per data page (default: polars' own default, ~1 MiB).

For the `path::String` method, a path containing `"://"` (e.g. `"s3://bucket/out.parquet"`) is
routed to [`sink_parquet`](@ref) instead of local file IO, accepting `sink_parquet`'s full keyword
set (including `storage_options`, `mkdir`, `maintain_order`) for such paths.
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
    compression_level_ref = _nullable_ref(compression_level, Int32)
    row_group_size_ref = _nullable_ref(row_group_size, Csize_t)
    data_page_size_ref = _nullable_ref(data_page_size, Csize_t)

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

Executes the query and writes the result directly to a parquet file via the streaming engine,
without materializing the full result in memory — suitable for out-of-core processing of
datasets larger than RAM.

Accepts the same `compression`/`compression_level`/`statistics`/`row_group_size`/`data_page_size`
keywords as [`write_parquet`](@ref), plus:
- `mkdir`: create missing parent directories (default `false`).
- `maintain_order`: preserve row order through the streaming pipeline (default `true`).
- `storage_options`: a `Dict` of cloud object-store configuration keys/values (e.g.
  `"aws_access_key_id"`, `"aws_endpoint_url"`, `"aws_region"`) for accessing cloud paths
  (`s3://`, `gs://`, `az://`, ...). Omitting it (`nothing`, the default) falls back to the
  provider's standard environment variables / config files (e.g. `~/.aws/credentials`).
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
    compression_level_ref = _nullable_ref(compression_level, Int32)
    row_group_size_ref = _nullable_ref(row_group_size, Csize_t)
    data_page_size_ref = _nullable_ref(data_page_size, Csize_t)

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

Executes the query and writes the result as a Hive-partitioned directory of parquet files (see
[`PartitionByKey`](@ref)), via the streaming engine.

Accepts the same `compression`/`compression_level`/`statistics`/`row_group_size`/`data_page_size`/
`storage_options` keywords as the single-file [`sink_parquet`](@ref) method, plus `maintain_order`
(default `true`).

!!! note
    There is no `mkdir` keyword here: each partition's parent directory is always created
    automatically.
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
    compression_level_ref = _nullable_ref(compression_level, Int32)
    row_group_size_ref = _nullable_ref(row_group_size, Csize_t)
    data_page_size_ref = _nullable_ref(data_page_size, Csize_t)
    max_rows_ref = _nullable_ref(target.max_rows_per_file, UInt64)
    approx_bytes_ref = _nullable_ref(target.approximate_bytes_per_file, UInt64)
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
