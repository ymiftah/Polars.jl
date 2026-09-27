module PolarsStatsBaseExt

using Polars, StatsBase

# `Polars.kurtosis` is unexported so the bare name stays StatsBase's; this adds the `Expr` method.

StatsBase.kurtosis(expr::Polars.Expr; fisher::Bool = true, bias::Bool = true) =
    Polars.kurtosis(expr; fisher, bias)

# StatsBase's name for `skew`.
StatsBase.skewness(expr::Polars.Expr; bias::Bool = true) = Polars.skew(expr; bias)

end
