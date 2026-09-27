import Statistics: cor, cov, mean, median, quantile, std, var

"""Shared `method` resolver for [`quantile`](@ref) and [`rolling_quantile`](@ref)."""
_quantile_method_enum(method::Symbol) = _enum_lookup(
    method, "quantile method",
    :nearest => API.PolarsQuantileMethodNearest,
    :lower => API.PolarsQuantileMethodLower,
    :higher => API.PolarsQuantileMethodHigher,
    :midpoint => API.PolarsQuantileMethodMidpoint,
    :linear => API.PolarsQuantileMethodLinear,
    :equiprobable => API.PolarsQuantileMethodEquiprobable,
)

"""
    mean(expr::Polars.Expr)::Polars.Expr

Reduce groups to the mean value.
"""
Statistics.mean(expr::Expr) = Expr(API.polars_expr_mean(expr))

"""
    median(expr::Polars.Expr)::Polars.Expr

Reduce groups to the median value.
"""
Statistics.median(expr::Expr) = Expr(API.polars_expr_median(expr))

"""
    std(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Standard deviation of the values of the Series.
"""
function Statistics.std(expr::Expr; ddof::Integer = 1)
    out = API.polars_expr_std(expr, UInt8(ddof))
    return Expr(out)
end

"""
    var(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Variance of the values of the Series.
"""
function Statistics.var(expr::Expr; ddof::Integer = 1)
    out = API.polars_expr_var(expr, UInt8(ddof))
    return Expr(out)
end

"""
    quantile(expr::Polars.Expr, q; method::Symbol=:nearest)::Polars.Expr

Compute the quantile per group. `method` is one of `:nearest` (default), `:lower`, `:higher`,
`:midpoint`, `:linear`, `:equiprobable`.
"""
function Statistics.quantile(expr::Expr, q; method::Symbol = :nearest)
    q = convert(Expr, q)
    method_enum = _quantile_method_enum(method)
    out = API.polars_expr_quantile(expr, q, method_enum)
    return Expr(out)
end

export mean, median, std, var, quantile

"""
    cov(a::Polars.Expr, b::Polars.Expr; ddof::Integer=1)::Polars.Expr

Compute the covariance between two columns.
"""
function Statistics.cov(a::Expr, b::Expr; ddof::Integer = 1)
    out = API.polars_expr_cov(a, b, UInt8(ddof))
    return Expr(out)
end

"""
    cor(a::Polars.Expr, b::Polars.Expr)::Polars.Expr

Compute the pearson correlation between two columns.
"""
function Statistics.cor(a::Expr, b::Expr)
    out = API.polars_expr_pearson_corr(a, b)
    return Expr(out)
end

export cov, cor

"""
    spearman_rank_corr(a::Polars.Expr, b::Polars.Expr; propagate_nans::Bool=false)::Polars.Expr

Compute the spearman rank correlation between two columns. Missing data will be excluded from the
computation.

- `propagate_nans`: if `true` any `NaN` encountered will lead to `NaN` in the output. If `false`
  then `NaN` are regarded as larger than any finite number and thus lead to the highest rank.
"""
function spearman_rank_corr(a::Expr, b::Expr; propagate_nans::Bool = false)
    out = API.polars_expr_spearman_rank_corr(a, b, propagate_nans)
    return Expr(out)
end

export spearman_rank_corr

@wrap_expr_method skew(expr::Expr; bias::Bool = true) polars_expr_skew "Compute the sample skewness of a data set.\n\nFor normally distributed data, the skewness should be about zero. For uni-modal continuous distributions, a skewness value greater than zero means that there is more weight in the right tail of the distribution.\n\nIf `bias` is `false`, the calculation is corrected for statistical bias."

@curry skew(; bias::Bool = true)

export skew

@wrap_expr_method kurtosis(expr::Expr; fisher::Bool = true, bias::Bool = true) polars_expr_kurtosis "Compute the kurtosis (Fisher or Pearson).\n\nKurtosis is the fourth central moment divided by the square of the variance. If Fisher's definition is used, then 3.0 is subtracted from the result to give 0.0 for a normal distribution. If bias is `false` then the kurtosis is calculated using k statistics to eliminate bias coming from biased moment estimators.\n\nNote: not exported; call it as `Polars.kurtosis`, or as `kurtosis` with StatsBase.jl loaded."

