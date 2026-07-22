# Close Polars.jl's Definitive-Guide API gaps

## Status
Done — all 8 phases landed on `features-round-2`, each independently reviewed (spec compliance +
code quality) and approved. Researched against vendored `polars` 0.54.4 sources
(`~/.cargo/registry/src/index.crates.io-*/polars-{core,plan,lazy}-0.54.4`) and this repo's current
`main`. All Rust-side templates cited below were spot-checked directly against
`c-polars/src/{dataframe,expr,ffi_util}.rs` and `c-polars/Cargo.toml`.

- **Phase 1 (`unnest`)**: Done — landed on `features-round-2` (`6976477`, `4658a82`).
- **Phase 2 (`polars.selectors`)**: Done — 11 new Rust FFI functions (7 primitives + 4
  combinators) + 2 new C enums (`polars_dtype_selector_kind_t`, `polars_selector_match_kind_t`),
  `src/expr/selectors.jl` (`Selector` type + `Selectors` namespace module, 27 constructor
  functions), `docs/src/reference/selectors.md`. Full suite 1663 passed / 2 broken (pre-existing
  Aqua ambiguity/unbound-args markers) / 0 failed, including 88 new selector tests.
- **Phase 3 + Phase 5 (`Expr.meta` namespace + `Dt` duration accessors)**: Done — landed together
  in one commit/rebuild cycle, per this plan's own Cargo-feature-batching table below. Added
  `"meta"` and `"dtype-duration"` to `c-polars/Cargo.toml`'s `polars` feature list; 8 new
  `Expr.meta` FFI functions (`is_column`/`is_literal`/`has_multiple_outputs`/`undo_aliases`/
  `output_name`/`tree_format`/`root_names_len`+`root_names_get`) in `c-polars/src/expr.rs`, new
  `src/expr/meta.jl` (`module Meta`); `date`/`time` added to the existing `gen_impl_expr_dt!`
  block plus a new `gen_impl_expr_dt_fractional!` macro backing the 7 `total_*` functions, in
  `c-polars/src/expr.rs`, hand-written Julia wrappers in `src/expr/datetime.jl`. **Cargo-feature
  sweep result** (done before writing any Rust, per CLAUDE.md's `dtype-time` precedent):
  `dtype-duration` was *already* transitively active on `polars-core`/`polars-ops`/`polars-plan`
  before this change (it's part of `dtype-slim`, itself part of the `polars` crate's own
  `default` features) — confirmed via `cargo tree -e features -i polars-ops`/`-i polars-plan` and
  actual build fingerprints (not `cargo metadata`, which gave a misleading answer for `"meta"`
  here — see CLAUDE.md's note that `cargo tree -e features` is the reliable source, not a
  `features = [...]` list *or* `cargo metadata`). The `take_chunked_unchecked` `Duration` arm
  (the exact mechanism that broke for `dtype-time`) was therefore never actually at risk; the
  Cargo.toml addition is belt-and-suspenders explicitness, confirmed safe (again) by a live
  gather/join/sort-over-Duration exercise mirroring `times.jl`'s own Time testset (see
  `test/datatypes/durations.jl`). One real deviation from this plan's spec: `Meta` is **not**
  exported from `Polars` (`export Meta` would make `using Polars` immediately ambiguous-error,
  since `Base.Meta` is itself an *exported* Base submodule) — always reached fully qualified as
  `Polars.Meta.output_name(...)` etc. `cargo build -j 1` clean; header drift clean; full suite
  1733 passed / 2 broken (pre-existing) / 0 failed, including 78 new tests (`test/expr/meta.jl`,
  `test/datatypes/durations.jl`, plus 2 extended in `test/datatypes/times.jl`).
