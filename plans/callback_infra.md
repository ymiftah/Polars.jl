# Generic Rust→Julia callback infrastructure (problem statement, not a plan)

## Status

Not started — this is a problem-statement stub, not an implementation plan. No design decisions
have been made yet; do not start implementing against this file without first writing an actual
plan (following this repo's usual `## Status`/`## Context`/phased-implementation structure) once
someone picks this up.

## Context

Four distinct API gaps identified across this repo's gap-closure work all reduce to the same
missing piece, discovered independently each time:

- `Expr.name.map(fn)` — flagged in `plans/definitive_guide_gap_closure.md`'s Phase 6, when adding
  `.name.to_lowercase`/`.name.to_uppercase`.
- `map_elements`, `map_batches`, `map_groups` — flagged in `plans/api_gap_batch_four.md` (this
  plan's sibling, Phase 8 of the same parent plan), researched but explicitly not attempted.

All four need Rust to call back into a **live Julia closure** at query-execution time — the
opposite direction from every other FFI boundary crossing in this codebase. Every existing `@ccall`
in this package is Julia calling into Rust; nothing currently goes the other way.

## Why this is a distinct, harder problem than anything else in this codebase

Per `CLAUDE.md`'s own architecture description, this package's entire FFI story is built around a
few conventions (opaque pointers + finalizers, out-param + error-pointer for fallibility, `(ptr,
len)` pairs for strings, `Vec<Expr>`-shaped pointer arrays) — all of which assume a **single
synchronous call from Julia, producing a result, returning to Julia**. A Rust→Julia callback breaks
that model in several concrete ways that need real design work, not just another `@ccall` wrapper:

- **Calling convention**: Rust needs a function pointer it can invoke from inside the query
  execution engine (potentially from a rayon worker thread, given `multithreaded: true` on select
  operations per CLAUDE.md's Concurrency notes) — this means a `@cfunction` trampoline on the Julia
  side, with all the usual constraints on what such a trampoline can safely do (no throwing
  exceptions across the boundary, no blocking indefinitely, careful about which Julia runtime calls
  are re-entrant-safe from a non-Julia-spawned thread).
- **Lifetime/GC-rooting**: the closure must stay alive and reachable for as long as the query plan
  that references it is alive — potentially much longer than the single `@ccall` that registered
  it, unlike every other object this package's finalizer pattern manages (which are all owned
  1:1 by a Julia-side wrapper with a clear destroy point).
- **Threading**: per CLAUDE.md's "Known sharp edges" section, no handle in this package is
  currently safe to share across Julia tasks/threads without external synchronization, and
  polars' own rayon pool is independent of `JULIA_NUM_THREADS`. A callback invoked from a rayon
  worker thread calling back into the Julia runtime is a materially new concurrency hazard this
  package has not had to reason about before.
- **Per-call marshaling**: unlike a fixed-shape `Vec<Expr>`/string/scalar argument, a callback's
  *payload* (a `Series`/batch/group passed to the closure, and the `Series`/`Column`/scalar it must
  return) needs its own to-Julia and from-Julia conversion on every invocation, potentially many
  times per query — a new recurring marshaling cost, not a one-time argument-passing cost.
- **Error handling across the boundary**: if the Julia closure throws, that error needs to surface
  as a clean `PolarsResult::Err` back in Rust (not a Julia exception unwinding into `extern "C"`,
  which is UB per the same reasoning CLAUDE.md already documents for Rust panics crossing the
  boundary the other direction) — this is a **new failure mode direction** the existing
  out-param+error-pointer convention was never designed to carry (that convention carries *Rust*
  errors *to* Julia, not Julia errors *through* Rust and back to Julia's own caller).

None of this is intractable — `jlrs`-style Julia-embeds-in-Rust patterns solve exactly this
problem in general — but it's a genuinely different shape of work than every other item in this
plan family, which is why it's been consistently deferred rather than attempted piecemeal per
call site.

## What NOT to do

Do not attempt a narrow one-off solution for just one of the four call sites (e.g. "just solve
`.name.map` since it's the simplest shape") without first deciding the general calling
convention/lifetime/threading answers above — a narrow solution built for `.name.map`'s specific
shape (`PlSmallStr -> PlSmallStr`, called once per query, no batching) would very likely need to be
redesigned from scratch for `map_batches`' shape (`Series -> Series`, called potentially many times
per query, must be thread-safe against polars' own rayon pool). Solve the general mechanism once,
then wrap each of the four call sites as thin, mostly-mechanical instances of it — matching this
repo's own stated philosophy ("prefer extending the thin layer with one new function per new
capability over building generic pass-through machinery") but applied one level up: the *callback
mechanism itself* is the one piece of generic machinery worth building here, precisely because
building it four separate times would be strictly worse than building it once.

## Next step, when someone picks this up

Write an actual plan (new file, or replace this stub's content) following this repo's usual
`## Status`/`## Context`/phased structure once the calling-convention/lifetime/threading questions
above have real answers — likely starting from a spike/prototype on the simplest single call site
(`.name.map`, `PlSmallStr -> PlSmallStr`, no batching, no thread-safety concern since renaming
happens during plan construction not execution) to validate the mechanism before generalizing to
the execution-time, potentially-multithreaded `map_elements`/`map_batches`/`map_groups` shapes.
