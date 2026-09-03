"""
    _name_ptrs(names)::Tuple{Vector{String}, Vector{Ptr{UInt8}}, Vector{Csize_t}}

Builds the `(owned, ptrs, lens)` triple for passing a list of column names across the C ABI.

`owned` is the `Vector{String}` that `ptrs`' raw pointers point into, and is what the caller must
name in its `GC.@preserve` -- **not** the argument passed in here. For a `Vector{String}` input
`owned === names`, but for any other `ColId` vector (`Vector{Symbol}`, most commonly) it is a
freshly converted copy that nothing else references: preserving only the caller's own argument
would leave every pointer in `ptrs` dangling the instant the GC runs between this call and the
ccall that consumes it -- and the `Ref` allocation each call site makes in between is exactly such
a safepoint. Returning the owner (rather than hiding it inside this function) is what makes that
rooting impossible to forget; `_cut_labels` in expr/statistics.jl already used this shape.
"""
_name_ptrs(names::Vector{String}) =
    (names, Ptr{UInt8}[pointer(s) for s in names], Csize_t[ncodeunits(s) for s in names])
_name_ptrs(names::AbstractVector{<:ColId}) = _name_ptrs(String[String(name) for name in names])

"""
    unique(lf::LazyFrame, subset::Vector{String}=String[]; keep::Symbol=:any, maintain_order::Bool=false)::LazyFrame
    unique(df::DataFrame, subset::Vector{String}=String[]; keep::Symbol=:any, maintain_order::Bool=false)::DataFrame

Drop non-unique rows, considering only `subset` columns if provided (all columns otherwise).
`keep` selects which duplicate to retain: `:first`, `:last`, `:none` (drop all duplicates), or
`:any` (default — no order guarantee, allows more optimization).

With `maintain_order=true`, the order of kept rows is maintained; with `maintain_order=false` (the
default), the order of the kept rows may change.
"""
Base.unique(df::DataFrame, subset::Vector{<:ColId} = String[]; keep::Symbol = :any, maintain_order::Bool = false) =
    unique(lazy(df), subset; keep, maintain_order) |> collect
