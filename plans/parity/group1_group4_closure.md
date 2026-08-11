# Group 1 + Group 4 closure: live-verified scope

## Status

**Scoping done, live-verified against `polars-plan-0.54.4`'s actual vendored source (not
`Cargo.toml`'s declared list) and the active feature closure (`cargo tree -e features -i
polars-plan`/`polars-ops`); implementation not started.** Method matches `gap_closure_scope.md`'s:
grep the `#[cfg(feature = ...)]` gate on each target method in
`~/.cargo/registry/src/*/polars-plan-0.54.4/src/dsl/{string,dt,list,struct_,name,mod}.rs`, then
check that feature name against the active set, not against `Cargo.toml`'s comment-derived guesses.

Per user direction: Group 1 items were verified live rather than fixed (most are inherent design
limitations, correctly documented already). Group 4 will be closed one namespace at a time,
no-Cargo-change functions first, per `CLAUDE.md`'s batching rule for Cargo feature changes.

---

## Group 1 — verification results

| Item | Verdict | Evidence |
|---|---|---|
| Decimal columns not materializable into Julia | **Accurate, deferred** | `docs/src/limitations.md:15-18` — no Julia-side decimal type exists yet; a real design decision (which Julia type? `Decimals.jl`? fixed-point?), not a thin wrapper. Not attempted here. |
| No `hive_partitioning` for CSV scans | **Accurate, inherent** | `polars-lazy-0.54.4/src/scan/csv.rs:362`: `hive_options: HiveOptions::new_disabled()` is hardcoded in `LazyCsvReader`'s build path — upstream itself has no way to turn this on for CSV. Not fixable from `c-polars` without patching vendored polars, which `CLAUDE.md` rules out. |
| `allow_missing_columns` covers missing, not extra, columns | **Accurate, and closable** — see [Group 1 closable item](#group-1-closable-item) below | `c-polars/src/io.rs:200` hardcodes `extra_columns_policy: ExtraColumnsPolicy::Raise`. The type is already imported and used (`c-polars/src/io.rs:10`, `c-polars/src/types.rs:468-488` already converts a Julia-side enum to `MissingColumnsPolicy`/`CastColumnsPolicy`) — this is the same shape as the already-shipped `MissingColumnsPolicy` plumbing, just never threaded through for the extra-columns case. |
| `lit(::DateTime)` always `:ns`; mismatched-resolution join errors | **Accurate, inherent to current design** | `src/expr/expr.jl:70-94`: there's no dedicated `polars_expr_literal_datetime` FFI primitive, so `Date`/`Time`/`DateTime` literals are built as `cast(lit(integer), dtype)`, always at `:ns` (comment explains this explicitly, citing the ~1678-2262 range limit). Fixing this needs a genuine literal FFI primitive per dtype plus generalizing join to align units the way `filter`/`==` already do — a real feature addition, not a bug fix. Not attempted here. |
| `Meta.is_literal` returns `false` for Date/Time/DateTime literals | **Accurate, same root cause as above** | `src/expr/expr.jl:76-78`, in-source comment: since these build as `Cast(Literal(...))` rather than a genuine `Literal` node, `is_literal` correctly reports `false` — "cosmetic only" per the comment, since polars' constant-folding collapses this before execution regardless. Would only change if the above literal-primitive work happens. |
| No handle is thread-safe | **Accurate, inherent by design** | `docs/src/limitations.md:110-119` — opaque pointer handles are unsynchronized by the C ABI's own design (`CLAUDE.md`'s "Opaque pointers + finalizers" section); this is an architectural property, not a gap to close. |

**Net: 5 of 6 are confirmed-accurate, inherent limitations — no code changes needed, docs already
correct. One (`extra_columns` policy) is a real, closable gap.**

### Group 1 closable item

