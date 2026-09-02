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
    Base.show(io::IO, gb::LazyGroupBy)

Prints a short placeholder; a group-by has no resolved schema of its own to show until
[`agg`](@ref) is called.
"""
Base.show(io::IO, ::LazyGroupBy) = print(io, "LazyGroupBy(...) (call agg(...) to materialize)")

"""
    group_by(df::LazyFrame, exprs...; maintain_order::Bool=false)

Returns a lazy group-by object over the provided [`LazyFrame`](@ref).
The values for the group-by can be aggregated using the [`agg`](@ref) function.

`maintain_order`: preserve each group's row order, and the order groups first appear in, through
`agg`'s output (default `false`, which allows more optimizations).
"""
group_by(df::LazyFrame, exprs...; maintain_order::Bool = false) =
    groupby(df, collect(exprs)::Vector; maintain_order)
function groupby(df::LazyFrame, exprs::Vector; maintain_order::Bool = false)
    owned, ptrs = _handle_ptrs(_expr_vector(exprs), Ptr{polars_expr_t})
    GC.@preserve owned begin
        out = polars_lazy_frame_group_by(df, ptrs, length(ptrs), maintain_order)
    end
    return LazyGroupBy(out)
end

"""
    agg(gb, exprs...)::LazyFrame

Aggregates the value over the group-by object and return a resulting [`LazyFrame`](@ref).
"""
agg(gb::LazyGroupBy, exprs...) = agg(gb, collect(exprs)::Vector)
function agg(gb::LazyGroupBy, exprs::Vector)
    owned, ptrs = _handle_ptrs(_expr_vector(exprs), Ptr{polars_expr_t})
    GC.@preserve owned begin
        out = polars_lazy_group_by_agg(gb, ptrs, length(ptrs))
    end
    return LazyFrame(out)
end

"""
    group_by_dynamic(df::LazyFrame, index_column, group_by::Vector=[];
                     every, period=nothing, offset="0ns",
                     closed::Symbol=:left, label::Symbol=:left,
                     include_boundaries::Bool=false, start_by::Symbol=:window_bound)::LazyGroupBy

Groups rows into fixed-size, dynamic time windows based on a time-indexed column. Returns a
[`LazyGroupBy`](@ref) object for aggregation with [`agg`](@ref).

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
    index_expr = _as_expr(index_column)
    group_by = _expr_vector(group_by)
    period = something(period, every)

    label_cenum = _enum_lookup(
        label, "label",
        :left => API.PolarsLabelLeft, :right => API.PolarsLabelRight,
        :data_point => API.PolarsLabelDataPoint,
    )

    closed_cenum = _enum_lookup(
        closed, "closed",
        :left => API.PolarsClosedWindowLeft, :right => API.PolarsClosedWindowRight,
        :both => API.PolarsClosedWindowBoth, :none => API.PolarsClosedWindowNone,
    )

    start_by_cenum = _enum_lookup(
        start_by, "start_by",
        :window_bound => API.PolarsStartByWindowBound, :data_point => API.PolarsStartByDataPoint,
        :monday => API.PolarsStartByMonday, :tuesday => API.PolarsStartByTuesday,
        :wednesday => API.PolarsStartByWednesday, :thursday => API.PolarsStartByThursday,
        :friday => API.PolarsStartByFriday, :saturday => API.PolarsStartBySaturday,
        :sunday => API.PolarsStartBySunday,
    )

    # `every`/`period`/`offset` are passed as raw (pointer, len) pairs below (not through a
    # `String`-accepting ccall wrapper that would `cconvert` them itself), so they must be listed
    # here too -- otherwise nothing roots them past their last "normal" use and the GC is free to
    # collect them before the ccall actually runs.
    GC.@preserve index_expr group_by every period offset begin
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

Creates rolling groups based on a time-indexed column. Returns a [`LazyGroupBy`](@ref) object for
aggregation with [`agg`](@ref).

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
    index_expr = _as_expr(index_column)
    group_by = _expr_vector(group_by)

    closed_cenum = _enum_lookup(
        closed, "closed",
        :left => API.PolarsClosedWindowLeft, :right => API.PolarsClosedWindowRight,
        :both => API.PolarsClosedWindowBoth, :none => API.PolarsClosedWindowNone,
    )

    # See the matching comment in `group_by_dynamic` above: `period`/`offset` are passed as raw
    # (pointer, len) pairs, so they must be preserved through the ccall explicitly.
    GC.@preserve index_expr group_by period offset begin
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