@curry kurtosis(; fisher::Bool = true, bias::Bool = true)


@wrap_expr_method top_k(expr::Expr, k::Expr) polars_expr_top_k "Returns the `k` largest elements.\n\nThis has time complexity `O(n + k log(n))`."
@curry top_k(k)
export top_k

@wrap_expr_method bottom_k(expr::Expr, k::Expr) polars_expr_bottom_k "Returns the `k` smallest elements.\n\nThis has time complexity `O(n + k log(n))`."
@curry bottom_k(k)
export bottom_k


"""
    value_counts(expr::Polars.Expr; sort::Bool=false, parallel::Bool=false, name::String="count",
                 normalize::Bool=false)::Polars.Expr

Count all unique values and create a struct mapping value to count. (Note that it is better to
turn parallel off in the aggregation context.) The name of the struct field with the counts is
given by the parameter `name`.
"""
function value_counts(
        expr::Expr; sort::Bool = false, parallel::Bool = false, name::String = "count",
        normalize::Bool = false
    )
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_value_counts(expr, sort, parallel, name, ncodeunits(name), normalize, out)
    polars_error(err)
    return Expr(out[])
end

@curry value_counts(; sort::Bool = false, parallel::Bool = false, name::String = "count", normalize::Bool = false)

export value_counts

"""
    sample_n(expr::Polars.Expr, n; with_replacement::Bool=false, shuffle::Bool=false,
             seed::Union{Nothing,Integer}=nothing)::Polars.Expr

Sample `n` values.
"""
function sample_n(
        expr::Expr, n; with_replacement::Bool = false, shuffle::Bool = false,
        seed::Union{Nothing, Integer} = nothing
    )
    n = convert(Expr, n)
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
    out = GC.@preserve seed_ref API.polars_expr_sample_n(expr, n, with_replacement, shuffle, seed_ref)
    return Expr(out)
end

@curry sample_n(n; with_replacement::Bool = false, shuffle::Bool = false, seed::Union{Nothing, Integer} = nothing)

export sample_n

"""
    sample_frac(expr::Polars.Expr, frac; with_replacement::Bool=false, shuffle::Bool=false,
                seed::Union{Nothing,Integer}=nothing)::Polars.Expr

Sample a fraction `frac` of the values.
"""
function sample_frac(
        expr::Expr, frac; with_replacement::Bool = false, shuffle::Bool = false,
        seed::Union{Nothing, Integer} = nothing
    )
    frac = convert(Expr, frac)
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
    out = GC.@preserve seed_ref API.polars_expr_sample_frac(expr, frac, with_replacement, shuffle, seed_ref)
    return Expr(out)
end

@curry sample_frac(frac; with_replacement::Bool = false, shuffle::Bool = false, seed::Union{Nothing, Integer} = nothing)

export sample_frac


@wrap_expr_method cum_sum(expr::Expr; reverse::Bool = false) polars_expr_cum_sum "Get an array with the cumulative sum computed at every element."
@wrap_expr_method cum_prod(expr::Expr; reverse::Bool = false) polars_expr_cum_prod "Get an array with the cumulative product computed at every element."
@wrap_expr_method cum_min(expr::Expr; reverse::Bool = false) polars_expr_cum_min "Get an array with the cumulative min computed at every element."
@wrap_expr_method cum_max(expr::Expr; reverse::Bool = false) polars_expr_cum_max "Get an array with the cumulative max computed at every element."
@wrap_expr_method cum_count(expr::Expr; reverse::Bool = false) polars_expr_cum_count "Cumulatively count values from 0 to len."

@curry cum_sum(; reverse::Bool = false)
@curry cum_prod(; reverse::Bool = false)
@curry cum_min(; reverse::Bool = false)
@curry cum_max(; reverse::Bool = false)
@curry cum_count(; reverse::Bool = false)

export cum_sum, cum_prod, cum_min, cum_max, cum_count