**Add an `extra_columns` policy option to `scan_parquet`/`scan_csv`/`scan_ipc`**, mirroring the
existing `allow_missing_columns` (itself backed by `MissingColumnsPolicy`) — same file, same
pattern, `ExtraColumnsPolicy::{Raise,Ignore}` already `use`d at `c-polars/src/io.rs:10`. Touches:
`c-polars/src/io.rs:200` (stop hardcoding `Raise`), the three FFI scan functions' signatures,
`regen_header.sh` + `gen/generate.jl`, then `src/io/{parquet,csv,ipc}.jl` keyword threading
(mirrors `allow_missing_columns::Bool` at e.g. `src/io/parquet.jl:44,97`). No Cargo change.

---

## Group 4 — namespace backlog

### `Dt` — cleanest win, effectively free

All of the following are **confirmed ungated** in `polars-plan-0.54.4/src/dsl/dt.rs` (no
`#[cfg(feature = ...)]` line above the `pub fn` at all) — closable with zero `Cargo.toml` changes:

- `iso_year` (dt.rs:100), `is_leap_year` (dt.rs:93), `century` (dt.rs:72), `millennium` (dt.rs:66)
- `combine` (dt.rs:279), `datetime` (dt.rs:168)
- `cast_time_unit` (dt.rs:42), `with_time_unit` (dt.rs:50)
- `to_string` (dt.rs:25) — distinct from `strftime` (dt.rs:37), check neither collides with an
  existing wrapped symbol before naming
- `replace` (dt.rs:348, i.e. `Dt.replace` for date-component replacement)

