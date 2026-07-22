"""
    Meta

Introspection over `Polars.Expr` values, mirroring py-polars' `Expr.meta`. Every function here
accepts anything [`_as_expr`](@ref) accepts (an `Expr`, a [`Selectors.Selector`](@ref Selectors),
or a column-name `String`/`Symbol`) and inspects the expression *tree itself* -- not any
DataFrame/LazyFrame it might later be applied to, so no schema is consulted (e.g.
[`tree_format`](@ref)/[`show_graph`](@ref) render unresolved column types as untyped).
"""
module Meta
using ..Polars: API, Expr, polars_error, _io_callback, _as_expr

"""
    output_name(expr)::String

Returns the single output column name `expr` would produce, e.g. `col("x")` -> `"x"`,
`col("x") |> alias("y")` -> `"y"`, `col("x") + col("y")` -> `"x"` (the left/first root column).
Raises a `PolarsError` if `expr` has no single well-defined output name -- e.g. a wildcard or a
selector-expanded expression that can match more than one column.
"""
function output_name(expr)
    expr = _as_expr(expr)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = API.polars_expr_meta_output_name(expr, io, callback)
    polars_error(err)
    return String(take!(io[]))
end

"""
    is_column(expr)::Bool

Returns `true` if `expr` is a plain (non-regex) column reference, e.g. `col("x")`. Returns
`false` for anything else, including an aliased column (`col("x") |> alias("y")`) or a
[`Selectors`](@ref) expression.
"""
function is_column(expr)
    expr = _as_expr(expr)
    return API.polars_expr_meta_is_column(expr)
end

"""
    is_literal(expr; allow_aliasing::Bool=false)::Bool

Returns `true` if `expr` is a literal value, e.g. `lit(1)`. If `allow_aliasing`, an aliased
literal (`lit(1) |> alias("x")`) also counts as one; otherwise it does not.
"""
function is_literal(expr; allow_aliasing::Bool = false)
    expr = _as_expr(expr)
    return API.polars_expr_meta_is_literal(expr, allow_aliasing)
end

"""
    has_multiple_outputs(expr)::Bool

Returns `true` if `expr` can expand to more than one output column -- e.g. a [`Selectors`](@ref)
expression like `Selectors.numeric()`. Returns `false` for a plain single-column expression like
`col("x")`.
"""
function has_multiple_outputs(expr)
    expr = _as_expr(expr)
    return API.polars_expr_meta_has_multiple_outputs(expr)
end

"""
    undo_aliases(expr)::Polars.Expr

Strips any renaming (`alias`/`keep_name`) applied anywhere in `expr`, returning the same
expression with those renames removed.
"""
function undo_aliases(expr)
    expr = _as_expr(expr)
    out = API.polars_expr_meta_undo_aliases(expr)
    return Expr(out)
end

"""
    root_names(expr)::Vector{String}

Returns the names of the root (leaf) columns `expr` reads from, e.g. `col("x") + col("y")` ->
`["x", "y"]`. Empty for an expression with no column reference at all, e.g. a bare literal
`lit(1)`.
"""
function root_names(expr)
    expr = _as_expr(expr)
    # `n` is `Csize_t` (unsigned): `n - 1` at `n == 0` (a real case -- e.g. a bare literal) would
    # wrap around instead of underflowing to a negative, turning `0:(n - 1)` into a giant nonempty
    # range instead of the intended empty one. Convert to a signed `Int` first.
    n = Int(API.polars_expr_meta_root_names_len(expr))
    callback = _io_callback()
    names = Vector{String}(undef, n)
    for i in 0:(n - 1)
        io = Ref(IOBuffer())
        err = API.polars_expr_meta_root_names_get(expr, i, io, callback)
        polars_error(err)
        names[i + 1] = String(take!(io[]))
    end
    return names
end

function _tree_format(expr, display_as_dot::Bool)
    expr = _as_expr(expr)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = API.polars_expr_meta_tree_format(expr, display_as_dot, io, callback)
    polars_error(err)
    return String(take!(io[]))
end

"""
    tree_format(expr)::String

Renders `expr` as a human-readable tree. No frame schema is consulted, so unresolved column
types show as untyped. See also [`show_graph`](@ref) for a Graphviz rendering of the same tree.
"""
tree_format(expr) = _tree_format(expr, false)

"""
    show_graph(expr)::String

Renders `expr` as a Graphviz (`.dot`) graph description -- write the result to a `.dot` file (or
pass it to a Graphviz renderer) to visualize. See also [`tree_format`](@ref) for a plain-text
rendering of the same tree.
"""
show_graph(expr) = _tree_format(expr, true)

export output_name, is_column, is_literal, has_multiple_outputs, undo_aliases, root_names,
    tree_format, show_graph

end # module Meta
