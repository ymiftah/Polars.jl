# Tier 1/2 sweep parity note: format / concat_arr / Dt.to_string / datetime / duration / date / Base.time / from_epoch

## Status

**Done.** Re-anchored `test/expr/horizontal.jl`'s `format`/`concat_arr` testsets,
`test/datatypes/datetimes.jl`'s `Dt.to_string` testset, and `test/expr/ranges.jl`'s
`datetime`/`duration`/`date`/`time`/`from_epoch` testsets on upstream fixtures per the
`pypolars-test-parity` skill. `format`/`concat_arr`/`Dt.to_string` were added in `ce9548e`; the
five temporal constructors in `f128f6e` (narrowed by `ce433d7`). Both sets of tests were derived
from live-observed behavior of our own implementation rather than upstream. This sweep found and
fixed **one genuine silent-wrong-answer bug** (`from_epoch`'s `:s`/`:ms` scaling), two genuine
naming-divergence bugs now fixed (`date`/`Base.time` missing their upstream `.alias(...)`), one
docstring inaccuracy fixed (`format`'s "plain scalars" claim), and one true Rust-crate-version-
pinned divergence recorded as `@test_broken` (`datetime`'s fixed `"datetime"` output name vs.
upstream's newer "follow left-hand rule" naming, not yet implemented in the vendored
`polars-plan` 0.54.4).

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `operations_test_format.py`
(the real `pl.format` test file -- `functions_as_datatype_test_format.py` is a near-empty
8-line stub, kept only as the first search hit), `functions_as_datatype_test_concat_arr.py`,
`functions_as_datatype_test_datetime.py`, `functions_as_datatype_test_duration.py`,
`functions_as_datatype_test_time.py`, `datatypes_test_temporal.py`, `datatypes_test_time.py`
(checked, not applicable -- see below), `expr_datetime.py` (full `Expr.dt` namespace Python
source, to confirm `to_string`/`strftime` share one binding), `functions_lazy.py` (full
`pl.from_epoch` Python source -- this is where the scaling bug was found), and the vendored
`polars-plan-0.54.4` crate source directly (`~/.cargo/registry/.../dsl/functions/temporal.rs`,
`concat.rs`) to distinguish a genuine bug from a version-pinned Rust behavior.

## Fixtures ported (all live-verified before asserting, Step 7)

### `format`

| upstream test | fixture | category | outcome |
|---|---|---|---|
| `test_format_expr` | 12-column fixture: literal/column args in every position, `{}` order permutations | happy path, null propagation | matches exactly; added |
| `test_format_with_nulls_25347` | `[None, "a"]` / two-column null fixture | null propagation | matches; added |
| `test_format_arg_passing` | `{0}`/`{name}` positional/named placeholders, automatic-vs-manual numbering, out-of-bounds index, unmatched braces, unacceptable name | non-default parameter value, wrong-argument raises | matches -- all raise `PolarsError` (upstream splits into `InvalidOperationError`/`ShapeError`/`ColumnNotFoundError`, collapsed per Step 6); added |
| `test_format_group_by_23858` | `format` inside `group_by(...).agg(...)` | non-default context | matches (shape `(1,2)`); added |
| `test_format_on_multiple_chunks_concat_25159` | `format` over a `concat`-produced multi-chunk frame | non-default input shape | matches; added |

**Not ported**: `test_format_fail_on_unequal`'s exact upstream call shapes use raw Python `int`/`lit`
args interchangeably; ported using `lit(...)` throughout instead of a bare numeric literal -- see
the API divergence below. `test_format_on_multiple_chunks_25159` (the flaky, env-var-gated,
`date_ranges`-dependent chunk test) -- out of scope (needs the `range` Cargo feature, explicitly
excluded from this batch).

### `concat_arr`

| upstream test | fixture | category | outcome |
|---|---|---|---|
| `test_concat_arr` / `test_concat_arr_broadcast` / `test_concat_arr_logical_types_20917` | value-level `Array` fixtures | happy path, non-default dtype | **not portable** -- see the Array-dtype caveat below |
| `test_concat_arr_broadcast` | a scalar `lit` argument broadcast against a column | non-default parameter shape | plan builds, `collect` succeeds (values not inspectable); added |
| n/a (own addition) | dtype mismatch between two `concat_arr` inputs | wrong-dtype raises | `PolarsError`; added |
| n/a (own addition) | a `missing` element in one input column | null propagation | plan builds, `collect` succeeds; added |
| n/a (own addition) | 0-row input frame | empty input | plan builds, `collect` succeeds, shape `(0,1)`; added |

**Not ported**: every value-checking fixture in `test_concat_arr*` (`assert_series_equal` against
an `Array`-dtype `Series`) -- per `CLAUDE.md`'s known caveat, `collect` succeeds but
`collect_schema`/`schema`/indexing an `Array` column all raise `ErrorException` from
`src/arrow/schema.jl:136` (the fixed-size-list Arrow format isn't recognized yet), and this
package has no `Arr`/`List`-cast escape hatch to read the values back another way (checked live --
no `Arr` namespace exists, and casting the `concat_arr` result to `List` before `collect` doesn't
avoid the same schema-resolution path). Confirmed this is *still* the case, not rediscovered from
scratch. `test_concat_arr_validity_combination(_zwa)`/`test_concat_arr_zero_fields` (zero-width
array edge cases), `test_concat_arr_scalar` (`_to_metadata()` internals), and the mismatched-length
top-level-`pl.select`-over-bare-`Series` case in `test_concat_arr_broadcast` -- this package's
`select` always takes a `DataFrame`/`LazyFrame` (no `pl.select(bare_series_expr, ...)` entry point
without a shared frame, so two differently-sized literal `Series` can't be constructed as select
args the way upstream's does), Step 9-adjacent API-shape mismatch, not portable.

### `Dt.to_string`

| upstream test | fixture | category | outcome |
|---|---|---|---|
| `test_temporal_to_string_iso_default` | `"iso"`/`"iso:strict"` sentinel format strings on Datetime/Date; `"polars"`/`"iso"` on a component-built Duration | non-default parameter value (sentinel formats, not chrono strings) | matches exactly (values, and the space-vs-`T` separator distinction); added |
| `test_temporal_to_string_error` | `"polars"` format on a Date dtype | wrong-parameter raises | matches (`PolarsError`); added |
| `test_to_string_invalid_format` | `%z` on a timezone-naive Datetime | domain edge, wrong-parameter raises | matches (`PolarsError`); added |
| `test_tz_aware_to_string` | `%c` format on a tz-aware `datetime_range` | happy path, tz-aware | **not ported** -- needs `datetime_range` (the `range` Cargo feature), explicitly out of scope |

Confirmed live and recorded in the testset comment: `strftime`/`to_string` genuinely share one
Rust binding upstream too (`Expr.dt.strftime` calls `self._pyexpr.dt_to_string(format)`, the exact
same call `to_string` makes) -- this package's shared `polars_expr_dt_strftime` wrapper for both is
not a simplification on our part.

### `datetime` / `duration` / `date` / `Base.time` / `from_epoch`

| upstream test | fixture | category | outcome |
|---|---|---|---|
| `test_date_datetime` | `pl.datetime(...).dt.hour()` / `pl.date(...).dt.day()` round-trip their own input columns | happy path | matches; added |
| `test_date_invalid_component` / `test_datetime_invalid_date_component` | `(2025,13,1)`/`(2025,1,32)`/`(2025,2,29)` | wrong-parameter raises | matches (`PolarsError`), for both `date` and `datetime`; added |
| `test_datetime_invalid_time_component` | hour=25, minute=60, second=60, microsecond=2_000_000 | domain edge, wrong-parameter raises | matches; added |
| `test_datetime_time_unit` | `:ms`/`:us`/`:ns` parametrized | non-default parameter value | matches; added |
| `test_datetime_time_zone` | `nothing`/`"Europe/Amsterdam"`/`"UTC"` parametrized | non-default parameter value | matches (shape-only, reading a tz-aware value needs `TimeZones.jl`); added |
| `test_datetime_ambiguous_time_zone` / `test_datetime_ambiguous_time_zone_earliest` | `2018-10-28 02:30` Europe/Brussels DST fall-back | non-default parameter value, domain edge | matches: `ambiguous="raise"` (default) raises; `"earliest"` resolves to the expected wall-clock instant; `"earliest"`/`"latest"` resolve to distinct UTC instants (checked via `Dt.timestamp`, since reading the tz-aware value needs `TimeZones.jl`); added |
| `test_datetime_invalid_time_zone` | unparseable tz name `"foo"`, empty vs. non-empty input column | wrong-parameter raises, empty input | matches on both; added |
| `test_datetime_from_empty_column` | 0-row input, `select`/`with_columns` | empty input | matches (`(0,1)`/`(0,2)`); added |
| `test_datetime_name` | column-name propagation ("year" / "literal") | Step 4 non-default / Step 8 divergence | **genuine divergence, `@test_broken`** -- see below |
| `test_empty_duration` | 0-row input, `duration(days="days")` | empty input | matches (`(0,1)`); added |
| `test_duration_time_units` | ms/us/ns parametrized, exact ns total (`86523004005006`) | non-default parameter value | matches; added |
| `test_duration_subseconds_us` | sub-second components vs. their pre-summed equivalent, per time_unit | domain edge (rounding/truncation) | matches exactly for `:ms`/`:us`/`:ns`; added |
| `test_duration_time_unit_ms` | unspecified `time_unit` defaults to `:us`, not `:ms` | non-default parameter (default confirmation) | matches; added |
| `test_datetime_duration_offset` / `test_date_duration_offset` | `Datetime`/`Date` +/- a component-built `duration`, several unit fields | happy path, arithmetic composition | matches exactly (values); added. Upstream's `year=3000` row dropped -- overflows Julia's ns-precision `DateTime` round-trip (`InexactError`), an unrelated general limitation, not specific to this batch |
| `test_duration_wildcard_expansion` | `duration(hours=pl.all()).name.keep()` | non-default parameter (wildcard expansion) | matches, using this package's `keep_name` (the `.name.keep()` counterpart); added |
| `test_time` (`functions/as_datatype/test_time.py`) | `pl.time(...).dt.hour()/.minute()/.second()/.microsecond()` round-trip their own input columns | happy path | matches; added |
| `test_from_epoch` (`lazyframe/test_lazyframe.py`) | `13285`/`1147880044`(x scale) across `:d`/`:s`/`:ms`/`:us`/`:ns` | happy path, non-default parameter value (every `time_unit`) | matches after the fix below; added |
| `test_from_epoch_seq_input` | `[1147880044]` default `:s` | happy path | matches; added |
| `test_from_epoch` docstring's fractional-seconds example | `[-609066.723456, 1066445333.8888, 3405071999.987654]` at `:s` | domain edge (sub-millisecond precision) | **found the genuine bug** -- see below |
| `test_from_epoch_str` | a `String` column at `:ms`/`:s` | wrong-dtype raises | **found the same bug's other half** -- see below |

**Not ported**: `test_duration_from_i128_23050` (`Int128` inputs -- this package has no `Int128`
literal support surfaced through `duration`'s scalar-literal `convert` overloads, same class of
limitation the `extend_constant` sibling sweep already documented for non-`Int32`/`Int64` scalar
literals); `datatypes/test_time.py`'s tests (`test_time_to_string_cast`,
`test_time_zero_3828`, `test_time_microseconds_3843`, `test_invalid_casts`) -- these exercise
`Series`/`Expr.cast(pl.Time)` and `Time` literal construction, not the `pl.time(...)` component
constructor this batch covers (Step 9: same search term, different function).

## Genuine bug found and fixed: `from_epoch`'s `:s`/`:ms` scaling silently lost precision

The task brief specifically flagged `from_epoch`'s unit handling as the likeliest spot for a
silent wrong-answer bug in this batch, and that's exactly what turned up. Reading upstream's own
Python source (`py-polars/src/polars/functions/lazy.py::from_epoch`) line by line:

```python
if time_unit in (scale := {"s": 1_000_000, "ms": 1_000}):
    ...
    column = column * F.lit(scale[time_unit], dtype=Int64)
    return column.cast(Datetime("us"))
if time_unit in DTYPE_TEMPORAL_UNITS:  # "us", "ns"
    return column.cast(Datetime(time_unit))
```

Upstream scales `:s` **x1,000,000** and `:ms` **x1,000**, casting *both* to `Datetime("us")` --
never to `Datetime("ms")`. The old implementation in `src/expr/ranges.jl` instead did:

```julia
if time_unit in (:ns, :us, :ms)
    return cast_datetime(expr; time_unit)          # :ms went straight to a *direct* ms cast
elseif time_unit == :s
    return cast_datetime(expr * convert(Expr, 1_000); time_unit = :ms)   # only x1,000, landing on :ms
```

For whole-second/whole-millisecond inputs (every hand-written fixture the original tests used) the
visible wall-clock value is identical either way -- the divergence only shows up at sub-millisecond
precision, which is exactly the case upstream's own `from_epoch` docstring uses as its second
example (fractional-second epoch floats). Live-verified before and after:

```julia
# before the fix (src/expr/ranges.jl, old :s branch: x1_000, cast to :ms)
from_epoch(col("ts"), :s)  # ts = -609066.723456
# => 1969-12-24T22:48:53.277        -- upstream: 1969-12-24 22:48:53.276544 (lost 5 digits)

# after the fix (x1_000_000, cast to :us)
cast(Dt.microsecond(from_epoch(col("ts"), :s)), Int64)
# => 276544                          -- matches upstream exactly
```

Fixed in `src/expr/ranges.jl`: `:s` now scales x1,000,000 and casts to `:us`; `:ms` now scales
x1,000 and casts to `:us` (previously a direct physical cast to `:ms`); `:ns`/`:us` are unchanged
(a direct physical cast at that same resolution, matching upstream); `:d` is unchanged (a direct
cast to `Date`). Docstring updated to describe the scaling exactly, including *why* `:ms`/`:s`
can't be a direct-cast-to-`:ms` shortcut.

**Side effect, also confirmed correct**: `test_from_epoch_str` (a `String` column at `:s`/`:ms`)
now raises `PolarsError` cleanly, where it previously silently returned `missing` for every row.
Before the fix, `:ms` reached `cast_datetime` directly, which on a `String` source dtype uses
Rust's *lenient string-to-datetime parsing* cast (nulls unparseable input rather than raising) --
an entirely different cast code path from the *physical* Int-to-Datetime reinterpret the function
is meant to perform. After the fix, `expr * 1_000` on a `String` column fails to build (raises)
before ever reaching a cast, matching upstream's own behavior (upstream's Python source multiplies
first too, so a `String` column hits the same wall). `:us`/`:ns` (still a direct
`cast_datetime` call, unchanged) still null a `String` input rather than raising -- confirmed this
matches upstream too (their `:us`/`:ns` branch is the same direct-cast call, inheriting the same
lenient string-cast semantics), so it is not a new or remaining divergence, just an accurately
ported inconsistency that already exists in upstream's own function.

## Genuine bugs found and fixed: `date`/`Base.time` were missing their upstream `.alias(...)`

Upstream's `pl.date`/`pl.time` (`py-polars/src/polars/functions/as_datatype.py`) are pure-Python
compositions over `pl.datetime`, exactly as this package's docstrings already claimed -- but each
one finishes with an explicit rename the old Julia implementations didn't have:

```python
def date_(year, month, day) -> Expr:
    return datetime_(year, month, day).cast(Date).alias("date")

def time_(hour=None, minute=None, second=None, microsecond=None) -> Expr:
    return datetime_(*epoch_start, hour, minute, second, microsecond).cast(Time).alias("time")
```

The old `src/expr/ranges.jl`:

```julia
date(year, month, day) = Dt.date(datetime(year, month, day))
Base.time(hour, minute=0, second=0, microsecond=0) = Dt.time(datetime(1970, 1, 1; hour, minute, second, microsecond))
```

`Dt.date`/`Dt.time` are plain namespaced extractions (`DateLikeNameSpace::date`/`::time`) that
don't rename their input, so the output column silently inherited `datetime`'s own fixed name
(`"datetime"`, see below) instead of `"date"`/`"time"`. Confirmed live before the fix:
`names(select(df, date(...)))` -> `["datetime"]`; upstream: `["date"]`. Fixed by wrapping both in
`alias(..., "date")`/`alias(..., "time")`; `alias(...)` on the caller's side (an explicit outer
rename) still overrides it, confirmed live.

## Genuine divergence found, not fixable here: `datetime`'s fixed `"datetime"` output name

Upstream's newer `test_datetime_name` (`functions/as_datatype/test_datetime.py`) expects:

```python
df.select(pl.datetime("year", "month", "day", "hour")).columns == ["year"]        # first arg's own name
df.select(pl.datetime(2024, "month", "day", "hour")).columns == ["literal"]       # first arg is a literal
```

This package's `polars_expr_datetime` (`c-polars/src/expr.rs`) calls upstream's own
`polars_plan::dsl::functions::datetime` directly, unmodified -- so this is not a Julia-marshalling
bug. Reading that Rust function's source in the exact vendored crate version
(`~/.cargo/registry/.../polars-plan-0.54.4/src/dsl/functions/temporal.rs:189-221`) shows it always
returns:

```rust
Expr::Alias(Arc::new(Expr::Function { ... }), PlSmallStr::from_static("datetime"))
// TODO: follow left-hand rule in Polars 2.0.
```

-- a fixed `"datetime"` alias, with the crate's own comment marking the "follow left-hand rule"
naming (what upstream's test now expects) as a **not-yet-implemented** future change. Live-verified
this package's actual behavior matches that source exactly: `names(select(dfh, datetime(col(...),
...)))` -> `["datetime"]` in both the column-name and literal-first-arg cases, never `["year"]` or
`["literal"]`. This is a genuine Rust-crate-version-pinned divergence, not fixable without bumping
the vendored `polars-plan` dependency (a `Cargo.toml`/`Cargo.lock` change, explicitly out of scope
for this sweep per its brief). Recorded as `@test_broken` in `test/expr/ranges.jl` against
upstream's expected names, alongside the actual behavior asserted as fact, and documented in
`datetime`'s own docstring in `src/expr/ranges.jl`.

## Docstring fix: `format`'s "plain scalars" claim was misleading

`format`'s docstring said each `{}` placeholder accepts "expressions or plain scalars" -- true for
`String`/`Symbol` (which `_as_expr` turns into a **column reference**, `col(name)`, matching
upstream's own `parse_into_expression` convention for a bare string argument), but false for a
numeric literal: `format("{} {}", 1)` raises `MethodError` (`_as_expr` has no method for `Int64`),
where upstream's `pl.format(..., 1)` accepts a raw Python int directly (wrapped as `pl.lit(1)`
internally). Every upstream `test_format_arg_passing` fixture that used a raw int was ported using
explicit `lit(...)` instead, and confirmed live it changes nothing about the *values* produced --
only about whether the literal has to be wrapped. Docstring corrected in `src/expr/expr.jl` to
describe exactly what "scalar" means here (a `String`/`Symbol` naming a column, not a numeric
literal) and to point at `lit(...)` for the numeric case.

## API divergence found, not fixed (Step 8): `Dt.to_string`/`Dt.strftime` have no zero-argument default

Upstream `Expr.dt.to_string(format: str | None = None)` defaults to `"iso"` when `format` is
omitted (`df.dt.to_string()`). This package's `to_string(expr, format)`/`strftime(expr, format)`
both require `format` positionally -- `Dt.to_string(col("d"))` raises `MethodError`, confirmed
live. Not fixed here (a one-line default-argument addition, but genuinely a separate, self-
contained code change rather than a test-parity fix); recorded as a deliberate omission for now,
same treatment as the sibling sweeps' Step 8 entries.

## Running ledger

| function | our test file | upstream file::test | status | note |
|---|---|---|---|---|
| `format` | `test/expr/horizontal.jl` | `operations/test_format.py::test_format_expr`, `test_format_with_nulls_25347`, `test_format_arg_passing`, `test_format_group_by_23858`, `test_format_on_multiple_chunks_concat_25159` | done | docstring fixed (scalar-literal claim); all error categories collapse to `PolarsError` per Step 6 |
| `concat_arr` | `test/expr/horizontal.jl` | `functions/as_datatype/test_concat_arr.py::test_concat_arr*` | done, value-level fixtures not portable | Array-dtype introspection limitation reconfirmed, not rediscovered; broadcast/null/empty/dtype-mismatch coverage added at the plan-construction level |
| `Dt.to_string` | `test/datatypes/datetimes.jl` | `datatypes/test_temporal.py::test_temporal_to_string_iso_default`, `test_temporal_to_string_error`, `test_to_string_invalid_format` | done | sentinel formats (`"iso"`/`"iso:strict"`/`"polars"`) confirmed pass-through; zero-arg default omission noted (Step 8) |
| `datetime` | `test/expr/ranges.jl` | `functions/as_datatype/test_datetime.py` (7 tests) | done, 2 `@test_broken` | fixed-`"datetime"`-name divergence confirmed as a pinned Rust-crate-version gap, not a Julia bug |
| `duration` | `test/expr/ranges.jl` | `functions/as_datatype/test_duration.py` (8 tests) | done | subsecond rounding, default time_unit, wildcard expansion (`keep_name`) all ported |
| `date` | `test/expr/ranges.jl` | `functions/as_datatype/test_datetime.py::date_` | done, **bug fixed** | missing `.alias("date")` added |
| `Base.time` | `test/expr/ranges.jl` | `functions/as_datatype/test_time.py::test_time` | done, **bug fixed** | missing `.alias("time")` added |
| `from_epoch` | `test/expr/ranges.jl` | `lazyframe/test_lazyframe.py::test_from_epoch`, `test_from_epoch_str`; `series/test_series.py::test_from_epoch_expr`, `test_from_epoch_seq_input` | done, **bug fixed** | `:s`/`:ms` scaling corrected to match upstream's x1e6/x1e3-then-`:us` exactly; sub-millisecond precision loss fixed; `String`-input silent-null fixed as a side effect |

## Verification

- `test/expr/horizontal.jl` alone: **73/73 pass** (includes every pre-existing testset in the
  file, not just `format`/`concat_arr`).
- `test/expr/ranges.jl` alone: **81 pass, 2 broken** (the `datetime`-naming divergence above).
- `test/datatypes/datetimes.jl` alone: all testsets pass (including the pre-existing, unrelated
  `Dt.replace` Rust-panic-recovery test further down the file, confirmed unaffected).
- `timeout 900 julia --project=. -e 'using Pkg; Pkg.test()'`: **3304 passed, 6 broken** (baseline
  3196 passed / 4 broken -- the delta is +108 passing assertions and +2 new `@test_broken` for the
  `datetime`-naming divergence above; the pre-existing 4 broken are unrelated Aqua/
  `Strings.titlecase` exclusions, per the sibling sweeps).
- `pre-commit run --all-files`: all hooks pass (`check runic formatting`, `cargo fmt (c-polars)`,
  `cargo clippy (c-polars)`, `clang-format (c-polars headers)`) -- runic auto-reformatted one
  multi-line `DataFrame((;...))` call in `test/expr/ranges.jl` on first run (cosmetic only, no
  behavior change; re-verified the affected testset still passes after the reformat).
- `timeout 1500 julia --project=docs -e 'include("docs/make.jl")'`: **passed** (docstring changes
  in `src/expr/expr.jl` and `src/expr/ranges.jl` build cleanly; pre-existing "not included in
  `@docs`" warnings are unrelated to this batch).
