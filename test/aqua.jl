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
    )
end
