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

Arithmetic mean of the values.
"""
Statistics.mean(expr::Expr) = Expr(API.polars_expr_mean(expr))

"""
    median(expr::Polars.Expr)::Polars.Expr

Median of the values.
"""
Statistics.median(expr::Expr) = Expr(API.polars_expr_median(expr))

"""
    std(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Standard deviation of the values, with `ddof` degrees of freedom subtracted (defaults to
`ddof=1`).

!!! note
    No curried (`|>`) form -- use `x -> std(x; ddof=2)` instead.
"""
function Statistics.std(expr::Expr; ddof::Integer = 1)
    out = API.polars_expr_std(expr, UInt8(ddof))
    return Expr(out)
end

"""
    var(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Variance of the values, with `ddof` degrees of freedom subtracted (defaults to `ddof=1`).

!!! note
    No curried (`|>`) form -- use `x -> var(x; ddof=2)` instead.
"""
function Statistics.var(expr::Expr; ddof::Integer = 1)
    out = API.polars_expr_var(expr, UInt8(ddof))
    return Expr(out)
end

"""
    quantile(expr::Polars.Expr, q; method::Symbol=:nearest)::Polars.Expr

Computes the `q`-th quantile (`q` an `Expr` or a numeric literal in `[0, 1]`) of the values, using
the given interpolation `method`: one of `:nearest` (default), `:lower`, `:higher`, `:midpoint`,
`:linear`, `:equiprobable`.

!!! note
    No curried (`|>`) form -- use `x -> quantile(x, 0.5)` instead.
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

Compute the covariance between two expressions.

`ddof` is the "delta degrees of freedom": the divisor used in the calculation is `N - ddof`, where
`N` is the number of elements. Defaults to `1`.

!!! note
    No curried (`|>`) form.
"""
function Statistics.cov(a::Expr, b::Expr; ddof::Integer = 1)
    out = API.polars_expr_cov(a, b, UInt8(ddof))
    return Expr(out)
end

"""
    cor(a::Polars.Expr, b::Polars.Expr)::Polars.Expr

Compute the Pearson correlation between two expressions.

A constant (zero-variance) input gives `NaN`.

See also [`spearman_rank_corr`](@ref) for the rank correlation.
"""
function Statistics.cor(a::Expr, b::Expr)
    out = API.polars_expr_pearson_corr(a, b)
    return Expr(out)
end

export cov, cor

"""
    spearman_rank_corr(a::Polars.Expr, b::Polars.Expr; propagate_nans::Bool=false)::Polars.Expr

Compute the Spearman rank correlation between two expressions.

If `propagate_nans` is `true`, any `NaN` encountered leads to `NaN` in the output. Defaults to
`false`, where `NaN`s are regarded as larger than any finite number and thus lead to the highest
rank.

See also [`cor`](@ref) for the Pearson correlation.
"""
function spearman_rank_corr(a::Expr, b::Expr; propagate_nans::Bool = false)
    out = API.polars_expr_spearman_rank_corr(a, b, propagate_nans)
    return Expr(out)
end

export spearman_rank_corr

"""
    skew(expr::Polars.Expr; bias::Bool=true)::Polars.Expr

Compute the sample skewness of the values.

For normally distributed data, the skewness should be about zero. For unimodal continuous
distributions, a skewness value greater than zero means that there is more weight in the right
tail of the distribution.

The sample skewness is computed as the Fisher-Pearson coefficient of skewness. If `bias` is
`false`, the calculation is corrected for statistical bias.
"""
function skew(expr::Expr; bias::Bool = true)
    out = API.polars_expr_skew(expr, bias)
    return Expr(out)
end

@curry skew(; bias::Bool = true)

export skew

"""
    kurtosis(expr::Polars.Expr; fisher::Bool=true, bias::Bool=true)::Polars.Expr

Compute the kurtosis (Fisher or Pearson) of the values.

Kurtosis is the fourth central moment divided by the square of the variance. If `fisher` is
`true` (default), `3.0` is subtracted from the result so that a normal distribution gives `0.0`;
if `false`, Pearson's definition is used (`3.0` for a normal distribution). If `bias` is `false`,
the calculation is corrected for statistical bias.

A constant (zero-variance) input gives `NaN`, not an error.

With StatsBase.jl loaded, the bare `kurtosis(expr)`/`skewness(expr)` also work.
"""
function kurtosis(expr::Expr; fisher::Bool = true, bias::Bool = true)
    out = API.polars_expr_kurtosis(expr, fisher, bias)
    return Expr(out)
end

@curry kurtosis(; fisher::Bool = true, bias::Bool = true)


"""
    top_k(expr::Polars.Expr, k)::Polars.Expr

Returns the `k` largest elements of `expr` (not necessarily sorted; combine with [`sort_by`](@ref)
if order matters).
"""
function top_k(expr::Expr, k)
    k = convert(Expr, k)
    out = API.polars_expr_top_k(expr, k)
    return Expr(out)
end

@curry top_k(k)

export top_k

"""
    bottom_k(expr::Polars.Expr, k)::Polars.Expr

Returns the `k` smallest elements of `expr` (not necessarily sorted; combine with
[`sort_by`](@ref) if order matters). The complement of [`top_k`](@ref).
"""
function bottom_k(expr::Expr, k)
    k = convert(Expr, k)
    out = API.polars_expr_bottom_k(expr, k)
    return Expr(out)
end

@curry bottom_k(k)

export bottom_k


"""
    value_counts(expr::Polars.Expr; sort::Bool=false, parallel::Bool=false, name::String="count",
                 normalize::Bool=false)::Polars.Expr

Counts the occurrences of each unique value in `expr`, returning a `Struct` column mapping value
to count (field `name`, default `"count"`). If `sort` is `true`, results are sorted by count
descending. If `normalize` is `true`, counts become fractions of the total instead.
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

Randomly samples `n` values from `expr`. If `seed` is given, sampling is reproducible.
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

Randomly samples a `frac` fraction of the values from `expr`. If `seed` is given, sampling is
reproducible.
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


"""
    cum_sum(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative sum of the values. If `reverse` is `true`, accumulates from the last value to the
first.
"""
cum_sum(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_sum(expr, reverse))

"""
    cum_prod(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative product of the values. If `reverse` is `true`, accumulates from the last value to
the first.
"""
cum_prod(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_prod(expr, reverse))

"""
    cum_min(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative minimum of the values. If `reverse` is `true`, accumulates from the last value to
the first.
"""
cum_min(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_min(expr, reverse))

"""
    cum_max(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative maximum of the values. If `reverse` is `true`, accumulates from the last value to
the first.
"""
cum_max(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_max(expr, reverse))

"""
    cum_count(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative count of non-null values. If `reverse` is `true`, accumulates from the last value to
the first.
"""
cum_count(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_count(expr, reverse))

@curry cum_sum(; reverse::Bool = false)
@curry cum_prod(; reverse::Bool = false)
@curry cum_min(; reverse::Bool = false)
@curry cum_max(; reverse::Bool = false)
@curry cum_count(; reverse::Bool = false)

export cum_sum, cum_prod, cum_min, cum_max, cum_count

"""
    rolling_mean(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                 center::Bool=false)::Polars.Expr

Apply a rolling mean (moving average) over the values.

A window of length `window_size` traverses the values; the window at a given row includes the
row itself and the `window_size - 1` elements before it. `min_samples` is the number of non-null
values required in the window before a result is computed (defaults to `window_size`, so the
leading `min_samples - 1` rows are `null`). `center` labels each window's result at its middle
row instead of its last.
"""
function rolling_mean(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_mean(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_sum(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                center::Bool=false)::Polars.Expr

Apply a rolling sum over the values. See [`rolling_mean`](@ref) for the meaning of `window_size`,
`min_samples`, and `center`.
"""
function rolling_sum(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_sum(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_min(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                center::Bool=false)::Polars.Expr

Apply a rolling minimum over the values. See [`rolling_mean`](@ref) for the meaning of
`window_size`, `min_samples`, and `center`.
"""
function rolling_min(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_min(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_max(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                center::Bool=false)::Polars.Expr

Apply a rolling maximum over the values. See [`rolling_mean`](@ref) for the meaning of
`window_size`, `min_samples`, and `center`.
"""
function rolling_max(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_max(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_std(expr::Polars.Expr, window_size::Integer; min_samples::Integer=window_size,
                center::Bool=false, ddof::Integer=1)::Polars.Expr

Compute a rolling standard deviation. See [`rolling_mean`](@ref) for the meaning of
`window_size`, `min_samples`, and `center`. `ddof` is the "delta degrees of freedom": the divisor
used for a window of length `N` is `N - ddof`.
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

Compute a rolling variance. See [`rolling_mean`](@ref) for the meaning of `window_size`,
`min_samples`, and `center`. `ddof` is the "delta degrees of freedom": the divisor used for a
window of length `N` is `N - ddof`.
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

Apply a rolling median. See [`rolling_mean`](@ref) for the meaning of `window_size`,
`min_samples`, and `center`.
"""
function rolling_median(expr::Expr, window_size::Integer; min_samples::Integer = window_size, center::Bool = false)
    out = API.polars_expr_rolling_median(expr, Csize_t(window_size), Csize_t(min_samples), center)
    return Expr(out)
end

"""
    rolling_quantile(expr::Polars.Expr, window_size::Integer, quantile::Real;
                     min_samples::Integer=window_size, center::Bool=false,
                     method::Symbol=:nearest)::Polars.Expr

Apply a rolling quantile. See [`rolling_mean`](@ref) for the meaning of `window_size`,
`min_samples`, and `center`. `method` controls how a quantile that falls between two values is
resolved -- one of `:nearest` (default), `:lower`, `:higher`, `:midpoint`, `:linear`,
`:equiprobable` (see [`quantile`](@ref) for details).
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

Assigns ranks to the values, dealing with ties according to `method`: one of `:average`,
`:min`, `:max`, `:dense` (default), `:ordinal`.
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

"""Resolves exactly one of `com`/`span`/`half_life`/`alpha` to a concrete decay factor in
`(0, 1]`, matching the one-liner conversions `EWMOptions`'s Rust-side builder methods use.
Errors if zero or more than one is given, or if the given one is out of its valid domain."""
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

Compute the exponentially-weighted moving average.

Exactly one of `com`, `span`, `half_life`, `alpha` must be given, specifying the decay in terms
of center of mass (`alpha = 1 / (1 + com)`, `com >= 0`), span (`alpha = 2 / (span + 1)`,
`span >= 1`), half-life (`alpha = 1 - exp(-ln(2) / half_life)`, `half_life > 0`), or the smoothing
factor directly (`0 < alpha <= 1`).

`adjust` selects between the two weighting schemes: when `true` (default), weights are
`(1 - alpha)^i`; when `false`, the average is computed recursively,
`y[0] = x[0]; y[t] = (1 - alpha) * y[t - 1] + alpha * x[t]`.

`min_samples` is the minimum number of observations in a window required to produce a value
(otherwise `missing`). `ignore_nulls` controls whether weights are based on relative (`true`) or
absolute (`false`) positions when nulls are present.

!!! note
    Time-based EWM (`ewm_mean_by`) is not implemented.
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

Compute the exponentially-weighted moving standard deviation. See [`ewm_mean`](@ref) for
`com`/`span`/`half_life`/`alpha`, `adjust`, `min_samples`, and `ignore_nulls`.

If `bias` is `false` (default), the calculation is corrected for statistical bias.
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

Compute the exponentially-weighted moving variance. See [`ewm_mean`](@ref) for
`com`/`span`/`half_life`/`alpha`, `adjust`, `min_samples`, and `ignore_nulls`, and [`ewm_std`](@ref)
for `bias`.
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

# Builds the `(owned, label_ptrs, label_lens)` triple shared by `cut`/`qcut`/`qcut_uniform` --
# `owned` being the `Vector{String}` the caller must name in its own `GC.@preserve`, see
# `_name_ptrs`. `labels === nothing` becomes an empty list, i.e. `n_labels = 0`, the FFI convention
# for "generate interval-string labels".
_cut_labels(labels::Union{Nothing, Vector{String}}) =
    _name_ptrs(labels === nothing ? String[] : labels)

"""
    cut(expr::Polars.Expr, breaks::AbstractVector{<:Real}; labels::Union{Nothing,Vector{String}}=nothing,
        left_closed::Bool=false)::Polars.Expr

Bin continuous values into discrete categories, given explicit cut points. `breaks` are the
interior cut points (not including the implicit `-inf`/`inf` ends), so the result has
`length(breaks) + 1` categories.

`labels`, if given, must have `length(breaks) + 1` entries; otherwise labels are generated as
interval strings (`"(-inf, b]"`, `"(b1, b2]"`, ..., `"(bn, inf]"`, or the `"[...)"` form if
`left_closed` is `true`).

Returns a labelled Enum column, which materializes as `String` (see [`cast_categorical`](@ref)).

With CategoricalArrays.jl loaded, the bare `cut(expr, breaks)` also works.

!!! note
    `include_breaks` (returning a `Struct` of breakpoint and category together) is not
    implemented.

See also [`qcut`](@ref)/[`qcut_uniform`](@ref) for quantile-based binning.
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

Bin continuous values into discrete categories based on their quantiles. `probs` are quantile
probabilities in `[0, 1]`; the result has `length(probs) + 1` categories.

`allow_duplicates`, if `true`, silently collapses repeated quantile breakpoints (which can occur
even with distinct probabilities, depending on the data) instead of raising.

Returns a `Categorical` column, which materializes as `String`. See [`cut`](@ref) for `labels`,
and [`qcut_uniform`](@ref) for uniformly-spaced probabilities given as a bin count.
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

Like [`qcut`](@ref), but with `n_bins` uniformly-spaced quantile probabilities instead of an
explicit `probs` list.
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

export col, alias, prefix, suffix, to_lowercase, to_uppercase, lit, cast, when, element,
    cast_datetime, cast_duration, cast_decimal, cast_categorical,
    Lists, Strings, Dt, Structs, Selectors
