module PolarsCategoricalArraysExt

using Polars, CategoricalArrays

# CategoricalArrays owns `cut`; `Polars.cut` is unexported so the bare name stays theirs. This adds
# the `Expr` method to their generic.

CategoricalArrays.cut(
    expr::Polars.Expr, breaks::AbstractVector{<:Real};
    labels::Union{Nothing, Vector{String}} = nothing, left_closed::Bool = false
) = Polars.cut(expr, breaks; labels, left_closed)

end
