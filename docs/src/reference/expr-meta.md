# [Meta](@id expr-meta)

The `Polars.Meta` namespace (py-polars' `Expr.meta`) inspects an expression *tree itself* --
what column(s) it reads from, what name it would produce, whether it's a plain column or a
literal -- without needing a DataFrame/LazyFrame to run it against.

!!! note "`Meta` is not exported from `Polars`"
    Unlike `Lists`/`Strings`/`Dt`/`Structs`/`Selectors`, `Meta` is always reached fully qualified,
    `Polars.Meta.output_name(...)` etc. -- `Base.Meta` is itself an *exported* Base submodule, so
    `export Meta` from `Polars` would make plain `using Polars` immediately ambiguous-error on the
    bare name `Meta` in the importing module.

```@setup meta
using Polars
```

```@docs
Polars.Meta
Polars.Meta.output_name
Polars.Meta.is_column
Polars.Meta.is_literal
Polars.Meta.has_multiple_outputs
Polars.Meta.undo_aliases
Polars.Meta.root_names
Polars.Meta.tree_format
Polars.Meta.show_graph
```

```@example meta
Polars.Meta.output_name(col("x") + col("y")), Polars.Meta.root_names(col("x") + col("y"))
```

`output_name`/`root_names` follow the whole expression tree, not just its top node -- an alias
buried inside one operand of a binary operation doesn't change the overall output name:

```@example meta
chained = (col("x") + col("y")) |> alias("total")
Polars.Meta.output_name(chained), Polars.Meta.output_name(Polars.Meta.undo_aliases(chained))
```

`output_name`/`root_names` need at least one well-defined root column: a wildcard or a
[`Selectors`](@ref) expression that could match more than one column raises a `PolarsError` from
`output_name` (there is no single name to report), while `root_names` on a column-free
expression (a bare literal) returns an empty `Vector{String}` rather than erroring:

```@example meta
try
    Polars.Meta.output_name(col("*"))
catch e
    println(sprint(showerror, e))
end
```

```@example meta
Polars.Meta.root_names(lit(1))
```

`tree_format`/`show_graph` render the same underlying tree as plain text or as a Graphviz graph
description, respectively -- no DataFrame/LazyFrame schema is consulted, so unresolved column
types show as untyped:

```@example meta
print(Polars.Meta.tree_format(col("x") + col("y")))
```

`show_graph` returns Graphviz `.dot` source rather than a picture -- rendering it (e.g. by piping
to `dot -Tsvg`, or via a Julia binding to Graphviz such as
[GraphViz.jl](https://github.com/JuliaGraphs/GraphViz.jl)) turns it into an actual diagram:

```@example meta
using GraphViz
q = when(col("qty") .> 1, col("price") * col("qty"), lit(0.0)) |> alias("revenue")
g = GraphViz.Graph(Polars.Meta.show_graph(q))
GraphViz.layout!(g; engine = "dot") # "dot" lays out top-down, matching a tree; the package default ("neato") is spring-directed
g
```
