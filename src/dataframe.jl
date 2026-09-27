mutable struct DataFrame
    ptr::Ptr{polars_dataframe_t}
    # Column names, cached on first use; a handle's columns never change.
    column_names::Union{Nothing, Tuple{Vararg{Symbol}}}

    DataFrame(ptr::Ptr{polars_dataframe_t}) =
        finalizer(polars_dataframe_destroy, new(ptr, nothing))
end

"""
    DataFrame(table)

A contiguous growable collection of `Series` that have the same length. Built from any
Tables.jl-compatible `table`.
"""
function DataFrame(table)
    array, schema = Polars.arrowtable(table, "polars.dataframe")
    try
        out = Ref{Ptr{polars_dataframe_t}}()
        err = API.polars_dataframe_new_from_carrow(schema, array, out)
        # Rust takes ownership of `array` (passed by value) on success and failure alike.
        _mark_released!(Base.unsafe_convert(Ptr{API.ArrowArray}, array))
        # On failure Rust has already released `array`; `release_array!` is an idempotent unroot.
        try
            polars_error(err)
        catch
            release_array!(array)
            rethrow()
        end
        return DataFrame(out[])
    finally
        release_schema!(schema)
    end
end

"""
    DataFrame(series::AbstractVector{<:Series})

Create a `DataFrame` from a vector of `Series`, one per column. An unnamed series is named
`"column_i"` (0-based `i`). Duplicate names are an error.
"""
function DataFrame(series::AbstractVector{<:Series})
    GC.@preserve series begin
        ptrs = Ptr{polars_series_t}[s.ptr for s in series]
        out = Ref{Ptr{polars_dataframe_t}}()
        err = API.polars_dataframe_new_from_series(ptrs, length(ptrs), out)
        polars_error(err)
        return DataFrame(out[])
    end
end

function Base.size(df::DataFrame)
    rows, cols = Ref{Csize_t}(), Ref{Csize_t}()
    API.polars_dataframe_size(df, rows, cols)
    return (Int(rows[]), Int(cols[]))
end
Base.size(df::DataFrame, dim::Integer) = size(df)[dim]

"""
    Polars.item(df::DataFrame)
    Polars.item(df::DataFrame, row::Integer, col)

Return the sole value of a 1×1 `df`, or the value at `row` and `col` (an index or a name).
"""
function item(df::DataFrame)
    sz = size(df)
    sz == (1, 1) || error("item() requires a DataFrame of shape (1, 1), got shape $sz")
    return df[1, 1]
end
item(df::DataFrame, row::Integer, col) = getindex(df, row, col)

Base.getindex(df::DataFrame, row_index, col_index) = getindex(getindex(df, col_index), row_index)
Base.getindex(df::DataFrame, idx::Int) = Tables.getcolumn(df, idx)
function Base.getindex(df::DataFrame, name::AbstractString)
    s = String(name)
    out = Ref{Ptr{polars_series_t}}()
    err = polars_dataframe_get(df, s, ncodeunits(s), out)
    polars_error(err)
    return Series(out[])
end
Base.getindex(df::DataFrame, s::Symbol) = getindex(df, String(s))

struct _NoDefault end
# Sentinel, since `default = nothing` is a valid value.
const _NO_DEFAULT = _NoDefault()

"""
    get_column(df::DataFrame, name::Union{AbstractString,Symbol})::Series
    get_column(df::DataFrame, name::Union{AbstractString,Symbol}; default)

Select a single column by name. Same as `df[name]`.

If `default` is given, it is returned for a missing column instead of an error.
"""
function get_column(df::DataFrame, name::Union{AbstractString, Symbol}; default = _NO_DEFAULT)
    try
        return df[name]
    catch e
        (e isa PolarsError && default !== _NO_DEFAULT) || rethrow()
        return default
    end
end

Base.unsafe_convert(::Type{Ptr{polars_dataframe_t}}, df::DataFrame) = df.ptr
Base.summary(df::DataFrame) = join(size(df), '×') * " DataFrame"

"""
    Base.collect(df::DataFrame)

Always raises: a `DataFrame` is already materialized. Use `collect(df[name])` for one column,
`collect(lazy(df))` to run a query, or `Tables.columns(df)` to iterate the columns.
"""
Base.collect(df::DataFrame) = throw(
    ArgumentError(
        "a DataFrame is already materialized -- there is nothing to collect. Use " *
            "`collect(df[name])` for one column as a Vector, `Tables.columns(df)` to iterate " *
            "the columns, or `collect(lazy(df))` to run a query."
    )
)

"""
    native_repr(df::DataFrame)::String

Format `df` with polars' own `Display` implementation.
"""
function native_repr(df::DataFrame)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = API.polars_dataframe_show(df, io, callback)
    polars_error(err)
    return String(take!(io[]))
end

function _pretty_tables_highlighter_func(data, i::Integer, j::Integer)
    try
        cell = data[i, j]
        return ismissing(cell) ||
            cell === nothing
    catch e
        if isa(e, UndefRefError)
            return true
        else
            rethrow(e)
        end
    end