Gated on `timezones`, **already active** (`c-polars/Cargo.toml`'s `polars` feature list):

- `base_utc_offset` (dt.rs:238), `dst_offset` (dt.rs:245)

Needs a Cargo change (batch into the [Cargo-gated batch](#cargo-gated-batch-separate-pr)):

- `add_business_days` (dt.rs:8) — gated `business`, confirmed **not** in the active feature closure
  (`grep -c '"business"' cargo-tree-dump` → 0)

(`month_start`/`month_end` already tracked as Group 0 stubs — separate feature, unaffected here.)

### `.name` — contradicts the audit's Group 9 blocker claim for two of three items

The audit lumped `name.map`/`prefix_fields`/`suffix_fields` together as all needing Group 9's
callback infra. That's wrong for two of them — checked `polars-plan-0.54.4/src/dsl/name.rs`
directly:

- `prefix_fields` (name.rs:91), `suffix_fields` (name.rs:99) — gated `dtype-struct`, **already
  active**. No `PlanCallback` involved at all. **Closable now, no Group 9 dependency.**
- `map` (name.rs:28) and `map_fields` (name.rs:83) — genuinely take a `PlanCallback<PlSmallStr,
  PlSmallStr>` argument. Correctly blocked on Group 9's callback design; not attempted here.

### `Strings`

Confirmed ungated or gated on an already-active feature (`polars-plan-0.54.4/src/dsl/string.rs`):

- `strptime` (string.rs:260, generic form) — gated `temporal`, active
- `to_time` (string.rs:306) — gated `dtype-time`, active (`c-polars/Cargo.toml` explicitly turns
  this on for `polars-ops` too, see its comment at line 21-23)
- `to_decimal` (string.rs:312) — gated `dtype-decimal`, active
- `escape_regex` (string.rs:521) — gated `regex`, active

Needs a Cargo change:

- `json_decode` (string.rs:511), `json_path_match` (string.rs:516) — gated `extract_jsonpath`, not
  active
- `normalize` (string.rs:413) — gated `string_normalize`, not active
- `contains_any` (string.rs:39), `replace_many` (string.rs:56), `extract_many` (string.rs:81),
  `find_many` (string.rs:106) — all gated `find_many`, not active
- **Correction to the audit's Group 10 table**: decode and encode are gated on *different*
  features, not both `binary_encoding`. `hex_decode`/`base64_decode` need `binary_encoding`
  (string.rs:138-150); `hex_encode`/`base64_encode` need **`string_encoding`** (string.rs:133,144),
  a feature Group 10's table never listed and which is also not active. Both need adding to the
  batched Cargo change.

(`to_integer`, `reverse`, `titlecase` already tracked as Group 0 stubs.)

### `Lists` and `Structs` — audit's remaining items don't clearly exist upstream; verify before writing anything

- **`Lists.concat`** — no `concat` method exists anywhere in `polars-plan-0.54.4/src/dsl/list.rs`.
  The only `concat` in that area is the top-level `concat_list` (`dsl/functions/concat.rs:108`),
  already tracked as a Group 2 gap (multi-column horizontal concat, not a per-expression namespace
  method). Recommend: close via `concat_list` under Group 2, and correct Group 4's text — this is
  very likely not a separate gap at all. Re-check against py-polars' actual `Expr.list.concat`
  Python source before doing anything, since polars-plan not having a `ListNameSpace::concat` is
  strong but not 100% conclusive (could be composed client-side in py-polars from other primitives).
- **Expression-level `explode`** — `Expr::explode` is a **plain, ungated** top-level `Expr` method
  (`dsl/mod.rs:220`), not something namespace-specific. This directly contradicts Group 4's own
  claim that it's missing — and contradicts nothing else, since Group 3 of the *same audit* already
  says `Expr.explode` "was never actually a gap — it's covered by `flatten`". Group 4's "Lists:
  ...and expression-level explode" line is a stale/duplicate entry that should be deleted from the
  audit, not implemented.
- **`Structs.unnest`** (expression-level) — no matching method found anywhere in
  `polars-plan-0.54.4/src/dsl/struct_.rs`, which only has `field_by_index`, `field_by_name(s)`,
  `rename_fields`, `with_fields`, and `json_encode` (gated `json`, active). Plausibly `Expr.struct.
  unnest` doesn't exist upstream either — only frame-level `.unnest()` does (already wrapped here).
  Needs a check against py-polars' actual Python API before concluding this is real.
- **`Structs.fields`/`schema`** (introspection) — not in `struct_.rs` either; if these exist
  upstream they most likely live under `DataType::Struct`/`Meta` introspection, not
  `StructNameSpace`. Needs the same kind of check as `unnest` before scoping any FFI work.

**Recommendation for these four**: spend a short research pass against py-polars' actual source
(not polars-plan's Rust DSL, which is one layer removed) before writing any `c-polars` code —
unlike `Dt`/`.name`/`Strings` above, these don't have a clean "confirmed ungated, write the shim"
answer yet.

---

## Cargo-gated batch (separate PR)

Per `CLAUDE.md`, batch into one `Cargo.toml` change + one `-j 1` full rebuild + one new `libpolars`
release, each option exercised live before merging:

`business` (`add_business_days`), `extract_jsonpath` (`json_decode`/`json_path_match`),
`string_normalize` (`normalize`), `find_many` (`contains_any`/`replace_many`/`extract_many`/
`find_many`), `binary_encoding` (`hex_decode`/`base64_decode`), `string_encoding`
(`hex_encode`/`base64_encode` — new finding, not in the audit's Group 10 table).

---

## Suggested execution order

1. **Group 1 closable item** — `extra_columns` policy, small, self-contained, same pattern as
   existing code.
2. **`Dt`** — ~9 functions, zero Cargo changes, single namespace file.
3. **`.name`** — `prefix_fields`/`suffix_fields`, 2 functions, zero Cargo changes.
4. **`Strings`** — 4 no-Cargo functions now (`strptime`, `to_time`, `to_decimal`,
   `escape_regex`); remaining 8 (json/normalize/find_many family/encode/decode) wait for the
   Cargo-gated batch.
5. **`Lists`/`Structs`** — research pass against py-polars Python source first; likely shrinks to
   near-zero real work (`concat` folds into Group 2's `concat_list`, `explode` gets deleted as a
   stale audit entry, `unnest`/`fields`/`schema` may not exist upstream).
6. **Cargo-gated batch** — one PR, once 1-5 are done, per `CLAUDE.md`'s batching rule.

Each numbered item follows `CLAUDE.md`'s "Workflow: adding a wrapped operation" (Rust shim → regen
→ Julia entry point → build/restart/exercise live → tests in the matching `test/<category>/` file).
