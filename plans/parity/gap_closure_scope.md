# Parity sweep: scope of remaining gap-closure work

## Status

**Done.** Groups A, B, C, and D below are implemented on the `parity-gap-closure` branch (PR #29):
Group A's two behavioural bugs fixed (`over()` zero-partition, all-missing-column `DataFrame`
construction), Groups B/C's ~45 new `Expr`/`Lists`/`Strings`/`Structs` functions added with a Rust
FFI symbol each, and Group D (batches 10-14) is tracked separately as still-unswept in
`LEDGER.md` rather than folded into this branch. The branch also had to reconcile with a large
concurrently-merged Wave 5 PR (#30) that independently closed some of the same gaps (`Lists.sort`/
`join`/`slice`/`diff`/`n_unique`/`any`/`all`, `Strings.find`/`pad_start`/`pad_end`) — where both
sides implemented the same function, the more complete implementation was kept and the other's
tests were superseded. See the branch's commit history for the full list; every new function has
live-verified, `@testset`-covered behavior, not just a passing build. Group E (this file, plus
`LEDGER.md`'s batch-order table) is addressed by this same status update.

Derived by re-reading all nine batch notes
(`plans/parity/batch-{1..9}-*.md`) plus `LEDGER.md`, then verifying every flagged gap against the
*current* `main` (post-Wave-1/2/3, post-libpolars-v0.3.0) rather than trusting the notes, since
Waves 2/3 silently closed several of them after they were written.

Verification method per gap: `grep` for the FFI symbol in `c-polars/src/expr.rs`, then check the
upstream method's `#[cfg(feature = ...)]` gate in the vendored
`polars-plan-0.54.4/src/dsl/{mod,list,string,struct_}.rs`, then cross-check that feature against
`cargo tree -e features -i polars-plan`'s **actually-active** set (not `Cargo.toml`'s declared
list — per CLAUDE.md, those differ). Behavioral bugs were re-run live today.

