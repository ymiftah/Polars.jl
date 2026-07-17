using Documenter
using DocumenterVitepress
using Polars

makedocs(;
    sitename = "Polars.jl",
    format = DocumenterVitepress.MarkdownVitepress(
        repo = "https://github.com/ymiftah/Polars.jl",
        devbranch = "main",
    ),
    modules = [Polars],
    checkdocs = :none,
    linkcheck = false,
    warnonly = true,
    pages = [
        "Home" => "index.md",
        "Tutorials" => [
            "tutorials/01-getting-started.md",
            "tutorials/02-loading-data.md",
            "tutorials/03-transforming-data.md",
            "tutorials/04-aggregating-and-grouping.md",
            "tutorials/05-time-series-analytics.md",
            "tutorials/06-joining-data.md",
            "tutorials/07-window-functions-and-ranking.md",
            "tutorials/08-strings-and-lists.md",
            "tutorials/09-combining-and-next-steps.md",
        ],
        "Reference" => [
            "reference/index.md",
            "reference/structures.md",
            "reference/laziness.md",
            "reference/manipulation.md",
            "reference/expressions.md",
            "reference/lists.md",
            "reference/strings.md",
            "reference/dt.md",
            "reference/structs.md",
            "reference/io.md",
            "reference/utils.md",
        ],
        "Limitations" => "limitations.md",
    ],
)

DocumenterVitepress.deploydocs(;
    repo = "github.com/ymiftah/Polars.jl",
    devbranch = "main",
    push_preview = false,
)