- **Phase 4 (`hstack`/`vstack`/`transpose`, DataFrame-only)**: Done — no Cargo feature or
  dependency-feature change needed, confirmed before writing any Rust (all three are plain
  `polars-core` inherent methods, ungated). No new direct dependency needed either:
  `DataFrame::transpose`'s `new_col_names: Option<Either<String, Vec<String>>>` parameter needs
  the `Either` enum, and while it isn't re-exported through `polars`/`polars_core`'s prelude, the
  already-direct `polars-utils` dependency does `pub use either;` unconditionally (no feature
  gate, `polars-utils-0.54.4/src/lib.rs:92`), so `polars_utils::either::Either` reaches it with
  zero `Cargo.toml` changes. (An earlier version of this phase added a direct `either = "1.16"`
  dependency instead, on the mistaken belief that no existing dependency re-exported it; that was
  corrected post-review — see git history for the fixup commit.) 3 new Rust
  FFI functions in `c-polars/src/dataframe.rs` (`polars_dataframe_hstack`/`_vstack`/`_transpose`,
  all `guard_error`-wrapped eager ops, matching `polars_dataframe_upsample`'s shape) + a new
  `read_series` helper in `c-polars/src/ffi_util.rs` (mirrors `read_exprs`, yields `Vec<Column>`
  since `DataFrame::hstack` takes `&[Column]` not `&[Series]`). `transpose` clones
  (`.inner.clone()`) before calling upstream's `&mut self`-requiring `transpose`, honoring this
  repo's "no caller observes the mutation" convention. Julia: `hstack`/`vstack` in `src/verbs.jl`
  (next to `concat`), `transpose` in `src/reshape.jl` (next to `pivot`/`upsample`/`unnest`,
  extending `Base.transpose` — exported from Base already, same as `unique`, so no `Base.rename`-
  style `import Base: transpose` needed, though `transpose` was still added to `Polars.jl`'s
  `export` list per the plan spec — confirmed harmless/redundant, not an error, to export a name
  already brought in via an implicit `using Base`). `hstack`'s `columns` parameter is typed
  `Vector{<:Series}` rather than `Vector{Series}` — `Series{T}` is parametric and invariant, so a
  literal `[s]`/`Vector{Series{Int64}}` argument would not otherwise match a bare `Vector{Series}`
  annotation.
  **Both flagged panic-risk candidates were live-verified and neither panics**: `hstack` with a
  length-mismatched Series raises a clean `PolarsError` (`DataFrame::new`'s own
  `validate_columns_slice`, e.g. `"height of column 'c' (2) does not match height of column 'a'
  (3)"`), and `transpose` with a wrong-length `new_col_names` likewise raises a clean
  `ShapeMismatch` `PolarsError` (`transpose_impl`'s own `polars_ensure!`, `"Length of new column
  names must be the same as the row count"`) in both the too-short and too-long directions — the
  process survives every case. Also live-verified: `hstack` duplicate-name (df-vs-attached and
  attached-vs-attached) both error cleanly rather than silently overwriting; `hstack` onto a
  0-row/nonzero-width `df` accepts a matching 0-length Series but still errors on a nonempty one,
  and `hstack` onto a truly 0×0 `df` errors even for a matching Series (height comes from `df`'s
  own stored `height` field, not inferred from the incoming Series); `vstack` schema mismatches
  (width, name, dtype) all error cleanly, no supertype casting; `transpose` over a Struct or List
  column errors cleanly (falls through to the generic supertype-cast path since the `object`
  Cargo feature isn't enabled, so the source's `Object`-dtype arm can never be reached); an empty
  `df` (0 rows, with or without columns) errors on `transpose` rather than producing an empty
  result. `cargo build -j 4` clean; header drift clean (`check_header_drift.py`); no new Aqua
  ambiguities from the new `Base.transpose` method (checked via
  `Test.detect_ambiguities(Polars; recursive=true)` directly, not just the existing
  `broken=true`-marked Aqua testset); `julia --project=docs docs/make.jl` clean. Full suite 1775
  passed / 2 broken (pre-existing) / 0 failed, including 42 new tests (13 `hstack` + 9 `vstack` in
  `test/operations/frame_verbs.jl`, 20 `transpose` in `test/operations/reshape.jl`).
- **Phase 6 (`.name.to_lowercase`/`.name.to_uppercase`)**: Done — 2 new Rust FFI functions in
  `c-polars/src/expr.rs` next to `polars_expr_prefix`/`suffix`/`keep_name` (no Cargo change, no
  Base-name collision), Julia `to_lowercase`/`to_uppercase` in `src/expr/expr.jl` added to the
  existing trailing batched export line. Live-verified (not assumed from the Rust doc comments'
  wording) that chained renames — `prefix`/`suffix`/`to_lowercase`/`to_uppercase`/`alias` — fold
  sequentially onto the *previous* node's running name, not the original root; only `keep_name`
  reverts to the true original root regardless of chain position. `.name.map` correctly left
  out of scope (needs the not-yet-built Rust→Julia callback infrastructure — see
  `plans/callback_infra.md`). Full suite 1785 passed / 2 broken (pre-existing) / 0 failed.
- **Phase 7 (literal `Date`/`Datetime`/`Time` expression constructors)**: Done — pure Julia
  composition, zero new Rust/C-ABI/Cargo changes, three `Base.convert(::Type{Expr}, ...)` methods
  in `src/expr/expr.jl` reusing `src/arrow/array.jl`'s `arrowvector` epoch math verbatim (byte-for-
  byte verified against it in review). Live-verified both documented caveats: `lit(DateTime(2300,
  1,1))` really does overflow (`InexactError` from `Dates.jl`'s own checked conversion, the same
  pre-existing failure mode `arrowvector` already has — not a new bug), and
  `Polars.Meta.is_literal(lit(Date(...)))` really does report `false` (a `Cast(Literal)` node, not
  a genuine `Literal` — cosmetic only). Both documented in `docs/src/limitations.md`. Full suite
  1795 passed / 2 broken (pre-existing) / 0 failed.
- **Phase 8 (long-tail triage)**: Done, as a triage deliverable — no code was implemented per this
  phase's own scope (see below). Produced `plans/api_gap_batch_four.md` (a new, independently-
  verified, fully actionable implementation plan for the ~13 remaining items:
  `rle`/`rle_id`/`gather`/`gather_every`/`is_between`/`partition_by`/`item`/`get_column`/
  `to_numpy`/`arccos`/`degrees`/`radians`/`log10`/`log1p`/`hist`) and `plans/callback_infra.md` (a
  problem-statement stub for the callback-blocked items, `map_elements`/`map_batches`/`map_groups`
  plus Phase 6's `.name.map`). Fresh research corrected several of this plan's own preliminary
  guesses: `rle`/`rle_id` are zero-arg (not extra-args), `log10` needs no new Rust `Expr` method at
  all, `get_column` is already fully implemented (`polars_dataframe_get`), and `gather`/
  `partition_by`'s underlying Cargo features are already active — only `is_between` and `hist` are
  genuinely gated-and-currently-inactive, needing a real `Cargo.toml` change. See
  `plans/api_gap_batch_four.md` for the actual next-step plan.

## Context

A prior audit compared every polars API symbol used across "Python Polars: The Definitive Guide"
(18 chapters + appendix + crash-course, 749 code cells, polars 1.33.0) against Polars.jl's actual
coverage. Roughly half of the ~295 distinct symbols touched have no equivalent yet, and the gaps
aren't evenly spread — they cluster around a handful of high-impact, currently-missing pieces
(`unnest`, the `polars.selectors` module, `Expr.meta`, frame reshaping, some `Dt`/`.name` namespace
gaps, and literal Date/Datetime/Time construction), plus a long tail of single-purpose methods with
no shared blocker. This plan sequences closing those gaps in impact order, each phase independently
shippable, following this repo's established C-ABI-then-Julia workflow (CLAUDE.md).

**Cross-reference**: `plans/analytics_gap_batch2.md` is already open (no `Done` status) and already
fully specs `rolling_mean`/`rolling_min`/`rolling_max`, `skew`/`kurtosis`, `ewm_mean`/`ewm_std`/
`ewm_var`, and `cut`/`qcut` — all four appear in this plan's long-tail (Phase 8). **Phase 8 excludes
these and defers to that plan** rather than re-planning them. No other existing plan touches
`unnest`, selectors, `Expr.meta`, `hstack`/`vstack`/`transpose`, or the `Dt`/`.name` additions here.

**Two design decisions resolved with the user up front** (both took the recommended option):
- Selectors are a new `Polars.Selector` wrapper type with `|`/`&`/`-`/`xor` operator overloads, not
  bare `Expr` + named combinator functions (Phase 2).
- Literal Date/Datetime/Time expressions are built by composing existing pieces (epoch-int literal +
  `cast`/`cast_datetime`), not new dedicated Rust literal constructors (Phase 7). Known cosmetic
  gap: `Meta.is_literal(lit(Date(...)))` reports `false` (a `Cast(Literal)` node, not a genuine
  `Literal` node) — cosmetic only, doesn't affect query correctness (polars' constant-folding pass
  collapses it before execution regardless); document in `docs/src/limitations.md`.

