# [Meta](@id expr-meta)

The `Polars.Meta` namespace (py-polars' `Expr.meta`) inspects an expression without running it.

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

```@example meta
chained = (col("x") + col("y")) |> alias("total")
Polars.Meta.output_name(chained), Polars.Meta.output_name(Polars.Meta.undo_aliases(chained))
```

`output_name` raises for an expression without a single output name, such as a wildcard:

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

```@example meta
print(Polars.Meta.tree_format(col("x") + col("y")))
```

`show_graph` returns Graphviz source, which
[GraphViz.jl](https://github.com/JuliaGraphs/GraphViz.jl) can render:

```@example meta
using GraphViz
q = when(col("qty") .> 1, col("price") * col("qty"), lit(0.0)) |> alias("revenue")
g = GraphViz.Graph(Polars.Meta.show_graph(q))
GraphViz.layout!(g; engine = "dot")
g
```
