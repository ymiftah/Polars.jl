module PolarsStatsBaseExt

using Polars, StatsBase

# StatsBase owns `kurtosis` and `skewness` -- they are its own generics, not re-exports of
# Statistics' (unlike `mean`/`std`/`var`/`cov`/`cor`, which are). Adding methods here lets a
# StatsBase user write `kurtosis(col("x"))` with the name they already have in scope, instead of
# reaching for `Polars.kurtosis`.
#
# This does not remove the ambiguity on the bare name when both packages are loaded: `Polars`
# exports its own `kurtosis` so that it works without StatsBase at all, and two packages exporting
# one name means neither binding is available unqualified. `StatsBase.kurtosis(expr)` and
# `Polars.kurtosis(expr)` both work; the bare name still needs a qualifier.

StatsBase.kurtosis(expr::Polars.Expr; fisher::Bool = true, bias::Bool = true) =
    Polars.kurtosis(expr; fisher, bias)

# StatsBase spells it `skewness`; this package follows polars and calls it `skew`. No collision
# exists, but accepting the StatsBase spelling keeps the two moment functions symmetric.
StatsBase.skewness(expr::Polars.Expr; bias::Bool = true) = Polars.skew(expr; bias)

end
