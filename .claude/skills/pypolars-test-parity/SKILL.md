---
name: pypolars-test-parity
description: Use when adding or reviewing tests for any Polars.jl function that wraps a
  py-polars/upstream-polars capability — after filling an API gap, before considering a wrapped
  operation done, or when auditing an existing testset for depth.
---

# py-polars test parity

## Overview

The upstream input data IS the test — copy it verbatim, don't invent your own. py-polars'
`test_rle`'s input is `[1, 1, 2, 1, None, 1, 3, 3]`: the value `1` appears on **both sides of a
null** specifically to prove a null breaks a run instead of merging it. A hand-written
`[1, 1, 2, 2, 3]` passes against a broken implementation that merges runs across nulls. Our
first-draft tests are consistently happy-path only (clean finite in-domain values); upstream
deliberately drives null / NaN / domain-edge / empty / wrong-dtype cases. Depth, not breadth, is
the recurring gap.

## Step 1 — locate the upstream test (do not guess paths)

py-polars is not installed locally and should not be pip-installed. Guessing wastes time
(`py-polars/tests/unit/operations/test_math.py` looks right for trig and 404s — trig lives in
`series/test_series.py`).

```bash
gh api -X GET search/code -f q='"arccos" repo:pola-rs/polars path:py-polars/tests' --jq '.items[].path'
```

The search often returns several files (a dedicated `test_<fn>.py` plus incidental hits where the
function is just used inside a test of something else, e.g. searching `pct_change` also turns up
`test_with_columns.py`). Prefer the file whose name matches the function; open the incidental hits
only to confirm they don't add a fixture the dedicated file lacks — usually they don't and can be
skipped.

To enumerate the whole tree instead:

```bash
curl -sSL "https://api.github.com/repos/pola-rs/polars/git/trees/main?recursive=1" \
  | python3 -c "import json,sys; [print(e['path']) for e in json.load(sys.stdin)['tree'] \
      if e['path'].startswith('py-polars/tests/unit/') and e['path'].endswith('.py')]"
```

## Step 2 — fetch raw, not rendered

```bash
curl -sSL -o test_rle.py \
  https://raw.githubusercontent.com/pola-rs/polars/main/py-polars/tests/unit/operations/test_rle.py
```

Use `curl` against `raw.githubusercontent.com`, **never WebFetch** — WebFetch converts to markdown
and mangles source. Cache fetched files on real disk (e.g. `/home/simba/workspace/pypolars-ref/`),
not `/tmp` (tmpfs here) or in-repo.

## Step 3 — extract the fixture before touching Julia

For each upstream test, record verbatim: input values, expected output values, any pinned dtype
(`pl.get_index_type()` → `UInt32` here). Write this into a parity note first, so the Julia test is
derived from upstream, not from whatever the implementation happens to return.

## Step 4 — classify every upstream test

| Category | Port? | Notes |
|---|---|---|
| Happy path | yes | usually already covered |
| Null propagation | yes | `None` → `missing` |
| NaN propagation | yes | distinct from null; check both |
| Domain edge | yes | `arccos(π)`→NaN, `log1p(-2)`→NaN, `log10(0)`→-Inf |
| Non-default parameter value (offset, ties-mode, ddof, negative `n`, …) | yes | e.g. `pct_change(n=-1)`, `rank(method=...)` — these are exactly the "our test only exercises the default" gap this sweep targets; classify as this, not "happy path" |
| Empty input | yes | often a named regression test |
| Wrong-dtype raises | **yes, high priority** | see Step 5 |
| Property-based (`@given`/hypothesis) | no | doesn't port mechanically |
| Exact upstream error-message text | no | our messages come from Rust and differ |
| numpy/pandas/Arrow interop, `to_numpy` | no | not applicable |
| `collect(engine="streaming")` | no | no streaming engine here |
| Argument-type overload we don't have (e.g. passing a `pl.Series`/expression where our binding only accepts a literal) | no | py-polars-only API surface; note it under Step 8 as a divergence, don't force it into another row |

