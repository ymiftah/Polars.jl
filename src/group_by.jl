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
