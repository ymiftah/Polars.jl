"""
    describe(df::DataFrame; percentiles::AbstractVector{<:Real}=[0.25, 0.5, 0.75])::DataFrame

Summary statistics for a DataFrame: `count`, `null_count`, `mean`, `std`, `min`, the
`percentiles`, and `max`, one row each. Values are strings; a statistic that doesn't apply to a
column's dtype is `missing`.
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
        pct = round(q * 100, digits = 10)  # clear float noise (e.g. 0.999*100 != 99.9 exactly)
        stat_name = string(pct == round(pct) ? string(Int(round(pct))) : string(pct), "%")
        push!(stat_names, stat_name)
        push!(rows, stat_row(stat_name, (name, T) -> is_numeric(T) ? quantile(col(name), q) : nothing))
    end

    push!(stat_names, "max")
    push!(rows, stat_row("max", (name, T) -> is_orderable(T) ? Polars.max(col(name)) : nothing))

    stats_df = concat(rows)
    table = merge((; statistic = stat_names), map(collect, Tables.columntable(stats_df)))
    return DataFrame(table)
end
