function _quote_style_enum(quote_style::Symbol)
    quote_style == :necessary && return API.PolarsQuoteStyleNecessary
    quote_style == :always && return API.PolarsQuoteStyleAlways
    quote_style == :non_numeric && return API.PolarsQuoteStyleNonNumeric
    quote_style == :never && return API.PolarsQuoteStyleNever
    return error(
        "unknown quote_style $quote_style, expected one of (:necessary, :always, :non_numeric, :never)"
    )
end

function _csv_compression_enum(compression::Symbol)
    compression == :uncompressed && return API.PolarsCsvCompressionUncompressed
    compression == :gzip && return API.PolarsCsvCompressionGzip
    compression == :zstd && return API.PolarsCsvCompressionZstd
    return error(
        "unknown compression $compression, expected one of (:uncompressed, :gzip, :zstd)"
    )
end

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
             allow_missing_columns::Bool=false)::LazyFrame

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

Note: unlike [`scan_parquet`](@ref)/[`scan_ipc`](@ref), CSV scanning has no `hive_partitioning`
option -- the underlying reader doesn't support hive-partition detection.
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
        allow_missing_columns::Bool = false
    )
    n_rows_ref = n_rows === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(n_rows))
    row_index_name_arg = row_index_name === nothing ? Ptr{UInt8}(C_NULL) : row_index_name
    row_index_name_len = row_index_name === nothing ? 0 : ncodeunits(row_index_name)
    quote_char_ref = quote_char === nothing ? Ptr{UInt8}(C_NULL) : Ref(UInt8(quote_char))
    comment_prefix_arg = comment_prefix === nothing ? Ptr{UInt8}(C_NULL) : comment_prefix
    comment_prefix_len = comment_prefix === nothing ? 0 : ncodeunits(comment_prefix)
    null_value_arg = null_value === nothing ? Ptr{UInt8}(C_NULL) : null_value
    null_value_len = null_value === nothing ? 0 : ncodeunits(null_value)
    infer_schema_length_ref = infer_schema_length === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(infer_schema_length))
    include_file_paths_arg = include_file_paths === nothing ? Ptr{UInt8}(C_NULL) : include_file_paths
    include_file_paths_len = include_file_paths === nothing ? 0 : ncodeunits(include_file_paths)

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = GC.@preserve n_rows_ref quote_char_ref infer_schema_length_ref begin
        polars_lazy_frame_scan_csv(
            path, length(path), n_rows_ref, row_index_name_arg, row_index_name_len,
            UInt32(row_index_offset), has_header, UInt8(separator), quote_char_ref,
            comment_prefix_arg, comment_prefix_len, Csize_t(skip_rows),
            Csize_t(skip_rows_after_header), null_value_arg, null_value_len, missing_is_null,
            truncate_ragged_lines, try_parse_dates, infer_schema_length_ref, ignore_errors,
            low_memory, rechunk, cache, glob, include_file_paths_arg, include_file_paths_len,
            allow_missing_columns, out
        )
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

Note: unlike [`write_parquet`](@ref), `write_csv` has no `compression` option -- only
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
    null_value_arg = null_value === nothing ? Ptr{UInt8}(C_NULL) : null_value
    null_value_len = null_value === nothing ? 0 : ncodeunits(null_value)
    line_terminator_arg = line_terminator === nothing ? Ptr{UInt8}(C_NULL) : line_terminator
    line_terminator_len = line_terminator === nothing ? 0 : ncodeunits(line_terminator)
    date_format_arg = date_format === nothing ? Ptr{UInt8}(C_NULL) : date_format
    date_format_len = date_format === nothing ? 0 : ncodeunits(date_format)
    time_format_arg = time_format === nothing ? Ptr{UInt8}(C_NULL) : time_format
    time_format_len = time_format === nothing ? 0 : ncodeunits(time_format)
    datetime_format_arg = datetime_format === nothing ? Ptr{UInt8}(C_NULL) : datetime_format
    datetime_format_len = datetime_format === nothing ? 0 : ncodeunits(datetime_format)
    float_precision_ref = float_precision === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(float_precision))
    quote_style_enum = _quote_style_enum(quote_style)

    callback = @cfunction(_write_callback, Cssize_t, (Any, Ptr{Cchar}, Cuint))
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
write_csv(p::String, df::DataFrame; kwargs...) = open(io -> write_csv(io, df; kwargs...), p, "w")

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
        maintain_order::Bool = true
    )
    null_value_arg = null_value === nothing ? Ptr{UInt8}(C_NULL) : null_value
    null_value_len = null_value === nothing ? 0 : ncodeunits(null_value)
    line_terminator_arg = line_terminator === nothing ? Ptr{UInt8}(C_NULL) : line_terminator
    line_terminator_len = line_terminator === nothing ? 0 : ncodeunits(line_terminator)
    date_format_arg = date_format === nothing ? Ptr{UInt8}(C_NULL) : date_format
    date_format_len = date_format === nothing ? 0 : ncodeunits(date_format)
    time_format_arg = time_format === nothing ? Ptr{UInt8}(C_NULL) : time_format
    time_format_len = time_format === nothing ? 0 : ncodeunits(time_format)
    datetime_format_arg = datetime_format === nothing ? Ptr{UInt8}(C_NULL) : datetime_format
    datetime_format_len = datetime_format === nothing ? 0 : ncodeunits(datetime_format)
    float_precision_ref = float_precision === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(float_precision))
    quote_style_enum = _quote_style_enum(quote_style)
    compression_enum = _csv_compression_enum(compression)
    compression_level_ref = compression_level === nothing ? Ptr{UInt32}(C_NULL) : Ref(UInt32(compression_level))

    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = GC.@preserve float_precision_ref compression_level_ref begin
        polars_lazy_frame_sink_csv(
            lf, path, length(path), include_header, include_bom, UInt8(separator),
            UInt8(quote_char), null_value_arg, null_value_len, line_terminator_arg,
            line_terminator_len, quote_style_enum, date_format_arg, date_format_len,
            time_format_arg, time_format_len, datetime_format_arg, datetime_format_len,
            float_precision_ref, decimal_comma, compression_enum, compression_level_ref, mkdir,
            maintain_order, out
        )
    end
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end
