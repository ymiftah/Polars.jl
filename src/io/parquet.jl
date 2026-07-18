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
                 include_file_paths::Union{Nothing,AbstractString}=nothing,
                 hive_partitioning::Union{Nothing,Bool}=nothing)::LazyFrame

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
- `include_file_paths`: if given, adds a column with this name containing each row's source path.
- `hive_partitioning`: force Hive-style partition-column detection on (`true`) or off (`false`);
  `nothing` (default) auto-detects.
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
        include_file_paths::Union{Nothing, AbstractString} = nothing,
        hive_partitioning::Union{Nothing, Bool} = nothing
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

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = GC.@preserve n_rows_ref hive_partitioning_ref begin
        polars_lazy_frame_scan_parquet(
            path, ncodeunits(path), n_rows_ref, row_index_name_arg, row_index_name_len,
            UInt32(row_index_offset), parallel_enum, low_memory, rechunk, cache, glob,
            use_statistics, allow_missing_columns, include_file_paths_arg, include_file_paths_len,
            hive_partitioning_ref, out
        )
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

Writes a dataframe to a parquet file provided as an `IO`.

- `compression`: one of `:zstd` (default), `:snappy`, `:gzip`, `:brotli`, `:lz4_raw`,
  `:uncompressed`.
- `compression_level`: tunes the chosen algorithm's compression level. Only valid for
  `:gzip`/`:brotli`/`:zstd` — an error for the others.
- `statistics`: whether to compute and write column statistics (default `true`).
- `row_group_size`: maximum rows per row group (default: a single row group).
- `data_page_size`: maximum bytes per data page (default: polars' own default, ~1 MiB).
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
write_parquet(p::String, df::DataFrame; kwargs...) = open(io -> write_parquet(io, df; kwargs...), p, "w")
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
        maintain_order::Bool = true
    )
    compression_enum = _parquet_compression_enum(compression)
    compression_level_ref = compression_level === nothing ? Ptr{Int32}(C_NULL) :
        Ref(Int32(compression_level))
    row_group_size_ref = row_group_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(row_group_size))
    data_page_size_ref = data_page_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(data_page_size))

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = GC.@preserve compression_level_ref row_group_size_ref data_page_size_ref begin
        polars_lazy_frame_sink_parquet(
            lf, path, ncodeunits(path), compression_enum, compression_level_ref, statistics,
            row_group_size_ref, data_page_size_ref, mkdir, maintain_order, out
        )
    end
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end