function Base.unique(
        lf::LazyFrame, subset::Vector{<:ColId} = String[];
        keep::Symbol = :any, maintain_order::Bool = false
    )
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
    owned_names, ptrs, lens = _name_ptrs(subset)
    GC.@preserve owned_names begin
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_unique(lf, ptrs, lens, length(ptrs), keep_enum, maintain_order, out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

function Base.unique(df::LazyFrame, subset::Vararg{ColId}; keep::Symbol = :any, maintain_order::Bool = false)
    return Base.unique(df, collect(subset); keep, maintain_order)
end
Base.unique(df::DataFrame, subset::Vararg{ColId}; keep::Symbol = :any, maintain_order::Bool = false) =
    Base.unique(lazy(df), subset...; keep, maintain_order) |> collect

"""
    drop(lf::LazyFrame, columns::Vector{String}; strict::Bool=true)::LazyFrame
    drop(df::DataFrame, columns::Vector{String}; strict::Bool=true)::DataFrame

Removes the given columns from the frame. It's better to only [`select`](@ref) the columns you
need and let projection pushdown optimize away the unneeded columns.

If `strict` is `true` (the default), any given column not in the schema raises a
[`PolarsError`](@ref); otherwise unknown names are silently ignored, matching [`rename`](@ref)'s
own `strict` convention.
"""
drop(df::DataFrame, columns::Vector{<:ColId}; strict::Bool = true) =
    drop(lazy(df), columns; strict) |> collect
function drop(lf::LazyFrame, columns::Vector{<:ColId}; strict::Bool = true)
    owned_names, ptrs, lens = _name_ptrs(columns)
    GC.@preserve owned_names begin
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_drop(lf, ptrs, lens, length(ptrs), strict, out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

import Base: rename

"""
    rename(lf::LazyFrame, existing::Vector{String}, new::Vector{String}; strict::Bool=true)::LazyFrame
    rename(df::DataFrame, existing::Vector{String}, new::Vector{String}; strict::Bool=true)::DataFrame

Rename columns in the frame. `existing` and `new` are vectors of the same length containing the
old and corresponding new column names. Renaming happens to all `existing` columns
simultaneously, not iteratively. If `strict` is `true` (the default), every column in `existing`
must be present when `rename` is called; otherwise, only those columns that are actually found
are renamed (others are ignored).
"""
Base.rename(df::DataFrame, existing::Vector{<:ColId}, new::Vector{<:ColId}; strict::Bool = true) =
    Base.rename(lazy(df), existing, new; strict) |> collect
function Base.rename(lf::LazyFrame, existing::Vector{<:ColId}, new::Vector{<:ColId}; strict::Bool = true)
    length(existing) == length(new) || error("existing and new must have the same length")
    existing_names, existing_ptrs, existing_lens = _name_ptrs(existing)
    new_names, new_ptrs, new_lens = _name_ptrs(new)
    GC.@preserve existing_names new_names begin
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_rename(
            lf, existing_ptrs, existing_lens, new_ptrs, new_lens, length(existing_ptrs), strict, out
        )
        polars_error(err)
    end
    return LazyFrame(out[])
end

Base.rename(df::DataFrame, pairs::Vararg{Pair{<:ColId, <:ColId}}; strict::Bool = true) =
    Base.rename(lazy(df), pairs...; strict) |> collect
function Base.rename(lf::LazyFrame, pairs::Vararg{Pair{<:ColId, <:ColId}}; strict::Bool = true)
    existing = [k for (k, v) in pairs]
    new = [v for (k, v) in pairs]
    return Base.rename(lf, existing, new; strict = strict)
end

"""
    drop_nulls(lf::LazyFrame, subset::Vector{String}=String[])::LazyFrame
    drop_nulls(df::DataFrame, subset::Vector{String}=String[])::DataFrame

Drop rows containing one or more `null` values, considering only `subset` columns (all columns if
not provided).

Note: an explicitly-empty `subset` behaves the same as omitting it (checks *all* columns) rather
than py-polars' `subset=[]`, which checks zero columns and is therefore a no-op — this wrapper has
no way to distinguish "not provided" from "provided empty" once both collapse to an empty
`Vector`.
"""
drop_nulls(df::DataFrame, subset::Vector{<:ColId} = String[]) = drop_nulls(lazy(df), subset) |> collect
function drop_nulls(lf::LazyFrame, subset::Vector{<:ColId} = String[])
    owned_names, ptrs, lens = _name_ptrs(subset)
    GC.@preserve owned_names begin
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_drop_nulls(lf, ptrs, lens, length(ptrs), out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

"""
    with_row_index(lf::LazyFrame, name::String="index"; offset::Integer=0)::LazyFrame
    with_row_index(df::DataFrame, name::String="index"; offset::Integer=0)::DataFrame

Add a new column as the first column that counts the rows, named `name`, starting at `offset` (`0`
if not given).

This can have a negative effect on query performance -- it may, for instance, block predicate
pushdown optimization.
"""
with_row_index(df::DataFrame, name::ColId = "index"; offset::Integer = 0) =
    with_row_index(lazy(df), name; offset) |> collect
function with_row_index(lf::LazyFrame, name::ColId = "index"; offset::Integer = 0)
    name = String(name)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_with_row_index(lf, name, ncodeunits(name), Int64(offset), true, out)
    polars_error(err)
    return LazyFrame(out[])
end
"""
    concat(frames::Vector{LazyFrame}; how::Symbol=:vertical)::LazyFrame
    concat(frames::Vector{DataFrame}; how::Symbol=:vertical)::DataFrame

Concatenate multiple frames. `how` selects the mode:
- `:vertical` (default): stack rows, matching columns by position -- every frame must have
  identical column names/order.
- `:vertical_relaxed`: like `:vertical`, but matching columns are cast to their common supertype
  instead of requiring identical dtypes.
- `:diagonal`: stack rows, matching columns by *name* -- frames may have different columns
  (missing ones are filled with `missing`).
- `:diagonal_relaxed`: `:diagonal` with the same supertype relaxation as `:vertical_relaxed`.
- `:horizontal`: stack columns side by side (all frames must have the same row count).
"""
concat(frames::Vector{DataFrame}; how::Symbol = :vertical) =
    collect(concat(map(lazy, frames); how))
function concat(frames::Vector{LazyFrame}; how::Symbol = :vertical)
    how_enum = if how == :vertical
        API.PolarsConcatHowVertical
    elseif how == :vertical_relaxed
        API.PolarsConcatHowVerticalRelaxed
    elseif how == :diagonal
        API.PolarsConcatHowDiagonal
    elseif how == :diagonal_relaxed
        API.PolarsConcatHowDiagonalRelaxed
    elseif how == :horizontal
        API.PolarsConcatHowHorizontal
    else
        error("unknown concat how=$how, expected one of (:vertical, :vertical_relaxed, :diagonal, :diagonal_relaxed, :horizontal)")
    end
    GC.@preserve frames begin
        frame_ptrs = Ptr{polars_lazy_frame_t}[frame.ptr for frame in frames]
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_concat(frame_ptrs, length(frame_ptrs), how_enum, out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

"""
    hstack(df::DataFrame, columns::Vector{<:Series})::DataFrame

Add multiple [`Series`](@ref) to `df`. The added series are required to have the same length.
"""
function hstack(df::DataFrame, columns::Vector{<:Series})
    GC.@preserve columns begin
        ptrs = Ptr{polars_series_t}[s.ptr for s in columns]
        out = Ref{Ptr{polars_dataframe_t}}()
        err = polars_dataframe_hstack(df, ptrs, length(ptrs), out)
        polars_error(err)
    end
    return DataFrame(out[])
end

"""
    vstack(df::DataFrame, other::DataFrame)::DataFrame

Concatenate `other` to `df` vertically and return as a newly allocated [`DataFrame`](@ref).
"""
function vstack(df::DataFrame, other::DataFrame)
    out = Ref{Ptr{polars_dataframe_t}}()
    err = polars_dataframe_vstack(df, other, out)
    polars_error(err)
    return DataFrame(out[])
end

"""
    fill_null(df::LazyFrame, value)::LazyFrame
    fill_null(df::DataFrame, value)::DataFrame

Fill `null` values in `df` with `value` (an `Expr`, or a literal promoted via [`lit`](@ref)).

Note: distinct from the `Expr`-level [`fill_null`](@ref) (fills nulls within one expression, for
use inside [`select`](@ref)/[`with_columns`](@ref)) and from
[`forward_fill`](@ref)/[`backward_fill`](@ref) (strategy-based, not a fixed replacement value).
"""
fill_null(df::DataFrame, value) = fill_null(lazy(df), value) |> collect
function fill_null(df::LazyFrame, value)
    value = _as_expr(value)
    API.polars_lazy_frame_fill_null(df, value)
    return df
end

"""
    cast(df::LazyFrame, dtypes::AbstractDict; strict::Bool=false)::LazyFrame
    cast(df::DataFrame, dtypes::AbstractDict; strict::Bool=false)::DataFrame

Cast the columns named in `dtypes` (a mapping of column name to Julia type, same spellings
[`Polars.cast`](@ref) accepts on a single `Expr`) to their new dtype, leaving every other column
unchanged, resulting in a new frame with updated dtypes.
"""
function cast(df::LazyFrame, dtypes::AbstractDict; strict::Bool = false)
    exprs = Expr[cast(col(String(name)), dtype; strict) for (name, dtype) in dtypes]
    return with_columns(df, exprs...)
end
cast(df::DataFrame, dtypes::AbstractDict; strict::Bool = false) = cast(lazy(df), dtypes; strict) |> collect

"""
    cast(df::LazyFrame, dtype::Type; strict::Bool=false)::LazyFrame
    cast(df::DataFrame, dtype::Type; strict::Bool=false)::DataFrame

Cast all frame columns of `df` to `dtype`, resulting in a new frame.

Note: only plain (parameter-free) dtypes are reachable through this whole-frame form, the same
restriction as the single-`Expr` [`Polars.cast`](@ref) — a `DateTime`/duration `Period` subtype
with its own `time_unit`/`time_zone` needs the `AbstractDict` form instead (per-column, going
through `Polars.cast` itself).
"""
function cast(df::LazyFrame, dtype::Type; strict::Bool = false)
    value_type = _plain_value_type_code(dtype)
    value_type === nothing && error("could not cast to type $dtype")
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_cast_all(df, value_type, strict, out)
    polars_error(err)
    return LazyFrame(out[])
end
cast(df::DataFrame, dtype::Type; strict::Bool = false) = cast(lazy(df), dtype; strict) |> collect

export fill_null, cast

"""
    Base.sum(df::LazyFrame)::LazyFrame
    Base.sum(df::DataFrame)::DataFrame

Aggregate all the columns of `df` as their sum values. Aggregated columns have the same names as
the original columns.

Boolean columns sum to the count of `true`s; string columns sum to `missing`; integer overflow
silently wraps.
"""
Base.sum(df::LazyFrame) = _frame_sum!(clone(df))
Base.sum(df::DataFrame) = _frame_sum!(lazy(df)) |> collect
function _frame_sum!(df::LazyFrame)
    API.polars_lazy_frame_sum(df)
    return df
end

"""
    Base.min(df::LazyFrame)::LazyFrame
    Base.min(df::DataFrame)::DataFrame

Aggregate all the columns of `df` as their minimum values. Aggregated columns have the same names
as the original columns.
"""
Base.min(df::LazyFrame) = _frame_min!(clone(df))
Base.min(df::DataFrame) = _frame_min!(lazy(df)) |> collect
function _frame_min!(df::LazyFrame)
    API.polars_lazy_frame_min(df)
    return df
end

"""
    Base.max(df::LazyFrame)::LazyFrame
    Base.max(df::DataFrame)::DataFrame

Aggregate all the columns of `df` as their maximum values. Aggregated columns have the same names
as the original columns.
"""
Base.max(df::LazyFrame) = _frame_max!(clone(df))
Base.max(df::DataFrame) = _frame_max!(lazy(df)) |> collect
function _frame_max!(df::LazyFrame)
    API.polars_lazy_frame_max(df)
    return df
end

"""
    Statistics.mean(df::LazyFrame)::LazyFrame
    Statistics.mean(df::DataFrame)::DataFrame

Aggregate all the columns of `df` as their mean values. Boolean and integer columns are converted
to `Float64` before computing the mean; string columns have a mean of `missing`.
"""
Statistics.mean(df::LazyFrame) = _frame_mean!(clone(df))
Statistics.mean(df::DataFrame) = _frame_mean!(lazy(df)) |> collect
function _frame_mean!(df::LazyFrame)
    API.polars_lazy_frame_mean(df)
    return df
end

"""
    Statistics.median(df::LazyFrame)::LazyFrame
    Statistics.median(df::DataFrame)::DataFrame

Aggregate all the columns of `df` as their median values. Boolean and integer results are
converted to `Float64` (though they are still susceptible to overflow before this conversion
occurs); string columns sum to `missing`.
"""
Statistics.median(df::LazyFrame) = _frame_median!(clone(df))
Statistics.median(df::DataFrame) = _frame_median!(lazy(df)) |> collect
function _frame_median!(df::LazyFrame)
    API.polars_lazy_frame_median(df)
    return df
end

"""
    Statistics.std(df::LazyFrame; ddof::Integer=1)::LazyFrame
    Statistics.std(df::DataFrame; ddof::Integer=1)::DataFrame

Aggregate all the columns of `df` as their standard deviation values.

`ddof` is the "Delta Degrees of Freedom"; `N - ddof` is the denominator when computing the
variance, where `N` is the number of rows. In standard statistical practice, `ddof=1` (the
default) provides an unbiased estimator of the variance of a hypothetical infinite population;
`ddof=0` provides a maximum likelihood estimate of the variance for normally distributed
variables. The standard deviation computed here is the square root of the estimated variance, so
even with `ddof=1` it is not an unbiased estimate of the standard deviation per se. Source:
[Numpy](https://numpy.org/doc/stable/reference/generated/numpy.std.html#).
"""
Statistics.std(df::LazyFrame; ddof::Integer = 1) = _frame_std!(clone(df), ddof)
Statistics.std(df::DataFrame; ddof::Integer = 1) = _frame_std!(lazy(df), ddof) |> collect
function _frame_std!(df::LazyFrame, ddof::Integer)
    API.polars_lazy_frame_std(df, UInt8(ddof))
    return df
end

"""
    Statistics.var(df::LazyFrame; ddof::Integer=1)::LazyFrame
    Statistics.var(df::DataFrame; ddof::Integer=1)::DataFrame

Aggregate all the columns of `df` as their variance values.

`ddof` is the "Delta Degrees of Freedom"; `N - ddof` is the denominator when computing the
variance, where `N` is the number of rows. In standard statistical practice, `ddof=1` (the
default) provides an unbiased estimator of the variance of a hypothetical infinite population;
`ddof=0` provides a maximum likelihood estimate of the variance for normally distributed
variables. Source: [Numpy](https://numpy.org/doc/stable/reference/generated/numpy.var.html#).
"""
Statistics.var(df::LazyFrame; ddof::Integer = 1) = _frame_var!(clone(df), ddof)
Statistics.var(df::DataFrame; ddof::Integer = 1) = _frame_var!(lazy(df), ddof) |> collect
function _frame_var!(df::LazyFrame, ddof::Integer)
    API.polars_lazy_frame_var(df, UInt8(ddof))
    return df
end

"""
    Statistics.quantile(df::LazyFrame, q; method::Symbol=:nearest)::LazyFrame
    Statistics.quantile(df::DataFrame, q; method::Symbol=:nearest)::DataFrame

Aggregate all the columns of `df` as their `q`-th quantile values (`q` an `Expr` or a numeric
literal in `[0, 1]`), using the given interpolation `method` (see the per-`Expr`
[`Statistics.quantile`](@ref) for the choices).
"""
Statistics.quantile(df::LazyFrame, q; method::Symbol = :nearest) = _frame_quantile!(clone(df), q, method)
Statistics.quantile(df::DataFrame, q; method::Symbol = :nearest) = _frame_quantile!(lazy(df), q, method) |> collect
function _frame_quantile!(df::LazyFrame, q, method::Symbol)
    q = convert(Expr, q)
    method_enum = _quantile_method_enum(method)
    API.polars_lazy_frame_quantile(df, q, method_enum)
    return df
end

"""
    Base.prod(df::LazyFrame)::LazyFrame
    Base.prod(df::DataFrame)::DataFrame

The product of the non-null values of every column of `df`, returning a single-row frame with the
same column names.
"""
function Base.prod(df::LazyFrame)
    sch = collect_schema(df)
    exprs = Expr[]
    for (name, T) in zip(sch.names, sch.types)
        e = nomissing(T) <: Real ? Base.prod(col(String(name))) : lit(missing)
        push!(exprs, alias(e, String(name)))
    end
    return select(df, exprs...)
end
Base.prod(df::DataFrame) = Base.prod(lazy(df)) |> collect

"""
    limit(df::LazyFrame, n::Integer)::LazyFrame
    limit(df::DataFrame, n::Integer)::DataFrame

Limit `df` to the first `n` rows. An alias for [`head`](@ref).
"""
limit(df::LazyFrame, n::Integer) = head(df, n)
limit(df::DataFrame, n::Integer) = head(df, n)

export limit

"""
    Base.reverse(df::LazyFrame)::LazyFrame
    Base.reverse(df::DataFrame)::DataFrame

Reverse `df` from top to bottom.
"""
Base.reverse(df::LazyFrame) = _frame_reverse!(clone(df))
Base.reverse(df::DataFrame) = _frame_reverse!(lazy(df)) |> collect
function _frame_reverse!(df::LazyFrame)
    API.polars_lazy_frame_reverse(df)
    return df
end

"""
    null_count(df::LazyFrame)::LazyFrame
    null_count(df::DataFrame)::DataFrame

Aggregate all the columns of `df` as the sum of their `null` value count. The per-column
expression form is [`null_count(::Polars.Expr)`](@ref).
"""
null_count(df::LazyFrame) = _frame_null_count!(clone(df))
null_count(df::DataFrame) = _frame_null_count!(lazy(df)) |> collect
function _frame_null_count!(df::LazyFrame)
    API.polars_lazy_frame_null_count(df)
    return df
end

"""
    Base.count(df::LazyFrame)::LazyFrame
    Base.count(df::DataFrame)::DataFrame

Return the number of non-`null` elements for each column of `df`, as a single-row frame with the
same column names -- the per-column expression form is [`Polars.count`](@ref); the complementary
[`null_count`](@ref) counts the other way.
"""
Base.count(df::LazyFrame) = _frame_count!(clone(df))
Base.count(df::DataFrame) = _frame_count!(lazy(df)) |> collect
function _frame_count!(df::LazyFrame)
    API.polars_lazy_frame_count(df)
    return df
end

"""
    fill_nan(df::LazyFrame, value)::LazyFrame
    fill_nan(df::DataFrame, value)::DataFrame

Fill `NaN` values in `df` with `value` (an expression or a plain scalar). The `null`-replacing
counterpart is [`fill_null`](@ref).
"""
fill_nan(df::LazyFrame, value) = _frame_fill_nan!(clone(df), convert(Expr, value))
fill_nan(df::DataFrame, value) = _frame_fill_nan!(lazy(df), convert(Expr, value)) |> collect
function _frame_fill_nan!(df::LazyFrame, value::Expr)
    API.polars_lazy_frame_fill_nan(df, value)
    return df
end
