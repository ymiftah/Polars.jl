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
