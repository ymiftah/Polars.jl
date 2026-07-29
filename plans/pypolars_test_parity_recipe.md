# Recipe: matching Polars.jl tests to their py-polars counterparts

## Status

Recipe/methodology, not an implementation plan. Extracted from the Wave 1 API-gap work
(2026-07-29), where the first-draft tests were all happy-path and upstream turned out to cover
null/NaN/domain/dtype edges deliberately.

Intended use: hand this to an agent doing a full sweep, so every Polars.jl testset is checked
against the upstream test for the same function. Complements `plans/test_porting.md`, which ported
py-polars tests *by area*; this is the per-function verification procedure.

## Why bother

Upstream fixtures are not arbitrary. `test_rle`'s input is `[1, 1, 2, 1, None, 1, 3, 3]` — the same
value appears on **both sides of a null** specifically to prove a null breaks a run instead of
merging it. A hand-written fixture like `[1,1,2,2,3]` passes against a buggy implementation that
merges across nulls. The input data is the test; copying it is most of the value.

Several upstream tests are named after the issue they fix (`test_empty_rle_21787`). Those are
regressions someone actually hit — the highest-value ones to port.

## Step 1 — find the upstream test (do not guess paths)

py-polars is **not installed locally** and should not be pip-installed for this. Guessing paths
wastes time: `py-polars/tests/unit/operations/test_math.py` seems obvious for trigonometry and does
not exist (404); the trig tests live in `series/test_series.py`.

Use authenticated code search:

```bash
gh api -X GET search/code \
  -f q='"arccos" repo:pola-rs/polars path:py-polars/tests' \
  --jq '.items[].path'
```

To enumerate the whole test tree instead:

```bash
curl -sSL "https://api.github.com/repos/pola-rs/polars/git/trees/main?recursive=1" \
  | python3 -c "import json,sys; [print(e['path']) for e in json.load(sys.stdin)['tree'] if e['path'].startswith('py-polars/tests/unit/') and e['path'].endswith('.py')]"
```

## Step 2 — fetch raw, not rendered

```bash
curl -sSL -o test_rle.py \
  https://raw.githubusercontent.com/pola-rs/polars/main/py-polars/tests/unit/operations/test_rle.py
```

Use `curl` against `raw.githubusercontent.com`, **not** WebFetch — WebFetch converts to markdown and
mangles source. Keep fetched files somewhere on real disk (not `/tmp`, which is tmpfs here) so the
reviewer can diff against them later.

## Step 3 — extract the fixture, not just the assertion

For each upstream test record, verbatim: the **input values**, the **expected output values**, and
any dtype the test pins (`pl.get_index_type()` → `UInt32` on our side). Write these into a parity
note before touching Julia code, so the test is derived from upstream rather than from what the
implementation happens to return.

## Step 4 — classify every upstream test

| Category | Port? | Notes |
|---|---|---|
| Happy path | yes | usually already covered |
| Null propagation | yes | `None` → `missing` |
| NaN propagation | yes | distinct from null in polars; both must be checked |
| Domain edge | yes | `arccos(π)` → NaN, `log1p(-2)` → NaN, `log10(0)` → -Inf |
| Empty input | yes | often a named regression test |
| Wrong-dtype raises | **yes, high priority** | see below |
| Property-based (`@given`, hypothesis) | no | does not port mechanically |
| Exact upstream error-message text | no | our messages come from Rust and differ |
| numpy/pandas/Arrow interop, `to_numpy` | no | not applicable |
| `collect(engine="streaming")` variants | no | no streaming engine exposed here |

## Step 5 — dtype-error tests deserve extra weight here

Upstream `test_trigonometric_invalid_input` asserts `sin()` on a String series raises. In Python
that is routine input validation. In this package it is a **process-abort check**: `CLAUDE.md`
documents two real incidents (`polars_series_get`, `polars_dataframe_show`) where a bad input path
took down the entire Julia process instead of raising. Every upstream "raises on wrong dtype" test
should become a `@test_throws PolarsError` on our side, and is worth porting even when the happy
path is already covered.

## Step 6 — translate idiom

| py-polars | Polars.jl |
|---|---|
| `None` | `missing` |
| `assert_frame_equal(a, b)` | column-wise `@test r[:col] == …` / `≈` for floats |
| `pytest.raises(E, match=…)` | `@test_throws PolarsError` (do not assert message text) |
| `pl.get_index_type()` | `UInt32` |
| `.unnest("a")` on an rle result | Struct field access, see `test/datatypes/structs.jl` |
| `np.log1p(x)` | `Base.log1p.(x)` |

## Step 7 — record API divergences the tests reveal

Reading upstream tests surfaces API surface you did not know existed. Wave 1 example:
`df.get_column("x", default=…)` has a `default` keyword and returns it instead of raising — not in
any of our plans. When this happens, either implement it or record the deliberate omission; do not
leave it silently divergent.

## Step 8 — do not conflate same-named functions

`Expr.item()` (an aggregation erroring with `"expected a single value, got N values"`) and
`DataFrame.item()` (1×1 accessor) are different functions with the same name. Check which one the
upstream test actually exercises before porting its assertions.

## Output format

Per function, produce: upstream file + test name, the fixture, expected output, category from
Step 4, and whether our current test covers it. See
`/home/simba/workspace/pypolars-ref/WAVE1_PYPOLARS_PARITY.md` for a worked example covering
`rle`/`rle_id`/`arccos`/`degrees`/`radians`/`log1p`/`log10`/`get_column`/`item`.

## For the full sweep

Enumerate our surface first, then map:

```julia
using Polars
for m in [Polars, Polars.Lists, Polars.Strings, Polars.Dt, Polars.Structs, Polars.Selectors]
    println(nameof(m), ": ", join(sort(string.(filter(n -> n !== nameof(m), names(m)))), " "))
end
```

194 exported names as of 2026-07-29, all of which appear somewhere in `test/` — so the sweep is
about **depth**, not zero-coverage gaps. Prioritise by category: functions whose upstream tests are
mostly Step-4 "null/NaN/domain/dtype" rows are where our happy-path bias will show up.

`test/` already mirrors py-polars' layout by concern, so the file mapping is mostly mechanical;
`plans/test_porting.md` has an area-level mapping table to start from.
