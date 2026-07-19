# Strings

The `Strings` namespace provides regex and text operations on `String`-typed columns.

```@setup strings
using Polars
```

## Case and length

| Function | Purpose |
|---|---|
| `Strings.uppercase`, `Strings.lowercase` | case conversion |
| `Strings.titlecase` | ⚠️ broken (see Limitations) |
| `Strings.len_chars`, `Strings.len_bytes` | character/byte count (differ on unicode) |

```@example strings
dfcase = DataFrame((; s = ["Hello World", "foo BAR"]))
select(
    dfcase,
    Strings.uppercase(col("s")) |> alias("upper"), Strings.lowercase(col("s")) |> alias("lower"),
    Strings.len_chars(col("s")) |> alias("chars"), Strings.len_bytes(col("s")) |> alias("bytes"),
)
```

## Substring operations

| Function | Purpose |
|---|---|
| `Strings.slice(expr, offset, length)` | extract substring (0-indexed, negative from end) |
| `Strings.head(expr, n)` | first n characters |
| `Strings.tail(expr, n)` | last n characters |

```@example strings
select(DataFrame((; s = ["Hello World"])), Strings.head(col("s"), lit(5)) |> alias("head"), Strings.tail(col("s"), lit(5)) |> alias("tail"))
```

## Searching & matching

| Function | Purpose |
|---|---|
| `Strings.contains(expr, pat; strict=true)` | regex match (strict=false returns null on invalid regex) |
| `Strings.contains_literal(expr, pat)` | plain substring search (non-regex) |
| `Strings.starts_with`, `Strings.ends_with` | prefix/suffix check |
| `Strings.extract(expr, pat, group_index)` | capture group from regex |
| `Strings.extract_all(expr, pat)` | all matches as a list |
| `Strings.count_matches(expr, pat; literal=false)` | count non-overlapping matches |

```@example strings
dfmatch = DataFrame((; s = ["Hello World", "foo BAR"]))
select(dfmatch, col("s") |> Strings.ends_with("World") |> alias("ends"), col("s") |> Strings.contains_literal("oo") |> alias("has_oo"))
```

## Replacement & stripping

| Function | Purpose |
|---|---|
| `Strings.replace(expr, pat, value; literal=false)` | replace first match |
| `Strings.replace_all(expr, pat, value; literal=false)` | replace all matches |
| `Strings.split(expr, pat)` | split into list |
| `Strings.strip_chars(expr, chars)` | remove leading/trailing characters |
| `Strings.strip_prefix`, `Strings.strip_suffix` | remove prefix/suffix |
| `Strings.zfill(expr, width)` | left-pad with zeros |

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

Example: extract email domain:

```@example strings
df = DataFrame((; email = ["alice@example.com", "bob@test.org"]))
select(df, Strings.extract(col("email"), lit(raw"@(.+)"), 1) |> alias("domain"))
```

## Parsing: `to_date` and `to_datetime`

Parse a `String` column into a temporal type:

- `Strings.to_date(expr; format=nothing, strict=true, exact=true)` — parses to `Date`.
- `Strings.to_datetime(expr; format=nothing, time_unit=:us, strict=true, exact=true)` — parses to
  `Datetime`; `time_unit` is one of `:ns`, `:us` (default), `:ms`.

Both share `format`/`strict`/`exact`: `format` is a `chrono`-style format string (e.g. `"%Y-%m-%d"`)
— if not given, polars attempts to infer it. If `strict` is `true` (default), an unparseable value
raises an error; if `false`, it becomes `null`. If `exact` is `true` (default), the entire string
must match `format`.

```@example strings
dates = DataFrame((; s = ["2024-03-15", "2024-06-01"]))
select(dates, Strings.to_date(col("s")) |> alias("d"), Strings.to_datetime(col("s"); format = "%Y-%m-%d") |> alias("dt"))
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
