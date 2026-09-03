# Batch 13 parity note: lazyframe/scan_*.jl, sink_*.jl, collect_schema.jl, head.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/` (prefixed `b13_`):
`io/test_csv.py` (3304 lines), `io/test_ipc.py` (617 lines), `io/test_lazy_csv.py` (795 lines),
`io/test_lazy_ipc.py` (732 lines), `io/test_lazy_parquet.py` (1908 lines), `io/test_parquet.py`
(4577 lines), `io/test_scan_options.py` (864 lines), `io/test_sink.py` (811 lines),
`lazyframe/test_collect_schema.py` (67 lines). All nine paths confirmed via a full tree listing
before fetching.

At ~13,700 combined lines (two files over 3000 lines each, one over 4500), and given this repo's
existing scan/sink test files are already substantial (294 lines for `scan_parquet.jl` alone, plus
dedicated `docs/src/limitations.md`-documented coverage of the `hive_partitioning`/
`allow_missing_columns`/`allow_extra_columns` sharp edges), this batch triaged almost entirely by
`grep`-ing for named-regression tests (`_\d{4,}` issue-number suffixes) and only read the tiny
`test_collect_schema.py` in full — depth over completeness applied at the file-selection level, per
the skill's own framing, same triage approach as Batch 11's similarly oversized files.

## Real bug found and fixed

**`head(df, n)` and `Base.tail(df, n)` crashed with a bare `InexactError` on a negative `n`.**
`polars_lazy_frame_head`/`_tail` take an unsigned `usize` in `c-polars/src/dataframe.rs`; a
negative Julia `Int` passed straight to the `@ccall` triggers an unguarded
`InexactError: convert(UInt64, -2)` instead of any kind of clear rejection. (Upstream's own
`.head(n=-2)` negative-index convenience — "all but the last 2" — is Python-side sugar computed
against a known `height` before ever reaching Rust; it was simply never ported here, but the
*absence* should have been a clean error, not a leaked internal conversion failure.) Fixed both
functions in `src/select.jl` with an explicit `n >= 0` guard raising a descriptive `ArgumentError`.
Negative-`n` support itself is not implemented: it's straightforward for `DataFrame` (known height)
but not for `LazyFrame` (unknown height without materializing), so partial support would be an
inconsistent API — left as a documented gap instead (docstring note on both functions).

Tests added: `test/lazyframe/head.jl` (both `head(df, -2)` and `head(lazy(df), -2)`), plus a
one-line addition to `test/operations/frame_verbs.jl`'s existing `"tail"` testset for the symmetric
`tail` case — that file is also touched by Batch 10's (already-open) PR #48, but the addition is a
single new line at the end of an existing testset with no overlap, so no conflict is expected.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `with_row_index` | `test_collect_schema_with_row_index_duplicate` | a real "index"-named column, or `with_row_index` called twice, collides at `collect_schema` time | Step-5 abort-safety | raises cleanly (`DuplicateError`-equivalent, matching message); added |
| `head`/`tail` | (this batch's own finding, not an upstream test) | negative `n` | Step-5 abort-safety | **was a bare `InexactError` — fixed**, see above |
| `write_parquet`/sink | `test_sink_boolean_panic_25806` | a large (300,000-row) all-`true` Boolean column round-trips without panicking | domain edge, regression | matches (black-box smoke test at comparable scale, not a reproduction of the original streaming-engine-internal crash path — this wrapper doesn't expose that engine's internals); added |

## Spot-checked against already-documented limitations (no new test needed)

- **`test_scan_csv_missing_columns_27268`** (`pl.scan_csv(files, missing_columns="insert")`
  merging differently-shaped CSV files) exercises a capability `CLAUDE.md`'s "Known sharp edges"
  already documents as absent here: *"`scan_csv` has no equivalent [to `allow_missing_columns`]
  (same `LazyCsvReader` hardcoding as `hive_partitioning`)."* Confirmed this documented limitation
  is still current and accurate — not a new gap, just a confirmation.

## Not ported (Step 4 exclusions)

- The overwhelming majority of `test_parquet.py` (4577 lines) and `test_csv.py` (3304 lines) —
  numpy/pyarrow interop, cloud-storage-credential paths, `hypothesis`-driven round-trips,
  streaming-engine-internal regressions (predicate pushdown into the streaming sink, deadlock/
  thread-pool-sizing regressions like `test_sink_deadlock_28284`/`test_sink_max_blocking_threads_28526`),
  and Python-file-handle-specific behavior (`io.BytesIO`/`io.StringIO` round-trips, `tmp_path`
  fixture plumbing) that don't map onto this wrapper's path-based or `IOBuffer`-based API.
- **`io/test_scan_options.py`'s cast-options family** (`test_scan_cast_options*`,
  `test_cast_options_ignore_extra_columns`, ~10 tests) — this is entirely about `CastColumnOptions`
  during scan-time schema resolution, a substantial subsystem of its own (this repo's
  `plans/cast_policy_abi_fix.md` shows it already got a dedicated review pass); scoping it properly
  is bigger than a test-porting-pass grep pass can responsibly do, flagged for its own future look
  rather than attempted here.
- `test_collect_all_lazy` (`pl.collect_all([...], lazy=True)` with a `SinkMultiple` query-plan
  node) — no equivalent top-level "collect several sinks in one query" entry point exists in this
  wrapper; each `sink_*` call here is its own independent operation, not portable as-is.
- `lazyframe/test_collect_schema.py`'s `test_collect_schema_parametric` (`hypothesis`-driven) and
  `test_collect_schema_unpivot_duplicate` — the latter is the same "name collision surfaces at
  `collect_schema`" shape already covered by Batch 10's `unpivot` tests (via direct materialization
  rather than a bare `collect_schema()` call) and this batch's `with_row_index` fixture above;
  redundant to port a third time.
- `test_arr_get_oob_errors_at_schema_26088` (`Array`-dtype `.arr.get()` out-of-bounds erroring at
  schema-resolution time) — gated on this repo's pre-existing, already-documented `Array`-dtype
  materialization limitation (schema resolution over an `Array` column already raises for
  unrelated reasons, per the `parity-low-hanging-tier12` sweep's findings); not a clean fixture to
  port on top of that.
- `io/test_ipc.py`, `io/test_lazy_ipc.py`, `io/test_lazy_csv.py` in full — grep-triaged for
  issue-numbered regressions; the hits found were all either streaming-engine-internal or
  pyarrow-interop, matching the exclusions above. This repo's existing `scan_ipc.jl`/`sink_ipc.jl`
  (93 + 175 lines) already cover the `ExtraColumnsPolicy` divergence documented in `CLAUDE.md`.

## Resolved non-issues (verified before assuming a bug)

- The `head`/`tail` negative-`n` `InexactError` was initially unclear whether it originated from a
  Julia-side conversion or an FFI-level abort — traced to a plain, catchable Julia `@ccall`
  argument-type coercion failure (not a Rust panic, not a process abort), confirming it was safe
  and appropriate to fix with a simple Julia-side guard rather than needing any Rust-side or
  `guard_error`-related change.
