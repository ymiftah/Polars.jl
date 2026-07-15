module Polars

import PrettyTables, Tables

const MaybeMissing{T} = Union{T, Union{T, Missing}}
const PhysicalDType = Union{
    Bool, Int8, Int16, Int32, Int64, UInt8,
    UInt16, UInt32, UInt64, Float32, Float64,
}

nomissing(::Type{MaybeMissing{T}}) where {T} = T
nomissing(::Type{T}) where {T} = T

"Internal function to write back to an IO from rustland"
function _write_callback(user, data, len)
    return try
        n = unsafe_write(user isa IO ? user : user[], data, len)
        Int(n)
    catch
        -1
    end
end

include("./API.jl")

using .API

"""
    Series(name::String, values::Vector{T})::Series{T}

A series is a collection of values used as columns inside a [`DataFrame`](@ref).
"""
mutable struct Series{T} <: AbstractVector{T}
    ptr::Ptr{polars_series_t}
    null_count::Int
    length::Int

    function Series(ptr)
        @assert ptr != C_NULL

        schema = polars_series_schema(ptr)
        _, T = load_series_schema(schema)

        len = polars_series_length(ptr)
        null_count = polars_series_null_count(ptr)

        T = iszero(null_count) ? nomissing(T) : T

        series = new{T}(ptr, null_count, len)

        return finalizer(polars_series_destroy, series)
    end
end

"""
    Polars.Value{T}

Internal type which represents a reference to a value of type `T` in a series or as a field to
a struct.
"""
mutable struct Value{T}
    ptr::Ptr{polars_value_t}
    parent::Union{Series, Value}

    Value{T}(ptr, parent = nothing) where {T} =
        finalizer(polars_value_destroy, new{T}(ptr, parent))
end

using Dates

include("./expr.jl")
include("./series.jl")
include("./arrow.jl")
include("./value.jl")

"""
    version()::VersionNumber

Returns the rust Polars version with which the C-API was built.
"""
function version()
    out = Ref{Ptr{UInt8}}()
    len = polars_version(out)
    ver = unsafe_string(out[], len)
    return VersionNumber(ver)
end

function polars_error(err::Ptr{polars_error_t})
    err == C_NULL && return
    str = Ref{Ptr{UInt8}}()
    len = polars_error_message(err, str)
    message = unsafe_string(str[], len)
    polars_error_destroy(err)
    error(message)
end

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
        df_ptr = API.polars_dataframe_new_from_carrow(schema, array)
        if df_ptr == C_NULL
            throw("something went wrong when creating dataframe; please report.")
        end
        DataFrame(df_ptr)
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
    err = polars_dataframe_get(df, s, length(s), out)
    polars_error(err)
    return Series(out[])
end

Base.unsafe_convert(::Type{Ptr{polars_dataframe_t}}, df::DataFrame) = df.ptr

mutable struct LazyFrame
    ptr::Ptr{polars_lazy_frame_t}

    LazyFrame(ptr) =
        finalizer(polars_lazy_frame_destroy, new(ptr))
end

Base.unsafe_convert(::Type{Ptr{polars_lazy_frame_t}}, df::LazyFrame) = df.ptr

"""
    lazy(df::DataFrame)::LazyFrame

Returns a lazy frame over the provided dataframe.

See also [`collect`](@ref).
"""
function lazy(df)
    out = polars_dataframe_lazy(df)
    return LazyFrame(out)
end

"""
    collect(lf::LazyFrame; engine=:default)::DataFrame

Materializes the lazy frame as a DataFrame.
`engine` can be either `:default` (in-memory engine) or `:streaming`.
"""
function Base.collect(df::LazyFrame; engine = :default)
    engine = engine === :default ? API.PolarsEngineInMemory : engine === :streaming ? API.PolarsEngineStreaming : error("unknown engine $engine, expected one of (:default, :streaming)")
    out = Ref{Ptr{polars_dataframe_t}}()
    err = polars_lazy_frame_collect(df, engine, out)
    polars_error(err)
    return DataFrame(out[])
end

"""
    read_parquet(path::String)::DataFrame

Reads a dataframe stored in a parquet file.
"""
function read_parquet(path)
    out = Ref{Ptr{polars_dataframe_t}}()
    err = polars_dataframe_read_parquet(path, length(path), out)
    polars_error(err)
    return DataFrame(out[])
end

"""
    scan_parquet(path::String)::LazyFrame

Lazily scans a parquet file, glob pattern, or directory of (optionally
Hive-partitioned) parquet files, without reading it into memory. Hive
partition keys are auto-detected and surfaced as columns.
"""
function scan_parquet(path)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_scan_parquet(path, length(path), out)
    polars_error(err)
    return LazyFrame(out[])
end

"""
    write_parquet(io::IO, df::DataFrame)
    write_parquet(path::String, df::DataFrame)

Writes a dataframe to a parquet file provided as an `IO`.
"""
function write_parquet(io::IO, df::DataFrame)
    callback = @cfunction(_write_callback, Cssize_t, (Any, Ptr{Cchar}, Cuint))
    ref = Ref(io)
    err = polars_dataframe_write_parquet(df, ref, callback)
    polars_error(err)
    return nothing
