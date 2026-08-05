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
        # `array` crosses the ccall boundary by value (see the Rust-side doc comment on
        # `polars_dataframe_new_from_carrow`), so Rust receives its own independent copy and takes
        # ownership unconditionally, on both the success and failure path -- `array`'s own copy is
        # moved-from the instant the ccall returns, so mark it released here too (harmless if
        # `base_release_array` already did this itself, e.g. on the synchronous failure path
        # below).
        _mark_released!(Base.unsafe_convert(Ptr{API.ArrowArray}, array))
        # On failure, Rust's `ArrowArray: Drop` impl already released synchronously before
        # returning (every early return in `polars_dataframe_new_from_carrow` drops its owned
        # `carray` local) -- `array` is therefore already unrooted from `LIVE_ARRAYS` by the time
        # we get here. On success, release is deferred until the imported buffers are eventually
        # dropped (`array` stays rooted until then). Either way, `release_array!` below is a
        # defensive, idempotent unroot, not a required one.
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

Builds a `DataFrame` directly from a vector of `Series`, one per column, in order. Each series is
cloned, not consumed. Column names are each series' own `name`; a series with an empty name is
assigned `"column_i"` (0-based) instead. Duplicate resulting names raise an error.
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

With no extra arguments, returns the sole value of a 1×1 `df`, and errors for any other shape.

With `row` and `col`, returns that single element; `col` accepts either an `Integer` index or a
column name (`String` or `Symbol`), the same as indexing.
"""
function item(df::DataFrame)
    sz = size(df)
    sz == (1, 1) || error("item() requires a DataFrame of shape (1, 1), got shape $sz")
    return df[1, 1]
end
item(df::DataFrame, row::Integer, col) = getindex(df, row, col)

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

struct _NoDefault end
# Sentinel rather than a `default = nothing` default value: `nothing` is itself a valid `default`
# upstream (`df.get_column("x", default=None)` returns `None`, not an error), so it can't double as
# "no default was given".
const _NO_DEFAULT = _NoDefault()

"""
    get_column(df::DataFrame, name::Union{AbstractString,Symbol})::Series
    get_column(df::DataFrame, name::Union{AbstractString,Symbol}; default)

Returns the column named `name` as a [`Series`](@ref), equivalent to `df[name]`.

A nonexistent column raises a [`PolarsError`](@ref) naming the column. If `default` is given, it is
returned instead of raising. `default = nothing` counts as a value and returns `nothing`; it is not
the same as omitting the keyword.
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

Structural equality: same column names in the same order, with pairwise-equal column data
(`missing == missing` is treated as `true`, so the result is always a concrete `Bool`).
"""
function Base.:(==)(a::DataFrame, b::DataFrame)
    # Uses `isequal`, not column data's own `==`, to keep `hash`'s semantics consistent and avoid
    # `==`'s missing-propagating three-valued logic turning a whole-dataframe comparison into
    # `missing`. Without this method, structurally-identical `DataFrame`s compare unequal via the
    # default `===` fallback.
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

Returns the column names of `df`.
"""
Base.names(df::DataFrame) = collect(String.(_column_names(df)))

"""
    Tables.schema(df::DataFrame)::Tables.Schema

Implements the Tables.jl interface method: returns a `Tables.Schema` with column names and types,
refined by each column's actual null count (unlike [`collect_schema`](@ref) on a `LazyFrame`, which
hasn't executed the query and so must conservatively report every column as nullable).
"""
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
