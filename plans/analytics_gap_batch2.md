# Analytics gap batch 2: rolling windows, correlation, concat modes, moments, EWM, cut/qcut, JSON

## Status

Follows on from `plans/analytics_gap_batch.md` (coalesce/upsample/interpolate/horizontal
reductions/as_struct, shipped) and `plans/timezones.md` (tz support, in progress as a package
extension). This covers the remaining Tier 1/Tier 2 items from the "what's missing for most
workflows" review, **excluding timezones** (its own plan/effort, tracked separately).

Researched against vendored polars 0.54.4 sources. Timezone item deliberately omitted here since
it's mid-implementation elsewhere.

## Tier 1 — genuinely common, cheap-to-medium cost

### B1 — Expr-level rolling window aggregates

Distinct from the existing `group_by`-based `rolling()` verb — this is the "3-day moving average
as a new column" shape (`Expr::rolling_mean(RollingOptionsFixedWindow) -> Expr`), no group-by
needed.

- **Cargo features**: `rolling_window` (fixed-size window variants below), `rolling_window_by`
  (the `_by` time-column variants — a **separate** feature from `rolling_window`, confirmed by
  checking `polars-plan/src/dsl/mod.rs`: every `rolling_*_by` method is gated
  `#[cfg(feature = "rolling_window_by")]` independently of the plain `rolling_*` methods' gate).
- **`RollingOptionsFixedWindow`** (`polars-core::chunked_array::ops::rolling_window`):
  `{ window_size: usize, min_periods: usize, weights: Option<Vec<f64>>, center: bool, fn_params:
  Option<RollingFnParams> }`, `Default`: `window_size=3, min_periods=1, weights=None,
  center=false, fn_params=None`. First cut: expose `window_size`, `min_periods` (default =
  `window_size`), `center`; skip `weights`/`fn_params` (quantile-specific, no use case yet).
- **Rust** (`c-polars/src/expr.rs`): one function per op, each building a
  `RollingOptionsFixedWindow` from three plain args —
  `polars_expr_rolling_mean(expr, window_size: usize, min_periods: usize, center: bool) -> Expr`
  (infallible, no `#[cfg]`-guarded panic risk found — `Expr::rolling_mean` itself doesn't panic,
  it returns a lazily-evaluated node) and siblings for `rolling_sum`/`rolling_min`/`rolling_max`/
  `rolling_var`/`rolling_std`. A shared `fn read_rolling_options(window_size, min_periods, center)
  -> RollingOptionsFixedWindow` helper avoids repeating the 6x. `_by` variants deferred to a
  follow-up (need `RollingOptionsDynamicWindow`, a materially different shape — time-based window
  spec via a duration string, mirroring `group_by_dynamic`'s `Duration::try_parse` pattern) unless
  requested.
- **Julia** (`src/expr.jl`, top-level, alongside `cum_sum`/`cum_prod` etc.):
  `rolling_mean(expr::Expr, window_size::Integer; min_periods::Integer = window_size, center::Bool
  = false)` and siblings. No Base collision for any of the 6 names — plain exports.
- Test: `test/expr/rolling.jl` — a small sequential fixture (`1:10`), hand-verify a 3-window mean/
  sum/min/max at a few positions, confirm `min_periods` controls leading `missing`s, confirm
  `center` shifts the window.

### B2 — `corr` / `cov` / `spearman_rank_corr` (two-column correlation)

Cheapest item in this batch — **zero new Cargo features**. `cov`/`pearson_corr` are unconditional
free functions in `polars_plan::dsl::functions::correlation` (same module `coalesce`/
`all_horizontal` etc. came from last batch — already have the direct-import pattern for this
exact module path). `spearman_rank_corr` needs `rank`+`propagate_nans`, **both already active**.

- **Rust** (`c-polars/src/expr.rs`): add `cov, pearson_corr, spearman_rank_corr` to the existing
  `use polars_plan::dsl::functions::{coalesce, as_struct, ...}` import block.
  `polars_expr_cov(a, b, ddof: u8) -> Expr`, `polars_expr_pearson_corr(a, b) -> Expr`,
  `polars_expr_spearman_rank_corr(a, b, propagate_nans: bool) -> Expr`. All infallible, all
  2-or-3-arg — same shape as last batch's horizontal reductions.
- **Julia**: `cov(a::Expr, b::Expr; ddof::Integer = 1)`, `pearson_corr(a::Expr, b::Expr)`,
  `spearman_rank_corr(a::Expr, b::Expr; propagate_nans::Bool = true)`. Check
  `isdefined(Base, :cov)`/`:corr` before naming — Statistics.jl (not a dependency here, but worth
  checking Base itself) doesn't define either, so no qualification expected, but verify live per
  the `product`/`prod` sharp edge in CLAUDE.md.
- Test: extend `test/expr/statistics.jl` (or a new testset there) — small fixture with a known
  linear relationship (`y = 2x`) → `pearson_corr` ≈ 1.0; a fixture with a known covariance/rank
  relationship.

### B3 — `concat` diagonal mode + horizontal concat

Current `polars_lazy_frame_concat` ([lib.rs:577](c-polars/src/lib.rs#L577)) hardcodes
`UnionArgs::default()` (strict vertical, identical schema only).

- **Diagonal is nearly free**: `UnionArgs` ([polars-plan `dsl/options/mod.rs`](https://docs.rs/polars-plan))
  already has a `diagonal: bool` field (plus `to_supertypes: bool`) — `concat_lf_diagonal` in
  upstream `polars-lazy` is confirmed to be *pure sugar* over the exact same `concat_impl` the
  existing vertical `concat` free function already calls, just with `args.diagonal = true` set
  first. **But** `concat_lf_diagonal` itself is gated `#[cfg(feature = "diagonal_concat")]` even
  though the underlying `UnionArgs.diagonal` field and `concat`/`concat_impl` are not
  feature-gated at the type level — per CLAUDE.md's "missing Cargo features are a live danger"
  warning, this strongly suggests the execution engine's diagonal-schema-alignment logic is only
  compiled in behind that feature, so **do not** just flip `diagonal: true` on the existing
  unconditional `concat` without adding `diagonal_concat` to Cargo.toml first — confirm this
  empirically at implementation time (small 2-frame diagonal-schema test) before trusting it.
- **Horizontal is a genuinely new function**: `concat_lf_horizontal(inputs, options:
  HConcatOptions) -> PolarsResult<LazyFrame>` in `polars_lazy::dsl::functions`, **no feature
  gate**. `HConcatOptions { parallel: bool, strict: bool, broadcast_unit_length: bool }`,
  `Default`: `{ parallel: true, strict: false, broadcast_unit_length: false }`.
- **Rust**: extend `polars_lazy_frame_concat` with a `diagonal: bool` param (passed through into
  `UnionArgs { diagonal, to_supertypes: diagonal, ..Default::default() }` — promoting dtypes
  together with diagonal mode is the sensible default, matching py-polars' `concat(how="diagonal")`
  behavior). Add a new `polars_lazy_frame_concat_horizontal(lfs, n, out)` mirroring the existing
  function's `Vec<LazyFrame>` marshaling exactly, calling `concat_lf_horizontal` with
  `HConcatOptions::default()`.
- **Julia** ([Polars.jl](src/Polars.jl)): extend `concat(frames::Vector{LazyFrame}; how::Symbol =
  :vertical)` (`:vertical` → `diagonal=false`, `:diagonal` → `diagonal=true`) — no signature
  break for existing callers (keyword has a default). New `hconcat(frames::Vector{LazyFrame})`
  sibling calling the new horizontal ccall. Both get free eager `DataFrame` forms via
  `collect ∘ concat ∘ map(lazy)` (same pattern `concat` already uses).
- Cargo feature: add `diagonal_concat`.
- Test: extend `test/operations/concat.jl` — diagonal: two frames with partially-overlapping
  column sets, confirm the union of columns with `missing` filled for the gaps (mirrors upstream's
  own `test_diag_concat_lf` fixture shape). Horizontal: two frames with disjoint columns, same row
  count, confirm column-wise stitching (`nrow` unchanged, `ncol` = sum).

### B4 — `skew` / `kurtosis`

One new Cargo feature (`moment`), two one-liner wraps — cheapest structural addition after B2.

- **Rust**: `gen_impl_expr!`-incompatible (extra bool args) —
  `polars_expr_skew(expr, bias: bool) -> Expr` (`Expr::skew(bias)`),
  `polars_expr_kurtosis(expr, fisher: bool, bias: bool) -> Expr` (`Expr::kurtosis(fisher, bias)`).
- **Julia**: `skew(expr::Expr; bias::Bool = true)`, `kurtosis(expr::Expr; fisher::Bool = true, bias::Bool
  = true)` (matching py-polars' defaults). Check Base collision for `skew`/`kurtosis` (expect
  none — neither is a Base/Statistics.jl name relevant here).
- Cargo feature: add `moment`.
- Test: extend `test/expr/statistics.jl` — a small skewed fixture (e.g. `[1,1,1,2,10]`) with a
  hand-computable or sign-checkable skew (positive skew expected); kurtosis on a fixture with
  known excess-kurtosis sign.

## Tier 2 — real value, still cheap, more specialized

### B5 — `ewm_mean` / `ewm_std` / `ewm_var` (exponentially-weighted)

- **Cargo feature**: `ewma` (all three share this gate; the time-based `ewm_mean_by` needs the
  separate `ewma_by` feature — deferred, same reasoning as rolling `_by` variants above: different
  shape, lower priority, easy follow-up).
- **`EWMOptions`** (`polars-compute::ewm::options`): `{ alpha: f64, adjust: bool, bias: bool,
  min_periods: usize, ignore_nulls: bool }`, `Default`: `alpha=0.5, adjust=true, bias=false,
  min_periods=1, ignore_nulls=true`. Upstream also exposes builder methods
  (`and_span`/`and_half_life`/`and_com`) that convert an alternate parameterization into `alpha` —
  matches py-polars' `ewm_mean(com=, span=, half_life=, alpha=, ...)` surface, where exactly one of
  the four must be given. First cut: mirror that on the Julia side (exactly one of `com`/`span`/
  `half_life`/`alpha` keyword, converted client-side via the same formulas
  `and_span`/`and_half_life`/`and_com` use, since those are Rust-side builder methods on a struct
  we're constructing fresh each call — cheaper to replicate the 3 one-line formulas in Julia than
  add 3 more C ABI round-trips).
- **Rust**: `polars_expr_ewm_mean(expr, alpha: f64, adjust: bool, bias: bool, min_periods: usize,
  ignore_nulls: bool) -> Expr`, plus `_std`/`_var` siblings (identical shape, `Expr::ewm_std`/
  `Expr::ewm_var`).
- **Julia**: `ewm_mean(expr::Expr; alpha=nothing, span=nothing, half_life=nothing, com=nothing,
  adjust::Bool=true, bias::Bool=false, min_periods::Integer=1, ignore_nulls::Bool=true)` — resolve
  exactly one of the four to a concrete `alpha` client-side, `error(...)` if zero or multiple are
  given; siblings `ewm_std`/`ewm_var`.
- Test: extend `test/expr/order_window.jl` (pairs naturally with the other window ops there) — a
  small fixture, hand-verify `ewm_mean` with `alpha=0.5, adjust=false` against the simple
  recurrence `y[i] = alpha*x[i] + (1-alpha)*y[i-1]` (the `adjust=false` case has a closed-form
  hand-checkable recurrence, unlike `adjust=true`'s weighted-average form).

### B6 — `cut` / `qcut` / `qcut_uniform` (binning)

- **Cargo feature**: `cutqcut`.
- **Rust**: `Expr::cut(breaks: Vec<f64>, labels: Option<Vec<PlSmallStr>>, left_closed: bool,
  include_breaks: bool)`, `Expr::qcut(probs: Vec<f64>, labels: Option<Vec<PlSmallStr>>,
  left_closed: bool, allow_duplicates: bool, include_breaks: bool)`, `Expr::qcut_uniform(n_bins:
  usize, labels: ..., left_closed, allow_duplicates, include_breaks)`. `breaks`/`probs` are plain
  `Vec<f64>` (not `Expr`) — marshal as a flat `(ptr: *const f64, len: usize)` pair, a new but
  trivial pattern (numeric-vector-by-value, distinct from the existing `Vec<Expr>` and
  `Vec<String>` marshaling conventions — add alongside them). `labels: Option<Vec<String>>`
  marshals via the existing `read_names`-style `(ptrs, lens, n)` convention, `n=0` → `None`.
  Output dtype is Categorical/Enum-ish (`include_breaks=false`) or a `Struct{breakpoint, category}`
  (`include_breaks=true`) — first cut: only support `include_breaks=false` to sidestep the
  Struct-output shape, revisit if needed. **Check for the categorical-output caveat**: `cut`'s
  return dtype needs `dtype-categorical` — confirm this is already active (it should be, given
  `value_counts`/other categorical-adjacent features from earlier batches) before assuming
  zero-extra-feature-cost beyond `cutqcut` itself.
- **Julia**: `cut(expr::Expr, breaks::Vector{Float64}; labels::Union{Nothing,Vector{String}} =
  nothing, left_closed::Bool = false)`, `qcut(expr::Expr, probs::Vector{Float64}; labels=...,
  left_closed::Bool=false, allow_duplicates::Bool=false)`, `qcut_uniform(expr::Expr, n_bins::Integer;
  ...)`.
- Test: `test/expr/cut_qcut.jl` — a small numeric fixture with hand-picked breakpoints, confirm
  bucket assignment at boundary values (tests `left_closed` semantics specifically, an easy
  off-by-one to get backwards).

### B7 — JSON I/O (`scan_ndjson` / `read_json` / `write_json`)

Lowest priority in this batch (parquet/CSV/IPC already cover the common cases) but genuinely
zero-coverage today — not even the Cargo feature is active.

- **Cargo feature**: `json` (activates `polars_io::ndjson`, `NDJsonWriterOptions`,
  `NDJsonReadOptions`, and the `#[cfg(feature = "json")] pub use ndjson::*;` re-export in
  `polars-lazy::frame`).
- **Rust**: mirror `scan_csv`'s exact shape (confirmed pattern from Milestone C: "eager =
  `collect ∘ scan ∘ lazy`" — only **one** new Rust constructor needed, no separate eager path).
  `polars_lazy_frame_scan_ndjson(path, pathlen, out) -> *const polars_error_t`, body
  `LazyJsonLineReader::new(PlRefPath::new(path)).finish()` (verify exact builder name/shape at
  implementation time — polars-lazy's `ndjson` module wasn't fully inspected this pass, but every
  other scan reader in this codebase follows this identical `XyzReader::new(path).finish()`
  builder pattern, high confidence it holds here too). `polars_dataframe_write_json(df, user,
  callback)` mirroring `polars_dataframe_write_csv`'s `UserIOCallback` usage, swapping in
  whatever `SerWriter`-implementing NDJSON writer type polars-io exposes (needs a quick check —
  likely `JsonWriter` or `NDJsonWriter`).
- **Julia**: `scan_ndjson(path)` mirroring `scan_csv`; `read_json(path) = collect(scan_ndjson(path))`
  (pure Julia, no new Rust — same trick as `read_csv`); `write_json(io_or_path, df)` mirroring
  `write_csv`, reusing `_write_callback`. Naming note: polars/py-polars calls the line-delimited
  format "ndjson" in Rust but exposes it as `read_json`/`scan_ndjson` asymmetrically in Python —
  match that same asymmetry here for user familiarity (`scan_ndjson`/`read_json`, not
  `scan_json`/`read_ndjson`).
- Test: `test/lazyframe/scan_ndjson.jl` + a `write_json`/`read_json` round-trip test, following
  `test/lazyframe/scan_csv.jl`'s pattern; add a `write_temp_json` sibling to
  [test/fixtures.jl](test/fixtures.jl)'s `write_temp_csv`.

## Cargo.toml changes

Add to `c-polars/Cargo.toml`'s `polars` feature list: `"rolling_window", "rolling_window_by",
"diagonal_concat", "moment", "ewma", "cutqcut", "json"`. (`rank`, `propagate_nans` already active
for B2's `spearman_rank_corr`.)

## Verification

Per item, build (`cd c-polars && cargo build -j 1`, memory-safety-tripped `Monitor` pattern —
mandatory on this machine per every prior batch), restart Julia, exercise live before writing each
test:
- B1: `select(df, alias(rolling_mean(col("x"), 3), "rm"))` on a `1:10` fixture, hand-check a few
  window positions.
- B2: `select(df, alias(pearson_corr(col("x"), col("y")), "r"))` on a perfectly-linear fixture →
  `≈ 1.0`.
- B3: diagonal-concat two frames with different (overlapping) column sets, confirm the upstream
  `test_diag_concat_lf`-shaped result; horizontal-concat two same-row-count frames, confirm
  `ncol` = sum and no row loss.
- B4: `select(df, alias(skew(col("x")), "s"))` on an asymmetric fixture, check the sign matches
  intuition.
- B5: `select(df, alias(ewm_mean(col("x"); alpha=0.5, adjust=false), "e"))`, hand-verify against
  the closed-form recurrence for a 4-5 element fixture.
- B6: `select(df, alias(cut(col("x"), [0.0, 5.0, 10.0]), "c"))`, check boundary-value bucket
  assignment against `left_closed`.
- B7: `write_json(path, df); read_json(path) == df` round-trip on a small fixture.

Then run the full suite via the scratch-env workaround (or Kaimon `run_tests` if connected),
confirming the established baseline (post-timezone-batch pass/broken counts) is unaffected.

## Suggested order

B2 (corr/cov — cheapest, zero new features, warms up the "add to the existing
`polars_plan::dsl::functions` import block" pattern already used for coalesce/horizontal
reductions) → B4 (skew/kurtosis — one feature, two one-liners) → B1 (rolling windows — highest
standalone value, moderate marshaling) → B3 (concat modes — verify the `diagonal_concat` feature
claim empirically first, since that's the one item in this batch with a real "silently wrong
without the feature" risk per CLAUDE.md's warning) → B5 (EWM) → B6 (cut/qcut) → B7 (JSON, lowest
priority, do last or skip if scope needs trimming).
