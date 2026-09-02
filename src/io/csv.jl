_quote_style_enum(quote_style::Symbol) = _enum_lookup(
    quote_style, "quote_style",
    :necessary => API.PolarsQuoteStyleNecessary, :always => API.PolarsQuoteStyleAlways,
    :non_numeric => API.PolarsQuoteStyleNonNumeric, :never => API.PolarsQuoteStyleNever,
)

_csv_compression_enum(compression::Symbol) = _enum_lookup(
    compression, "compression",
    :uncompressed => API.PolarsCsvCompressionUncompressed, :gzip => API.PolarsCsvCompressionGzip,
    :zstd => API.PolarsCsvCompressionZstd,
)

"""
    scan_csv(path::String;
             n_rows::Union{Nothing,Integer}=nothing,
             row_index_name::Union{Nothing,AbstractString}=nothing,
             row_index_offset::Integer=0,
             has_header::Bool=true,
             separator::Char=',',
             quote_char::Union{Nothing,Char}='"',
             comment_prefix::Union{Nothing,AbstractString}=nothing,
             skip_rows::Integer=0,
             skip_rows_after_header::Integer=0,
             null_value::Union{Nothing,AbstractString}=nothing,
             missing_is_null::Bool=true,
             truncate_ragged_lines::Bool=false,
             try_parse_dates::Bool=false,
             infer_schema_length::Union{Nothing,Integer}=100,
             ignore_errors::Bool=false,
             low_memory::Bool=false,
             rechunk::Bool=false,
             cache::Bool=true,
             glob::Bool=true,
             include_file_paths::Union{Nothing,AbstractString}=nothing,
             allow_missing_columns::Bool=false,
             storage_options::Union{Nothing,AbstractDict{<:AbstractString,<:AbstractString}}=nothing)::LazyFrame

Lazily scans a CSV file, glob pattern, or directory of CSV files, without reading it into memory.

- `n_rows`: only scan the first `n_rows` rows.
- `row_index_name`/`row_index_offset`: if `row_index_name` is given, adds a row-index column with
  that name, starting at `row_index_offset`.
- `has_header`: whether the file has a header row.
- `separator`/`quote_char`: field separator and quote character (`quote_char = nothing` disables
  quote parsing entirely).
- `comment_prefix`: lines starting with this prefix are ignored.
- `skip_rows`/`skip_rows_after_header`: skip this many rows before/after the header.
- `null_value`: a single string value (e.g. `"NA"`) to interpret as null across every column.
- `missing_is_null`: treat missing (short-row) fields as null.
- `truncate_ragged_lines`: truncate lines longer than the schema instead of erroring.
- `try_parse_dates`: attempt to parse date/datetime/time columns automatically.
- `infer_schema_length`: rows to sample for schema inference (`nothing` does a full scan).
- `ignore_errors`: continue with the next batch when a parse error is encountered.
- `low_memory`: trade speed for lower peak memory use.
- `rechunk`: rechunk each file's columns into contiguous memory after reading.
- `cache`: cache the result of the scan (only relevant if reused within the same plan).
- `glob`: expand `path` as a glob pattern.
- `include_file_paths`: if given, adds a column with this name containing each row's source path.
- `allow_missing_columns`: allow columns present in some files but not others (filled with nulls).
- `storage_options`: a `Dict` of cloud object-store configuration keys/values (e.g.
  `"aws_access_key_id"`, `"aws_endpoint_url"`, `"aws_region"`) for accessing cloud paths
  (`s3://`, `gs://`, `az://`, ...). Omitting it (`nothing`, the default) falls back to the
  provider's standard environment variables / config files (e.g. `~/.aws/credentials`).

!!! note
    Unlike [`scan_parquet`](@ref)/[`scan_ipc`](@ref), CSV scanning has no `hive_partitioning`
    option.
"""
function scan_csv(
        path;
        n_rows::Union{Nothing, Integer} = nothing,
        row_index_name::Union{Nothing, AbstractString} = nothing,
        row_index_offset::Integer = 0,
        has_header::Bool = true,
        separator::Char = ',',
        quote_char::Union{Nothing, Char} = '"',
        comment_prefix::Union{Nothing, AbstractString} = nothing,
        skip_rows::Integer = 0,
        skip_rows_after_header::Integer = 0,
        null_value::Union{Nothing, AbstractString} = nothing,
        missing_is_null::Bool = true,
        truncate_ragged_lines::Bool = false,
        try_parse_dates::Bool = false,
        infer_schema_length::Union{Nothing, Integer} = 100,
        ignore_errors::Bool = false,
        low_memory::Bool = false,
        rechunk::Bool = false,
        cache::Bool = true,
        glob::Bool = true,
        include_file_paths::Union{Nothing, AbstractString} = nothing,
        allow_missing_columns::Bool = false,
        storage_options::Union{Nothing, AbstractDict{<:AbstractString, <:AbstractString}} = nothing
    )
    n_rows_ref = _nullable_ref(n_rows, Csize_t)
    row_index_name_arg, row_index_name_len = _nullable_str(row_index_name)
    quote_char_ref = _nullable_ref(quote_char, UInt8)
    comment_prefix_arg, comment_prefix_len = _nullable_str(comment_prefix)
    null_value_arg, null_value_len = _nullable_str(null_value)
    infer_schema_length_ref = _nullable_ref(infer_schema_length, Csize_t)
    include_file_paths_arg, include_file_paths_len = _nullable_str(include_file_paths)

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = _with_cloud_options(storage_options) do cloud_options
        GC.@preserve n_rows_ref quote_char_ref infer_schema_length_ref begin
            polars_lazy_frame_scan_csv(
                path, ncodeunits(path), n_rows_ref, row_index_name_arg, row_index_name_len,
                UInt32(row_index_offset), has_header, UInt8(separator), quote_char_ref,
                comment_prefix_arg, comment_prefix_len, Csize_t(skip_rows),
                Csize_t(skip_rows_after_header), null_value_arg, null_value_len, missing_is_null,
                truncate_ragged_lines, try_parse_dates, infer_schema_length_ref, ignore_errors,
                low_memory, rechunk, cache, glob, include_file_paths_arg, include_file_paths_len,
                allow_missing_columns, cloud_options, out
            )
        end
    end
    polars_error(err)
    return LazyFrame(out[])