## Step 5 — wrong-dtype tests are process-abort checks here, not input validation

Upstream `test_trigonometric_invalid_input` asserts `sin()` on a String series raises — routine
input validation in Python. Here it is load-bearing: `polars_series_get` and
`polars_dataframe_show` both used to **abort the entire Julia process** on a bad input path before
being converted to the out-param + error-pointer FFI convention (see `CLAUDE.md`). Every upstream
"raises on wrong dtype" test becomes a `@test_throws PolarsError` here, worth porting even when the
happy path is already covered — it is the only thing standing between "raises cleanly" and "kills
the process," and only a live run proves which one currently happens.

## Step 6 — idiom translation

| py-polars | Polars.jl |
|---|---|
| `None` | `missing` |
| `assert_frame_equal(a, b)` | column-wise `@test r[:col] == …` |
| exact compare, any `missing`/`NaN` present | `isequal(actual, expected)`, never `==` — `==` against a `missing`-bearing vector silently evaluates to `missing`, not `false`, and the `@test` reports it as non-boolean rather than as a mismatch |
| float compare, all-finite | `≈` |
| float compare, mixed `missing`/`NaN`/finite | `approx_or_missing(actual, expected)` (`test/fixtures.jl`) |
| `pytest.raises(E, match=…)` | `@test_throws PolarsError` — **do not assert the message text**, ours comes from Rust and differs |
| `pl.get_index_type()` | `UInt32` |
| `.unnest("a")` on a struct-returning result | Struct field access, see `test/datatypes/structs.jl` |
| `np.log1p(x)` | `Base.log1p.(x)` |

## Step 7 — verify live before asserting, always

Never write an expected value copied from upstream without first running it and observing the
actual output — a clean `cargo build` is not evidence a path is safe (`CLAUDE.md` documents
`decompress`/panic bugs that only surface at runtime), and this sweep deliberately drives `NaN`,
empty, and wrong-dtype inputs that have aborted this process before.

| Live result vs. upstream | Action |
|---|---|
| Matches | Assert it |
| Differs, Julia-side cause (wrapper/marshalling/missing kwarg) | Fix `src/`, then assert upstream's value |
| Differs, Rust/FFI/Cargo-feature cause | `@test_broken` + a parity-note entry explaining why, do not silently skip |

A running Julia session does not pick up a `cargo build` — restart it after any Rust change before
re-testing.

## Step 8 — record API divergences the upstream tests reveal

Reading upstream tests surfaces API surface you didn't know existed — e.g. `df.get_column("x",
default=…)` returns the default instead of raising. When this happens, either implement it or
write down the deliberate omission. Never leave it silently divergent.

## Step 9 — don't conflate same-named functions

`Expr.item()` (aggregation, errors on N≠1 values) and `DataFrame.item()` (1×1 accessor) share a
name upstream but are different functions. Confirm which one the upstream test actually exercises
before porting its assertions.

## Output format

Per function: upstream file + test name, the fixture (input/expected), Step-4 category, whether our
test already covered it. Draft the note with Steps 1-4 before touching Julia — the live-verify
outcome (Step 7) is filled in afterward, once the test is actually patched and run; leave it as
"TBD" until then rather than skipping the field. Keep a running ledger (one row per swept function:
`function | our test file | upstream file::test | status | note`) so a sweep spanning many
functions is resumable.

## Common mistakes

- Guessing an upstream path instead of searching (`test_math.py` doesn't exist; see Step 1).
- Using WebFetch instead of raw `curl` — it mangles Python source.
- `==` instead of `isequal` on a vector containing `missing`/`NaN` — passes silently instead of
  failing, because `missing == missing` is `missing`, not `true`.
- Asserting Rust error message text instead of just the exception type.
- Porting `@given`/hypothesis, `to_numpy`/pandas interop, or `engine="streaming"` cases — none
  apply here.
- Skipping the live-verify step and trusting upstream's expected value blindly — the two live
  incidents this exists to catch never look like a compile error.
