# Timezone support via a Julia package extension

## Status

Done. `Dt.replace_time_zone`/`Dt.convert_time_zone` ship unconditionally (core, no TimeZones.jl
dependency); tz-aware column reads route through `PolarsTimeZonesExt` (`ext/PolarsTimeZonesExt.jl`)
once `using TimeZones` activates it, materializing `TimeZones.ZonedDateTime`, and error with a
clear "load TimeZones.jl" message otherwise (`Polars._tz_aware_datetime_type`,
`src/arrow/schema.jl`). Covered by `test/datatypes/timezones.jl`.

## Context

Two independent gaps, decided to be tackled together:

1. **No `Dt.replace_time_zone`/`Dt.convert_time_zone`** — Expr-level tz functions, gated by the
   `timezones` Cargo feature (currently off). These take a plain tz-name `String` and need
   **nothing** from TimeZones.jl — polars carries the tz as a string internally (`TimeZone` wraps
   `PlSmallStr`), so this part is unconditional core functionality.
2. **Reading a tz-aware column silently produces a wrong-shaped value today.** Arrow C Data
   Interface timestamp formats are `"tsX:tz"` (`X` = resolution letter, `tz` = IANA name or empty
   for naive). [arrow.jl's `parse_format`](src/arrow.jl#L122) currently does
   `startswith(fmt, "tsu:") && return MaybeMissing{Dates.DateTime}` — this matches **both** naive
   (`"tsu:"`) and tz-aware (`"tsu:America/New_York"`) formats and silently discards the tz suffix
   in the second case, materializing a naive `DateTime` with no indication the column was ever
   tz-aware.

**User decision**: don't add `TimeZones.jl` as a hard dependency. Use a Julia package extension
(`[weakdeps]` + `[extensions]`, Julia ≥1.9 — already satisfied, `Project.toml` targets `julia =
"1.10"`) so `TimeZones.ZonedDateTime` materialization only activates when the user has
`using TimeZones` loaded. Without the extension loaded, reading a tz-aware column must **error
clearly** (not silently drop the tz) — confirmed by user.

## Design

### Hook point: `Polars._tz_aware_datetime_type(tz::AbstractString)`

A single extensible function, defined in core as an unconditional error:

```julia
_tz_aware_datetime_type(tz::AbstractString) = error(
    "column has timezone \"$tz\" -- load TimeZones.jl (`using TimeZones`) to read " *
    "timezone-aware Datetime columns"
)
```

[`parse_format`](src/arrow.jl#L122)'s three `tsX:` branches change from unconditionally returning
`MaybeMissing{Dates.DateTime}` to: parse out the tz suffix; if empty, `Dates.DateTime` as before;
if non-empty, call `_tz_aware_datetime_type(tz)` for the element type. This function is shared by
both top-level `Series` construction *and* recursive Struct/List child-schema parsing, so a
tz-aware field nested inside a List or Struct column gets the same error/extension behavior for
free — no separate code path needed for the nested case.

Because `Series(ptr)`'s inner constructor ([Polars.jl:38](src/Polars.jl#L38)) calls
`load_series_schema` eagerly, the error fires the moment a tz-aware column is touched (e.g.
`df[:tz_col]`), before any `Series` object is even constructed. Fail-fast, matches user's "err
out" decision.

The extension overrides the *exact same signature* (a standard, well-established pattern for this
kind of hook — see e.g. Requires.jl-style extensions):

```julia
# ext/PolarsTimeZonesExt.jl
Polars._tz_aware_datetime_type(::AbstractString) = TimeZones.ZonedDateTime
```

`TimeZones.ZonedDateTime <: Dates.AbstractDateTime <: Dates.TimeType`, so the *existing*
[`Base.getindex(series::Series{MT}, index) where {MT <: Union{MaybeMissing{Dates.TimeType}, ...}}`
scalar-read method](src/series.jl#L33) already dispatches correctly with zero core changes needed
there — it routes through `load_value(Value{ZonedDateTime}(...))`, and multiple dispatch lets the
extension add that `load_value` method without touching `value.jl`.

### New Rust: per-value tz query (mirrors `polars_value_time_unit`)

`load_value(::Value{ZonedDateTime})` (defined in the extension) needs the tz string at read time.
Values are recovered through `Value.parent`, which is the containing `Series` for a top-level
column but another `Value` for a nested Struct/List field — so relying on a `Series`-level cached
field would break the nested case. Instead, add a genuine per-value C ABI query, mirroring the
existing `polars_value_time_unit` pattern exactly:

```rust
// c-polars/src/value.rs
#[no_mangle]
pub unsafe extern "C" fn polars_value_time_zone(
    value: *mut polars_value_t,
    out: *mut *const u8,
) -> usize {
    match &(*value).inner {
        AnyValue::Datetime(_, _, Some(tz)) => {
            let s = tz.as_str(); // TimeZone derefs to PlSmallStr, which has as_str()
            *out = s.as_ptr();
            s.len()
        }
        _ => 0, // naive datetime, or (defensively) not a datetime at all
    }
}
```

Borrowed pointer, same lifetime convention as `polars_series_name` — valid as long as `value`
(hence its owned `AnyValue`) is alive, no separate destroy call needed. `polars_value_datetime_get`
+ `polars_value_time_unit` (both already exist) supply the epoch offset/resolution; this is the
only new primitive needed for the read path.

Extension's `load_value`:

```julia
# ext/PolarsTimeZonesExt.jl
function Polars.load_value(value::Polars.Value{TimeZones.ZonedDateTime})
    v = Ref{Int64}()
    err = Polars.polars_value_datetime_get(value.ptr, v)
    Polars.polars_error(err)

    tu = Polars.polars_value_time_unit(value)
    naive_utc = if tu == Polars.API.PolarsTimeUnitNanosecond
        Dates.DateTime(1970, 1, 1) + Dates.Nanosecond(v[])
    elseif tu == Polars.API.PolarsTimeUnitMicrosecond
        Dates.DateTime(1970, 1, 1) + Dates.Microsecond(v[])
    else
        Dates.DateTime(1970, 1, 1) + Dates.Millisecond(v[])
    end

    tz_ptr = Ref{Ptr{UInt8}}()
    tz_len = Polars.API.polars_value_time_zone(value.ptr, tz_ptr)
    tz = unsafe_string(tz_ptr[], tz_len)

    utc = TimeZones.ZonedDateTime(naive_utc, TimeZones.tz"UTC")
    return TimeZones.astimezone(utc, TimeZones.TimeZone(tz))
end
```

(exact ccall wiring TBD at implementation time — needs `Value` internals to be accessible from the
extension, which they are since `Polars.Value`/`.ptr` etc. are not currently marked private beyond
module-qualification.)

### Expr-level `Dt.convert_time_zone` / `Dt.replace_time_zone` (unconditional core, no TimeZones.jl)

- **`convert_time_zone(self, time_zone: TimeZone) -> Expr`** — single non-optional tz name.
  `polars_expr_dt_convert_time_zone(expr, tz_ptr, tz_len) -> (out, error)` (fallible only for
  UTF-8 validation, matching `alias`'s convention).
- **`replace_time_zone(self, time_zone: Option<TimeZone>, ambiguous: Expr, non_existent:
  NonExistent) -> Expr`** — more complex: `time_zone` is optional (None = strip tz back to naive),
  `ambiguous` is itself an `Expr` (py-polars passes a string expr: `"raise"`/`"earliest"`/
  `"latest"`/`"null"`), `non_existent` is a 2-variant enum (`Null`, `Raise`). New
  `#[repr(C)] polars_non_existent_t` mirror (`Raise = 0` default, `Null = 1`) + `@cenum`.
  `polars_expr_dt_replace_time_zone(expr, has_tz: bool, tz_ptr, tz_len, ambiguous: *const
  polars_expr_t, non_existent: polars_non_existent_t) -> (out, error)`.
- Julia (`module Dt`): `convert_time_zone(expr, tz::String)`; `replace_time_zone(expr, tz::Union{Nothing,String} = nothing; ambiguous::String = "raise", non_existent::Symbol = :raise)`
  (builds `lit(ambiguous)` internally for the `ambiguous: Expr` param).

## Cargo.toml changes

Add `"timezones"` to the `polars` feature list in `c-polars/Cargo.toml`. Nothing else new —
`rank`/`propagate_nans` (irrelevant here) already active; no other feature needed for
`convert_time_zone`/`replace_time_zone`/`polars_value_time_zone` (the last is unconditional, no
`#[cfg]` on `AnyValue::Datetime` itself).

## Julia package extension scaffolding

`Project.toml`:
```toml
[weakdeps]
TimeZones = "f269a46b-ccf7-5d73-abea-4c690281aa53"

[extensions]
PolarsTimeZonesExt = "TimeZones"

[compat]
TimeZones = "1"
```

`ext/PolarsTimeZonesExt.jl`:
```julia
module PolarsTimeZonesExt

using Polars, TimeZones, Dates

Polars._tz_aware_datetime_type(::AbstractString) = ZonedDateTime

function Polars.load_value(value::Polars.Value{ZonedDateTime})
    ...
end

end
```

Testing the extension needs `TimeZones` as an actual test dependency (extensions aren't loaded by
just `Pkg.develop`-ing the package — the test environment must `using TimeZones` itself). Add
`TimeZones` to `test/Project.toml`'s `[deps]`/`[compat]`, and put extension-specific tests in a new
`test/datatypes/timezones.jl`, included from `test/runtests.jl` with `using TimeZones` scoped
inside that file (so the *rest* of the suite still exercises the "extension not loaded" error path
implicitly — actually not true once `using TimeZones` happens anywhere in the same test process,
since extensions activate process-wide once both deps are loaded, not lexically scoped). This means
**the "errors without the extension" behavior needs its own dedicated, separate test run** (a
second `julia` process / `Project.toml` that never loads `TimeZones`) rather than being provable
inside the same `runtests.jl` that also tests the extension itself. Plan:
- `test/datatypes/timezones.jl`: assumes `TimeZones` IS loaded (extension active), tests full
  round-trip (`Dt.replace_time_zone` on a naive column → read back as `ZonedDateTime`, DST
  transition correctness, `Dt.convert_time_zone` between two zones).
- A short informal live-check (not a committed test, since it needs a `TimeZones`-free process) at
  implementation time: fresh `julia --project=.` **without** `using TimeZones`, construct a
  tz-aware column via `write_parquet`/`read_parquet` of data written by a TimeZones-having process
  or via `Dt.replace_time_zone`, confirm `df[:col]` throws the expected error message.

## Verification

Build (memory-safety-tripped `Monitor` pattern), restart Julia, exercise live before writing
tests:
- `select(df, alias(Dt.convert_time_zone(Dt.replace_time_zone(col("t"), "UTC"), "America/New_York"), "t2"))`
  then read back with `using TimeZones` active — confirm the wall-clock hour shifts correctly
  across a known UTC offset.
- Without `using TimeZones`: `df[:t]` on a tz-replaced column throws with the expected message.
- Nested case: a `Struct` field or `List` element of tz-aware `Datetime` also errors/extends
  correctly (exercises the shared `parse_format` hook, not just the top-level `Series` path).

Then run the full suite via the scratch-env workaround, confirming the existing 574-pass/3-broken
baseline is unaffected when `TimeZones` is *not* added to the scratch env, and a *separate* run
with `TimeZones` added exercises `test/datatypes/timezones.jl` successfully.

## Scope note: write path deferred

Constructing a tz-aware column *from* Julia (`DataFrame((; t = [ZonedDateTime(...)]))`,
`lit(::ZonedDateTime)`) is not covered by this plan — real workflows more commonly start from a
naive/UTC column (parquet/CSV) and localize via the new `Dt.replace_time_zone`, which this plan
does cover. Write-path `arrowvector`/`convert(Expr, ::ZonedDateTime)` support in the extension is
a natural follow-on if needed later.
