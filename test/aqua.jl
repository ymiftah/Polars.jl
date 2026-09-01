using Aqua

@testset "Aqua" begin
    Aqua.test_all(
        Polars;
        # Ambiguities are real (e.g. `filter(df::DataFrame, expr)` vs several Base.filter
        # methods, Union{Missing,T} dispatch overlaps in series.jl/arrow.jl, and `Expr`'s
        # unconstrained mixed-argument operators -- see expr/expr.jl -- vs Base's own
        # equally-unconstrained `==(::WeakRef, ::Any)`/`==(::Any, ::WeakRef)`) but none are
        # reachable through normal use of this package; `broken=true` keeps them visible
        # instead of silently disabling detection.
        ambiguities = (broken = true,),
        # `nomissing`/`format`/`arrowvector` all dispatch on `::Type{Union{Missing,T}} where T`,
        # a standard idiom for handling the Missing-union pattern; Aqua's heuristic can't tell
        # T is bound by the passed type argument, so this is a known false-positive shape.
        unbound_args = (broken = true,),
        # `Base.time(hour, minute=0, second=0, microsecond=0)` (src/expr/ranges.jl) is a
        # deliberate, *narrow* exception. Unlike this package's other `Base.*` extensions
        # (`reverse`/`count`/`reshape`/...), it takes temporal components rather than a frame or
        # an `Expr` in the first position, so no argument is typed as this package's own `Expr`
        # alone and Aqua's blanket rule flags it. The arguments are pinned to
        # `Union{Expr,Real}` precisely so this stays narrow: an `Any`-typed version really would
        # be dangerous piracy, capturing every downstream two-to-four-argument `time(...)` call,
        # whereas this can only capture calls that were already passing numbers or this
        # package's own `Expr`. Keeping bare `time(9, 30)` working is the whole point of
        # extending `Base.time` instead of defining a shadowing non-exported function.
        piracies = (treat_as_own = [Base.time],),
    )
end