**Already closed since the notes were written, do not re-do:** `corr`/`cov` (Wave 2),
`skew`/`kurtosis` (Wave 3), `gather`/`gather_every` at the *Expr* level (Wave 2). Wave 4 (open
PR #28) adds EWM + `cut`/`qcut` — no overlap with anything below.

## The headline finding: three quarters of this needs no Cargo change

The batch notes assumed most gaps meant "new Cargo feature + full ~3 min optimized rebuild + a new
libpolars release". Checked against the active feature set, that is wrong for most of them:

- `round_series`, `top_k`, `string_pad`, `regex`, `dtype-struct`, `diff`, `is_in` are **already on**
- `neg`, `floor_div`, `shift_and_fill`, `strict_cast`, `Expr::item`, `explode`'s options,
  `Structs::with_fields`, and **most of `ListNameSpace`** are **ungated entirely**

So Group B below is pure `c-polars/src/expr.rs` + regen + Julia-side work, no `Cargo.toml` edit, no
dependency rebuild. Only Group C pays the rebuild, and it can be paid **once** for all of it.

## Group A — behavioural bugs (2). Highest priority: these are wrong, not just absent

Both re-verified live today against current `main`; both still broken.

### A1. `over()` with zero `partition_by` fails at execution time — ~3-line Rust fix

Flagged in Batch 4, `@test_broken` markers live at `test/expr/over.jl:87-88`. Constructing the
`Expr` succeeds; running it raises `PolarsError: at least one key is required in a group_by
operation`.

**Root cause found (new — Batch 4 left this as "needs Rust-side investigation").**
`c-polars/src/expr.rs:604` passes `Some(vec![])` for an empty partition list, with a comment
asserting that empty-means-whole-frame. Upstream `over_with_options`
(`polars-plan/src/dsl/mod.rs:835-843`) disagrees — its own convention is that **`None`** means
whole-frame, and it implements that as a substituted `vec![lit(1)]` (one constant key = one group):

```rust
let partition_by = if let Some(partition_by) = partition_by {
    partition_by.as_ref().iter().map(...).collect()   // empty Some(..) stays empty -> 0 keys -> error
} else {
    vec![lit(1)]                                      // None -> the real whole-frame spec
};
```

Passing `None` outright doesn't work either — the `polars_ensure!` on line 834 then rejects the
no-`order_by` case. **Fix: substitute `vec![lit(1)]` ourselves when the incoming list is empty**,
mirroring upstream's own `None` branch while still satisfying the ensure. Then flip the two
`@test_broken`s to `@test` and add the `order_by`-set variant.

### A2. `DataFrame((; a = [missing, missing]))` throws `UndefVarError`, not a clean error

Flagged in Batch 1, routed to Batch 12, still live. `format(::Type{Nothing}) = "n"` exists
(`src/arrow/array.jl:122`) but there is no `format(::Type{Missing})` / `arrowvector(::Vector{Missing})`
pair, so a bare all-`missing` column dies with `UndefVarError: T not defined in static parameter
matching` instead of either working or raising cleanly. `Vector{Nothing}` at least gives a catchable
`MethodError`.

Julia-side only. Decide deliberately between *support it* (map to Null dtype, consistent with the
existing `Nothing` handling) and *reject it cleanly*; supporting it is the better answer since
`Nothing` already is. Batch 1 worked around this in its fixtures with explicit
`Union{Missing,Int}[...]` annotations — those can stay either way.

## Group B — missing functions, **no `Cargo.toml` change, no dependency rebuild**

All verified ungated, or gated on a feature `cargo tree` confirms is already active. Each is a
`c-polars/src/expr.rs` function + `regen_header.sh` + `gen/generate.jl` + a Julia entry point.

### B1. `Lists.eval` — do this one first, it is the multiplier

`ListNameSpace::eval` is **ungated** and the crate already calls it internally: `list_reverse`,
`list_unique`, `list_unique_stable` are each implemented as `.list().eval(element().X())`
(`c-polars/src/expr.rs:1040-1057`). `element()` is already exported on the Julia side and tested.

Exposing `eval` therefore costs one FFI function and hands users a large fraction of Batch 9's
"missing list namespace" finding as compositions rather than as ~18 separate symbols — including
`all`/`any`, which **do not exist as `ListNameSpace` methods at all** in 0.54.4 and can *only* be
reached this way (`eval(element().all(ignore_nulls))`). Also covers `n_unique`, `filter`, and any
future element-wise op for free.

Do this before writing any other list function, then re-scope B2 against what's left.

### B2. Remaining `Lists` methods that are genuinely their own upstream symbol

Ungated: `join`, `median`, `std`, `var`, `sort`, `shift`, `slice`, `tail`, `agg`.
Gated on `diff`, already active: `diff`.

Worth wrapping directly (not via `eval`) because they are real `ListNameSpace` methods with their
own semantics/arguments — but lower priority than B1, and the list shrinks if `eval` covers a
caller's need.

### B3. Top-level `Expr` gaps

| function | gate | note |
|---|---|---|
| unary `-` / `neg` | UNGATED (`impl Neg for Expr`) | Batch 1 proved `0 - expr` is **not** a valid substitute: it silently wraps on `UInt8` where upstream raises. Needs the real `FunctionExpr::Negate`. |
| `floor_div` (`//`) | UNGATED | `binary_expr(.., Operator::FloorDivide, ..)` |
| `clip_min` / `clip_max` | `round_series` ✓ active | two-sided `clip` already wrapped; these are the single-sided forms |
| `bottom_k` | `top_k` ✓ active | mirrors existing `polars_expr_top_k` almost exactly |
| `shift_and_fill` | UNGATED | Batch 4's `shift(n, fill_value=)` gap |
| `strict_cast` | UNGATED | **Closed** (verified live 2026-08-25, see `plans/parity/api_gap_audit.md`'s Status) — `cast(expr, T; strict=true)` already dispatches to `polars_expr_strict_cast`; this row's own suggested spelling (`strict=false`) was simply the wrong default to describe the *strict* branch. Batch 6 + Batch 8 both hit the original gap. |
| `Expr.item()` | UNGATED (`item(allow_empty)`) | Batch 2's Step-9 finding — verified today that only `DataFrame`/`Series` `item` exist |
| `explode` opts | UNGATED (`ExplodeOptions{empty_as_null, keep_nulls}`) | Batch 9. Both `LazyFrame::explode` and `Expr::explode` take it. Upstream now deprecation-warns on every call site that omits `empty_as_null`. |

### B4. `Strings` gaps

Gated on `string_pad` (✓ active — `zfill` already uses it): **`pad_start`, `pad_end`** (Batch 7).
UNGATED: `strip_chars_start`, `strip_chars_end`.
Gated on `regex` (✓ active): `find`, `replace_n`, `escape_regex`.
Gated on `dtype-struct` (✓ active): `split_exact`, `splitn`.

### B5. `Structs.with_fields`

UNGATED. Batch 9. `src/expr/struct.jl` has only 3 functions today.

## Group C — needs new Cargo features. Batch these into **one** rebuild

Per CLAUDE.md: a feature change forces a full optimized rebuild of every vendored crate, which is
real memory pressure — use `-j 1` the first time, and it invalidates the built `.so` for every
worktree. So do not trickle these out one wave at a time; land them together.

| feature to add | unlocks |
|---|---|
| `is_first_distinct`, `is_last_distinct` | Batch 5's `is_first_distinct`/`is_last_distinct` (upstream devotes a whole ~160-line file to them) |
| `list_sets` | Batch 9's four set ops: `union`, `set_intersection`, `set_difference`, `set_symmetric_difference` (upstream `test_set_operations.py` is 100% these) |
| `list_count` | `Lists.count_matches` |
| `list_gather` | `Lists.gather`, `Lists.gather_every` |
| `list_drop_nulls` | `Lists.drop_nulls` |
| `list_sample` | `Lists.sample_n`, `Lists.sample_fraction` |
| `list_to_struct` | `Lists.to_struct` |
| `dtype-array` | `Lists.to_array` (and Array dtype generally, which several excluded upstream tests need) |
| `concat_str` | Batch 7's `Strings.join` (aggregating join-with-separator, incl. `ignore_nulls`) — **closed**. The feature also gates the unrelated top-level `pl.concat_str`/`pl.concat_list` (row-wise horizontal concat), which this row didn't mention; those are **closed** too, as of 2026-08-25 — see `plans/parity/api_gap_audit.md`'s Status. |
| `extract_groups` | Batch 7's named-capture-group extraction into a Struct column |
| `json` | Batch 9's `Structs.json_encode` |

**Optional, only if wanted** — not flagged by any batch, listed so the rebuild is paid once:
`extract_jsonpath` (`Strings.json_decode`), `string_to_integer`, `string_reverse`, `find_many`
(`contains_any`/`replace_many`), `string_normalize`.

**Do not add:** `to_titlecase` is gated on **`nightly`**, which this repo pins away from
deliberately (CLAUDE.md). That is the real reason for the long-standing `Strings.titlecase`
`@test_broken` — worth recording in the test's comment rather than leaving it look like an
unexplained failure.

## Group D — batches never swept (5 of 15)

Batches 10–14 remain `unswept`; each will surface its own gaps, so Groups A–C are **not** the final
list. Rough sizing from the ledger's upstream-file column:

| # | area | upstream files |
|---|---|---|
| 10 | frame verbs, reshape, concat, select/with_columns, filter | 11 |
| 11 | join, group_by, group_by_dynamic, rolling | 7 |
| 12 | series, binary, dataframe construction/io/describe | 9 — **owns bug A2** |
| 13 | lazyframe scan/sink/collect_schema/head | 9 |
| 14 | selectors, meta, horizontal, naming, sample, curried forms | 8 |

## Group E — ledger hygiene (cheap, do alongside anything)

1. `LEDGER.md`'s batch-order table still says `unswept` for batches **1–7**, all of which are
   merged. Only 8, 9, and 0 were updated. Fix the rows.
2. The 211-row per-function skeleton is **entirely** `unswept` — the per-batch refinement its own
   preamble promises (`covered`/`gaps-filled`/`broken-flagged`) never happened for any batch. Either
   backfill it from the nine batch notes or delete it and let the notes be the record; leaving it
   as-is makes it look like nothing has been swept at all.
3. The `## Status` preamble still describes the pre-sweep baseline (1863 tests, Batch 0 in
   progress). Current `main` is ~2105 passing. Update.

## Suggested sequencing

1. **A1 + A2** — real bugs, small, unblock two `@test_broken`s and a crash. No rebuild.
2. **B1 (`Lists.eval`)** — one function, largest surface gain. No rebuild. Re-scope B2 after.
3. **B3 + B4 + B5** — the ungated/already-enabled bulk. No rebuild. Splits cleanly into 2–3 PRs
   (`Expr` core / strings / structs) if preferred.
4. **C** — one `Cargo.toml` change, one `-j 1` rebuild, one libpolars release, all features at once.
   Then the FFI functions on top can land in as many PRs as convenient without further rebuilds.
5. **E** alongside any of the above.
6. **D** — resume the sweep at Batch 10.

Note that Group C's release step matters beyond this repo: per CLAUDE.md, anything under
`c-polars/` is invisible to installing users until a new libpolars artifact is cut, and
`Artifacts.toml` currently pins v0.3.0.
