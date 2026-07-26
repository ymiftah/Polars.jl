Ready for review
Select text to add comments on the plan
Plan: Land the codebase-review improvements, priority-ranked
Context
A full review of Polars.jl (branch review-one) verified the three earlier hardening passes held up, and found a remaining set of issues: one genuine memory-safety bug (GC use-after-free in the Value accessors), two uncommitted stragglers in the working tree, a resource leak, a structural panic-guard blind spot in the Rust layer, two O(n²) performance defects, and assorted consistency/CI/hygiene debt. This plan lands those fixes in priority tiers P0–P5. Each tier is independently verifiable and committable, so execution can stop cleanly at any tier boundary. P5 items are explicitly deferred to separate efforts.

Once approved, copy this plan into the repo as plans/review_three_fixes.md with a ## Status line (repo convention, CLAUDE.md workflow step 9), and keep its status updated.

P0 — Resolve the uncommitted working tree (do first; everything else stacks on it)
Why first: two unstaged changes sit in limbo; one is a real UB fix that must not be lost, the other likely breaks the test suite if committed as-is.

Commit the c-polars/src/dataframe.rs fix (out.write(...) replacing *out = ... in polars_lazy_frame_collect_schema). It prevents running ArrowSchema::drop on uninitialized caller memory — a genuine UB fix, already carrying a good explanatory comment.
Verify before committing: cd c-polars && cargo build -j 4 (stable toolchain, job cap per CLAUDE.md), cargo clippy --all-targets -- -D warnings, cargo test.
Resolve test/aqua.jl:12 (the ambiguities = (broken = true,) line is commented out, flipping Aqua to strict ambiguities mode while the file's own comment says ambiguities are real).
Decision procedure: run the Aqua testset once in the scratch env. If strict mode fails (expected per the comment) → restore the line (revert the edit). If it passes (i.e. the ambiguities were actually fixed on this branch) → delete the line and the now-stale comment block above it.
Commit as one or two clean commits ending the limbo state.
P1 — Memory safety: Value GC use-after-free + Series constructor leak (Julia-only)
Why: the only remaining memory-unsafety reachable from normal use. ccall roots arguments passed through cconvert/unsafe_convert; passing raw value.ptr bypasses that, so a dead wrapper can be finalized (running polars_value_destroy) while Rust still uses the pointer — ccalls are GC-safe regions, so another thread's GC can do this mid-call.

Replace value.ptr with value at all six sites so the existing Base.unsafe_convert(::Type{Ptr{polars_value_t}}, ::Value) (src/value.jl:15) roots the wrapper for the duration of each ccall:
src/value.jl:124 (polars_value_duration_get), :144 (polars_value_datetime_get), :164 (polars_value_date_get), :174 (polars_value_time_get)
ext/PolarsTimeZonesExt.jl:14 (polars_value_datetime_get)
Fix the extension's cross-statement borrow at ext/PolarsTimeZonesExt.jl:28-31: polars_value_time_zone returns a pointer into the value's Rust-owned memory, and unsafe_string (an allocating call — a GC point) reads it in a later statement. Wrap the ccall and the unsafe_string in a single GC.@preserve value begin ... end block.
Fix the Series constructor leak (src/series.jl:11-25): three ccalls + load_series_schema run before finalizer(polars_series_destroy, series) is registered; parse_format throws on unsupported dtypes (e.g. fixed-size list, src/arrow/schema.jl:134), leaking the owned pointer. Wrap the pre-finalizer body in try ... catch; polars_series_destroy(ptr); rethrow(); end (the generated wrapper accepts a raw Ptr, so calling it directly is fine). Check whether the ArrowSchema returned by polars_series_schema needs release_schema! on the error path too — mirror whatever load_series_schema does on success.
Tests: existing Date/Time/Duration/tz tests cover functional correctness. Add a GC-stress smoke test to test/misc_ffi_safety.jl: materialize date/time/tz values in a loop with interleaved GC.gc() (documents intent; won't deterministically catch regressions, note that in a comment). For the Series-leak fix, assert the unsupported-dtype error is still a clean PolarsError/ErrorException, not a crash.
Run the full suite in the scratch env (see Verification), commit.
P2 — Rust: close the panic-guard blind spot + destructor uniformity (C ABI change)
Why: guard_error (c-polars/src/lib.rs:84-99) covers all execution paths except three functions that return Arrow structs by value and therefore can't use the error-pointer convention: any panic inside them aborts the whole Julia process. They sit on hot paths (Series construction, columnnames). Breaking the C ABI is acceptable — the header/bindings/.so all live in and version with this repo.

Convert the three by-value exports to out-param + error-pointer (follow the exact shape of polars_lazy_frame_collect_schema, c-polars/src/dataframe.rs:491-515, including guard_error + out.write(...) — the out.write is mandatory since ArrowSchema/ArrowArray have Drop impls and the caller passes uninitialized memory):
polars_series_schema (c-polars/src/series.rs:35) → (series, out: *mut ArrowSchema) -> *const polars_error_t
polars_series_export_carray (series.rs:46) → (series, out: *mut ArrowArray) -> *const polars_error_t; also replace the unguarded rechunked.chunks()[0] with a match .first() that returns make_error on None
polars_dataframe_schema (dataframe.rs:82) → (df, out: *mut ArrowSchema) -> *const polars_error_t
Add the missing null asserts for uniformity: polars_dataframe_destroy (dataframe.rs:130) and polars_dataframe_schema; sweep the other entry points for stragglers.
Header + bindings workflow (CLAUDE.md steps 4-5): hand-edit c-polars/include/polars.h to the new prototypes → python3 c-polars/check_header_drift.py → julia --project=gen gen/generate.jl → runic -i src/api/generated.jl.
Update the Julia call sites to the Ref pattern already used by collect_schema (src/lazyframe.jl:68-73: out = Ref{CArrowSchema}(); err = ...; polars_error(err); use out[]):
src/series.jl:14 (constructor), src/arrow/read.jl:80 (polars_series_schema)
src/arrow/read.jl:86-117 (polars_series_export_carray — ~9 branch sites; hoist into one small helper returning ExportedArray to avoid repeating the Ref dance)
src/dataframe.jl:101 (_column_names), :112 (schema)
Fix the stale ownership doc in c-polars/src/lib.rs:10-16 (and CLAUDE.md's matching paragraph): the code no longer uses Box::from_raw + mem::forget for in-place mutators — it borrows via &mut (*h).inner, which is cleaner; describe the real pattern.
Build & live-verify (CLAUDE.md step 7 — a clean build is not sufficient evidence): cargo build -j 4, restart the Kaimon REPL (a running session never picks up a rebuilt .so), then exercise live: Series("x", [1,2,3]), names(df), collect(df[:col]) for string + numeric + list columns, collect_schema, a tz-aware column with TimeZones loaded.
Full suite + cargo clippy/fmt/test + drift check, commit.
P3 — Performance fixes (Julia-only)
O(n²) list flattening (src/arrow/array.jl:367 and :375): reduce(vcat, ...; init = T[]) — the init keyword (and the generator form at :375) miss Base's optimized single-allocation vcat and degrade to left-fold concatenation. The cumulative offsets computed two lines earlier already give the total length, so replace with a preallocated fill:
flattened = Vector{T}(undef, Int(offsets[end]))
i = 1
for x in v
    ismissing(x) && continue
    copyto!(flattened, i, x, 1, length(x)); i += length(x)
end
(non-missing method: same without the ismissing skip). Benchmark before/after on a ~100k-sublist column and record the numbers in the plan doc (repo convention). Existing list round-trip tests cover correctness.
schema(df) without the full-frame query (src/dataframe.jl:111-126): it currently runs a select with null_count over every column of the whole frame just to refine Union{T,Missing} → T. The same information is available as per-column metadata: df[name] is an Arc-clone (polars_dataframe_get), and the Series constructor already fetches polars_series_null_count (a validity-bitmap count, no query engine). Replace the select with iszero(df[string(name)].null_count) per column — identical semantics, no query. Keep the docstring's promise accurate.
Positional column iteration O(ncols²) (src/dataframe.jl:141): Tables.getcolumn(df, ::Int) re-runs _column_names (ccall + full Arrow schema parse) per call. Fix Tables-idiomatically: make Tables.columns(df) return a small DataFrameColumns snapshot struct holding df + the names computed once; define Tables.getcolumn/columnnames/schema on it delegating to the existing methods. Leave the direct DataFrame methods as-is for standalone use. (Don't cache inside the mutable DataFrame struct — avoids thread-safety questions for no benefit.)
Small API completeness: add Base.size(df::DataFrame, dim::Integer) delegating to the tuple form.
Full suite, commit.
P4 — Consistency, docs, CI, hygiene polish
Exports: move the scattered top-level export statements (src/describe.jl:64, src/reshape.jl:107,135) into the canonical block in src/Polars.jl; leave the expr/expr.jl exports where its macro generates them but add a comment in Polars.jl pointing there. Drop the Base-colliding exports from the namespace submodules (Lists: get, contains, head at src/expr/list.jl:65; Strings' overlapping names at src/expr/string.jl:244 and the macro-generated ones): they're designed for qualified use (Lists.get), and using Polars.Lists currently produces clashes. Check tests for using Polars.Lists-style imports and qualify them. Breaking at 0.2.0 is acceptable; note in commit message.
Docstrings: add one for clone (src/lazyframe.jl:55); extend @generate_expr_fns (src/expr/expr.jl:301-348) so Base-qualified methods also get a docstring attached (currently the doc/export block is skipped for them); fix the src/arrow.jl path typos in src/arrow/schema.jl and ext/PolarsTimeZonesExt.jl:6.
Repo hygiene: add .claude/ to .gitignore (its worktrees hold ~44 GB; one git add -A from disaster); fix README typo "thWe" (line 11) and add a note that the walkthrough example is illustrative (files not shipped); add ## Status lines to plans/parquet_io_options.md and plans/timezones.md; refresh the stale "not yet committed/pushed" claims in the Done plans' Status lines.
CI: add a macOS job to the test matrix in .github/workflows/Tests.yml (Rust build via the same steps; Swatinem/rust-cache handles per-OS caches; gen/prologue.jl already handles .dylib). Keep Windows out of scope for now (no .dll handling exists).
Optional cosmetics, only if time permits: rename PolarsEngine → polars_engine_t (c-polars/src/types.rs:148) for header naming uniformity — full header/regen workflow as in P2; skip if P2 didn't land.
Full suite + CI green on the PR, commit(s).
P5 — Deferred (recommend separate plans; do NOT fold into this one)
Docs reference-page curation: ~200 exported symbols absent from @docs/@autodocs blocks (checkdocs=:exports currently softened via warnonly=[:missing_docs]). Content-authoring effort, needs deliberate page structure — its own plan.
Zero-copy read path revival: plans/zero_copy_rust_to_julia.md says the work is Done on the unmerged zero-copy-rust-to-julia branch. Merging it would eliminate the per-element ccall fallback for nested columns — the biggest remaining read-path win — but it predates this branch's large refactors and needs its own rebase/review cycle.
Verification (per tier and final)
Rust (P0, P2): cd c-polars && cargo build -j 4 (stable, never nightly), cargo clippy --all-targets -- -D warnings, cargo fmt --check, cargo test, python3 check_header_drift.py. After any header change: regenerate + runic -i src/api/generated.jl, and CI's drift check (git diff --exit-code on the regenerated file) must pass.
Live exercise (mandatory after every rebuild — clean builds are not evidence): restart the Kaimon REPL, then run the touched paths with real data: non-ASCII column names (col("café")), each converted export function, nested list/struct columns, a tz-aware datetime with TimeZones loaded (needs the scratch env that has TimeZones — the default project won't load the extension).
Julia suite: scratch env per CLAUDE.md — Pkg.develop(path=".") + Pkg.add(["Aqua","Test","Tables","TimeZones","Statistics"]), then JULIA_PROJECT=<scratch> julia -e 'include("test/runtests.jl")'. Baseline to beat: 1235 passed / 2 broken / 0 failed, Aqua green.
Per-tier commits so each priority level is a reviewable, revertable unit; update plans/review_three_fixes.md's ## Status as tiers land, marking it Done with the final test count at the end.
Add Comment