end

"""
    read_csv(path::String; kwargs...)::DataFrame

Reads a dataframe stored in a CSV file. Accepts the same keyword options as [`scan_csv`](@ref).
"""
read_csv(path; kwargs...) = collect(scan_csv(path; kwargs...))

"""
    write_csv(io::IO, df::DataFrame;
              include_header::Bool=true,
              include_bom::Bool=false,
              separator::Char=',',
              quote_char::Char='"',
              null_value::Union{Nothing,AbstractString}=nothing,
              line_terminator::Union{Nothing,AbstractString}=nothing,
              quote_style::Symbol=:necessary,
              date_format::Union{Nothing,AbstractString}=nothing,
              time_format::Union{Nothing,AbstractString}=nothing,
              datetime_format::Union{Nothing,AbstractString}=nothing,
              float_precision::Union{Nothing,Integer}=nothing,
              decimal_comma::Bool=false)
    write_csv(path::String, df::DataFrame; kwargs...)

Writes a dataframe to a CSV file provided as an `IO`.

- `include_header`/`include_bom`: whether to write a header row / UTF-8 byte-order mark.
- `separator`/`quote_char`: field separator and quote character.
- `null_value`: string written for null values (default empty string).
- `line_terminator`: string appended after every row (default `"\\n"`).
- `quote_style`: when to quote fields — one of `:necessary` (default), `:always`, `:non_numeric`,
  `:never`.
- `date_format`/`time_format`/`datetime_format`: `chrono`-style format strings for those dtypes
  (default: `chrono`'s own default formatting).
- `float_precision`: number of digits after the decimal point for floats.
- `decimal_comma`: use a comma as the decimal separator instead of a period.

For the `path::String` method, a path containing `"://"` (e.g. `"s3://bucket/out.csv"`) is
rejected with an error pointing at [`sink_csv`](@ref) instead of silently writing a local file.

!!! note
    Unlike [`write_parquet`](@ref), `write_csv` has no `compression` option -- only
    [`sink_csv`](@ref) supports writing compressed CSV.
"""
function write_csv(
        io::IO, df::DataFrame;
        include_header::Bool = true,
        include_bom::Bool = false,
        separator::Char = ',',
        quote_char::Char = '"',
        null_value::Union{Nothing, AbstractString} = nothing,
        line_terminator::Union{Nothing, AbstractString} = nothing,
        quote_style::Symbol = :necessary,
        date_format::Union{Nothing, AbstractString} = nothing,
        time_format::Union{Nothing, AbstractString} = nothing,
        datetime_format::Union{Nothing, AbstractString} = nothing,
        float_precision::Union{Nothing, Integer} = nothing,
        decimal_comma::Bool = false
    )
    null_value_arg, null_value_len = _nullable_str(null_value)
    line_terminator_arg, line_terminator_len = _nullable_str(line_terminator)
    date_format_arg, date_format_len = _nullable_str(date_format)
    time_format_arg, time_format_len = _nullable_str(time_format)
    datetime_format_arg, datetime_format_len = _nullable_str(datetime_format)
    float_precision_ref = _nullable_ref(float_precision, Csize_t)
    quote_style_enum = _quote_style_enum(quote_style)

    callback = _io_callback()
    ref = Ref(io)
    err = GC.@preserve float_precision_ref begin
        polars_dataframe_write_csv(
            df, ref, callback, include_header, include_bom, UInt8(separator), UInt8(quote_char),
            null_value_arg, null_value_len, line_terminator_arg, line_terminator_len,
            quote_style_enum, date_format_arg, date_format_len, time_format_arg, time_format_len,
            datetime_format_arg, datetime_format_len, float_precision_ref, decimal_comma
        )
    end
    polars_error(err)
    return nothing
