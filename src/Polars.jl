module Polars

import PrettyTables, Tables

const MaybeMissing{T} = Union{T,Union{T,Missing}}
const PhysicalDType = Union{Bool,Int8,Int16,Int32,Int64,UInt8,
    UInt16,UInt32,UInt64,Float32,Float64}

nomissing(::Type{MaybeMissing{T}}) where {T} = T
nomissing(::Type{T}) where {T} = T

"Internal function to write back to an IO from rustland"
function _write_callback(user, data, len)
    try
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

        finalizer(polars_series_destroy, series)
    end
end

"""
    Polars.Value{T}

Internal type which represents a reference to a value of type `T` in a series or as a field to
a struct.
"""
mutable struct Value{T}
    ptr::Ptr{polars_value_t}
    parent::Union{Series,Value}

    Value{T}(ptr, parent=nothing) where {T} =
        finalizer(polars_value_destroy, new{T}(ptr, parent))
end

using Dates

struct Datetime{Res}
    v::Value{Datetime{Res}}
end

struct Duration{Res}
    v::Value{Duration{Res}}
end

@enum TimeUnit Nanosecond Microsecond Millisecond

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
    VersionNumber(ver)
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
    try
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
    (Int(rows[]), Int(cols[]))
end

Base.getindex(df::DataFrame, row_index, col_index) = getindex(getindex(df, col_index), row_index)
Base.getindex(df::DataFrame, idx::Int) = Tables.getcolumn(df, idx)
Base.getindex(df::DataFrame, s::String) = getindex(df, Symbol(s))
function Base.getindex(df::DataFrame, s::Symbol)
    s = string(s)::String
    out = Ref{Ptr{polars_series_t}}()
    err = polars_dataframe_get(df, s, length(s), out)
    polars_error(err)
    Series(out[])
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
    LazyFrame(out)
end

"""
    collect(lf::LazyFrame; engine=:default)::DataFrame

Materializes the lazy frame as a DataFrame.
`engine` can be either `:default` (in-memory engine) or `:streaming`.
"""
function Base.collect(df::LazyFrame; engine=:default)
    engine = engine === :default ? API.PolarsEngineInMemory : engine === :streaming ? API.PolarsEngineStreaming : error("unknown engine $engine, expected one of (:default, :streaming)")
    out = Ref{Ptr{polars_dataframe_t}}()
    err = polars_lazy_frame_collect(df, engine, out)
    polars_error(err)
    DataFrame(out[])
end

"""
    read_parquet(path::String)::DataFrame

Reads a dataframe stored in a parquet file.
"""
function read_parquet(path)
    out = Ref{Ptr{polars_dataframe_t}}()
    err = polars_dataframe_read_parquet(path, length(path), out)
    polars_error(err)
    DataFrame(out[])
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
    LazyFrame(out[])
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
    nothing
end
write_parquet(p::String, df::DataFrame) = open(io -> write_parquet(io, df), p, "w")

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
        PrettyTables.TextTableFormat(; PrettyTables.@text__no_horizontal_lines,
            PrettyTables.@text__no_vertical_lines,
            ellipsis_line_skip=3,
            horizontal_line_after_column_labels=true,
            horizontal_line_before_summary_rows=true,
            vertical_line_after_row_label_column=true,
            vertical_line_after_row_number_column=true)

    PrettyTables.pretty_table(io, df;
        alignment_anchor_fallback=:r,
        title=Base.summary(df),
        title_alignment=:l,
        column_label_alignment=:l,
        compact_printing=true,
        maximum_data_column_widths=32,
        vertical_crop_mode=:middle,
        highlighters=[PrettyTables.TextHighlighter(_pretty_tables_highlighter_func, PrettyTables.Crayon(foreground=:dark_gray))],
        table_format=format,
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
    df
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
    df
end

"""
    fetch(lf::LazyFrame, n)::DataFrame

Fetches the `n` first samples from the provided lazy frame and
collect them in a `DataFrame`.
"""
function Base.fetch(df::LazyFrame, n)
    out = Ref{Ptr{polars_dataframe_t}}()
    err = polars_lazy_frame_fetch(df, n, out)
    polars_error(err)
    DataFrame(out[])
end

function _filter!(df::LazyFrame, expr)
    polars_lazy_frame_filter(df, expr)
    df
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
    LazyFrame(out)
end

innerjoin(a, b, expr) = innerjoin(a, b, expr, expr)
innerjoin(a::DataFrame, b::DataFrame, exprs_a, exprs_b) = innerjoin(lazy(a), lazy(b), exprs_a, exprs_b) |> collect
innerjoin(a::LazyFrame, b::LazyFrame, expr_a, expr_b) = innerjoin(a, b, [expr_a], [expr_b])
function innerjoin(a::LazyFrame, b::LazyFrame, exprs_a::Vector, exprs_b::Vector)
    exprs_a = map(ex -> ex isa String ? col(ex) : ex, exprs_a)
    exprs_a = convert(Vector{Expr}, exprs_a)
    exprs_b = map(ex -> ex isa String ? col(ex) : ex, exprs_b)
    exprs_b = convert(Vector{Expr}, exprs_b)
    GC.@preserve exprs_a exprs_b begin
        exprs_a_ptr = Ptr{polars_expr_t}[expr.ptr for expr in exprs_a]
        exprs_b_ptr = Ptr{polars_expr_t}[expr.ptr for expr in exprs_b]
        out = polars_lazy_frame_join_inner(
            a, b,
            exprs_a_ptr, length(exprs_a_ptr),
            exprs_b_ptr, length(exprs_b_ptr),
        )
    end
    LazyFrame(out)
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
    LazyGroupBy(out)
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
    LazyFrame(out)
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
Base.sort(df::LazyFrame, exprs...; rev=false, stable=true, nulls_last=true) =
    _sort!(clone(df), collect(exprs)::Vector, rev, stable, nulls_last)
Base.sort(df::DataFrame, exprs...; rev=false, stable=true, nulls_last=true) =
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

    df
end

export Series, DataFrame,
    select, with_columns, fetch,
    read_parquet, write_parquet, scan_parquet,
    lazy, innerjoin, group_by, agg

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

    Tables.Schema(names, types)
end

Tables.istable(::DataFrame) = true

Tables.columnaccess(::DataFrame) = true
Tables.rowaccess(::DataFrame) = true # enables Pluto.jl viewer

Tables.columns(df::DataFrame) = df

Tables.columnnames(df::DataFrame) = schema(df).names
Tables.getcolumn(df::DataFrame, col::Symbol) = getindex(df, col)
Tables.getcolumn(df::DataFrame, idx::Int) = Tables.getcolumn(df, Tables.columnnames(df)[idx])

end # module Polars
