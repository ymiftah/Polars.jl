# API wave 5: null filling, datetime extras, rolling median/quantile, list/string namespace fill-ins

## Status

**Done.** Implemented on branch `api-wave5-fill-dt-list-str` (stacked on `api-wave4-ewm-cutqcut`).
No Cargo feature was added — every item below was implemented with the currently-active feature
set, or explicitly deferred (with a working "unavailable in this build" stub, matching the existing
`Strings.titlecase` precedent) when it genuinely needed one that isn't active. Test suite:
**2258 pass, 4 broken, 0 fail (2262 total)**, up from the stated 2168/4/0 (2172 total) baseline --
net +90 new passing assertions, the same 4 pre-existing `broken` (unrelated `cut`/`qcut` panics,
see `test/expr/cut_qcut.jl`), zero failures. Scratch-env note: the CLAUDE.md recipe's package list
(`Aqua`, `Test`, `Tables`, `TimeZones`) is incomplete for a full `runtests.jl` run -- it also needs
`StatsBase` and `CategoricalArrays` (both are `[weakdeps]`/`[extensions]` in `Project.toml`, backing
`test/expr/statsbase_ext.jl`/`test/expr/categoricalarrays_ext.jl`), or those two files error out
before the rest of the suite runs.

## Scope and disposition

### Group 1 — null filling (`src/expr/expr.jl`) -- DONE, no new FFI
- `forward_fill(expr; limit=nothing)`, `backward_fill(expr; limit=nothing)`: implemented purely in
  Julia as thin wrappers over the existing `fill_null(expr; strategy=:forward/:backward, limit)` --
  polars itself has no separate `Expr::forward_fill`/`backward_fill` method (grepped
  polars-plan/src, nothing found); py-polars' own Python layer builds them the same way. Zero new
  Rust surface.

### Group 2 — datetime namespace (`src/expr/datetime.jl`, module `Dt`)
- `Dt.week`, `Dt.quarter` -- **DONE**. `DateLikeNameSpace::week`/`quarter` are unconditional (no
  `#[cfg]`) in polars-plan 0.54.4.
- `Dt.timestamp` -- **DONE**. `DateLikeNameSpace::timestamp(tu: TimeUnit)` is unconditional; new
  fallible FFI fn `polars_expr_dt_timestamp` (the `polars_time_unit_t` conversion can fail, same
  shape as `polars_expr_cast_datetime`).
- `Dt.epoch` -- **DONE, pure Julia on top of `Dt.timestamp`.** No native `epoch` method exists
  anywhere in polars-plan; py-polars' own Python binding builds `:ns`/`:us`/`:ms` as `timestamp`
  directly and `:s`/`:d` by floor-dividing the millisecond timestamp (confirmed against upstream's
  `test_epoch_matches_timestamp`: `epoch("s") == timestamp("ms") // 1000`,
  `epoch("d") == (timestamp("ms") // 86_400_000).cast(Int32)`). Implemented identically.
