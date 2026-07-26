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

import Base: rename

"""
    rename(lf::LazyFrame, existing::Vector{String}, new::Vector{String}; strict::Bool=true)::LazyFrame
    rename(df::DataFrame, existing::Vector{String}, new::Vector{String}; strict::Bool=true)::DataFrame

Renames `existing` columns to the corresponding `new` names (same length, paired by position).
If `strict` is `true` (default), every `existing` column must be present; otherwise, missing
ones are silently ignored.

Extends `Base.rename` (a `Base.Filesystem` path-renaming function). Like `tail` in `select.jl`,
this is `isdefined(Base, :rename) == true` but **not exported**, so the explicit `import Base:
rename` above is required for the `export rename` in `Polars.jl` to resolve to anything --
without it, plain `rename(df, ...)` raises `UndefVarError` even though `Base.rename(df, ...)`
works.
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

Attaches loose `columns` (bare [`Series`](@ref), not another `DataFrame`) to `df` as new columns,
side by side. This is the real value-add over [`concat`](@ref)'s `:horizontal` mode, which needs a
second full `DataFrame` on the right-hand side — `hstack` accepts standalone `Series` directly.
Eager-only (no `LazyFrame` method — bare `Series` have no lazy equivalent to attach to a plan).

Every `Series` in `columns` must have the same length as `df`'s existing height (an empty `df`
therefore requires length-0 `columns` too); a length mismatch, or a name collision with an
existing `df` column or between two of the given `columns`, errors rather than silently
truncating or overwriting.
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

Stacks `other`'s rows beneath `df`'s. Unlike [`concat`](@ref)'s `:vertical_relaxed` mode, `vstack`
does no supertype casting: `df` and `other` must already share identical column names/dtypes, or
this errors rather than casting. Eager-only (no `LazyFrame` method) — the lazy equivalent is
`concat` with `how=:vertical`.
"""
function vstack(df::DataFrame, other::DataFrame)
    out = Ref{Ptr{polars_dataframe_t}}()
    err = polars_dataframe_vstack(df, other, out)
    polars_error(err)
    return DataFrame(out[])
end
