"""
    read_json(path::String)::DataFrame

Reads a JSON file containing a single top-level array of objects into a `DataFrame`. Unlike
[`read_parquet`](@ref)/[`read_csv`](@ref)/[`read_ipc`](@ref), this has no lazy `scan_json`
counterpart -- plain JSON has no polars streaming reader upstream either, since the whole array
must be parsed before its shape is known. For a streamable, one-object-per-line format, see
[`read_ndjson`](@ref)/[`scan_ndjson`](@ref).
"""
function read_json(path::String)
    out = Ref{Ptr{polars_dataframe_t}}()
    err = polars_dataframe_read_json(path, ncodeunits(path), out)
    polars_error(err)
    return DataFrame(out[])
end

"""
    scan_ndjson(path::String;
                n_rows::Union{Nothing,Integer}=nothing,
                row_index_name::Union{Nothing,AbstractString}=nothing,
                row_index_offset::Integer=0,
                infer_schema_length::Union{Nothing,Integer}=100,
                ignore_errors::Bool=false,
                low_memory::Bool=false,
                rechunk::Bool=false,
                include_file_paths::Union{Nothing,AbstractString}=nothing,
                storage_options::Union{Nothing,AbstractDict{<:AbstractString,<:AbstractString}}=nothing)::LazyFrame

Lazily scans a newline-delimited JSON (NDJSON/JSON Lines) file, glob pattern, or directory, without
reading it into memory.

- `n_rows`: only scan the first `n_rows` rows.
- `row_index_name`/`row_index_offset`: if `row_index_name` is given, adds a row-index column with
  that name, starting at `row_index_offset`.
- `infer_schema_length`: number of leading rows scanned to infer the schema (`nothing` scans the
  whole file, which is slow).
- `ignore_errors`: turn a per-row schema mismatch into `null` instead of raising.
- `low_memory`: reduce memory usage at the expense of performance.
- `rechunk`: rechunk each file's columns into contiguous memory after reading.
- `include_file_paths`: if given, adds a column with this name containing each row's source path.
- `storage_options`: a `Dict` of cloud object-store configuration keys/values (e.g.
  `"aws_access_key_id"`, `"aws_endpoint_url"`, `"aws_region"`) for accessing cloud paths
  (`s3://`, `gs://`, `az://`, ...). Omitting it (`nothing`, the default) falls back to the
  provider's standard environment variables / config files (e.g. `~/.aws/credentials`).
"""
function scan_ndjson(
        path;
        n_rows::Union{Nothing, Integer} = nothing,
        row_index_name::Union{Nothing, AbstractString} = nothing,
        row_index_offset::Integer = 0,
        infer_schema_length::Union{Nothing, Integer} = 100,
        ignore_errors::Bool = false,
        low_memory::Bool = false,
        rechunk::Bool = false,
        include_file_paths::Union{Nothing, AbstractString} = nothing,
        storage_options::Union{Nothing, AbstractDict{<:AbstractString, <:AbstractString}} = nothing
    )
    n_rows_ref = _nullable_ref(n_rows, Csize_t)
    row_index_name_arg, row_index_name_len = _nullable_str(row_index_name)
    infer_schema_length_ref = _nullable_ref(infer_schema_length, Csize_t)
    include_file_paths_arg, include_file_paths_len = _nullable_str(include_file_paths)

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = _with_cloud_options(storage_options) do cloud_options
        GC.@preserve n_rows_ref infer_schema_length_ref begin
            polars_lazy_frame_scan_ndjson(
                path, ncodeunits(path), n_rows_ref, row_index_name_arg, row_index_name_len,
                UInt32(row_index_offset), infer_schema_length_ref, ignore_errors, low_memory,
                rechunk, include_file_paths_arg, include_file_paths_len, cloud_options, out
            )
        end
    end
    polars_error(err)
    return LazyFrame(out[])
end

"""
    read_ndjson(path::String; kwargs...)::DataFrame

Reads a newline-delimited JSON (NDJSON/JSON Lines) file into a `DataFrame`. Accepts the same
keyword options as [`scan_ndjson`](@ref).
"""
read_ndjson(path; kwargs...) = collect(scan_ndjson(path; kwargs...))

"""
    write_json(io::IO, df::DataFrame)
    write_json(path::String, df::DataFrame)

Writes `df` as a single top-level JSON array of objects.

For the `path::String` method, a path containing `"://"` (e.g. `"s3://bucket/out.json"`) is
rejected with an error -- there is no cloud-sink counterpart for plain JSON (matching upstream:
only NDJSON has a streaming sink, see [`sink_ndjson`](@ref)).
"""
function write_json(io::IO, df::DataFrame)
    callback = _io_callback()
    ref = Ref(io)
    err = polars_dataframe_write_json(df, ref, callback)
    polars_error(err)
    return nothing
end
function write_json(p::String, df::DataFrame)
    occursin("://", p) && error("write_json writes local files only; there is no cloud sink for plain JSON")
    return open(io -> write_json(io, df), p, "w")
end

"""
    write_ndjson(io::IO, df::DataFrame)
    write_ndjson(path::String, df::DataFrame)

Writes `df` as newline-delimited JSON (NDJSON/JSON Lines).

For the `path::String` method, a path containing `"://"` (e.g. `"s3://bucket/out.jsonl"`) is
rejected with an error pointing at [`sink_ndjson`](@ref) instead of silently writing a local file.
"""
function write_ndjson(io::IO, df::DataFrame)
    callback = _io_callback()
    ref = Ref(io)
    err = polars_dataframe_write_ndjson(df, ref, callback)
    polars_error(err)
    return nothing
end
function write_ndjson(p::String, df::DataFrame)
    occursin("://", p) && error("write_ndjson writes local files; use sink_ndjson for cloud URIs")
    return open(io -> write_ndjson(io, df), p, "w")
end

"""
    sink_ndjson(lf::LazyFrame, path::String; kwargs...)
    sink_ndjson(df::DataFrame, path::String; kwargs...)

Executes the query and writes the result directly to a newline-delimited JSON (NDJSON) file via
the streaming engine, without materializing the full result in memory.

- `mkdir`: create missing parent directories (default `false`).
- `maintain_order`: preserve row order through the streaming pipeline (default `true`).
- `storage_options`: a `Dict` of cloud object-store configuration keys/values (e.g.
  `"aws_access_key_id"`, `"aws_endpoint_url"`, `"aws_region"`) for accessing cloud paths
  (`s3://`, `gs://`, `az://`, ...). Omitting it (`nothing`, the default) falls back to the
  provider's standard environment variables / config files (e.g. `~/.aws/credentials`).
"""
sink_ndjson(df::DataFrame, path::String; kwargs...) = sink_ndjson(lazy(df), path; kwargs...)
function sink_ndjson(
        lf::LazyFrame, path::String;
        mkdir::Bool = false,
        maintain_order::Bool = true,
        storage_options::Union{Nothing, AbstractDict{<:AbstractString, <:AbstractString}} = nothing
    )
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = _with_cloud_options(storage_options) do cloud_options
        polars_lazy_frame_sink_ndjson(lf, path, ncodeunits(path), mkdir, maintain_order, cloud_options, out)
    end
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end