- `Dt.month_start`, `Dt.month_end` -- **SKIPPED, needs Cargo features `month_start` and
  `month_end`** respectively (two *separate* features in the `polars` facade Cargo.toml, both
  `#[cfg(feature = "month_start"/"month_end")]`-gated in `polars-plan/src/dsl/dt.rs`, neither in
  `cargo tree -e features -i polars-plan`'s active set). Left as "unavailable in this build" stub
  functions (matching the `Strings.titlecase`/nightly precedent) rather than silently missing, so
  calling them explains why instead of raising a bare `UndefVarError`.

### Group 3 — rolling family (`src/expr/expr.jl`) -- DONE, no new feature
- `rolling_median`, `rolling_quantile`: both unconditional under the already-active
  `rolling_window` feature (same as the existing six). `rolling_median` reuses the shared
  `gen_rolling!` Rust macro verbatim (mirrors `rolling_mean`/etc. exactly: `window_size`,
  `min_periods`/`min_samples`, `center`, no extra params). `rolling_quantile` is hand-written
  (extra `quantile: f64` + `polars_quantile_method_t` params, reusing the existing quantile-method
  enum from the top-level `quantile` wrapper) -- verified live that `rolling_median(w) ==
  rolling_quantile(w, 0.5; method=:linear)` exactly, matching upstream's own documented relationship
  (`Expr::rolling_median` is literally implemented as `self.rolling_quantile(Linear, 0.5, options)`
  in polars-plan).

### Group 4 — list namespace (`src/expr/list.jl`, module `Lists`)
- `Lists.sort`, `Lists.join`, `Lists.slice`, `Lists.diff` -- **DONE.** None of these four are
  feature-gated except `diff` (`#[cfg(feature = "diff")]`, already active). `Lists.join` in
  particular is **not** the same capability as `Strings.join`/`concat_str` -- `ListNameSpace::join`
  (joining the *string elements of a list* into one string) is a wholly separate, ungated method
  from `StringNameSpace::join` (concatenating a whole *String column*), which really is
  `concat_str`-gated. Conflating the two would have wrongly skipped a working capability.
- `Lists.n_unique`, `Lists.any`, `Lists.all` -- **DONE**, but not the way the task brief guessed.
  There is no `list_any_all` Cargo feature in polars 0.54.4 at all (searched the whole vendored
  `polars`/`polars-plan` source tree; no such feature, no such `ListFunction`/`BooleanFunction`
  variant restricted by one) -- `any`/`all`/`n_unique` on the list namespace simply don't exist as
  native `ListNameSpace` methods in this version, gated or not. Built the same way python-polars
  itself builds them: `.list().agg(element().any(ignore_nulls))` etc. -- reducing per-list plain
  `Expr::any`/`Expr::all`/`Expr::n_unique` (all three unconditional). **Important correction made
  during implementation:** the first attempt used `.list().eval(...)` (the combinator already used
  by `Lists.reverse`/`unique`/`unique_stable` in this file) and produced a `List`-wrapped
  single-element result (`[true]` instead of `true`) because `eval` always re-wraps its result in a
  length-1 list per row for a reducing sub-expression. `.list().agg(...)` (a second, until-now-unused
  `EvalVariant`) is what unwraps a per-list reduction back down to a flat scalar column -- confirmed
  by testing against upstream's exact `test_list_any`/`test_list_all`/`test_list_n_unique` fixtures.
- `Lists.to_struct` -- **SKIPPED, needs Cargo feature `list_to_struct`** (confirmed gated,
  confirmed inactive). Stub function added, matching the `titlecase` precedent.

### Group 5 — string namespace (`src/expr/string.jl`, module `Strings`)
- `Strings.pad_start`, `Strings.pad_end` -- **DONE.** Both `#[cfg(feature = "string_pad")]`, already
  active. `fill_char` crosses the FFI boundary as a `u32` Unicode codepoint (there is no `char32_t`
  binding on the Julia side) via a new fallible pair of FFI fns (`char::from_u32` can fail on an
  invalid codepoint, so this goes through the out-param + error-pointer convention rather than a
  panic). Verified live against upstream's `test_pad_start_unicode`/`test_pad_end_unicode` fixture
  (non-ASCII, multi-byte `'日'` fill char, char-count not byte-count width) -- correct.
- `Strings.find` -- **DONE.** `#[cfg(feature = "regex")]`, already active; identical shape to the
  already-wrapped `contains(pat, strict)`, just returning the match position instead of a boolean.
  Verified against upstream's `test_str_find` fixture (regex + column-pattern + `strict`
  true/false-on-invalid-regex cases) exactly.
- `Strings.join`, `Strings.to_integer`, `Strings.extract_groups`, `Strings.reverse` -- **all four
  SKIPPED**, confirmed gated behind features that are **not** active: `concat_str`,
  `string_to_integer`, `extract_groups`, `string_reverse` respectively (each is its own standalone
  feature in the `polars` facade Cargo.toml, none implied by any currently-active feature). All four
  match the task brief's suspicion. Stub functions added for each, matching the `titlecase`
  precedent, rather than leaving a bare missing-`ccall`-symbol `UndefVarError`.

