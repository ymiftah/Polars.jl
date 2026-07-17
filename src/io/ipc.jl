function _ipc_compression_enum(compression::Symbol)
    compression == :uncompressed && return API.PolarsIpcCompressionUncompressed
    compression == :lz4 && return API.PolarsIpcCompressionLz4
    compression == :zstd && return API.PolarsIpcCompressionZstd
    return error(
        "unknown compression $compression, expected one of (:uncompressed, :lz4, :zstd)"
    )
end

"""
    scan_ipc(path::String;
             n_rows::Union{Nothing,Integer}=nothing,
             row_index_name::Union{Nothing,AbstractString}=nothing,
             row_index_offset::Integer=0,
             rechunk::Bool=false,
             cache::Bool=true,
             glob::Bool=true,
             include_file_paths::Union{Nothing,AbstractString}=nothing,
             hive_partitioning::Union{Nothing,Bool}=nothing,
             allow_missing_columns::Bool=false)::LazyFrame

Lazily scans an Arrow IPC (Feather) file, glob pattern, or directory of (optionally
Hive-partitioned) IPC files, without reading it into memory.

- `n_rows`: only scan the first `n_rows` rows.
- `row_index_name`/`row_index_offset`: if `row_index_name` is given, adds a row-index column with
  that name, starting at `row_index_offset`.
- `rechunk`: rechunk each file's columns into contiguous memory after reading.
- `cache`: cache the result of the scan (only relevant if reused within the same plan).
- `glob`: expand `path` as a glob pattern.
- `include_file_paths`: if given, adds a column with this name containing each row's source path.
- `hive_partitioning`: force Hive-style partition-column detection on (`true`) or off (`false`);
  `nothing` (default) auto-detects.
- `allow_missing_columns`: allow columns present in some files but not others (filled with nulls).
"""
function scan_ipc(
        path;
        n_rows::Union{Nothing, Integer} = nothing,
        row_index_name::Union{Nothing, AbstractString} = nothing,
        row_index_offset::Integer = 0,
        rechunk::Bool = false,
        cache::Bool = true,
        glob::Bool = true,
        include_file_paths::Union{Nothing, AbstractString} = nothing,
        hive_partitioning::Union{Nothing, Bool} = nothing,
        allow_missing_columns::Bool = false
    )
    n_rows_ref = n_rows === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(n_rows))
    row_index_name_arg = row_index_name === nothing ? Ptr{UInt8}(C_NULL) : row_index_name
    row_index_name_len = row_index_name === nothing ? 0 : ncodeunits(row_index_name)
    include_file_paths_arg = include_file_paths === nothing ? Ptr{UInt8}(C_NULL) : include_file_paths
    include_file_paths_len = include_file_paths === nothing ? 0 : ncodeunits(include_file_paths)
    hive_partitioning_ref = hive_partitioning === nothing ? Ptr{Bool}(C_NULL) : Ref(hive_partitioning)

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = GC.@preserve n_rows_ref hive_partitioning_ref begin
        polars_lazy_frame_scan_ipc(
            path, length(path), n_rows_ref, row_index_name_arg, row_index_name_len,
            UInt32(row_index_offset), rechunk, cache, glob, include_file_paths_arg,
            include_file_paths_len, hive_partitioning_ref, allow_missing_columns, out
        )
    end
    polars_error(err)
    return LazyFrame(out[])
end

"""
    read_ipc(path::String; kwargs...)::DataFrame

Reads a dataframe stored in an Arrow IPC (Feather) file. Accepts the same keyword options as
[`scan_ipc`](@ref).
"""
read_ipc(path; kwargs...) = collect(scan_ipc(path; kwargs...))

"""
    write_ipc(io::IO, df::DataFrame;
              compression::Symbol=:uncompressed,
              compression_level::Union{Nothing,Integer}=nothing,
              record_batch_size::Union{Nothing,Integer}=nothing)
    write_ipc(path::String, df::DataFrame; kwargs...)

Writes a dataframe to an Arrow IPC (Feather) file provided as an `IO`.

- `compression`: one of `:uncompressed` (default), `:lz4`, `:zstd`. `compression_level` tunes zstd
  (ignored/rejected for the others).
- `record_batch_size`: number of rows per record batch (default: polars' own default).
"""
function write_ipc(
        io::IO, df::DataFrame;
        compression::Symbol = :uncompressed,
        compression_level::Union{Nothing, Integer} = nothing,
        record_batch_size::Union{Nothing, Integer} = nothing
    )
    compression_enum = _ipc_compression_enum(compression)
    compression_level_ref = compression_level === nothing ? Ptr{Int32}(C_NULL) : Ref(Int32(compression_level))
    record_batch_size_ref = record_batch_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(record_batch_size))

    callback = @cfunction(_write_callback, Cssize_t, (Any, Ptr{Cchar}, Cuint))
    ref = Ref(io)
    err = GC.@preserve compression_level_ref record_batch_size_ref begin
        polars_dataframe_write_ipc(
            df, ref, callback, compression_enum, compression_level_ref, record_batch_size_ref
        )
    end
    polars_error(err)
    return nothing
end
write_ipc(p::String, df::DataFrame; kwargs...) = open(io -> write_ipc(io, df; kwargs...), p, "w")

"""
    sink_ipc(lf::LazyFrame, path::String; kwargs...)
    sink_ipc(df::DataFrame, path::String; kwargs...)

Executes the query and writes the result directly to an Arrow IPC (Feather) file via the streaming
engine, without materializing the full result in memory.

Accepts the same `compression`/`compression_level`/`record_batch_size` keywords as
[`write_ipc`](@ref), plus:
- `mkdir`: create missing parent directories (default `false`).
- `maintain_order`: preserve row order through the streaming pipeline (default `true`).
"""
sink_ipc(df::DataFrame, path::String; kwargs...) = sink_ipc(lazy(df), path; kwargs...)
function sink_ipc(
        lf::LazyFrame, path::String;
        compression::Symbol = :uncompressed,
        compression_level::Union{Nothing, Integer} = nothing,
        record_batch_size::Union{Nothing, Integer} = nothing,
        mkdir::Bool = false,
        maintain_order::Bool = true
    )
    compression_enum = _ipc_compression_enum(compression)
    compression_level_ref = compression_level === nothing ? Ptr{Int32}(C_NULL) : Ref(Int32(compression_level))
    record_batch_size_ref = record_batch_size === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(record_batch_size))

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = GC.@preserve compression_level_ref record_batch_size_ref begin
        polars_lazy_frame_sink_ipc(
            lf, path, length(path), compression_enum, compression_level_ref,
            record_batch_size_ref, mkdir, maintain_order, out
        )
    end
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end