end
write_parquet(p::String, df::DataFrame) = open(io -> write_parquet(io, df), p, "w")

"""
    scan_csv(path::String)::LazyFrame

Lazily scans a CSV file without reading it into memory.
"""
function scan_csv(path)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_scan_csv(path, length(path), out)
    polars_error(err)
    return LazyFrame(out[])
end

"""
    read_csv(path::String)::DataFrame

Reads a dataframe stored in a CSV file.
"""
read_csv(path) = collect(scan_csv(path))

"""
    write_csv(io::IO, df::DataFrame)
    write_csv(path::String, df::DataFrame)

Writes a dataframe to a CSV file provided as an `IO`.
"""
function write_csv(io::IO, df::DataFrame)
    callback = @cfunction(_write_callback, Cssize_t, (Any, Ptr{Cchar}, Cuint))
    ref = Ref(io)
    err = polars_dataframe_write_csv(df, ref, callback)
    polars_error(err)
    return nothing
end
write_csv(p::String, df::DataFrame) = open(io -> write_csv(io, df), p, "w")

"""
    scan_ipc(path::String)::LazyFrame

Lazily scans an Arrow IPC (Feather) file without reading it into memory.
"""
function scan_ipc(path)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_scan_ipc(path, length(path), out)
    polars_error(err)
    return LazyFrame(out[])
end

"""
    read_ipc(path::String)::DataFrame

Reads a dataframe stored in an Arrow IPC (Feather) file.
"""
read_ipc(path) = collect(scan_ipc(path))

"""
    sink_parquet(lf::LazyFrame, path::String)
    sink_parquet(df::DataFrame, path::String)

Executes the query and writes the result directly to a parquet file via the streaming engine,
without materializing the full result in memory — suitable for out-of-core processing of
datasets larger than RAM.
"""
sink_parquet(df::DataFrame, path::String) = sink_parquet(lazy(df), path)
function sink_parquet(lf::LazyFrame, path::String)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_sink_parquet(lf, path, length(path), out)
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end

"""
    sink_csv(lf::LazyFrame, path::String)
    sink_csv(df::DataFrame, path::String)

Executes the query and writes the result directly to a CSV file via the streaming engine, without
materializing the full result in memory.
"""
sink_csv(df::DataFrame, path::String) = sink_csv(lazy(df), path)
function sink_csv(lf::LazyFrame, path::String)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_sink_csv(lf, path, length(path), out)
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end

"""
    sink_ipc(lf::LazyFrame, path::String)
    sink_ipc(df::DataFrame, path::String)

Executes the query and writes the result directly to an Arrow IPC (Feather) file via the streaming
engine, without materializing the full result in memory.
"""
sink_ipc(df::DataFrame, path::String) = sink_ipc(lazy(df), path)
function sink_ipc(lf::LazyFrame, path::String)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_sink_ipc(lf, path, length(path), out)
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end

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

function Base.show(io::IO, df::DataFrame)
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

