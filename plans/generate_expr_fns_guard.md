# Scope: closing the `@generate_expr_fns` name-collision holes

## Status

Scoped, not started. Written after the third incident traceable to this macro.

## Why

`@generate_expr_fns` (`src/expr/expr.jl`, macro body ~line 493) decides how to bind each generated
function with one line:

```julia
base_collision = isdefined(Base, orig_fname)
base_qualified = __module__ == Polars && base_collision
fname = base_qualified ? :(Base.$orig_fname) : orig_fname
```

That single check has produced three separate defects across three waves:

| wave | name | what happened |
|---|---|---|
| 1 | `log` | macro passes arguments in source order; `Base.log(b, x)` is base-first, polars' `Expr::log(base)` is value-first, so the generated method computed the reverse. Both arguments are `Expr`, so a flipped call type-checked and returned a **wrong number**, not an error. |
| 2 | `cov` / `cor` | `isdefined(Base, :cov)` is **false** — the names live in `Statistics`, a direct dependency. The macro would have defined and exported bare `Polars.cov`, colliding for anyone doing `using Statistics, Polars`. Caught only because the wave hand-wrote them. |
| 3 | `kurtosis` | same shape, third-party (`StatsBase`). Not macro-generated, but the same blind spot: the guard sees only `Base`. |

Plus a pre-existing one the guard half-handles: `prod`. `Expr::product` collided with the
**unexported** `Base.product`, so the generated `Base.product(expr)` was unreachable from a normal
session. Fixed by hand-writing it under `prod`; the macro would happily reintroduce it.

## Current exposure

Measured on `main` (2026-07-31):

- **63** names generated through the macro in `src/expr/expr.jl`; namespace submodules
  (`list`/`string`/`datetime`/`struct`) generate none, so the `__module__ == Polars` branch is the
  only live one.
- **20** of those collide with `Base`. All but one are exported from Base and resolve unqualified.
- **1** (`lt`) is defined-but-not-exported in Base — reachable only as `Base.lt`. Handled by
  docstring, not by the macro.
- **0** currently collide with `Statistics`. That is luck plus two hand-written exceptions, not
  something the macro enforces.

So nothing is broken today. The hole is that nothing *stops the next one*, and all three past
failures were silent — wrong numbers or an unusable exported name, never an error at definition.

## Three holes, two of them fixable at expansion

**H1 — ownership check is `Base`-only.** A name owned by `Statistics` (a dependency) or any
third-party package gets defined as a bare `Polars.<name>` and exported. Detectable at expansion.

**H2 — defined-but-not-exported in Base.** `isdefined` is true, so the macro emits `Base.<name>`,
which then cannot be called unqualified. Detectable at expansion (`Base.isexported`).

**H3 — argument order.** The macro cannot know whether polars' argument order matches the `Base`
namesake's semantics. **Not** detectable at expansion — this needs a behavioural test.

## Proposed fix

### 1. Make the macro refuse ambiguous names (H1, H2)

Replace the single `isdefined(Base, …)` with an explicit resolution that errors rather than
guessing:

- Look the name up in `Base` **and** `Statistics` (both are dependencies and both are `using`-ed by
  the package).
- If found in exactly one, and exported there → qualify to that module, as today.
- If found in Base but **not exported** there → `error()` at expansion, naming the `prod` precedent
  and instructing the author to hand-write under an exported name.
- If found in more than one module, or in a module the macro was not told about → `error()` at
  expansion.

Escape hatch for deliberate cases: an explicit fourth/fifth argument such as
`bind = :(Statistics.cov)` that asserts the author made the call. That keeps `cov`/`cor` expressible
through the macro if wanted, rather than only by hand.

Cost: ~25 lines in the macro body plus the error text. No change to any existing call site — all 63
current names resolve the same way, verified by the counts above.

### 2. Add a collision test for names the macro cannot see (H1, third-party)

The macro cannot check `StatsBase` — it is not a dependency. A test can:

- For every name Polars exports, assert it is not *also* owned by a module in a watchlist
  (`StatsBase`, `CategoricalArrays`, `DataFrames`), loaded in the test environment only.
- Failure means "this name will conflict for a user with both loaded" — at which point the choice is
  the `kurtosis` one: extend their generic via an extension, or don't export.

This is where `cut` should be re-checked before it lands: it is clean against Base/Statistics/
StatsBase today, but `CategoricalArrays.cut` exists and that package is common in this ecosystem.

### 3. Add an argument-order test for binary ops bound to a Base name (H3)

For each macro-generated **binary** op whose name collides with Base, evaluate both forms on plain
scalars and assert they agree:

```julia
# for f in (pow, div, rem, xor, ...)
@test only(select(df, alias(f(lit(a), lit(b)), "r"))[:r]) == f(a, b)
```

`log` would have failed this the day it shipped. Names where polars deliberately differs get an
explicit exception list with a comment, so the divergence is recorded rather than discovered.

## Verification

- The macro change must leave all 63 generated names binding exactly as they do now — diff
  `names(Polars)` and each function's `parentmodule` before and after.
- Add a negative test: a `@test_throws` proving the macro rejects a name it should refuse
  (e.g. a fixture invoking it with `Expr::cov` and no explicit `bind`).
- Full suite unchanged otherwise.

## Not in scope

Detecting semantic argument-order differences automatically. There is no introspection for "what
does the first argument mean" — item 3 is a behavioural test precisely because the macro cannot
decide it.