### Group 6 — inverse trigonometry (`src/expr/expr.jl`) -- DONE, no new feature
- `arcsin`, `arctan`: plain `gen_impl_expr!` one-liners mirroring `arccos` exactly, under the
  already-active `trigonometry` feature. Verified against upstream's `test_trigonometric`
  parametrized fixture (null propagates, NaN propagates, `arcsin(π)` is `NaN` since π > 1 is
  out-of-domain, `arctan` has no domain restriction) -- exact match.

### Supporting addition not in the original scope list: `floor_div`
`Dt.epoch`'s `:s`/`:d` units need floor division (matching Python's `//`, which floors towards
negative infinity) to be correct for pre-1970 (negative) timestamps -- this repo's existing `/`/`div`
(`Expr::div` / `Operator::RustDivide`) turned out, after live testing, to already floor for *integer*
operands (empirically identical to `Operator::FloorDivide` for every integer case tried), but
diverges for *float* operands, where `div`/`RustDivide` gives the exact (unrounded) quotient instead
of flooring. Added `floor_div` (`Expr::floor_div` / `Operator::FloorDivide`, itself an unconditional,
non-feature-gated operator) as a small new top-level binary op, mirroring the existing
`add`/`sub`/`div` entries in the `@generate_expr_fns` block, and used it inside `Dt.epoch` rather
than relying on `div`'s currently-accidental integer-flooring behavior. Verified live: `epoch(dt,
:s)` on `1969-12-31T23:59:59` (one second before the epoch) correctly gives `-1`, not `0` --
confirms the floor (not truncating) semantics this depended on.

## Symbol counts

`python3 c-polars/check_header_drift.py`: **324 -> 342** exported symbols (+18), matching exactly
the 18 new `#[no_mangle] extern "C"` functions added: `polars_expr_arcsin`, `polars_expr_arctan`,
`polars_expr_floor_div`, `polars_expr_rolling_median`, `polars_expr_rolling_quantile`,
`polars_expr_dt_week`, `polars_expr_dt_quarter`, `polars_expr_dt_timestamp`,
`polars_expr_list_n_unique`, `polars_expr_list_any`, `polars_expr_list_all`,
`polars_expr_list_sort`, `polars_expr_list_join`, `polars_expr_list_slice`,
`polars_expr_list_diff`, `polars_expr_str_find`, `polars_expr_str_pad_start`,
`polars_expr_str_pad_end`. (`polars_expr_str_to_titlecase` remains the one pre-existing
`#[cfg]`-gated symbol invisible to a default build.)

## Verification

Every new function was exercised live in a fresh `julia --project=.` process (native `.so`
rebuilt between every Rust change) against real upstream py-polars fixtures fetched from
`pola-rs/polars`'s GitHub tree, not just the happy path -- see the corresponding `test/` files for
the exact fixtures used (`test/expr/arithmetic.jl` for `arcsin`/`arctan`/`floor_div`,
`test/expr/null_handling.jl` for `forward_fill`/`backward_fill`, `test/expr/rolling.jl` for
`rolling_median`/`rolling_quantile`, `test/datatypes/datetimes.jl` for the `Dt` additions,
`test/datatypes/lists.jl` for the `Lists` additions, `test/datatypes/strings.jl` for the `Strings`
additions).

## Not attempted / out of scope

- No `docs/src/reference/*.md` page was updated for the newly-exported names (`forward_fill`,
  `backward_fill`, `floor_div`, `arcsin`, `arctan`, `rolling_median`, `rolling_quantile`,
  `Dt.week`/`quarter`/`timestamp`/`epoch`, `Lists.slice`/`n_unique`, `Strings.find`/`pad_start`/
  `pad_end`). `docs/make.jl`'s `checkdocs = :exports` is non-fatal (`warnonly = [:missing_docs]`),
  so this doesn't break the docs build, but it is a real curation gap consistent with the
  pre-existing "~200 exported symbols missing from a reference page" note already in that file.
