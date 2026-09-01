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
        # deliberate exception, not a bug: unlike this package's other `Base.*` extensions
        # (`reverse`/`count`/`reshape`/...), every argument here is a plain scalar/`Expr`
        # component, so none of the four generated methods (one per default-arg arity) has an
        # argument typed as this package's own `Expr` -- Aqua's blanket rule flags any Base
        # method with no argument type it recognizes as "owned". This is exactly Aqua's own
        # documented use case for `treat_as_own` ("packages adding higher-level functionality to
        # a lightweight C-wrapper"): the alternative is losing bare `time(9, 30)` -- the whole
        # point of extending `Base.time` rather than defining a same-named, non-exported
        # function -- for no real safety benefit, since this package registers exactly the
        # `Base.time` methods this file documents and no others.
        piracies = (treat_as_own = [Base.time],),
    )
end
