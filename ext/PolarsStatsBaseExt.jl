module PolarsStatsBaseExt

using Polars, StatsBase

# StatsBase owns `kurtosis` and `skewness` -- they are its own generics, not re-exports of
# Statistics' (unlike `mean`/`std`/`var`/`cov`/`cor`, which are).
#
# `Polars.kurtosis` is deliberately not exported so the bare name stays usable: with this extension
# loaded it resolves to StatsBase's generic, and the method below dispatches an `Expr` argument back
# to this package. `Polars.kurtosis(expr)` works either way, including with no extension loaded.

StatsBase.kurtosis(expr::Polars.Expr; fisher::Bool = true, bias::Bool = true) =
    Polars.kurtosis(expr; fisher, bias)

# StatsBase spells it `skewness`; this package follows polars and calls it `skew`. No collision
# exists, but accepting the StatsBase spelling keeps the two moment functions symmetric.
StatsBase.skewness(expr::Polars.Expr; bias::Bool = true) = Polars.skew(expr; bias)

end
