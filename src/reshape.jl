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
            variable_name, ncodeunits(variable_name), value_name, ncodeunits(value_name), out
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

    lf = lazy(df)
    on_columns = collect(unique(select(lf, map(col, on)...)))

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
            lf, on_ptrs, on_lens, length(on_ptrs), on_columns,
            index_ptrs, index_lens, length(index_ptrs),
            values_ptrs, values_lens, length(values_ptrs),
            agg, maintain_order, separator, ncodeunits(separator), naming_enum, out
        )
        polars_error(err)
    end
    return collect(LazyFrame(out[]))
end

"""
    upsample(df::DataFrame, time_column::String; by::Vector{String}=String[], every::String,
             stable::Bool=true)::DataFrame

Upsamples `df` to a regular `every`-spaced grid along `time_column` (a duration string like
`"1h"`/`"1d"`; `time_column` must already be sorted within each `by` group). Newly-inserted rows
have `missing` in every column except `time_column`/`by`. If `by` is given, upsampling happens
independently per group. If `stable` is `true` (default), the original row order is maintained
when `by` is given (at some extra cost); if `false`, order is not guaranteed.
"""
function upsample(
        df::DataFrame, time_column::String; by::Vector{String} = String[], every::String,
        stable::Bool = true
    )
    GC.@preserve by begin
        by_ptrs, by_lens = _name_ptrs(by)
        out = Ref{Ptr{polars_dataframe_t}}()
        err = polars_dataframe_upsample(
            df, by_ptrs, by_lens, length(by_ptrs), time_column, ncodeunits(time_column), every,
            ncodeunits(every), stable, out
        )
        polars_error(err)
    end
    return DataFrame(out[])
end
