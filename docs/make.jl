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
    checkdocs = :exports,
    linkcheck = false,
    # `:missing_docs` alone stays non-fatal: `checkdocs = :exports` currently reports ~200
    # exported symbols whose docstring isn't pulled into any reference page's `@docs`/`@autodocs`
    # block (a pre-existing reference-page curation gap, not something this pass attempts to
    # close wholesale) -- but every *other* Documenter error category (broken cross-refs,
    # doctests, footnotes, ...) that the previous blanket `warnonly = true` was also silencing
    # now fails the build for real.
    warnonly = [:missing_docs],
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
            "reference/selectors.md",
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
