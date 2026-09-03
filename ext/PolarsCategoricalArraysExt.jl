module PolarsCategoricalArraysExt

using Polars, CategoricalArrays

# CategoricalArrays owns `cut`; `Polars.cut` is unexported so the bare name stays theirs. This adds
# the `Expr` method to their generic.

CategoricalArrays.cut(
    expr::Polars.Expr, breaks::AbstractVector{<:Real};
    labels::Union{Nothing, Vector{String}} = nothing, left_closed::Bool = false
) = Polars.cut(expr, breaks; labels, left_closed)

# Materializes a Categorical/Enum column as a `CategoricalArray` instead of a plain `String`
# vector -- see `_categorical_column_type`'s docstring (src/arrow/schema.jl) and
# `_read_categorical`'s docstring (src/arrow/read.jl) for the full mechanism and its limits.
Polars._resolve_categorical_column_type() = CategoricalArrays.CategoricalValue{String, UInt32}
Polars._resolve_categorical_array(strings) = CategoricalArrays.categorical(strings)

end