end

# Compact form for `print`/`string` and nested display; the full table is `MIME"text/plain"`.
Base.show(io::IO, df::DataFrame) = print(io, Base.summary(df))

function Base.show(io::IO, ::MIME"text/plain", df::DataFrame)
    # PrettyTables setup adapted from DataFrames.jl:
    # https://github.com/JuliaData/DataFrames.jl/blob/e341cc7873a08977cc8e4d56f28303883582c920/src/abstractdataframe/show.jl#L253-L279
    format =
        PrettyTables.TextTableFormat(;
        PrettyTables.@text__no_horizontal_lines,
        PrettyTables.@text__no_vertical_lines,
        ellipsis_line_skip = 3,
        horizontal_line_after_column_labels = true,
        horizontal_line_before_summary_rows = true,
        vertical_line_after_row_label_column = true,
        vertical_line_after_row_number_column = true
    )

    return PrettyTables.pretty_table(
        io, df;
        alignment_anchor_fallback = :r,
        title = Base.summary(df),
        title_alignment = :l,
        column_label_alignment = :l,
        compact_printing = true,
        maximum_data_column_widths = 32,
        vertical_crop_mode = :middle,
        highlighters = [PrettyTables.TextHighlighter(_pretty_tables_highlighter_func, PrettyTables.Crayon(foreground = :dark_gray))],
        table_format = format,
    )
end

"""
    ==(a::DataFrame, b::DataFrame)::Bool

Equal column names, in the same order, and equal column data. `missing` values compare equal, so
the result is always a `Bool`.
"""
function Base.:(==)(a::DataFrame, b::DataFrame)
    # `isequal`, so that missing values don't make the result `missing`.
    na, nb = names(a), names(b)
    na == nb || return false
    return all(isequal(collect(a[n]), collect(b[n])) for n in na)
end

function Base.hash(df::DataFrame, h::UInt)
    h = hash(:Polars_DataFrame, h)
    for n in names(df)
        h = hash(collect(df[n]), h)
    end
    return h
end

## Tables.jl interface

import Tables: schema

"""
Column names from the Arrow schema (no query), memoized in `df.column_names` so positional
column access stays O(1) per column.
"""
function _column_names(df::DataFrame)
    cached = df.column_names
    cached === nothing || return cached

    out = Ref{CArrowSchema}()
    err = API.polars_dataframe_schema(df, out)
    polars_error(err)
    resolved = load_dataframe_schema(out[]).names
    df.column_names = resolved
    return resolved
end

# A comprehension: broadcasting over the name tuple would specialize on the column count.
"""
    Base.names(df::DataFrame)::Vector{String}

Get the names of the columns of `df`.
"""
Base.names(df::DataFrame) = String[String(name) for name in _column_names(df)]

"""
    Tables.schema(df::DataFrame)::Tables.Schema

Get the column names and types of `df`. A column is typed `Union{T,Missing}` only if it contains
nulls.
"""
function schema(df::DataFrame)
    schema_out = Ref{CArrowSchema}()
    err = API.polars_dataframe_schema(df, schema_out)
    polars_error(err)
    (; names, types) = load_dataframe_schema(schema_out[])

    # Refine types by each column's null count (metadata only, no query).
    types = map(zip(names, types)) do (name, T)
        iszero(df[name].null_count) ? nomissing(T) : T
    end

    return Tables.Schema(names, types)
end

Tables.istable(::DataFrame) = true

Tables.columnaccess(::DataFrame) = true
Tables.rowaccess(::DataFrame) = true # enables Pluto.jl viewer

"""
    Tables.rows(df::DataFrame)

Row iterator over `df`. Every column is materialized first; prefer `Tables.columns` where
possible.
"""
Tables.rows(df::DataFrame) = Tables.rows(map(collect, Tables.columntable(df)))

"""
    DataFrameColumns

The value of `Tables.columns(df)`: `df` plus its column names, so positional column access doesn't
look up the names each time.
"""
struct DataFrameColumns{N}
    df::DataFrame
    names::NTuple{N, Symbol}
end

Tables.columns(df::DataFrame) = DataFrameColumns(df, _column_names(df))
# Tables.jl requires `columns` to be idempotent.
Tables.columns(cols::DataFrameColumns) = cols

Tables.istable(::DataFrameColumns) = true
Tables.columnaccess(::DataFrameColumns) = true
Tables.columnnames(cols::DataFrameColumns) = cols.names
Tables.getcolumn(cols::DataFrameColumns, col::Symbol) = getindex(cols.df, col)
Tables.getcolumn(cols::DataFrameColumns, idx::Int) = Tables.getcolumn(cols, cols.names[idx])
schema(cols::DataFrameColumns) = schema(cols.df)

Tables.columnnames(df::DataFrame) = _column_names(df)
Tables.getcolumn(df::DataFrame, col::Symbol) = getindex(df, col)
Tables.getcolumn(df::DataFrame, idx::Int) = Tables.getcolumn(df, Tables.columnnames(df)[idx])
