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

Removes duplicate rows, considering only `subset` columns if provided (all columns otherwise).
`keep` selects which duplicate to retain: `:first`, `:last`, `:none` (drop all duplicates), or
`:any` (default — no order guarantee, allows more optimization). `maintain_order` preserves row
order in the output (default `false`, which allows more optimization).
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
    drop(lf::LazyFrame, columns::Vector{String})::LazyFrame
    drop(df::DataFrame, columns::Vector{String})::DataFrame

Removes the given columns from the frame.
"""
drop(df::DataFrame, columns::Vector{<:ColId}) = drop(lazy(df), columns) |> collect
function drop(lf::LazyFrame, columns::Vector{<:ColId})
    owned_names, ptrs, lens = _name_ptrs(columns)
    GC.@preserve owned_names begin
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_drop(lf, ptrs, lens, length(ptrs), out)
        polars_error(err)
    end
    return LazyFrame(out[])
end

import Base: rename

"""
    rename(lf::LazyFrame, existing::Vector{String}, new::Vector{String}; strict::Bool=true)::LazyFrame
    rename(df::DataFrame, existing::Vector{String}, new::Vector{String}; strict::Bool=true)::DataFrame

Renames `existing` columns to the corresponding `new` names (same length, paired by position).
If `strict` is `true` (default), every `existing` column must be present; otherwise, missing
ones are silently ignored.
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

Removes rows containing a `null` in any of the `subset` columns (all columns if not provided).
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

Adds a row-index column named `name`, starting at `offset` (default `0`).
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

Concatenates the provided frames. `how` selects the mode:
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

Return a new [`DataFrame`](@ref) grown horizontally by stacking multiple [`Series`](@ref) to it.
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

Grow a [`DataFrame`](@ref) vertically by stacking a DataFrame to it.
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

Replaces every `null` value across all columns of `df` with `value` (an `Expr`, or a literal
promoted via [`lit`](@ref)). Distinct from the `Expr`-level [`fill_null`](@ref) (fills nulls within
one expression, for use inside [`select`](@ref)/[`with_columns`](@ref)) and from
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

Casts the columns named in `dtypes` (a mapping of column name to Julia type, same spellings
[`Polars.cast`](@ref) accepts on a single `Expr`) to their new dtype, leaving every other column
unchanged. Composed from [`with_columns`](@ref) and the per-`Expr` [`Polars.cast`](@ref), so it
supports the same dtypes that one does (including `DateTime`/duration `Period` subtypes via their
`time_unit`/`time_zone` special-casing there) -- there is no dedicated FFI function for this form.
"""
function cast(df::LazyFrame, dtypes::AbstractDict; strict::Bool = false)
    exprs = Expr[cast(col(String(name)), dtype; strict) for (name, dtype) in dtypes]
    return with_columns(df, exprs...)
end
cast(df::DataFrame, dtypes::AbstractDict; strict::Bool = false) = cast(lazy(df), dtypes; strict) |> collect

"""
    cast(df::LazyFrame, dtype::Type; strict::Bool=false)::LazyFrame
    cast(df::DataFrame, dtype::Type; strict::Bool=false)::DataFrame

Casts *every* column of `df` to `dtype`. Only plain (parameter-free) dtypes are reachable here --
same restriction as the single-`Expr` [`Polars.cast`](@ref) -- since the underlying FFI type code
can't carry a `DateTime`'s time unit/zone; use the `AbstractDict` form (per-column, going through
`Polars.cast` itself) for that.
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