**Remaining lower-stakes decisions** (adopted the researched recommendation, not re-asked — flagged
here so they're visible and overridable during implementation review):
- Ship `vstack` even though `concat([df, other])` mostly covers the same case (matches py-polars'
  own surface; cheap to add once `hstack` needs the same `read_series` helper anyway).
- Batch all seven `total_*` Duration accessors (`total_seconds`/`total_days`/`total_hours`/
  `total_minutes`/`total_milliseconds`/`total_microseconds`/`total_nanoseconds`) into Phase 5, not
  just the two named in the original gap list — same file, same feature, near-zero marginal cost.
- `Expr.meta`'s `root_names()` marshals as count + per-index `IOCallback` loop (reuses two
  already-established idioms) rather than a delimiter-joined buffer or a new boxed-Vec handle type.
- `tree_format`/`show_graph` return a plain `String` (Graphviz DOT / plain tree text) via the
  existing `IOCallback` pattern — no in-session rendering, no new dependency.
- `transpose`'s "use a column's values as new names" mode (py-polars' `Either::Left` arm) is
  deferred — first cut supports "auto-generated names" and "explicit `Vec{String}`" only.
- New `test/datatypes/durations.jl` file for Phase 5 (rather than folding into `times.jl`), since
  Duration has its own construction story (`cast_duration`) distinct from Date/Time.

---

## Cargo feature changes, at a glance

| Phase | Feature change | Risk |
|---|---|---|
| 1. `unnest` | none — `dtype-struct` already transitively active via `performant`/`pivot` | none |
| 2. Selectors | none — `Selector`/`DataTypeSelector` fully ungated, already used by `polars_expr_nth` | none |
| 3. `Expr.meta` | add `"meta"` to `c-polars/Cargo.toml`'s `polars` feature list | low (`polars-plan`'s own `meta = []`, zero sub-deps) |
| 4. `hstack`/`vstack`/`transpose` | none | none |
| 5. `Dt` duration accessors | add `"dtype-duration"` | needs the CLAUDE.md feature-sweep — see Phase 5 |
| 6. `.name.to_lowercase`/`to_uppercase` | none | none |
| 7. Literal Date/Datetime/Time | none (composition approach) | none |
| 8. Long tail | per-item, mostly none | see triage |

`"meta"` and `"dtype-duration"` are the only two `Cargo.toml` diffs in this whole plan. Since any
feature change forces the expensive full optimized rebuild regardless of how many features change
at once, **land Phase 3 + Phase 5 together** in one commit/rebuild cycle to pay that cost once. Per
CLAUDE.md, use `cargo build -j 1` for that rebuild, not the usual `-j 4`.

---

## Phase 1 — `unnest` (DataFrame + LazyFrame)

**Rust** (`c-polars/src/dataframe.rs`, template: `polars_lazy_frame_explode` at line 779, same
clone-and-wrap shape as `unpivot`/`drop`):
- `polars_lazy_frame_unnest(lf, names: *const *const u8, lens, n, separator: *const u8, separator_len, out) -> *const polars_error_t` — `read_names` → `selector_by_name(names, true)` (strict — unnesting a nonexistent column errors) → `read_opt_str` for `separator` → `(*lf).inner.clone().unnest(selector, separator_opt)`. `LazyFrame::unnest` (`polars-lazy-0.54.4/src/frame/mod.rs:1946`) is infallible (`-> Self`), so no `Result` unwrap needed here — a runtime failure surfaces through the existing `guard_error`-wrapped `collect`.
- No eager `polars_dataframe_unnest` — only wrap the lazy builder, matching this repo's `collect ∘ op ∘ lazy` philosophy.

**Julia** (`src/reshape.jl`, next to `explode`/`unpivot`/`pivot`):
- `unnest(lf::LazyFrame, columns::Vector{String}; separator::Union{Nothing,AbstractString}=nothing)::LazyFrame`
- `unnest(df::DataFrame, columns::Vector{String}; separator=nothing)::DataFrame = collect(unnest(lazy(df), columns; separator))`
- Export `unnest` from `src/Polars.jl`, next to `explode, unpivot`.

