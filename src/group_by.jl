"""
    LazyGroupBy

Utility struct for lazy group_by operation. Aggregate it with [`agg`](@ref).
"""
mutable struct LazyGroupBy
    ptr::Ptr{polars_lazy_group_by_t}

    LazyGroupBy(ptr) =
        finalizer(polars_lazy_group_by_destroy, new(ptr))
end

Base.unsafe_convert(::Type{Ptr{polars_lazy_group_by_t}}, gb::LazyGroupBy) = gb.ptr

"""
    Base.show(io::IO, gb::LazyGroupBy)

Print a placeholder; a group-by has no schema until [`agg`](@ref) is called.
"""
Base.show(io::IO, ::LazyGroupBy) = print(io, "LazyGroupBy(...) (call agg(...) to materialize)")

"""
    group_by(df::LazyFrame, exprs...; maintain_order::Bool=false)

Performs a "group-by" on a `LazyFrame`, producing a [`LazyGroupBy`](@ref), which can
subsequently be aggregated. Takes a list of expressions to group on.

With `maintain_order=true`, groups are kept in order of first appearance.
"""
group_by(df::LazyFrame, exprs...; maintain_order::Bool = false) =
    groupby(df, collect(exprs)::Vector; maintain_order)
function groupby(df::LazyFrame, exprs::Vector; maintain_order::Bool = false)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        out = polars_lazy_frame_group_by(df, exprs_ptrs, length(exprs_ptrs), maintain_order)
    end
    return LazyGroupBy(out)
end

"""
    agg(gb, exprs...)::LazyFrame

Group by and aggregate.

Select a column with [`col`](@ref) and choose an aggregation. If you want to aggregate all columns
use `col("*")`.
"""
agg(gb::LazyGroupBy, exprs...) = agg(gb, collect(exprs)::Vector)
function agg(gb::LazyGroupBy, exprs::Vector)
    exprs = _expr_vector(exprs)
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

Group based on a time value (or index value of type Int32, Int64).

Time windows are calculated and rows are assigned to windows. Different from a normal group_by is
that a row can be member of multiple groups.

- `every`: interval of the windows, e.g. `"1d"`.
- `period`: length of the windows (defaults to `every`).
- `offset`: offset of the window start.
- `closed`: `:left` (default), `:right`, `:both` or `:none`.
- `label`: `:left` (default), `:right` or `:data_point`.
- `include_boundaries`: add the window boundaries as columns.
- `start_by`: `:window_bound` (default), `:data_point`, or a weekday (`:monday`, ...).
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

    label_cenum = label === :left ? API.PolarsLabelLeft :
        label === :right ? API.PolarsLabelRight :
        label === :data_point ? API.PolarsLabelDataPoint :
        error("invalid label $label, expected :left, :right, or :data_point")

    closed_cenum = _closed_window_enum(closed)

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

    # Passed as raw (pointer, len) pairs, so root them explicitly.
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

Create rolling groups based on a time column.

Also works for index values of type UInt32, UInt64, Int32, or Int64. Different from a
[`group_by_dynamic`](@ref), the windows are now determined by the individual values and are not of
constant intervals.

- `period`: length of the window, e.g. `"7d"`.
- `offset`: offset of the window.
- `closed`: `:left`, `:right` (default), `:both` or `:none`.
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

    closed_cenum = _closed_window_enum(closed)

    # Passed as raw (pointer, len) pairs, so root them explicitly.
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
