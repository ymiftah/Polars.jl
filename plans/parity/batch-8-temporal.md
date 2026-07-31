# Batch 8 parity note: datatypes/datetimes.jl, times.jl, durations.jl, timezones.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_datetime.py`,
`test_offset_by.py`, `test_round.py`, `test_truncate.py`, `test_temporal_replace.py` (renamed
from `test_replace.py` to avoid colliding with the earlier-fetched string-replace file),
`test_temporal.py` (2547 lines), `test_duration.py`, `test_time.py`.

Baseline: `durations.jl` is already exhaustively deep per its own header comment (Phase 5 of the
gap-closure plan). `datetimes.jl`/`times.jl`/`timezones.jl` cover the common accessors, DST-aware
`replace_time_zone`/`convert_time_zone`, and truncate/round across several duration strings
already. This batch's finds are two untested edges plus one cross-reference to an already-flagged
gap (Batch 6's missing `strict` cast option, which turns out to affect `Time` casts too).

## Note on API surface: `Dt.truncate`/`Dt.round` aren't in the exported-names ledger enumeration

While investigating this batch, confirmed `Dt.truncate`/`Dt.round`/`Dt.offset_by` are generated via
`@generate_expr_fns`'s Base-name-collision path (`truncate`/`round` collide with *exported* `Base`
bindings, so they become `Base.truncate`/`Base.round` extensions per the `@generate_expr_fns`
convention documented in `CLAUDE.md`) — reachable as `Dt.truncate(...)` via the `Dt` submodule's own
curried-form definitions, but invisible to a bare `names(Polars.Dt)` sweep since they're not
*exported from* `Dt` under those bare names. `LEDGER.md`'s generated skeleton (built from
`names(...)` for each module) undercounts this class of function. Noted here rather than silently
left as a blind spot — doesn't change this batch's actual test coverage, since these functions were
already tested before this sweep started.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `Dt.offset_by` | `test_date_offset_by` (the `-2mo`/month-arithmetic case, extended to a month-end fixture) | `Date(2020,1,31)` offset by `"1mo"` | domain edge — month-end clamps to the shorter month (Feb 29 in a leap year), doesn't overflow into March | matches (`2020-02-29`); added |
| `Dt.truncate`/`Dt.round`/`Dt.offset_by` | (general null-propagation behavior implicit throughout `test_datetime.py`) | one non-null + one `missing` `DateTime` row | null propagation | matches across all three; added |

## Cross-reference to an already-flagged gap (not a new finding)

`test_time.py`'s `test_invalid_casts` expects `pl.Series([-1]).cast(pl.Time)` (and other
out-of-range nanosecond values) to raise `InvalidOperationError`. Live-verified our own
`cast(col("a"), Dates.Time)` on the same out-of-range values instead returns `missing` — **this is
the same root cause as Batch 6's already-flagged finding** (`cast()` always uses
`CastOptions::NonStrict`; Python's own `Expr.cast(dtype, strict=True)` defaults to `strict=True`,
which our binding doesn't reach). Not re-added as a second `LEDGER.md` entry — cross-referenced
instead, per Step 9's "don't conflate/duplicate" discipline extended to gap-tracking. Added a test
capturing our **actual, consistent, already-correct-per-our-own-design** non-strict behavior
(`missing`, not an error) rather than upstream's strict-mode raise, since asserting the raise would
just be re-describing the same known gap a second time.

## Not ported (Step 4 exclusions)

- `test_offset_by_unique_29_feb_19608`, `test_month_then_day_21283`,
  `test_offset_by_rfc_5545_boundaries*` — combine timezone-aware `datetime_range` construction
  (`pl.datetime_range`, no Polars.jl counterpart) with the offset-by clamp behavior; the underlying
  clamp behavior is already captured by the simpler fixture above without needing that machinery.
- `test_duration.py`'s remaining ~370 lines (`test_duration_cum_sum`, `_std_var`, `_to_string`,
  `_float_types_*`, `_i64_overflow`) — dtype-preservation/aggregation-composition checks already
  well-covered by the existing exhaustive Phase-5 `Dt.total_*` tests, or Series-level dtype
  round-trips with no clean assertion path here (same reasoning as prior batches' dtype-focused
  exclusions).
- `test_temporal.py` (2547 lines) — skimmed; overwhelmingly Categorical/Enum-adjacent temporal
  interop, numpy/pandas round-trips, and internal schema-inference regressions. Nothing pulled.
- `test_temporal_replace.py` (`Dt.replace`, i.e. replacing individual date/time *components* like
  "set the year to X") — **`Dt.replace` doesn't exist in Polars.jl at all**. Genuine gap, but a
  large one (component-wise replacement needs several new optional-int-per-field FFI arguments);
  recorded in `LEDGER.md` as a distinct, sizeable missing-function gap, not investigated further
  this batch given the volume already found.
- `test_round.py`/`test_truncate.py`'s DST-crossing-specific parametrizations — the non-DST
  truncate/round behavior (across several duration strings) is already covered by the existing
  "Dt.truncate / Dt.round with different duration strings" testset; DST-specific rounding needs a
  `TimeZones.jl`-backed fixture crossing an actual transition, which the existing
  `timezones.jl` file's `replace_time_zone`/`convert_time_zone` tests don't currently set up and
  would be a substantial addition on its own — left for a future, dedicated pass rather than bolted
  on here.

## Resolved non-issues (verified before assuming a bug)

- The `Time`-cast-out-of-range difference above was checked against the actual Rust
  `CastOptions` source before concluding it was a duplicate of the Batch 6 finding rather than a
  distinct new bug — confirmed same root cause, not re-flagged separately.