_select!(df::LazyFrame, exprs...) = _select!(df, collect(exprs)::Vector)
function _select!(df::LazyFrame, exprs::Vector)
    exprs = map(ex -> ex isa String ? col(ex) : ex, exprs)
    exprs = convert(Vector{Expr}, exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        polars_lazy_frame_select(df, exprs_ptrs, length(exprs_ptrs))
    end
    return df
end

"""
    select(lf::LazyFrame, exprs...)::LazyFrame
    select(df::DataFrame, exprs...)::DataFrame

Select a fixed set of expressions from the provided frames.
"""
select(df::LazyFrame, exprs...) = _select!(clone(df), exprs...)
select(df::DataFrame, exprs...) = _select!(lazy(df), exprs...) |> collect

"""
    with_columns(lf::LazyFrame, exprs...)::LazyFrame
    with_columns(df::DataFrame, exprs...)::DataFrame

Select a fixed set of expressions from the provided frames and
also returns the existing columns.

```julia-repl
julia> df = DataFrame((; x=[1,2,3]))
3×1 DataFrame
 x      
 Int64? 
────────
      1
      2
      3

julia> with_columns(df, col("x") * 2 |> alias("2x"))
3×2 DataFrame
 x       2x     
 Int64?  Int64? 
────────────────
      1       2
      2       4
      3       6
```
"""
with_columns(df::LazyFrame, exprs...) = _with_columns!(clone(df), collect(exprs)::Vector)
with_columns(df::DataFrame, exprs...) = _with_columns!(lazy(df), collect(exprs)::Vector) |> collect

function _with_columns!(df::LazyFrame, exprs::Vector)
    exprs = map(ex -> ex isa String ? col(ex) : ex, exprs)
    exprs = convert(Vector{Expr}, exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        polars_lazy_frame_with_columns(df, exprs_ptrs, length(exprs_ptrs))
    end
    return df
end

"""
    head(lf::LazyFrame, n)::LazyFrame
    head(df::DataFrame, n)::DataFrame

Returns the first `n` rows of the frame.
"""
head(df::LazyFrame, n = 5) = _head!(clone(df), n)
head(df::DataFrame, n = 5) = _head!(lazy(df), n) |> collect


function _head!(df::LazyFrame, n)
    polars_lazy_frame_head(df, n)
    return df
end

"""
    tail(lf::LazyFrame, n)::LazyFrame
    tail(df::DataFrame, n)::DataFrame

Returns the last `n` rows of the frame.
"""
Base.tail(df::LazyFrame, n = 5) = _tail!(clone(df), n)
Base.tail(df::DataFrame, n = 5) = _tail!(lazy(df), n) |> collect

function _tail!(df::LazyFrame, n)
    polars_lazy_frame_tail(df, n)
    return df
end

"""Builds `(ptrs, lens)` pointer/length arrays for a `Vector{String}`, to pass across the C ABI
under `GC.@preserve names`."""
_name_ptrs(names::Vector{String}) =
    (Ptr{UInt8}[pointer(s) for s in names], Csize_t[ncodeunits(s) for s in names])

"""
    unique(lf::LazyFrame, subset::Vector{String}=String[]; keep::Symbol=:any)::LazyFrame
    unique(df::DataFrame, subset::Vector{String}=String[]; keep::Symbol=:any)::DataFrame

Removes duplicate rows, considering only `subset` columns if provided (all columns otherwise).
`keep` selects which duplicate to retain: `:first`, `:last`, `:none` (drop all duplicates), or
`:any` (default — no order guarantee, allows more optimization).
"""
Base.unique(df::DataFrame, subset::Vector{String} = String[]; keep::Symbol = :any) =
    unique(lazy(df), subset; keep) |> collect
function Base.unique(lf::LazyFrame, subset::Vector{String} = String[]; keep::Symbol = :any)
    keep_enum = if keep == :first
        API.PolarsUniqueKeepFirst
    elseif keep == :last
        API.PolarsUniqueKeepLast
    elseif keep == :none
        API.PolarsUniqueKeepNone
    elseif keep == :any
        API.PolarsUniqueKeepAny
    else
        error("unknown keep strategy $keep, expected one of (:first, :last, :none, :any)")
    end
    GC.@preserve subset begin
        ptrs, lens = _name_ptrs(subset)
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_unique(lf, ptrs, lens, length(ptrs), keep_enum, out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

"""
    drop(lf::LazyFrame, columns::Vector{String})::LazyFrame
    drop(df::DataFrame, columns::Vector{String})::DataFrame

Removes the given columns from the frame.
"""
drop(df::DataFrame, columns::Vector{String}) = drop(lazy(df), columns) |> collect
function drop(lf::LazyFrame, columns::Vector{String})
    GC.@preserve columns begin
        ptrs, lens = _name_ptrs(columns)
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_drop(lf, ptrs, lens, length(ptrs), out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

"""
    rename(lf::LazyFrame, existing::Vector{String}, new::Vector{String}; strict::Bool=true)::LazyFrame
    rename(df::DataFrame, existing::Vector{String}, new::Vector{String}; strict::Bool=true)::DataFrame

Renames `existing` columns to the corresponding `new` names (same length, paired by position).
If `strict` is `true` (default), every `existing` column must be present; otherwise, missing
ones are silently ignored.
"""
Base.rename(df::DataFrame, existing::Vector{String}, new::Vector{String}; strict::Bool = true) =
    Base.rename(lazy(df), existing, new; strict) |> collect
function Base.rename(lf::LazyFrame, existing::Vector{String}, new::Vector{String}; strict::Bool = true)
    length(existing) == length(new) || error("existing and new must have the same length")
    GC.@preserve existing new begin
        existing_ptrs, existing_lens = _name_ptrs(existing)
        new_ptrs, new_lens = _name_ptrs(new)
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_rename(
            lf, existing_ptrs, existing_lens, new_ptrs, new_lens, length(existing_ptrs), strict, out
        )
        polars_error(err)
    end
    return LazyFrame(out[])
end

"""
    drop_nulls(lf::LazyFrame, subset::Vector{String}=String[])::LazyFrame
    drop_nulls(df::DataFrame, subset::Vector{String}=String[])::DataFrame

Removes rows containing a `null` in any of the `subset` columns (all columns if not provided).
"""
drop_nulls(df::DataFrame, subset::Vector{String} = String[]) = drop_nulls(lazy(df), subset) |> collect
function drop_nulls(lf::LazyFrame, subset::Vector{String} = String[])
    GC.@preserve subset begin
        ptrs, lens = _name_ptrs(subset)
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_drop_nulls(lf, ptrs, lens, length(ptrs), out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

"""
    with_row_index(lf::LazyFrame, name::String="index"; offset::Integer=0)::LazyFrame
    with_row_index(df::DataFrame, name::String="index"; offset::Integer=0)::DataFrame

Adds a row-index column named `name`, starting at `offset` (default `0`).
"""
with_row_index(df::DataFrame, name::String = "index"; offset::Integer = 0) =
    with_row_index(lazy(df), name; offset) |> collect
function with_row_index(lf::LazyFrame, name::String = "index"; offset::Integer = 0)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_with_row_index(lf, name, length(name), Int64(offset), true, out)
    polars_error(err)
    return LazyFrame(out[])
end

"""
    explode(lf::LazyFrame, columns::Vector{String})::LazyFrame
    explode(df::DataFrame, columns::Vector{String})::DataFrame

Explodes list-typed `columns`, turning each list element into its own row (other columns are
repeated to match).
"""
explode(df::DataFrame, columns::Vector{String}) = explode(lazy(df), columns) |> collect
function explode(lf::LazyFrame, columns::Vector{String})
    GC.@preserve columns begin
        ptrs, lens = _name_ptrs(columns)
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_explode(lf, ptrs, lens, length(ptrs), out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

"""
    unpivot(lf::LazyFrame, index::Vector{String}; on::Vector{String}=String[],
            variable_name=nothing, value_name=nothing)::LazyFrame
    unpivot(df::DataFrame, index::Vector{String}; on::Vector{String}=String[],
            variable_name=nothing, value_name=nothing)::DataFrame

Unpivots (melts) `on` columns (all non-`index` columns if not provided) from wide to long
format: `index` columns are repeated, and the melted columns become two new columns —
`variable_name` (default `"variable"`) holding the original column name, and `value_name`
(default `"value"`) holding its value.
"""
function unpivot(
        df::DataFrame, index::Vector{String};
        on::Vector{String} = String[], variable_name::Union{Nothing, String} = nothing,
        value_name::Union{Nothing, String} = nothing
    )
    return unpivot(lazy(df), index; on, variable_name, value_name) |> collect
end
function unpivot(
        lf::LazyFrame, index::Vector{String};
        on::Vector{String} = String[], variable_name::Union{Nothing, String} = nothing,
        value_name::Union{Nothing, String} = nothing
    )
    variable_name = something(variable_name, "")
    value_name = something(value_name, "")
    GC.@preserve index on begin
        index_ptrs, index_lens = _name_ptrs(index)
        on_ptrs, on_lens = _name_ptrs(on)
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_unpivot(
            lf, index_ptrs, index_lens, length(index_ptrs), on_ptrs, on_lens, length(on_ptrs),
            variable_name, length(variable_name), value_name, length(value_name), out
        )
        polars_error(err)
    end
    return LazyFrame(out[])
end

"""
    pivot(df::DataFrame, on, index, values; agg=Base.first(element()), maintain_order::Bool=true,
          separator::String="_", column_naming::Symbol=:auto)::DataFrame

Reshapes `df` from long to wide format: creates one new column per distinct value of `on`
(named after that value, or `"\$(value_col)\$(separator)\$(on_value)"` when there's more than one
`values` column or `column_naming=:combine`), grouping the remaining rows by `index` and
aggregating each group's `values` column via `agg` -- an expression built from [`element`](@ref),
a placeholder for "the values in this group", e.g. `Base.sum(element())`. `on`/`index`/`values`
may each be a single column name or a `Vector` of names.

Wraps polars' own native `pivot` DSL node, which expands into an ordinary
`group_by(index).agg(...)` plan internally (one conditional aggregation per distinct `on` value),
so it reuses the same executor as `group_by`/`agg` rather than anything bespoke. Eager-only (no
`LazyFrame` method) since it needs the distinct `on` values computed upfront.
"""
function pivot(
        df::DataFrame, on, index, values; agg::Expr = Base.first(element()),
        maintain_order::Bool = true, separator::String = "_", column_naming::Symbol = :auto
    )
    on = on isa AbstractVector ? String.(on) : [String(on)]
    index = index isa AbstractVector ? String.(index) : [String(index)]
    values = values isa AbstractVector ? String.(values) : [String(values)]

    on_columns = collect(unique(select(lazy(df), map(col, on)...)))

    naming_enum = if column_naming == :auto
        API.PolarsPivotColumnNamingAuto
    elseif column_naming == :combine
        API.PolarsPivotColumnNamingCombine
    else
        error("unknown column_naming $column_naming, expected one of (:auto, :combine)")
    end

    GC.@preserve on index values begin
        on_ptrs, on_lens = _name_ptrs(on)
        index_ptrs, index_lens = _name_ptrs(index)
        values_ptrs, values_lens = _name_ptrs(values)
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_pivot(
            lazy(df), on_ptrs, on_lens, length(on_ptrs), on_columns,
            index_ptrs, index_lens, length(index_ptrs),
            values_ptrs, values_lens, length(values_ptrs),
            agg, maintain_order, separator, length(separator), naming_enum, out
        )
        polars_error(err)
    end
    return collect(LazyFrame(out[]))
end

export pivot

function _filter!(df::LazyFrame, expr)
    polars_lazy_frame_filter(df, expr)
    return df
end

"""
    filter(lf::LazyFrame, expr)
    filter(df::DataFrame, expr)

Filters the rows of the provided frames based on the provided expression.
"""
Base.filter(df::LazyFrame, expr) = _filter!(clone(df), expr)
Base.filter(df::DataFrame, expr) = _filter!(lazy(df), expr) |> collect

function clone(df::LazyFrame)
    out = polars_lazy_frame_clone(df)
    return LazyFrame(out)
end

"""
    concat(frames::Vector{LazyFrame})::LazyFrame
    concat(frames::Vector{DataFrame})::DataFrame

Concatenates the provided frames vertically (stacking rows), matching columns by position.
"""
concat(frames::Vector{DataFrame}) = collect(concat(map(lazy, frames)))
function concat(frames::Vector{LazyFrame})
    GC.@preserve frames begin
        frame_ptrs = Ptr{polars_lazy_frame_t}[frame.ptr for frame in frames]
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_concat(frame_ptrs, length(frame_ptrs), out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

function _join(a::LazyFrame, b::LazyFrame, exprs_a::Vector, exprs_b::Vector, how)
    exprs_a = map(ex -> ex isa String ? col(ex) : ex, exprs_a)
    exprs_a = convert(Vector{Expr}, exprs_a)
    exprs_b = map(ex -> ex isa String ? col(ex) : ex, exprs_b)
    exprs_b = convert(Vector{Expr}, exprs_b)
    GC.@preserve exprs_a exprs_b begin
        exprs_a_ptr = Ptr{polars_expr_t}[expr.ptr for expr in exprs_a]
        exprs_b_ptr = Ptr{polars_expr_t}[expr.ptr for expr in exprs_b]
        out = polars_lazy_frame_join(
            a, b,
            exprs_a_ptr, length(exprs_a_ptr),
            exprs_b_ptr, length(exprs_b_ptr),
            how,
        )
    end
    return LazyFrame(out)
end

for (jl_name, how) in (
        (:innerjoin, :PolarsJoinTypeInner),
        (:leftjoin, :PolarsJoinTypeLeft),
        (:rightjoin, :PolarsJoinTypeRight),
        (:outerjoin, :PolarsJoinTypeFull),
        (:semijoin, :PolarsJoinTypeSemi),
        (:antijoin, :PolarsJoinTypeAnti),
    )
    @eval begin
        $jl_name(a, b, expr) = $jl_name(a, b, expr, expr)
        $jl_name(a::DataFrame, b::DataFrame, exprs_a, exprs_b) = $jl_name(lazy(a), lazy(b), exprs_a, exprs_b) |> collect
        $jl_name(a::LazyFrame, b::LazyFrame, expr_a, expr_b) = $jl_name(a, b, [expr_a], [expr_b])
        $jl_name(a::LazyFrame, b::LazyFrame, exprs_a::Vector, exprs_b::Vector) =
            _join(a, b, exprs_a, exprs_b, API.$how)
    end
end

"""
    crossjoin(a::LazyFrame, b::LazyFrame)::LazyFrame
    crossjoin(a::DataFrame, b::DataFrame)::DataFrame

Returns the Cartesian product of the rows of `a` and `b` (`nrow(a) * nrow(b)` rows, no join
keys involved).
"""
crossjoin(a::DataFrame, b::DataFrame) = crossjoin(lazy(a), lazy(b)) |> collect
crossjoin(a::LazyFrame, b::LazyFrame) = _join(a, b, Expr[], Expr[], API.PolarsJoinTypeCross)

"""
    join_asof(a, b, on; by_left=String[], by_right=String[], strategy::Symbol=:backward)

Joins `a` (left) and `b` (right) on the nearest key in `on` (columns/expressions, typically
sorted numeric or temporal), matching each left row to the nearest right row according to
`strategy`: `:backward` (default, the last right row `<=` the left key), `:forward` (the first
right row `>=` the left key), or `:nearest`. `by_left`/`by_right` are optional equality
group-by column names applied before the asof match.
"""
function join_asof(
        a, b, on;
        by_left::Vector{String} = String[], by_right::Vector{String} = String[],
        strategy::Symbol = :backward
    )
    return join_asof(a, b, on, on; by_left, by_right, strategy)
end
function join_asof(
        a::DataFrame, b::DataFrame, on_a, on_b;
        by_left::Vector{String} = String[], by_right::Vector{String} = String[],
        strategy::Symbol = :backward
    )
    return join_asof(lazy(a), lazy(b), on_a, on_b; by_left, by_right, strategy) |> collect
end
function join_asof(
        a::LazyFrame, b::LazyFrame, on_a, on_b;
        by_left::Vector{String} = String[], by_right::Vector{String} = String[],
        strategy::Symbol = :backward
    )
    on_a = on_a isa String ? col(on_a) : on_a
    on_b = on_b isa String ? col(on_b) : on_b
    strategy_enum = if strategy == :backward
        API.PolarsAsofStrategyBackward
    elseif strategy == :forward
        API.PolarsAsofStrategyForward
    elseif strategy == :nearest
        API.PolarsAsofStrategyNearest
    else
        error("unknown asof strategy $strategy, expected one of (:backward, :forward, :nearest)")
    end
    GC.@preserve by_left by_right begin
        by_left_ptrs = Ptr{UInt8}[pointer(s) for s in by_left]
        by_left_lens = Csize_t[ncodeunits(s) for s in by_left]
        by_right_ptrs = Ptr{UInt8}[pointer(s) for s in by_right]
        by_right_lens = Csize_t[ncodeunits(s) for s in by_right]
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_join_asof(
            a, b, on_a, on_b,
            by_left_ptrs, by_left_lens, length(by_left_ptrs),
            by_right_ptrs, by_right_lens, length(by_right_ptrs),
            strategy_enum, out,
        )
        polars_error(err)
    end
    return LazyFrame(out[])
end

"""
    LazyGroupBy()

A groupby over a [`LazyFrame`] whose values can be aggregated using the
[`agg`](@ref) function.
"""
mutable struct LazyGroupBy
    ptr::Ptr{polars_lazy_group_by_t}

    LazyGroupBy(ptr) =
        finalizer(polars_lazy_group_by_destroy, new(ptr))
end

Base.unsafe_convert(::Type{Ptr{polars_lazy_group_by_t}}, gb::LazyGroupBy) = gb.ptr

"""
    group_by(df::LazyFrame, exprs...)

Returns a lazy group-by object over the provided [`LazyFrame`](@ref).
The values for the group-by can be aggregated using the [`agg`](@ref) function.
"""
group_by(df::LazyFrame, exprs...) = groupby(df, collect(exprs)::Vector)
function groupby(df::LazyFrame, exprs::Vector)
    exprs = map(ex -> ex isa String ? col(ex) : ex, exprs)
    exprs = convert(Vector{Expr}, exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        out = polars_lazy_frame_group_by(df, exprs_ptrs, length(exprs_ptrs))
    end
    return LazyGroupBy(out)
end

"""
    agg(gb, exprs...)::LazyFrame

Aggregates the value over the group-by object and return a resulting [`LazyFrame`](@ref).
"""
agg(gb::LazyGroupBy, exprs...) = agg(gb, collect(exprs)::Vector)
function agg(gb::LazyGroupBy, exprs::Vector)
    exprs = map(ex -> ex isa String ? col(ex) : ex, exprs)
    exprs = convert(Vector{Expr}, exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        out = polars_lazy_group_by_agg(gb, exprs_ptrs, length(exprs_ptrs))
    end
    return LazyFrame(out)
end

"""
    group_by_dynamic(df::LazyFrame, index_column, group_by::Vector=[];
                     every, period=nothing, offset="0ns",
                     closed::Symbol=:left, label::Symbol=:left,
                     include_boundaries::Bool=false, start_by::Symbol=:window_bound)::LazyGroupBy

Time-window grouping: bucket rows into fixed-size time windows (e.g. "daily sum per store").
Returns a [`LazyGroupBy`](@ref) object for aggregation with [`agg`](@ref).

- `index_column`: time-indexed column (as `String` or `Expr`), e.g. `"timestamp"`
- `group_by`: optional extra grouping keys (as `String`s or `Expr`s), e.g. `["store"]`
- `every`: time window size (string, e.g. `"1d"`, `"2h"`)
- `period`: repeat interval (defaults to `every`); string like `"1d"`
- `offset`: time offset for window boundaries; string like `"0ns"` or `"1h"`
- `closed`: window closure `:left` (default), `:right`, `:both`, or `:none`
- `label`: which timestamp to label the window `:left` (default), `:right`, or `:data_point`
- `include_boundaries`: whether to label boundaries (default `false`)
- `start_by`: where to start the first window `:window_bound` (default), `:data_point`, or day-of-week `:monday`...`:sunday`
"""
function group_by_dynamic(
        df::LazyFrame,
        index_column,
        group_by::Vector = [];
        every,
        period = nothing,
        offset = "0ns",
        closed::Symbol = :left,
        label::Symbol = :left,
        include_boundaries::Bool = false,
        start_by::Symbol = :window_bound,
    )
    index_expr = index_column isa String ? col(index_column) : index_column
    group_by = convert(Vector{Expr}, map(ex -> ex isa String ? col(ex) : ex, group_by))
    period = something(period, every)

    label_cenum = label === :left ? API.PolarsLabelLeft :
        label === :right ? API.PolarsLabelRight :
        label === :data_point ? API.PolarsLabelDataPoint :
        error("invalid label $label, expected :left, :right, or :data_point")

    closed_cenum = closed === :left ? API.PolarsClosedWindowLeft :
        closed === :right ? API.PolarsClosedWindowRight :
        closed === :both ? API.PolarsClosedWindowBoth :
        closed === :none ? API.PolarsClosedWindowNone :
        error("invalid closed $closed, expected :left, :right, :both, or :none")

    start_by_cenum = start_by === :window_bound ? API.PolarsStartByWindowBound :
        start_by === :data_point ? API.PolarsStartByDataPoint :
        start_by === :monday ? API.PolarsStartByMonday :
        start_by === :tuesday ? API.PolarsStartByTuesday :
        start_by === :wednesday ? API.PolarsStartByWednesday :
        start_by === :thursday ? API.PolarsStartByThursday :
        start_by === :friday ? API.PolarsStartByFriday :
        start_by === :saturday ? API.PolarsStartBySaturday :
        start_by === :sunday ? API.PolarsStartBySunday :
        error("invalid start_by $start_by")

    GC.@preserve index_expr group_by begin
        group_by_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in group_by]
        out = Ref{Ptr{polars_lazy_group_by_t}}()
        err = polars_lazy_frame_group_by_dynamic(
            df,
            index_expr,
            group_by_ptrs,
            length(group_by_ptrs),
            pointer(every),
            ncodeunits(every),
            pointer(period),
            ncodeunits(period),
            pointer(offset),
            ncodeunits(offset),
            label_cenum,
            include_boundaries,
            closed_cenum,
            start_by_cenum,
            out,
        )
        polars_error(err)
    end
    return LazyGroupBy(out[])
end

"""
    rolling(df::LazyFrame, index_column, group_by::Vector=[];
            period, offset="0ns", closed::Symbol=:right)::LazyGroupBy

Sliding time-window grouping: compute per-row rolling windows over a time-indexed column.
Returns a [`LazyGroupBy`](@ref) object for aggregation with [`agg`](@ref).

- `index_column`: time-indexed column (as `String` or `Expr`), e.g. `"timestamp"`
- `group_by`: optional extra grouping keys (as `String`s or `Expr`s), e.g. `["store"]`
- `period`: rolling window size (string, e.g. `"7d"`, `"1h"`)
- `offset`: time offset for window boundaries; string like `"0ns"` or `"-1d"`
- `closed`: window closure `:left`, `:right` (default), `:both`, or `:none`
"""
function rolling(
        df::LazyFrame,
        index_column,
        group_by::Vector = [];
        period,
        offset = "0ns",
        closed::Symbol = :right,
    )
    index_expr = index_column isa String ? col(index_column) : index_column
    group_by = convert(Vector{Expr}, map(ex -> ex isa String ? col(ex) : ex, group_by))

    closed_cenum = closed === :left ? API.PolarsClosedWindowLeft :
        closed === :right ? API.PolarsClosedWindowRight :
        closed === :both ? API.PolarsClosedWindowBoth :
        closed === :none ? API.PolarsClosedWindowNone :
        error("invalid closed $closed, expected :left, :right, :both, or :none")

    GC.@preserve index_expr group_by begin
        group_by_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in group_by]
        out = Ref{Ptr{polars_lazy_group_by_t}}()
        err = polars_lazy_frame_rolling(
            df,
            index_expr,
            group_by_ptrs,
            length(group_by_ptrs),
            pointer(period),
            ncodeunits(period),
            pointer(offset),
            ncodeunits(offset),
            closed_cenum,
            out,
        )
        polars_error(err)
    end
    return LazyGroupBy(out[])
end

"""
    sort(df::LazyFrame, exprs...; rev=false, stable=true, nulls_last=true)::LazyFrame
    sort(df::DataFrame, exprs...; rev=false, stable=true, nulls_last=true)::DataFrame

Sorts the columns of the dataframe based on the provided expressions.

 - The `rev` keyword parameter can be used to sort in reverse (descending) order. It
can also be provided as an array of booleans of the same size as the provided expressions.
 - The `stable` keyword argument ensures that rows with equal values from the provided expression
are still in the same order after sorting the dataframe.
 - The `nulls_last` keyword argument indicates whether the null values in the dataframe should be
placed last or first in the resulting sorted dataframe.

```julia
julia> df = DataFrame((; letters=rand(["a", "b", "c", missing], 4)));

julia> sort(df, col("letters"); nulls_last=true)
4×1 DataFrame
 letters
 String?
─────────
       b
       b
       c
 missing


julia>

julia> sort(df, col("letters"); nulls_last=false)
4×1 DataFrame
 letters
 String?
─────────
 missing
       b
       b
       c


julia> sort(df, col("letters"); rev=true)
4×1 DataFrame
 letters
 String?
─────────
       c
       b
       b
 missing
```
"""
Base.sort(df::LazyFrame, exprs...; rev = false, stable = true, nulls_last = true) =
    _sort!(clone(df), collect(exprs)::Vector, rev, stable, nulls_last)
Base.sort(df::DataFrame, exprs...; rev = false, stable = true, nulls_last = true) =
    _sort!(lazy(df), collect(exprs)::Vector, rev, stable, nulls_last) |> collect

function _sort!(df::LazyFrame, exprs::Vector, rev, stable, nulls_last)
    nexprs = length(exprs)
    descending = rev isa Bool ? fill(rev, nexprs) : rev
    @assert length(descending) == nexprs "the rev array should be the same size as the number of exprs (got $nexprs expressions and $(length(rev)) rev)"

    maintain_order = stable

    exprs = map(ex -> ex isa String ? col(ex) : ex, exprs)
    exprs = convert(Vector{Expr}, exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        API.polars_lazy_frame_sort(
            df, exprs_ptrs,
            nexprs, descending,
            nulls_last, maintain_order,
        )
    end

    return df
end

export Series, DataFrame,
    select, with_columns, head, collect_schema,
    read_parquet, write_parquet, scan_parquet,
    read_csv, write_csv, scan_csv, sink_parquet,
    read_ipc, scan_ipc, sink_csv, sink_ipc,
    lazy, group_by, group_by_dynamic, rolling, agg, concat,
    innerjoin, leftjoin, rightjoin, outerjoin, semijoin, antijoin, crossjoin, join_asof,
    drop, with_row_index, explode, unpivot

"""
    collect_schema(lf::LazyFrame)::Tables.Schema

Resolves and returns the schema of the provided lazy frame, without collecting it.

Since this does not execute the query, actual null counts are unknown and every column is
reported as nullable (`Union{T,Missing}`); see [`schema`](@ref) for a `DataFrame`'s schema
refined by actual null counts.
"""
function collect_schema(df::LazyFrame)
    out = Ref{CArrowSchema}()
    err = polars_lazy_frame_collect_schema(df, out)
    polars_error(err)
    return load_dataframe_schema(out[])
end

## Tables.jl interface

import Tables: schema

function schema(df::DataFrame)
    schema = API.polars_dataframe_schema(df)
    (; names, types) = load_dataframe_schema(schema)

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

Tables.columnnames(df::DataFrame) = schema(df).names
Tables.getcolumn(df::DataFrame, col::Symbol) = getindex(df, col)
Tables.getcolumn(df::DataFrame, idx::Int) = Tables.getcolumn(df, Tables.columnnames(df)[idx])

"""
    describe(df::DataFrame; percentiles::AbstractVector{<:Real}=[0.25, 0.5, 0.75])::DataFrame

Computes summary statistics for each column of `df`, returning one row per statistic
(`"count"`, `"null_count"`, `"mean"`, `"std"`, `"min"`, one row per value in `percentiles`
(named e.g. `"25%"`), `"max"`) and one column per column of `df`, plus a leading `"statistic"`
column.

There is no single polars function for this -- py-polars itself composes `describe` from
lower-level primitives, which is what this does too: every value is stringified (via `cast`),
since a single output column otherwise couldn't coherently hold both e.g. a count (integer) and
a mean (float). `mean`/`std`/percentile rows are `missing` for non-numeric columns (only
`count`/`null_count`/`min`/`max` apply there); `min`/`max` are themselves `missing` for columns
whose dtype has no natural ordering (e.g. `List`/`Struct`).
"""
function describe(df::DataFrame; percentiles::AbstractVector{<:Real} = [0.25, 0.5, 0.75])
    sch = schema(df)
    names_ = string.(sch.names)
    types_ = map(nomissing, sch.types)

    is_numeric(T) = T <: Real && T != Bool
    is_orderable(T) = T <: Real || T <: AbstractString || T <: Dates.TimeType

    function stat_row(stat_name, statfn)
        exprs = map(names_, types_) do name, T
            e = statfn(name, T)
            alias(cast(e === nothing ? lit(missing) : e, String), name)
        end
        return select(df, exprs...)
    end

    rows = DataFrame[]
    stat_names = String[]

    push!(stat_names, "count")
    push!(rows, stat_row("count", (name, T) -> Polars.count(col(name))))

    push!(stat_names, "null_count")
    push!(rows, stat_row("null_count", (name, T) -> null_count(col(name))))

    push!(stat_names, "mean")
    push!(rows, stat_row("mean", (name, T) -> is_numeric(T) ? Polars.mean(col(name)) : nothing))

    push!(stat_names, "std")
    push!(rows, stat_row("std", (name, T) -> is_numeric(T) ? Polars.std(col(name)) : nothing))

    push!(stat_names, "min")
    push!(rows, stat_row("min", (name, T) -> is_orderable(T) ? Polars.min(col(name)) : nothing))

    for q in percentiles
        stat_name = string(round(Int, q * 100), "%")
        push!(stat_names, stat_name)
        push!(rows, stat_row(stat_name, (name, T) -> is_numeric(T) ? quantile(col(name), q) : nothing))
    end

    push!(stat_names, "max")
    push!(rows, stat_row("max", (name, T) -> is_orderable(T) ? Polars.max(col(name)) : nothing))

    stats_df = concat(rows)
    table = merge((; statistic = stat_names), map(collect, Tables.columntable(stats_df)))
    return DataFrame(table)
end

export describe

end # module Polars
