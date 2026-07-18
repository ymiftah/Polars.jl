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
    return try
        out = Ref{Ptr{polars_dataframe_t}}()
        err = API.polars_dataframe_new_from_carrow(schema, array, out)
        polars_error(err)
        DataFrame(out[])
    finally
        release_schema!(schema)
    end
end

function Base.size(df::DataFrame)
    rows, cols = Ref{Csize_t}(), Ref{Csize_t}()
    API.polars_dataframe_size(df, rows, cols)
    return (Int(rows[]), Int(cols[]))
end

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
## Tables.jl interface

import Tables: schema

"""Reads column names straight from the Arrow schema, with no query executed -- the cheap half
of what [`schema`](@ref) below does (it additionally refines nullability from real null counts,
which needs a `select` over the whole frame)."""
_column_names(df::DataFrame) = load_dataframe_schema(API.polars_dataframe_schema(df)).names

"""
    Base.names(df::DataFrame)::Vector{String}

Returns the column names of `df`. Unlike [`schema`](@ref)/`Tables.schema(df)`, this reads only
the Arrow schema and runs no query at all, so it's cheap regardless of `df`'s size.
"""
Base.names(df::DataFrame) = collect(String.(_column_names(df)))

function schema(df::DataFrame)
    (; names, types) = load_dataframe_schema(API.polars_dataframe_schema(df))

    # Refine types by fetching real null counts, this should be quite
    # cheap.
    null_counts = select(df, map(null_count ∘ col ∘ string, names)...)
    types = map(zip(names, types)) do (name, T)
        if iszero(only(null_counts[name]))
            nomissing(T)
        else
            T
        end
    end

    return Tables.Schema(names, types)
end

Tables.istable(::DataFrame) = true

Tables.columnaccess(::DataFrame) = true
Tables.rowaccess(::DataFrame) = true # enables Pluto.jl viewer

Tables.columns(df::DataFrame) = df

# Cheap (schema-only, no query) -- see `_column_names`'s docstring. This used to call
# `schema(df).names`, so simply materializing column names -- or, via `getcolumn(df, ::Int)`
# below, reading a *single* column by position -- ran a null-count `select` over every column of
# the whole frame first.
Tables.columnnames(df::DataFrame) = _column_names(df)
Tables.getcolumn(df::DataFrame, col::Symbol) = getindex(df, col)
Tables.getcolumn(df::DataFrame, idx::Int) = Tables.getcolumn(df, Tables.columnnames(df)[idx])
