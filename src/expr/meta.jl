"""
    Meta

Inspect the expression tree. Every function accepts an `Expr`, a [`Polars.Selector`](@ref), or
a column name.
"""
module Meta
using ..Polars: API, Expr, polars_error, _io_callback, _as_expr

"""
    output_name(expr)::String

Get the output name of this expression.
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

Indicate if this expression is a basic (non-regex) column.
"""
function is_column(expr)
    expr = _as_expr(expr)
    return API.polars_expr_meta_is_column(expr)
end

"""
    is_literal(expr; allow_aliasing::Bool=false)::Bool

Indicate if this expression represents a literal value (optionally aliased).

Note: `Date`/`Time`/`DateTime` literals are built as a cast and return `false`.
"""
function is_literal(expr; allow_aliasing::Bool = false)
    expr = _as_expr(expr)
    return API.polars_expr_meta_is_literal(expr, allow_aliasing)
end

"""
    has_multiple_outputs(expr)::Bool

Indicate if this expression expands to multiple expressions.
"""
function has_multiple_outputs(expr)
    expr = _as_expr(expr)
    return API.polars_expr_meta_has_multiple_outputs(expr)
end

"""
    undo_aliases(expr)::Polars.Expr

Undo any renaming operation like `alias`, `keep_name`.
"""
function undo_aliases(expr)
    expr = _as_expr(expr)
    out = API.polars_expr_meta_undo_aliases(expr)
    return Expr(out)
end

"""
    root_names(expr)::Vector{String}

Get the root column names.
"""
function root_names(expr)
    expr = _as_expr(expr)
    # Signed, so `0:(n - 1)` is empty when `n == 0`.
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

Format the expression as a tree.
"""
tree_format(expr) = _tree_format(expr, false)

"""
    show_graph(expr)::String

Format the expression as a Graphviz `dot` graph.
"""
show_graph(expr) = _tree_format(expr, true)

export output_name, is_column, is_literal, has_multiple_outputs, undo_aliases, root_names,
    tree_format, show_graph

end # module Meta