"""
    rolling_mean(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                 center::Bool=false)::Polars.Expr

Apply a rolling mean.

`min_samples` is the minimum number of non-null values in the window required to compute a
result. `center` sets the result at the center of the window.
"""
function rolling_mean(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_mean(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_sum(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                center::Bool=false)::Polars.Expr

Apply a rolling sum.

`min_samples` is the minimum number of non-null values in the window required to compute a
result. `center` sets the result at the center of the window.
"""
function rolling_sum(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_sum(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_min(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                center::Bool=false)::Polars.Expr

Apply a rolling minimum.

`min_samples` is the minimum number of non-null values in the window required to compute a
result. `center` sets the result at the center of the window.
"""
function rolling_min(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_min(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_max(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                center::Bool=false)::Polars.Expr

Apply a rolling maximum.

`min_samples` is the minimum number of non-null values in the window required to compute a
result. `center` sets the result at the center of the window.
"""
function rolling_max(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_max(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_std(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                center::Bool=false, ddof::Integer=1)::Polars.Expr

Apply a rolling std-dev.

`min_samples` is the minimum number of non-null values in the window required to compute a
result. `center` sets the result at the center of the window.
"""
function rolling_std(
        expr::Expr, window_size::Integer;
        min_samples::Integer = window_size, center::Bool = false, ddof::Integer = 1
    )
    out = API.polars_expr_rolling_std(expr, Csize_t(window_size), Csize_t(min_samples), center, UInt8(ddof))
    return Expr(out)
end

"""
    rolling_var(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                center::Bool=false, ddof::Integer=1)::Polars.Expr

Apply a rolling variance.

`min_samples` is the minimum number of non-null values in the window required to compute a
result. `center` sets the result at the center of the window.
"""
function rolling_var(
        expr::Expr, window_size::Integer;
        min_samples::Integer = window_size, center::Bool = false, ddof::Integer = 1
    )
    out = API.polars_expr_rolling_var(expr, Csize_t(window_size), Csize_t(min_samples), center, UInt8(ddof))
    return Expr(out)
end

"""
    rolling_median(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                   center::Bool=false)::Polars.Expr

Apply a rolling median.

`min_samples` is the minimum number of non-null values in the window required to compute a
result. `center` sets the result at the center of the window.
"""
function rolling_median(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_median(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_quantile(expr::Polars.Expr, window_size::Integer, quantile::Real;
                     min_samples::Integer=window_size, center::Bool=false,
                     method::Symbol=:nearest)::Polars.Expr

Apply a rolling quantile. `method` is as in [`quantile`](@ref).

`min_samples` is the minimum number of non-null values in the window required to compute a
result. `center` sets the result at the center of the window.
"""
function rolling_quantile(
        expr::Expr, window_size::Integer, quantile::Real;
        min_samples::Integer = window_size, center::Bool = false, method::Symbol = :nearest
    )
    method_enum = _quantile_method_enum(method)
    out = API.polars_expr_rolling_quantile(
        expr, Csize_t(window_size), Csize_t(min_samples), center, Float64(quantile), method_enum
    )
    return Expr(out)
end

@curry rolling_mean(window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
@curry rolling_sum(window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
@curry rolling_min(window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
@curry rolling_max(window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
@curry rolling_std(window_size::Integer; min_samples::Integer = window_size, center::Bool = false, ddof::Integer = 1)
@curry rolling_var(window_size::Integer; min_samples::Integer = window_size, center::Bool = false, ddof::Integer = 1)
@curry rolling_median(window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
@curry rolling_quantile(
    window_size::Integer, quantile::Real; min_samples::Integer = window_size, center::Bool = false,
    method::Symbol = :nearest,
)

export rolling_mean, rolling_sum, rolling_min, rolling_max, rolling_std, rolling_var,
    rolling_median, rolling_quantile


"""
    rank(expr::Polars.Expr; method::Symbol=:dense, descending::Bool=false)::Polars.Expr

Assign ranks to data, dealing with ties appropriately. `method` is one of `:average`, `:min`,
`:max`, `:dense` (default), `:ordinal`.
"""
function rank(expr::Expr; method::Symbol = :dense, descending::Bool = false)
    method_enum = _enum_lookup(
        method, "rank method",
        :average => API.PolarsRankMethodAverage,
        :min => API.PolarsRankMethodMin,
        :max => API.PolarsRankMethodMax,
        :dense => API.PolarsRankMethodDense,
        :ordinal => API.PolarsRankMethodOrdinal,
    )
    out = API.polars_expr_rank(expr, method_enum, descending)
    return Expr(out)
end

@curry rank(; method::Symbol = :dense, descending::Bool = false)

export rank

"""
Converts exactly one of `com`/`span`/`half_life`/`alpha` to the decay factor `alpha`, as
`EWMOptions`' builder methods do. Errors if not exactly one is given or it is out of range.
"""
function _resolve_ewm_alpha(; com = nothing, span = nothing, half_life = nothing, alpha = nothing)
    given = count(!isnothing, (com, span, half_life, alpha))
    given == 1 ||
        error("specify exactly one of `com`, `span`, `half_life`, `alpha` (got $given)")
    if alpha !== nothing
        0 < alpha <= 1 || error("require 0 < `alpha` <= 1, got $alpha")
        return Float64(alpha)
    elseif com !== nothing
        com >= 0 || error("require `com` >= 0, got $com")
        return 1.0 / (1.0 + com)
    elseif span !== nothing
        span >= 1 || error("require `span` >= 1, got $span")
        return 2.0 / (span + 1.0)
    else
        half_life > 0 || error("require `half_life` > 0, got $half_life")
        return 1.0 - exp(-log(2.0) / half_life)
    end
end

"""
    ewm_mean(expr::Polars.Expr; com=nothing, span=nothing, half_life=nothing, alpha=nothing,
             adjust::Bool=true, min_samples::Integer=1, ignore_nulls::Bool=true)::Polars.Expr

Calculate the exponentially-weighted moving average.

Exactly one of these sets the decay:
- `com`: center of mass, `alpha = 1 / (1 + com)`, `com >= 0`
- `span`: `alpha = 2 / (span + 1)`, `span >= 1`
- `half_life`: `alpha = 1 - exp(-ln(2) / half_life)`, `half_life > 0`
- `alpha`: `0 < alpha <= 1`
"""
function ewm_mean(
        expr::Expr; com = nothing, span = nothing, half_life = nothing, alpha = nothing,
        adjust::Bool = true, min_samples::Integer = 1, ignore_nulls::Bool = true
    )
    a = _resolve_ewm_alpha(; com, span, half_life, alpha)
    out = API.polars_expr_ewm_mean(expr, a, adjust, Csize_t(min_samples), ignore_nulls)
    return Expr(out)
end

@curry ewm_mean(;
    com = nothing, span = nothing, half_life = nothing, alpha = nothing,
    adjust::Bool = true, min_samples::Integer = 1, ignore_nulls::Bool = true,
)

export ewm_mean

"""
    ewm_std(expr::Polars.Expr; com=nothing, span=nothing, half_life=nothing, alpha=nothing,
            adjust::Bool=true, bias::Bool=false, min_samples::Integer=1,
            ignore_nulls::Bool=true)::Polars.Expr

Calculate the exponentially-weighted moving standard deviation. See [`ewm_mean`](@ref) for the
decay arguments.
"""
function ewm_std(
        expr::Expr; com = nothing, span = nothing, half_life = nothing, alpha = nothing,
        adjust::Bool = true, bias::Bool = false, min_samples::Integer = 1, ignore_nulls::Bool = true
    )
    a = _resolve_ewm_alpha(; com, span, half_life, alpha)
    out = API.polars_expr_ewm_std(expr, a, adjust, bias, Csize_t(min_samples), ignore_nulls)
    return Expr(out)
end

@curry ewm_std(;
    com = nothing, span = nothing, half_life = nothing, alpha = nothing,
    adjust::Bool = true, bias::Bool = false, min_samples::Integer = 1, ignore_nulls::Bool = true,
)

export ewm_std

"""
    ewm_var(expr::Polars.Expr; com=nothing, span=nothing, half_life=nothing, alpha=nothing,
            adjust::Bool=true, bias::Bool=false, min_samples::Integer=1,
            ignore_nulls::Bool=true)::Polars.Expr

Calculate the exponentially-weighted moving variance. See [`ewm_mean`](@ref) for the decay
arguments.
"""
function ewm_var(
        expr::Expr; com = nothing, span = nothing, half_life = nothing, alpha = nothing,
        adjust::Bool = true, bias::Bool = false, min_samples::Integer = 1, ignore_nulls::Bool = true
    )
    a = _resolve_ewm_alpha(; com, span, half_life, alpha)
    out = API.polars_expr_ewm_var(expr, a, adjust, bias, Csize_t(min_samples), ignore_nulls)
    return Expr(out)
end

@curry ewm_var(;
    com = nothing, span = nothing, half_life = nothing, alpha = nothing,
    adjust::Bool = true, bias::Bool = false, min_samples::Integer = 1, ignore_nulls::Bool = true,
)

export ewm_var

# `(owned, ptrs, lens)` for `labels`, as `_name_ptrs`; `nothing` becomes an empty list (generated
# labels).
_cut_labels(labels::Union{Nothing, Vector{String}}) =
    _name_ptrs(labels === nothing ? String[] : labels)

"""
    cut(expr::Polars.Expr, breaks::AbstractVector{<:Real}; labels::Union{Nothing,Vector{String}}=nothing,
        left_closed::Bool=false)::Polars.Expr

Bin continuous values into discrete categories.

`labels` must have `length(breaks) + 1` entries; by default the labels are the interval strings.

Note: not exported; call it as `Polars.cut`, or as `cut` with CategoricalArrays.jl loaded.
`include_breaks` is not supported.
"""
function cut(
        expr::Expr, breaks::AbstractVector{<:Real};
        labels::Union{Nothing, Vector{String}} = nothing, left_closed::Bool = false
    )
    breaks_f64 = Vector{Float64}(breaks)
    labels_v, ptrs, lens = _cut_labels(labels)
    GC.@preserve breaks_f64 labels_v begin
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_cut(
            expr, pointer(breaks_f64), length(breaks_f64), ptrs, lens, length(ptrs), left_closed, out
        )
        polars_error(err)
    end
    return Expr(out[])
end

@curry cut(breaks::AbstractVector{<:Real}; labels::Union{Nothing, Vector{String}} = nothing, left_closed::Bool = false)

"""
    qcut(expr::Polars.Expr, probs::AbstractVector{<:Real}; labels::Union{Nothing,Vector{String}}=nothing,
         left_closed::Bool=false, allow_duplicates::Bool=false)::Polars.Expr

Bin continuous values into discrete categories based on their quantiles.
"""
function qcut(
        expr::Expr, probs::AbstractVector{<:Real};
        labels::Union{Nothing, Vector{String}} = nothing, left_closed::Bool = false,
        allow_duplicates::Bool = false
    )
    probs_f64 = Vector{Float64}(probs)
    labels_v, ptrs, lens = _cut_labels(labels)
    GC.@preserve probs_f64 labels_v begin
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_qcut(
            expr, pointer(probs_f64), length(probs_f64), ptrs, lens, length(ptrs),
            left_closed, allow_duplicates, out
        )
        polars_error(err)
    end
    return Expr(out[])
end

@curry qcut(
    probs::AbstractVector{<:Real}; labels::Union{Nothing, Vector{String}} = nothing,
    left_closed::Bool = false, allow_duplicates::Bool = false,
)

export qcut

"""
    qcut_uniform(expr::Polars.Expr, n_bins::Integer; labels::Union{Nothing,Vector{String}}=nothing,
                 left_closed::Bool=false, allow_duplicates::Bool=false)::Polars.Expr

Bin continuous values into discrete categories using uniform quantile probabilities.
"""
function qcut_uniform(
        expr::Expr, n_bins::Integer;
        labels::Union{Nothing, Vector{String}} = nothing, left_closed::Bool = false,
        allow_duplicates::Bool = false
    )
    labels_v, ptrs, lens = _cut_labels(labels)
    GC.@preserve labels_v begin
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_qcut_uniform(
            expr, Csize_t(n_bins), ptrs, lens, length(ptrs), left_closed, allow_duplicates, out
        )
        polars_error(err)
    end
    return Expr(out[])
end

@curry qcut_uniform(
    n_bins::Integer; labels::Union{Nothing, Vector{String}} = nothing,
    left_closed::Bool = false, allow_duplicates::Bool = false,
)

export qcut_uniform
