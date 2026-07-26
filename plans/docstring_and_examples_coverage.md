# Full docstring + example coverage for `Expr`/`Lists`/`Strings`/`Dt`

## Status

**Done** (branch `docs-full-coverage`, off `review-one`). Rebaselined 2026-07-19 after
`plans/review_three_fixes.md` (commits `e62b708`..`c0db17f`) landed on the same files — see
"Rebaseline" below; the first attempt at this plan was reverted mid-edit by that concurrent session
and rewritten against the new macro.

All 96 functions (93 macro-generated + 3 hand-written `head`/`tail`) now carry a real, specific
docstring and are exercised in a runnable, Documenter-verified `@example` block — confirmed by a
scripted scan (0/96 missing description content, 0/96 missing an example) and a full `makedocs`
build with `warnonly = [:missing_docs]` (206 → 182 uncurated docstrings; the residual gap is
reference-page curation, explicitly out of scope, not missing content). Also fixed two stale
`Expr <: Number` claims (`structures.md:79`, `expressions.md`'s "Deliberately not curried" section)
left over from the `a31bc9b` Expr-API redesign, and one factual bug in `expressions.md`'s
aggregation table (`nan_min`/`nan_max` were documented as "ignoring NaN" — they do the opposite,
propagating it; regular `min`/`max` are the ones that ignore it).

Full test suite: **1485 passed / 2 broken (pre-existing) / 0 failed** — unchanged from the
`review_three_fixes.md` baseline, as expected for a docs-only change. `runic --check` and
`c-polars/check_header_drift.py` both clean. Full `docs/make.jl`-equivalent build succeeds
(exit 0) with zero `@example`-block failures.

## Problem

`?functionname` in the REPL is the primary way a Julia user reads documentation. 96 exported
functions across `src/expr/{expr,list,string,datetime}.jl` carry no real prose — only a generated
boilerplate stub pointing at the Rust crate's docs:

```
    sum(expr::Polars.Expr)::Polars.Expr

Refer to [the polars documentation](https://docs.rs/polars/...).
```

No description of behavior, null/NaN handling, or arguments. Every *hand-written* docstring in the
package (`col`, `Lists.get`, `Strings.contains`, `Dt.strftime`, ...) is already real prose; this gap
is confined to the macro-generated bindings plus the three functions recently pulled out of the
macro (below).

Breakdown of the 96:

| Source | Count | Names |
|---|---|---|
| `src/expr/expr.jl` `@generate_expr_fns` | 57 | `sum`, `min`, `max`, `abs`, `log`, `rem`, ... |
| `src/expr/list.jl` `@generate_expr_fns` | 12 | `lengths`, `max`, `min`, `mean`, ... |
| `src/expr/string.jl` `@generate_expr_fns` | 13 | `uppercase`, `len_chars`, `zfill`, ... |
| `src/expr/datetime.jl` `@generate_expr_fns` | 11 | `year`, `month`, `truncate`, `round`, ... |
| Hand-written, boilerplate body | 3 | `Lists.head`, `Strings.head`, `Strings.tail` |

Separately, 73 of the 93 macro-generated functions are never exercised in a runnable `@example`
block on the `docs/src/reference/*.md` pages — only named in a table, if at all. Adding
`Strings.head`/`Strings.tail` (also exampleless) makes it 75 of 96.

And two reference pages still assert `Expr <: Number`, which the `a31bc9b` Expr-API redesign
removed (see `Expr`'s own docstring, `src/expr/expr.jl:8-23`, "Not `<: Number`"):
`docs/src/reference/structures.md:79` and `docs/src/reference/expressions.md:209`. Still present as
of `c0db17f` — a factual error to fix alongside the coverage gap.

## Rebaseline (what changed under this plan, and what it got wrong)

`review_three_fixes.md`'s P4 tier (`554fe75`) touched the same macro. Net effect on this plan:

1. **A premise of the first draft was wrong.** It assumed all 96 functions carried the boilerplate
   docstring. In fact `@generate_expr_fns` was *skipping the docstring entirely* for any name
   colliding with a Base binding (`sum`, `min`, `max`, `first`, `last`, `abs`, `count`, ...) — the
   same check that decides whether to re-export. Roughly half the set had **no reachable polars
   docstring at all**; `?sum` showed only Base's. `554fe75` split the two checks so docstrings
   always attach. Verified: `@doc Polars.sum`, `@doc Polars.n_unique`, `@doc Polars.Lists.max` all
   now contain a `docs.rs/polars` link. The content gap this plan closes is unchanged, but the
   starting point is better than the first draft claimed.
2. **Count moved 96 → 93 macro-generated.** `554fe75` pulled `Lists.head`, `Strings.head`,
   `Strings.tail` out of their `@generate_expr_fns` blocks into hand-written definitions (they
   collide with Polars's *own* top-level `head`/`tail`, which the macro's Base-only check can't
   catch). Those three got hand-written docstrings whose body is still the same boilerplate link,
   so they stay in scope — total still 96.
3. **The macro's argument extraction was NOT hardened, despite the claim.**
   `review_three_fixes.md:23-24` states its P4 change built "a `call.args[3]`-based, always-correct
   extraction". The committed code does not do this — `src/expr/expr.jl:307` is still
   `orig_fname = last(last(call.args).args)` and `:340` still
   `namespace = string(first(last(call.args).args))`. So the fragility remains: adding a 4th
   positional arg makes `last(call.args)` return the description string instead of the
   `Namespace::fname` node, and precompile dies with
   `TypeError: in isdefined, expected Symbol, got a value of type String` — exactly the transient
   breakage that session observed and attributed to an incomplete edit. **Step 1 below must
   therefore still include the `call.args[3]` fix**; it is a prerequisite, not a duplicate.

The first attempt's working-tree edit (macro change + one `sum` description) was reverted to the
committed baseline by that session and is gone. No substantive loss — ~15 lines, and it would need
rewriting against the new macro shape (`orig_fname`/`base_collision`/`sig`-as-`@doc`-target) regardless.

## Fix

1. Harden + extend `@generate_expr_fns` (`src/expr/expr.jl:301`):
   - Replace both `last(call.args)` uses with `call.args[3]` so a 4th argument is safe (see
     Rebaseline #3 — this is still outstanding).
   - Accept an optional 4th positional arg, the description:
     `gen_impl_expr!(polars_expr_sum, Expr::sum, "Sums the non-null values...")`, used as the
     docstring body with the Rust link demoted to a trailing "See also". Calls with no description
     keep today's generic docstring, so the change is backward compatible and can land before the
     93 call sites are filled in.
   - Threading the description through the macro is required, *not* optional styling: re-attaching
     a second `"""..."""` to an already-documented binding after the macro block adds a second
     docstring entry rather than replacing the first (verified — both render under `?fname`).
2. Add a real description to all 93 `gen_impl_expr*!` call sites.
3. Replace the boilerplate body in the 3 hand-written docstrings (`Lists.head`, `Strings.head`,
   `Strings.tail`).
4. Add `@example` blocks to `docs/src/reference/{expressions,lists,strings,dt}.md` covering the 75
   functions that lack one, grouped naturally (one block per related cluster — the trig functions,
   the null/NaN predicates — not one block per function).
5. Fix the two stale `Expr <: Number` claims (`structures.md:79`, `expressions.md:209`).
6. Verify: docs build succeeds; rerun the coverage scripts to confirm 0 functions without a
   description and 0 without an example; run the full suite (docs-only change — the 1485/2/0
   baseline from `c0db17f` must be unchanged).

## Out of scope

- The pre-existing "~206 docstrings not pulled into any `@docs`/`@autodocs` block" Documenter
  warning (`docs/make.jl`'s `warnonly = [:missing_docs]`) — reference-page *curation* (which prose
  page a function is summarized on), already deliberately non-fatal, and distinct from "does this
  function have real documentation", which is what this plan fixes.
- Rewriting already-good hand-written docstrings elsewhere in `src/`.
