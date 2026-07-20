mutable struct DataFrame
    ptr::Ptr{polars_dataframe_t}

    DataFrame(ptr::Ptr{polars_dataframe_t}) =
        finalizer(polars_dataframe_destroy, new(ptr))
end

"""
    DataFrame(table)

A wrapper around an immutable polars dataframe object.
"""
function DataFrame(table)
    array, schema = Polars.arrowtable(table, "polars.dataframe")
    try
        out = Ref{Ptr{polars_dataframe_t}}()
        err = API.polars_dataframe_new_from_carrow(schema, array, out)
        # On success, Rust has taken ownership of `array` via the release-callback protocol (it
        # stays rooted in `LIVE_ARRAYS` until Rust itself calls `base_release_array` later, once
        # the imported buffers are dropped) -- do not release it here. On failure, Rust never
        # took ownership, so `array` (and its Julia-owned buffers) would otherwise stay rooted in
        # `LIVE_ARRAYS` forever; unroot it explicitly so it can be GC'd like any other object.
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

function Base.size(df::DataFrame)
    rows, cols = Ref{Csize_t}(), Ref{Csize_t}()
    API.polars_dataframe_size(df, rows, cols)
    return (Int(rows[]), Int(cols[]))
end
Base.size(df::DataFrame, dim::Integer) = size(df)[dim]

Base.getindex(df::DataFrame, row_index, col_index) = getindex(getindex(df, col_index), row_index)
Base.getindex(df::DataFrame, idx::Int) = Tables.getcolumn(df, idx)
Base.getindex(df::DataFrame, s::String) = getindex(df, Symbol(s))
function Base.getindex(df::DataFrame, s::Symbol)
    s = string(s)::String
    out = Ref{Ptr{polars_series_t}}()
    err = polars_dataframe_get(df, s, ncodeunits(s), out)
    polars_error(err)
    return Series(out[])
end

Base.unsafe_convert(::Type{Ptr{polars_dataframe_t}}, df::DataFrame) = df.ptr
Base.summary(df::DataFrame) = join(size(df), '×') * " DataFrame"

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

# Compact 2-arg form (e.g. `println(df)`, `string(df)`, a `DataFrame` nested inside another
# container's own display) -- unlike the full PrettyTables render below, this never grows with
# the number of rows/columns, so a `Vector{DataFrame}` or similar doesn't turn into a wall of
# tables. The verbose, human-facing render is reserved for MIME"text/plain" (the REPL's own
# top-level display), matching Julia's own two-tier convention for `AbstractArray`.
Base.show(io::IO, df::DataFrame) = print(io, Base.summary(df))

function Base.show(io::IO, ::MIME"text/plain", df::DataFrame)
    # Copied from the nice PrettyTables setup in DataFrames.jl
    # https://github.com/JuliaData/DataFrames.jl/blob/e341cc7873a08977cc8e4d56f28303883582c920/src/abstractdataframe/show.jl#L253-L279
    # Still needs some tuning/options
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

Structural equality: same column names in the same order, with pairwise-`isequal` column data.
Uses `isequal` (not the column data's own `==`) so two `missing`s compare equal and the result is
always a concrete `Bool` -- matches `hash`'s semantics below, and avoids `==`'s usual
`missing`-propagating three-valued logic, which would otherwise make a whole-dataframe comparison
return `missing` instead of `true`/`false` whenever any column has nulls. Without this method,
two structurally-identical `DataFrame`s compared unequal via the default `===` fallback.
"""
function Base.:(==)(a::DataFrame, b::DataFrame)
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

"""Reads column names straight from the Arrow schema, with no query executed -- the cheap half
of what [`schema`](@ref) below does (it additionally refines nullability from real null counts,
which needs a `select` over the whole frame)."""
function _column_names(df::DataFrame)
    out = Ref{CArrowSchema}()
    err = API.polars_dataframe_schema(df, out)
    polars_error(err)
    return load_dataframe_schema(out[]).names
end

"""
    Base.names(df::DataFrame)::Vector{String}

Returns the column names of `df`. Unlike [`schema`](@ref)/`Tables.schema(df)`, this reads only
the Arrow schema and runs no query at all, so it's cheap regardless of `df`'s size.
"""
Base.names(df::DataFrame) = collect(String.(_column_names(df)))

function schema(df::DataFrame)
    schema_out = Ref{CArrowSchema}()
    err = API.polars_dataframe_schema(df, schema_out)
    polars_error(err)
    (; names, types) = load_dataframe_schema(schema_out[])

    # Refine types by real null counts -- each `df[name]` is an Arc-refcount clone
    # (`polars_dataframe_get`), and the `Series` constructor already fetches
    # `polars_series_null_count` (a validity-bitmap count, no query engine), so this is a plain
    # per-column metadata read rather than a `select` query over the whole frame.
    types = map(zip(names, types)) do (name, T)
        iszero(df[string(name)].null_count) ? nomissing(T) : T
    end

    return Tables.Schema(names, types)
end

Tables.istable(::DataFrame) = true

Tables.columnaccess(::DataFrame) = true
Tables.rowaccess(::DataFrame) = true # enables Pluto.jl viewer

"""
    DataFrameColumns

`Tables.columns(df)`'s return value: a thin snapshot holding `df` plus its column names computed
once. Without this, `Tables.getcolumn(df, ::Int)` re-ran `_column_names` (a ccall + full Arrow
schema parse) on *every* call, so iterating a `DataFrame`'s columns positionally (as many Tables.jl
consumers do via `Tables.columns`) cost O(ncols²) rather than O(ncols).
"""
struct DataFrameColumns
    df::DataFrame
    names::Tuple{Vararg{Symbol}}
end

Tables.columns(df::DataFrame) = DataFrameColumns(df, _column_names(df))

Tables.istable(::DataFrameColumns) = true
Tables.columnaccess(::DataFrameColumns) = true
Tables.columnnames(cols::DataFrameColumns) = cols.names
Tables.getcolumn(cols::DataFrameColumns, col::Symbol) = getindex(cols.df, col)
Tables.getcolumn(cols::DataFrameColumns, idx::Int) = Tables.getcolumn(cols, cols.names[idx])
schema(cols::DataFrameColumns) = schema(cols.df)

# Cheap (schema-only, no query) -- see `_column_names`'s docstring.
Tables.columnnames(df::DataFrame) = _column_names(df)
Tables.getcolumn(df::DataFrame, col::Symbol) = getindex(df, col)
Tables.getcolumn(df::DataFrame, idx::Int) = Tables.getcolumn(df, Tables.columnnames(df)[idx])