**Tests** (`test/operations/reshape.jl`, new `@testset "unnest"`, struct-column construction per `test/datatypes/structs.jl`'s pattern):
basic single/multiple struct unnest; `separator` present vs. `nothing` (verify actual field-naming behavior live, don't assume); struct-of-struct one level deep; whole-row-null struct entry → fields become `missing`, not an error; name collision (two unnested fields sharing a name, or colliding with an existing column) → `PolarsError`, not a panic; empty frame; exercised via the `LazyFrame` path directly, not only the `DataFrame` convenience wrapper.

**Docs**: `docs/src/reference/manipulation.md`, new "Unnest" section (table + `@example`); cross-link from `docs/src/reference/structs.md` (the write-side counterpart, `as_struct`, already documented there).

---

## Phase 2 — `polars.selectors` module

**Representation**: new `Polars.Selector` type (decided above) — `struct Selector; expr::Expr; end`, no new opaque pointer/destroy machinery (it just carries an `Expr`, whose own finalizer owns the pointer — the `Selector` registers none); `_as_expr(s::Selector) = s.expr` so it composes transparently with `select`/`with_columns`/etc.; `Base.:|`, `Base.:&`, `Base.:-`, `Base.xor` methods dispatch on `Selector`. Note the one real naming mismatch: Python's `^` (selector xor) maps to Julia's `xor`/`⊻`, **not** `^` (always exponentiation in Julia).

**Decide up front — `Selector`↔`Expr` mixing (don't "confirm live"):** `Base.:|(::Expr, ::Expr)` already means boolean-*or* (the operator loop in `src/expr/expr.jl`), while `|(::Selector, ::Selector)` will mean selector-*union*. Same-type dispatch is unambiguous (a `Selector` is a distinct type, so `numeric() | string()` and `col("a") | col("b")` never collide), but the *mixed* case `numeric() | col("x")` has genuinely ambiguous intent and no method yet. **Chosen behavior: leave it a clean `MethodError`** — do *not* silently promote a bare `Expr` to a selector. Rationale: the Rust combinators (below) require both operands be `Expr::Selector(...)` and a bare `col("x")` is `Expr::Column`, so promotion would need a Julia-side `col`→`by_name` rewrite that diverges from py-polars' own selector-vs-expr edge cases; a loud error is safer than a subtly-wrong union. (If parity is wanted later, add `convert(Expr, ::Selector)` + explicit mixed-arg methods as a deliberate follow-up, not an accident.)

**Rust** (`c-polars/src/expr.rs`, near the struct-namespace functions; no Cargo change — `Selector`/`DataTypeSelector` are ungated and `ffi_util.rs`'s `selector_by_name`/`selector_by_name_opt` plus `polars_expr_nth` already exercise this machinery):
- `polars_expr_selector_all()`, `polars_expr_selector_empty()` — trivial leaves (`Selector::Wildcard` / `Selector::Empty`, the *top-level* variants, **not** `DataTypeSelector::Wildcard`/`Empty` — those are redundant with these and are dropped from the `_simple` enum below).
- `polars_expr_selector_by_name(names, lens, n, strict: bool, out)` — backs `by_name`.
- `polars_expr_selector_by_index(indices: *const i64, n, strict: bool)` — `Selector::ByIndex`. **Index-base decision:** `Selector::ByIndex` is 0-based upstream, but this repo's `nth` (`src/expr/expr.jl:167`) deliberately exposes **1-based** Julia indexing with a negative-index passthrough and `n-1` conversion. **Match `nth`: `Selectors.by_index` is 1-based on the Julia side** (convert `i -> i < 0 ? i : i-1` there, keep this Rust primitive 0-based). Document the divergence from py-polars' 0-based `cs.by_index`.
- `polars_expr_selector_matches(kind: polars_selector_match_kind_t, pattern, len, out)` — backs `matches` **and** `starts_with`/`ends_with`/`contains` (py-polars implements all three as regex sugar over `Selector::Matches`). **Do the anchoring + escaping in Rust, not Julia:** Base Julia has *no* regex-escape function (`escape_string` escapes string literals, not regex metacharacters) and this repo has none, so a Julia-side `"^" * escape(prefix)` would mean hand-rolling `. ^ $ * + ? ( ) [ ] { } | \` escaping. Instead pass the raw substring + a `kind` tag (`Regex` verbatim / `StartsWith` / `EndsWith` / `Contains`) and build the `Selector::Matches(...)` pattern Rust-side. The `regex` crate isn't a direct dep here (only polars' `regex` *feature*), so either add `regex` for `regex::escape` or inline a small metacharacter-escaping fn. Test with regex-special and non-ASCII column names given this repo's string-marshaling history.
- `polars_expr_selector_dtype_simple(kind: polars_dtype_selector_kind_t)` — one new `#[repr(C)]` enum (per CLAUDE.md's enum-mirroring convention). Zero-*Julia*-arg `DataTypeSelector` variants, including four that are **parametrized in Rust but "any" from Julia's view** — the match maps them to their all-permissive forms: `Datetime → Datetime(TimeUnitSet::all(), TimeZoneSet::Any)`, `Duration → Duration(TimeUnitSet::all())`, `List → List(None)`, `Array → Array(None, None)`. Full kind set: `Numeric`, `Integer`, `UnsignedInteger`, `SignedInteger`, `Float`, `Enum`, `Categorical`, `Nested`, `Struct`, `Decimal`, `Temporal`, `Object`, `Datetime`, `Duration`, `List`, `Array`.
- `polars_expr_selector_dtype_any_of(value_types: *const polars_value_type_t, n, out)` — `ByDType(AnyOf([...]))`, backing `string()`/`boolean()`/`binary()`/`date()`/`time()`/explicit `by_dtype([...])` (the dtypes with no dedicated `DataTypeSelector` variant — there is **no** `DataTypeSelector::Date`/`Time`, so those *must* route here, not through `_simple`). Reuse the existing `polars_value_type_t` enum + its `to_dtype` (`value.rs:87`, confirmed present — backs `cast`). **Fallible and that's correct:** `to_dtype` errors on Datetime/Duration/Decimal/List/Struct (they need parameters a plain type code can't carry), so `by_dtype([Datetime, …])` surfaces a clean `PolarsError` — expected, not a bug; the parametrized temporal/nested selectors are reached via `_simple` instead.
- `polars_expr_selector_union/difference/exclusive_or/intersect(a, b, out)` — the one genuinely new logic: pattern-match that both inputs are actually `Expr::Selector(...)`, returning a clear `PolarsError` (not a panic) otherwise (e.g. `Selectors.numeric() | col("x")`) via the `out`-param + error-pointer channel; rebuild as `Selector::Union(Arc::new(a), Arc::new(b))` etc.
- **First-cut scope exclusions** (flag, don't silently build): matching a *specific* time unit/zone (`datetime()`/`duration()` ship "any unit/any tz" only — see the `_simple` mapping above); recursive `List(Some(...))`/`Array(Some(...), _)` inner-selector composition (`list()`/`array()` ship "any List"/"any Array" only, no `cs.list(cs.numeric())` nesting).

**Routing table** (all 26 Julia functions → the Rust primitive backing each; `ByDType(X)` is `Selector::ByDType(DataTypeSelector::X)`):

| Julia | Rust primitive | Builds |
|---|---|---|
| `all()` | `_all` | `Selector::Wildcard` |
| `numeric()`/`integer()`/`unsigned_integer()`/`signed_integer()`/`float()` | `_dtype_simple` | `ByDType(Numeric)` … `ByDType(Float)` |
| `temporal()`/`categorical()`/`decimal()`/`nested()` | `_dtype_simple` | `ByDType(Temporal)` etc. |
| `struct_()` | `_dtype_simple` | `ByDType(Struct)` |
| `datetime()` | `_dtype_simple` | `ByDType(Datetime(all, Any))` |
| `duration()` | `_dtype_simple` | `ByDType(Duration(all))` |
| `list()` | `_dtype_simple` | `ByDType(List(None))` |
| `array()` | `_dtype_simple` | `ByDType(Array(None, None))` |
| `string()`/`boolean()`/`binary()`/`date()`/`time()` | `_dtype_any_of` | `ByDType(AnyOf([String]))` … `ByDType(AnyOf([Time]))` |
| `by_dtype(dtypes...)` | `_dtype_any_of` | `ByDType(AnyOf([...]))` |
| `by_name(names...; strict)` | `_by_name` | `Selector::ByName{names, strict}` |
| `by_index(indices...; strict)` | `_by_index` | `Selector::ByIndex{indices, strict}` (1-based→0-based) |
| `matches(p)` | `_matches` (kind `Regex`) | `Selector::Matches(p)` |
| `starts_with(p...)`/`ends_with(p...)`/`contains(p...)` | `_matches` (kind `StartsWith`/`EndsWith`/`Contains`) | `Selector::Matches(<anchored, Rust-escaped>)` |
| `x \| y`, `x & y`, `x - y`, `xor(x, y)` | `_union`/`_intersect`/`_difference`/`_exclusive_or` | `Selector::Union(...)` etc. |

(No Julia `empty()` is exposed in the first cut — `polars_expr_selector_empty` exists as the identity element for the combinators/tests but isn't in the public `Selectors` surface; add it only if the book needs it.)

**Julia**: new `src/expr/selectors.jl`, `module Selectors` (mirrors `Structs`/`Dt`, qualified-use only — matches py-polars' own `import polars.selectors as cs` convention, avoids clashing with `string`/`float`/`struct`/etc.):
`all()`, `numeric()`, `integer()`, `unsigned_integer()`, `signed_integer()`, `float()`, `string()`, `boolean()`, `binary()`, `temporal()`, `categorical()`, `date()`, `time()`, `datetime()`, `duration()`, `decimal()`, `struct_()` (trailing underscore, `struct` is reserved), `list()`, `array()`, `nested()`, `by_dtype(dtypes...)`, `by_name(names...; strict=true)`, `by_index(indices...; strict=true)`, `matches(pattern)`, `starts_with(prefixes...)`, `ends_with(suffixes...)`, `contains(substrings...)`. Extend `_as_expr` in `src/expr/expr.jl` with the `Selector`-accepting method — easy to miss since it's a different file. Include `selectors.jl` in `src/Polars.jl`'s `include()` sequence after `expr/expr.jl`; export `Selectors` at top level next to `Lists, Strings, Dt, Structs`.

**Tests**: new `test/expr/selectors.jl` — `by_name` strict vs. non-strict; `starts_with`/`ends_with`/`contains` with regex-special/non-ASCII column names; each dtype-family selector against a mixed-dtype frame; explicit `by_dtype`; combinators (`numeric() | string()`, `numeric() & starts_with("x")`, `all() - numeric()`, `xor`) checked via `select(df, ...)`'s resulting column set; selector inside `with_columns`/`sort`; empty-match selector → 0-column result, not an error; mixing a plain `Expr` with a `Selector` via `|`/`&` → asserts a `MethodError` (the decided behavior above), *not* a silently-wrong result; `by_index` 1-based indexing incl. a negative index, cross-checked against the same column that `nth` would pick.

**Docs**: new `docs/src/reference/selectors.md`, wired into `docs/make.jl`'s `pages` list; cross-link from `expressions.md`'s column-reference section.

**Scope note**: confirm the exact 14 selectors from the book before considering this phase complete — the design above covers the full `DataTypeSelector` surface (a superset), but the explicit exclusions above are real scope-narrowing calls.

---

## Phase 3 — `Expr.meta` namespace

**Cargo**: add `"meta"` to `c-polars/Cargo.toml`'s `polars` feature list (single line; `polars-plan`'s own `meta = []` has zero sub-deps).

**Rust** (`c-polars/src/expr.rs`, `.meta()`-namespace shape, same as the existing `.struct_()` functions):
- `polars_expr_meta_is_column(expr) -> bool`, `polars_expr_meta_is_literal(expr, allow_aliasing: bool) -> bool`, `polars_expr_meta_has_multiple_outputs(expr) -> bool` — infallible, direct return.
- `polars_expr_meta_undo_aliases(expr) -> *const polars_expr_t` — infallible constructor.
- `polars_expr_meta_output_name(expr, user, callback: IOCallback) -> *const polars_error_t` — `output_name()` is fallible (`PolarsResult<PlSmallStr>`, e.g. on a wildcard/selector-expanded expr with no single name); write through the existing `IOCallback` machinery (see `load_value(::Value{String})` in `src/value.jl:56-63` for the Julia-side consumption pattern: `IOBuffer` + `_io_callback()` + `String(take!(io[]))`).
- `polars_expr_meta_tree_format(expr, display_as_dot: bool, user, callback) -> *const polars_error_t` — backs both `tree_format` (false) and `show_graph` (true) via the single `into_tree_formatter` code path. First cut passes no schema (`None`) — unresolved columns show untyped; a schema-aware overload is a plausible future enhancement, not blocking.
- `root_names()`: `polars_expr_meta_root_names_len(expr) -> usize` + `polars_expr_meta_root_names_get(expr, index, user, callback) -> *const polars_error_t` (count + per-index `IOCallback` loop — decided above). *Perf micro-note (non-blocking):* `root_names()` returns a fresh `Vec<PlSmallStr>` per call, so `_len` + N × `_get` recomputes it N+1 times (`root_names` is cheap and N is tiny, so it's fine). A single `polars_expr_meta_root_names(expr, user, callback)` that fires the callback once per name — with a Julia-side callback that pushes each chunk as a new `String` into a `Vector{String}` rather than the append-to-one-`IOBuffer` pattern — is one FFI call / one computation if the extra callback shape is felt worth it. Either is acceptable.

**Julia**: new `src/expr/meta.jl`, `module Meta`: `output_name`, `is_column`, `is_literal(; allow_aliasing=false)`, `has_multiple_outputs`, `undo_aliases`, `root_names`, `tree_format`, `show_graph`, each `(expr::Expr) -> ...`. Include in `src/Polars.jl` after `expr/expr.jl`, alongside `struct.jl`; export `Meta` at top level next to `Lists, Strings, Dt, Structs`.

**Tests**: new `test/expr/meta.jl` — `output_name` on plain column / aliased expr / arithmetic expr / wildcard-or-selector expr (must error cleanly); `is_column` true/false cases; `is_literal` with `allow_aliasing` both ways; `has_multiple_outputs` true for a `Selectors.numeric()` expr (cross-phase dep on Phase 2), false for `col("x")`; `root_names` on simple/binary/literal-only exprs (verify empty-vs-non-empty, don't assume); `undo_aliases` round-trip; `tree_format`/`show_graph` smoke tests (non-empty string, `show_graph` contains a Graphviz marker) rather than exact-string assertions; a deeply chained expr (`.dt()`/`.str()`/arithmetic mixed) to confirm no choking on non-trivial trees.

**Docs**: `docs/src/reference/expressions.md`, new "Introspection: Meta" section.

---

## Phase 4 — `hstack` / `vstack` / `transpose` (DataFrame only)

Actual upstream signatures: `DataFrame::hstack(&self, columns: &[Column]) -> PolarsResult<Self>` (attaches loose `Series`, **not** another `DataFrame` — the real value-add over `concat`), `DataFrame::vstack(&self, other: &DataFrame) -> PolarsResult<Self>`, `DataFrame::transpose(&mut self, keep_names_as: Option<&str>, new_col_names: Option<Either<String, Vec<String>>>) -> PolarsResult<DataFrame>`. **`hstack` takes bare `Series`, so there's no `collect ∘ op ∘ lazy` shortcut available** — a structural exception to the usual lazy-first default, not a shortcut being skipped. All eager-only; no LazyFrame equivalent upstream for any of the three (transpose needs full materialization; hstack/vstack's lazy equivalent is the already-wrapped `concat`).

**Rust** (`c-polars/src/dataframe.rs`, template: `polars_dataframe_upsample` — eager, `guard_error`-wrapped since these execute immediately rather than deferring to `collect`):
- `polars_dataframe_hstack(df, series: *const *const polars_series_t, n, out)` — needs a new `read_series` helper in `ffi_util.rs`, modeled on `read_exprs` but note `hstack(&self, columns: &[Column])` (confirmed, `polars-core-0.54.4/src/frame/mod.rs:514`) takes **`&[Column]`, not `&[Series]`** — so the helper yields `Vec<Column>`, converting each borrowed handle via `(**s).inner.clone().into_column()`. `&self`, so no input mutation.
- `polars_dataframe_vstack(df, other, out)` — direct wrap; `vstack(&self, other: &DataFrame)`, `&self`.
- `polars_dataframe_transpose(df, keep_names_as: *const u8/len via read_opt_str, new_col_names: *const *const u8/lens/n, out)` — first cut supports only "auto-generated names" and "explicit `Vec<String>`" (decided above). **`transpose(&mut self, …)` takes `&mut self`** (confirmed, `frame/row/transpose.rs:94` — it rechunks/materializes `self` internally), unlike `hstack`/`vstack`. To honor this repo's "no caller observes the mutation" convention, operate on a clone: `(*df).inner.clone().transpose(...)` (cheap Arc-level clone), **not** `&mut (*df).inner`. The `Object`-dtype `polars_bail!` it can hit is a non-issue here (the `object` feature isn't enabled, so no `Object` column can exist); Struct/List columns fall through to the generic supertype-cast path and should surface a clean `PolarsError` (verify live).

**Julia**: `hstack(df::DataFrame, columns::Vector{Series})::DataFrame`, `vstack(df::DataFrame, other::DataFrame)::DataFrame` in `src/verbs.jl` next to `concat`; `transpose(df::DataFrame; keep_names_as=nothing, new_col_names=nothing)::DataFrame` in `src/reshape.jl` next to `pivot`/`upsample`.

**Tests**: `hstack`/`vstack` in `test/operations/frame_verbs.jl`; `transpose` in `test/operations/reshape.jl`. Cases: `hstack` with 1 and multiple Series, length-mismatch Series (verify error not panic — real candidate panic path via `DataFrame::new`'s internal validation, exercise live first), duplicate name between `df` and an attached Series (verify actual behavior, don't assume), attaching to an empty `df`; `vstack` schema mismatch (verify clean error, not panic — unlike `concat`'s `:vertical_relaxed`, `vstack` has no documented supertype-casting), 0-row `other`, matching-schema case; `transpose` numeric-only frame (fast path) **and** mixed-dtype frame (generic path) — both are genuinely different Rust code paths, both need coverage — with/without `keep_names_as`, `new_col_names` of the wrong length (real candidate for an index-out-of-bounds panic — treat as a genuine live panic-safety risk per this repo's `ffi_panic_safety.md` history), a Struct/List column (verify a clean error like the source's `Object`-dtype `polars_bail!`, not a panic), empty frame.

**Docs**: `docs/src/reference/manipulation.md` — `hstack`/`vstack` next to `concat`; `transpose` next to `pivot`/`upsample`.

---

## Phase 5 — `Dt.date` / `Dt.time` / `Dt.total_seconds` / `Dt.total_days` (+ 5 sibling `total_*`, batched per decision above)

**Cargo**: `date()`/`time()` are ungated (`polars-plan-0.54.4/src/dsl/dt.rs:156,162`, no `#[cfg]`) — no change needed for those two. The `total_*` family (same file, `#[cfg(feature = "dtype-duration")]`) needs `"dtype-duration"` added to `c-polars/Cargo.toml`.

**Before trusting this feature is safe**: run `cargo tree -e features -i polars-ops` and re-grep `activate .* feature` across the touched `polars-core`/`polars-ops`/`polars-time` sources. **Specifically check whether Duration columns hit the same `take_chunked_unchecked`/gather code path that `dtype-time` broke before** (documented in CLAUDE.md) — Duration and Time are sibling temporal dtypes reaching similar `polars-ops` internals via join/gather; this is a concretely plausible recurrence, not generic boilerplate caution.

**Rust**: `date`/`time` fit the existing plain-unary `gen_impl_expr_dt!` macro shape exactly like `year`/`month`/`day` — two macro-invocation lines added to the existing block in `c-polars/src/expr.rs`. The seven `total_*` methods take a `fractional: bool` arg each (don't fit the plain-unary macro, same "extra args" category as `round`/`rank`) — hand-written `polars_expr_dt_total_seconds(a, fractional: bool)` etc., infallible, direct-return.

**Julia** (`src/expr/datetime.jl`, `module Dt`): add `date`/`time` into the existing `@generate_expr_fns` block; hand-write `total_seconds(expr::Expr; fractional::Bool=false)::Expr` (and the 6 siblings) plus curried forms, exported from `Dt`'s own export list (module-qualified, matching `Dt.strftime`'s existing convention).

**Tests**: extend `test/datatypes/times.jl` for `Dt.date`/`Dt.time` — reuse its existing `"Time sort/join (polars-ops gather over Time)"` testset as the direct template for a matching Duration-column gather/join/sort test (same class of latent risk this repo hit once before for Time). New `test/datatypes/durations.jl` for the `total_*` family (decided above): both `fractional` values, varying source resolutions (ns/us/ms — verify resolution-correct, not just resolution-dependent), negative durations (sign handling), empty frame, null Duration entry, plus the polars-ops gather/join/sort-over-Duration live-exercise test.

**Docs**: `docs/src/reference/dt.md` — extend "Component extraction" with `date`/`time`; new "Duration components" section for `total_*`.

---

## Phase 6 — `.name.to_lowercase` / `.name.to_uppercase` (`.name.map` explicitly out of scope)

Confirmed ungated, zero-arg, infallible `Expr -> Expr` — same shape as the already-wrapped `.name().keep()`. Confirmed live: `isdefined(Base, :to_lowercase)` and `:to_uppercase` are both `false`, so no Base-collision handling needed.

**Rust** (`c-polars/src/expr.rs`, immediately next to `polars_expr_prefix`/`suffix`/`keep_name`, matching their naming precedent — no `_name_` infix despite being `.name()`-namespaced Rust-side): `polars_expr_to_lowercase(expr)`, `polars_expr_to_uppercase(expr)` — `make_expr((*expr).inner.clone().name().to_lowercase())` and the uppercase equivalent. No Cargo change.

**Julia** (`src/expr/expr.jl`, right after the existing `suffix` definition): plain `to_lowercase(expr)`/`to_uppercase(expr)`, no curried form needed (no extra argument to partially apply — `col("x") |> to_lowercase` already works). Add both to the file's existing trailing batched export line (`export col, alias, prefix, suffix, lit, cast, ...`), matching how `prefix`/`suffix` are exported there rather than via a standalone `export` at the definition site.

**Tests**: extend `test/expr/naming.jl` with a new `@testset "to_lowercase/to_uppercase"` (sibling to, not folded into, the existing `"alias/prefix/suffix"` testset) — mixed-case and non-ASCII column names; chained with `alias`/`prefix`/`suffix`/`keep_name` — **verify and document (don't assume) whether chained `RenameAlias` nodes operate on the original root name or the previous node's running name**; the Rust doc comments say "root column name" for each, suggesting they may all reference the original root — a real behavior to pin down live, not assume.

**Docs**: `docs/src/reference/expressions.md`'s existing "Literals & casting" section (where `prefix`/`suffix`/`keep_name` already live) — add two rows.

**`.name.map(fn)` — out of scope, note only**: needs Rust to call back into a live Julia closure at query-execution time (`PlanCallback<PlSmallStr, PlSmallStr>`) — the opposite FFI direction from everything else in this codebase, needing a dedicated calling convention (`@cfunction` trampoline, GC-rooting for the query plan's lifetime). This is the same missing infrastructure that blocks `map_elements`/`map_batches`/`map_groups` in Phase 8 — recommend a dedicated follow-up plan ("generic Rust↔Julia callback infrastructure"), not a sub-item here.

---

## Phase 7 — Literal Date/Datetime/Time expression constructors

**Approach** (decided above): pure Julia composition, zero new Rust/C-ABI code, zero Cargo changes. The epoch math is already implemented and tested in `src/arrow/array.jl`'s `arrowvector(::Vector{Date})`/`arrowvector(::Vector{DateTime})`/`arrowvector(::Vector{Time})` — reuse verbatim:
- `Base.convert(::Type{Expr}, d::Dates.Date)` → `Int32` days-since-epoch (`Int32(Dates.value(d - Dates.Date(1970,1,1)))`, identical to `arrowvector`'s conversion) via `polars_expr_literal_i32`, then `cast(_, Date)`.
- `Base.convert(::Type{Expr}, t::Dates.Time)` → `Int64` nanoseconds (`Dates.value(t)`) via `polars_expr_literal_i64`, then `cast(_, Dates.Time)`.
- `Base.convert(::Type{Expr}, dt::Dates.DateTime)` → nanoseconds-since-epoch `Int64` (matching `arrowvector`'s `Dates.Nanosecond(dt - Dates.DateTime(1970,1,1)).value`) via `polars_expr_literal_i64`, then `cast_datetime(_; time_unit=:ns, time_zone=nothing)`.

All three slot into `src/expr/expr.jl`'s existing `Base.convert(::Type{Expr}, ...)` block (~lines 41-90), right after the existing `AbstractVector` method. No new exports — flows implicitly through `lit(x)`/`convert(Expr, x)` like every other literal type.

**Known caveats to document**:
- (from decision above) `Meta.is_literal(lit(Date(...)))` → `false` under this approach (a `Cast(Literal)` node, not a genuine `Literal`), diverging from py-polars. Cosmetic only — polars' constant-folding optimizer collapses `Cast(Literal(...))` before execution regardless.
- The `DateTime` literal is built at `:ns` (matching `arrowvector(::Vector{DateTime})`), so it inherits that path's **~1678–2262 range limit**: `lit(DateTime(2300,1,1))` overflows `Int64` nanoseconds-since-epoch exactly as `[DateTime(2300,1,1)]` does today. Consistent with existing behavior, not a new bug — but note it alongside the `is_literal` caveat, and add a far-future case to the tests below (the current list has a pre-1970 case but no far-future one).

Both go in `docs/src/limitations.md`.

**Tests**: extend `test/expr/literals_cast.jl`'s `"literal convert overloads"` testset — `lit(Date(...))`/`lit(Time(...))`/`lit(DateTime(...))` used in a real `filter`/comparison against a matching column (verify the **value** round-trips, not just that construction doesn't error); a Datetime literal built at `:ns` compared/joined against a column at a different native resolution (`:us`) — verify polars' own unit-alignment handles it; `col("d") - lit(Date(1970,1,1))` should equal the column's own epoch-day value (cross-checks the epoch math); a pre-1970 date (negative epoch days) — verify signed `Int32` arithmetic doesn't wrap.

**Docs**: `docs/src/reference/expressions.md`'s "Literals & casting" section — before/after note + new `@example`; `docs/src/limitations.md` gets the `is_literal` caveat.

---

## Phase 8 — Long tail (~50 items): triage approach, not per-function specs

**Exclude** everything already covered by `plans/analytics_gap_batch2.md` (confirmed open, none implemented yet): `rolling_mean`/`rolling_min`/`rolling_max`, `skew`/`kurtosis`, `ewm_mean`/`ewm_std`/`ewm_var`, `cut`/`qcut`. Execute that plan for those rather than re-planning here. `hist` isn't covered there and would need its own small addition alongside it.

**For the genuine remainder** (`rle`/`rle_id`, `gather`/`gather_every`, `is_between`, `partition_by`, `item`, `get_column`, `to_numpy`, `arccos`/`degrees`/`radians`/`log10`/`log1p`, `hist`, plus the callback-blocked `map_elements`/`map_batches`/`map_groups`), triage per item along two axes rather than speccing each one now:

1. **Cargo-feature risk**: ungated (wrap directly) vs. gated-and-already-active (`cargo tree -e features -i <crate>` confirms) vs. gated-and-inactive (needs `Cargo.toml` change + the full CLAUDE.md sweep: `grep -rn "activate .* feature"` **and** a scan for `unreachable!()` in `#[cfg]`-gated match arms — the ungrep-able failure mode that bit `dtype-time` before).
2. **Mechanism needed**:
   - **(a) Same shape as an already-wrapped function** — `arccos`/`degrees`/`radians`/`log10`/`log1p` are trivially the same unary-macro shape as the already-wrapped `cos`/`sin`/`log`/`exp`. Near-zero risk; batch into one commit.
   - **(b) Extra-args shape, no new mechanism** — `is_between(low, high; closed=:both)`, `gather`/`gather_every(n; offset=0)`, `rle`/`rle_id` — same hand-written pattern as `clip`/`round`/`rank`.
   - **(c) DataFrame-level, no `Expr`/lazy equivalent** — `item()`, `get_column(name)`, `partition_by(cols...)` (returns *multiple* `DataFrame`s — needs a genuinely new "return N handles" C-ABI shape, related to Phase 3's `root_names` `Vec<String>`-return problem but for `Vec<DataFrame>`). `to_numpy()`: recommend **not** porting under that name — no NumPy-equivalent target in this ecosystem; `collect(series)`/Tables.jl column access already cover the underlying need.
   - **(d) Callback-blocked** — `map_elements`/`map_batches`/`map_groups`: defer to the same "generic Rust↔Julia callback infrastructure" follow-up flagged in Phase 6. Do not attempt here.
3. **Process per remaining item**: grep the vendored source for the method + its `#[cfg(...)]` gate → `cargo tree -e features -i <owning crate>` → the two-pronged CLAUDE.md sweep → bucket into (near-zero-risk, batch) / (needs-Cargo-change, batch by shared feature) / (needs new marshaling shape, one-off) / (blocked on callback infra, defer).
4. Seed a new follow-up plan (e.g. `plans/api_gap_batch_four.md`) from this triage as the actual home for Phase 8's implementation work, rather than fully speccing ~50 functions inline here.

---

## Critical files

- `c-polars/src/dataframe.rs` — template for `unnest`/`hstack`/`vstack`/`transpose` (lazy-builder shape via `polars_lazy_frame_explode`:779/`unpivot`:803, eager-guarded shape via `polars_dataframe_upsample`:268)
- `c-polars/src/expr.rs` — template for selectors, `Expr.meta`, `Dt` additions, `.name` additions (`polars_expr_nth`:90, `polars_expr_prefix`:227/`suffix`:240/`keep_name`:253, `polars_expr_struct_field_by_name`:1223)
- `c-polars/src/ffi_util.rs` — `selector_by_name`/`selector_by_name_opt`:90,99, `read_exprs`:17/`read_names`:29/`read_opt_str`:78 (templates for the new `read_series` helper Phase 4 needs)
- `c-polars/Cargo.toml` — the two feature-flag additions (`meta`, `dtype-duration`), landed together per the table above
- `src/expr/expr.jl` — `Base.convert(::Type{Expr}, ...)` block (Phase 7), `prefix`/`suffix`/`keep_name` precedent (Phase 6), `_as_expr` (Phase 2's required cross-cutting touch), `@generate_expr_fns` macro
- `src/Polars.jl` — `include()` sequence and top-level `export` list every new namespace/function threads into
- `plans/analytics_gap_batch2.md` — sibling plan; execute for the four Phase-8 items it already covers rather than re-planning them here

## Verification (per phase, before marking it done)

1. `cd c-polars && python3 check_header_drift.py` after any header edit.
2. `cargo build -j 4` (or `-j 1` for the Phase 3+5 feature-adding rebuild — see table above).
3. Restart the Julia session (native `.so` doesn't hot-reload) and exercise the new path live in a
   real session *before* writing tests — construct the smallest input that exercises it, inspect the
   actual result, and specifically hit the panic-risk edge cases called out per phase above (this
   repo has a documented history of code that compiles clean but aborts the process at runtime).
4. `julia --project=gen gen/generate.jl` then `runic -i src/api/generated.jl` after any header change.
5. Add the test(s) per phase above; run via a scratch env (`Pkg.develop(path=".")` +
   `Pkg.add(["Aqua","Test","Tables","TimeZones"])`), `JULIA_PROJECT=<scratch> julia -e 'include("test/runtests.jl")'`.
6. Update the relevant `docs/src/reference/*.md` page(s) and confirm `docs/make.jl`'s
   `checkdocs=:exports` build still passes for any newly-exported name.
7. Update this file's `## Status` line as each phase lands.
