# [String](@id expr-string)

The `Strings` namespace provides regex and text operations on `String`-typed columns.

```@setup strings
using Polars
```

## Case and length

```@docs
Polars.Strings.uppercase
Polars.Strings.lowercase
Polars.Strings.titlecase
Polars.Strings.len_chars
Polars.Strings.len_bytes
```

!!! warning "`titlecase` is broken"
    See [Limitations](@ref).

```@example strings
dfcase = DataFrame((; s = ["Hello World", "foo BAR"]))
select(
    dfcase,
    Strings.uppercase(col("s")) |> alias("upper"), Strings.lowercase(col("s")) |> alias("lower"),
    Strings.len_chars(col("s")) |> alias("chars"), Strings.len_bytes(col("s")) |> alias("bytes"),
)
```

## Substring operations

```@docs
Polars.Strings.slice
Polars.Strings.head
Polars.Strings.tail
```

```@example strings
select(DataFrame((; s = ["Hello World"])), Strings.head(col("s"), lit(5)) |> alias("head"), Strings.tail(col("s"), lit(5)) |> alias("tail"))
```

## Searching & matching

```@docs
Polars.Strings.contains
Polars.Strings.contains_literal
Polars.Strings.starts_with
Polars.Strings.ends_with
Polars.Strings.extract
Polars.Strings.extract_all
Polars.Strings.count_matches
Polars.Strings.escape_regex
```

```@example strings
dfmatch = DataFrame((; s = ["Hello World", "foo BAR"]))
select(dfmatch, col("s") |> Strings.ends_with("World") |> alias("ends"), col("s") |> Strings.contains_literal("oo") |> alias("has_oo"))
```

Example: extract email domain:

```@example strings
df = DataFrame((; email = ["alice@example.com", "bob@test.org"]))
select(df, Strings.extract(col("email"), lit(raw"@(.+)"), 1) |> alias("domain"))
```

## Replacement & stripping

```@docs
Polars.Strings.replace
Polars.Strings.replace_all
Polars.Strings.split
Polars.Strings.strip_chars
Polars.Strings.strip_prefix
Polars.Strings.strip_suffix
Polars.Strings.zfill
```

```@example strings
select(DataFrame((; s = ["  padded  "])), col("s") |> Strings.strip_chars(" ") |> alias("stripped"))
```

```@example strings
select(DataFrame((; s = ["prefix_val"])), col("s") |> Strings.strip_prefix("prefix_") |> alias("no_prefix"))
```

```@example strings
select(DataFrame((; s = ["val_suffix"])), col("s") |> Strings.strip_suffix("_suffix") |> alias("no_suffix"))
```

```@example strings
select(DataFrame((; s = ["a,b,c"])), col("s") |> Strings.split(",") |> alias("parts"))
```

```@example strings
select(DataFrame((; s = ["cat hat bat"])), col("s") |> Strings.extract_all(raw"\w+at") |> alias("matches"))
```

```@example strings
select(DataFrame((; n = [7, 42])), Strings.zfill(cast(col("n"), String), lit(4)) |> alias("padded"))
```

## Parsing

```@docs
Polars.Strings.to_date
Polars.Strings.to_datetime
```

Both share `format`/`strict`/`exact`: `format` is a `chrono`-style format string (e.g.
`"%Y-%m-%d"`) — if not given, polars attempts to infer it. If `strict` is `true` (default), an
unparseable value raises an error; if `false`, it becomes `null`. If `exact` is `true` (default),
the entire string must match `format`.

```@example strings
dates = DataFrame((; s = ["2024-03-15", "2024-06-01"]))
select(dates, Strings.to_date(col("s")) |> alias("d"), Strings.to_datetime(col("s"); format = "%Y-%m-%d") |> alias("dt"))
```

## Joining

```@docs
Polars.Strings.join
```

```@example strings
select(DataFrame((; s = ["a", "b", "c"])), Strings.join(col("s"), "-") |> alias("joined"))
```

## Curried forms

Every function above has a curried form for `|>` pipelines — see
[Curried forms for pipe-based composition](@ref):

```@example strings
df2 = DataFrame((; s = ["hello world", "foo bar"]))
select(df2, col("s") |> Strings.starts_with("hello") |> alias("starts"), col("s") |> Strings.replace_all("o", "0") |> alias("r"))
```

```@example strings
select(dates, col("s") |> Strings.to_date(format = "%Y-%m-%d") |> alias("d"))
```
