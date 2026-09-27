"""
    read_json(path::String)::DataFrame

Read a JSON file containing a top-level array of objects into a `DataFrame`. There is no lazy
`scan_json`; see [`scan_ndjson`](@ref) for newline-delimited JSON.
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

Create a LazyFrame directly from a newline-delimited JSON scan. `path` may be a file, a glob
pattern, or a directory.

- `n_rows`: only scan the first `n_rows` rows.
- `row_index_name`/`row_index_offset`: if `row_index_name` is given, adds a row-index column with
  that name, starting at `row_index_offset`.
- `infer_schema_length`: number of leading rows scanned to infer the schema (`nothing` scans the
  whole file, which is slow).
- `ignore_errors`: turn a per-row schema mismatch into `null` instead of raising.
- `low_memory`: reduce memory usage at the expense of performance.
- `rechunk`: rechunk each file's columns into contiguous memory after reading.
- `include_file_paths`: if given, adds a column with this name containing each row's source path.
- `storage_options`: cloud storage configuration (e.g. `"aws_region" => "us-east-1"`) for
  `s3://`, `gs://`, `az://` paths. By default the provider's environment variables and config
  files are used.
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
    n_rows_ref = n_rows === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(n_rows))
    row_index_name_arg = row_index_name === nothing ? Ptr{UInt8}(C_NULL) : row_index_name
    row_index_name_len = row_index_name === nothing ? 0 : ncodeunits(row_index_name)
    infer_schema_length_ref =
        infer_schema_length === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(infer_schema_length))
    include_file_paths_arg = include_file_paths === nothing ? Ptr{UInt8}(C_NULL) : include_file_paths
    include_file_paths_len = include_file_paths === nothing ? 0 : ncodeunits(include_file_paths)

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

Read a newline-delimited JSON file into a `DataFrame`. Accepts the keywords of
[`scan_ndjson`](@ref).
"""
read_ndjson(path; kwargs...) = collect(scan_ndjson(path; kwargs...))

"""
    write_json(io::IO, df::DataFrame)
    write_json(path::String, df::DataFrame)

Write `df` as a JSON array of objects. A `path` containing `"://"` is an error.
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

Write `df` as newline-delimited JSON. A `path` containing `"://"` is an error; use
[`sink_ndjson`](@ref) for cloud storage.
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

Stream the results of the query to a newline-delimited JSON file, without materializing the full
result in memory.

- `mkdir`: create missing parent directories (default `false`).
- `maintain_order`: preserve row order through the streaming pipeline (default `true`).
- `storage_options`: cloud storage configuration (e.g. `"aws_region" => "us-east-1"`) for
  `s3://`, `gs://`, `az://` paths. By default the provider's environment variables and config
  files are used.
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
