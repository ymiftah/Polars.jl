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
    # Only `:missing_docs` is non-fatal: many exported symbols are not yet pulled into a
    # reference page. Every other Documenter error (broken cross-refs, doctests, ...) fails the
    # build.
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
            "reference/dataframe.md",
            "reference/lazyframe.md",
            "reference/series.md",
            "reference/expressions.md",
            "reference/functions.md",
            "reference/selectors.md",
            "reference/expr-list.md",
            "reference/expr-string.md",
            "reference/expr-datetime.md",
            "reference/expr-struct.md",
            "reference/expr-meta.md",
            "reference/io.md",
            "reference/datatypes.md",
            "reference/metadata.md",
            "reference/exceptions.md",
        ],
        "Limitations" => "limitations.md",
        "Developer" => "developer.md",
    ],
)

DocumenterVitepress.deploydocs(;
    repo = "github.com/ymiftah/Polars.jl",
    devbranch = "main",
    push_preview = false,
)