end
@wrap_path_writer write_csv "write_csv writes local files; use sink_csv for cloud URIs"

"""
    sink_csv(lf::LazyFrame, path::String; kwargs..., compression::Symbol=:uncompressed,
             compression_level::Union{Nothing,Integer}=nothing, mkdir::Bool=false,
             maintain_order::Bool=true)
    sink_csv(df::DataFrame, path::String; kwargs...)

Executes the query and writes the result directly to a CSV file via the streaming engine, without
materializing the full result in memory.

Accepts the same formatting keywords as [`write_csv`](@ref), plus:
- `compression`: one of `:uncompressed` (default), `:gzip`, `:zstd`. `compression_level` tunes the
  chosen algorithm (gzip/zstd only).
- `mkdir`: create missing parent directories (default `false`).
- `maintain_order`: preserve row order through the streaming pipeline (default `true`).
- `storage_options`: a `Dict` of cloud object-store configuration keys/values (e.g.
  `"aws_access_key_id"`, `"aws_endpoint_url"`, `"aws_region"`) for accessing cloud paths
  (`s3://`, `gs://`, `az://`, ...). Omitting it (`nothing`, the default) falls back to the
  provider's standard environment variables / config files (e.g. `~/.aws/credentials`).
"""
sink_csv(df::DataFrame, path::String; kwargs...) = sink_csv(lazy(df), path; kwargs...)
function sink_csv(
        lf::LazyFrame, path::String;
        include_header::Bool = true,
        include_bom::Bool = false,
        separator::Char = ',',
        quote_char::Char = '"',
        null_value::Union{Nothing, AbstractString} = nothing,
        line_terminator::Union{Nothing, AbstractString} = nothing,
        quote_style::Symbol = :necessary,
        date_format::Union{Nothing, AbstractString} = nothing,
        time_format::Union{Nothing, AbstractString} = nothing,
        datetime_format::Union{Nothing, AbstractString} = nothing,
        float_precision::Union{Nothing, Integer} = nothing,
        decimal_comma::Bool = false,
        compression::Symbol = :uncompressed,
        compression_level::Union{Nothing, Integer} = nothing,
        mkdir::Bool = false,
        maintain_order::Bool = true,
        storage_options::Union{Nothing, AbstractDict{<:AbstractString, <:AbstractString}} = nothing
    )
    null_value_arg, null_value_len = _nullable_str(null_value)
    line_terminator_arg, line_terminator_len = _nullable_str(line_terminator)
    date_format_arg, date_format_len = _nullable_str(date_format)
    time_format_arg, time_format_len = _nullable_str(time_format)
    datetime_format_arg, datetime_format_len = _nullable_str(datetime_format)
    float_precision_ref = _nullable_ref(float_precision, Csize_t)
    quote_style_enum = _quote_style_enum(quote_style)
    compression_enum = _csv_compression_enum(compression)
    compression_level_ref = _nullable_ref(compression_level, UInt32)

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = _with_cloud_options(storage_options) do cloud_options
        GC.@preserve float_precision_ref compression_level_ref begin
            polars_lazy_frame_sink_csv(
                lf, path, ncodeunits(path), include_header, include_bom, UInt8(separator),
                UInt8(quote_char), null_value_arg, null_value_len, line_terminator_arg,
                line_terminator_len, quote_style_enum, date_format_arg, date_format_len,
                time_format_arg, time_format_len, datetime_format_arg, datetime_format_len,
                float_precision_ref, decimal_comma, compression_enum, compression_level_ref, mkdir,
                maintain_order, cloud_options, out
            )
        end
    end
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end
