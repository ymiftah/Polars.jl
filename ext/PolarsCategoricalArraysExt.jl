module PolarsCategoricalArraysExt

using Polars, CategoricalArrays

# CategoricalArrays owns `cut`, and is the common way to work with categorical data in Julia.
# `Polars.cut` is deliberately not exported so that the bare name stays usable: with this extension
# loaded it resolves to CategoricalArrays' generic, and the method below dispatches an `Expr`
# argument back to this package. `Polars.cut(expr, breaks)` works either way, including with no
# extension loaded.

CategoricalArrays.cut(
        expr::Polars.Expr, breaks::AbstractVector{<:Real};
        labels::Union{Nothing, Vector{String}} = nothing, left_closed::Bool = false
    ) = Polars.cut(expr, breaks; labels, left_closed)

end
