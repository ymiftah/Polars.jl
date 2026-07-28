# Generate `c-polars/include/polars.h` from the Rust FFI surface

## Status

**Done.** All 6 phases landed as separate commits on `header_gen`. Verification results:

- **Symbol parity:** `check_header_drift.py` → `OK: 296 exported symbols match include/polars.h`
  (plus the `nightly`-gated `polars_expr_str_to_titlecase`), unchanged from before.
- **Signature equivalence:** normalised-tuple diff against the pre-change header found 296/296
  symbols on both sides, zero real ABI differences, and no reordering at all this run (better than
  the "7 runs" the doc's research predicted). Two cosmetic diffs, both investigated and confirmed
  benign: `polars_lazy_frame_group_by_dynamic`/`polars_lazy_frame_rolling` had three enum params
  spelled as the bare typedef name instead of `enum polars_x_t` (a hand-maintenance inconsistency
  the generator fixed — same C type either way, zero ABI impact). Doc-comment expansion matched the
  doc's own predicted example exactly.
- **`src/api/generated.jl` diff:** every changed `@ccall` line is a paired reorder (identical
  before/after text) — zero net signature changes, confirming the header regen is ABI-transparent
  to the Julia bindings.
- **Idempotence:** `regen_header.sh` run twice produces byte-identical output on the second run.
- Full Rust/Julia verification (clippy, fmt, C ABI link + restart, full Julia suite) run per the
  Verification section below.

**One correction to the original research, found during Phase 4:** the sketched CI step
(`uvx --from clang-format==22.1.8 --with-executables-from=clang-format bash -c '...'`) does not
work — `--with-executables-from` is not a real `uvx`/`uv run` flag on the installed uv version
(0.11.28). Replaced with `uv tool install clang-format==22.1.8` + prepending its bin dir
(`uv tool dir --bin`) to `PATH`/`GITHUB_PATH`, verified end-to-end locally with clang-format
stripped from `PATH` first to confirm cold resolution actually works.

## Context

`c-polars/include/polars.h` is hand-maintained today: adding an FFI function means hand-writing the
prototype (CLAUDE.md workflow step 4), and `src/api/generated.jl` is then generated *from* that
header by Clang.jl. So the header is the single source of truth for the Julia side's `@ccall`
signatures — but nothing checks it against the Rust definitions it claims to describe.

`c-polars/check_header_drift.py` closes half the hole: it compares **names**. It cannot compare
**signatures**. A header prototype with a wrong argument type, a missing argument, or `usize` where
Rust says `u8` passes every gate in CI, flows into `generated.jl`, and becomes a silently-wrong
`@ccall` — an ABI mismatch, which is memory corruption, not a Julia error. That is the defect class
this work eliminates.

The header was originally cbindgen output (commit `0765afc "generate c bindings"`) and the
generator is still wired up in `c-polars/build.rs`, gated behind `CBINDGEN_GENERATE=1` and
documented as nightly-only. **That nightly requirement is what killed it, and it no longer holds.**

Outcome: `polars.h` becomes generated, hand-edits are forbidden, and CI fails on any drift between
the Rust source and the committed header.

## Verified findings

Checked live (stable `rustc 1.97.0`, cbindgen 0.29.0 sources in the registry):

1. **48% of the FFI surface is macro-generated**, so cbindgen's syn-based parser cannot see it
   without `parse.expand`:

   | file | direct `#[no_mangle] extern "C"` | `macro_rules!`-generated |
   |---|---|---|
   | expr.rs | 80 | 121 |
   | value.rs | 13 | 11 |
   | series.rs | 10 | 11 |
   | dataframe.rs / io.rs / lib.rs | 51 | 0 |
   | **total** | **154** | **143** |

   297 total; the header declares 296 (`polars_expr_str_to_titlecase` is `#[cfg(feature =
   "nightly")]`-gated and absent from a default build). These are the numbers Phase 0 must
   reproduce.

2. **`RUSTC_BOOTSTRAP=1` dissolves the nightly blocker.** `polars-ops`' build.rs is only:

   ```rust
   let channel = version_check::Channel::read().unwrap();
   if channel.is_nightly() { println!("cargo:rustc-cfg=feature=\"nightly\""); }
   ```

   It reads the **version string**, not feature-gate state. Confirmed: `RUSTC_BOOTSTRAP=1 rustc
   -vV` still reports `release: 1.97.0` (no `-nightly`), while `RUSTC_BOOTSTRAP=1 rustc
   -Zunpretty=expanded` correctly expands a `macro_rules!`-generated `#[no_mangle] extern "C" fn`
   (without it: `error: 1 nightly option were parsed`). So expansion works on the pinned stable
   toolchain with the polars-ops nightly path still off.

3. **cbindgen honours `CARGO_EXPAND_TARGET_DIR`** (`cargo_expand.rs`; `use_tempdir` is the
   `--clean` flag, default false), so the check-build it triggers can be cached across runs instead
   of thrown away.

4. **The reordering diff is small and bounded.** Header declaration order, as runs of defining
   file: `lib×3, dataframe×17, io×6, dataframe×25, expr×200, series×21, value×24` — 7 runs over 296
   symbols. Within-file order already matches source order. Expansion inlines `mod` blocks at their
   declaration site in `lib.rs`, so generated order becomes
   `dataframe, expr, io, series, value, lib` — i.e. only the 3 `lib.rs` declarations and the 6
   `io.rs` declarations move. Not a scramble.

5. **No platform-conditional code.** The only non-test `#[cfg]` in `c-polars/src/` is the `nightly`
   feature gate at `expr.rs:957`, so a header generated on Linux is valid everywhere.

6. **The committed header is clang-format'd**, not raw cbindgen output — `.pre-commit-config.yaml`
   runs `mirrors-clang-format` v22.1.8 over `^c-polars/include/.*\.h$` with `ColumnLimit: 100`,
   `IndentWidth: 2`. Generation must be followed by clang-format or the CI diff gate will never be
   stable.

### Not yet verified (Phase 0 settles all of these)

- Whether the expansion of this specific crate parses cleanly in cbindgen 0.29's `syn`.
- Whether `IOCallback` survives: it is `pub(crate) type IOCallback = ...`
  (`c-polars/src/ffi_util.rs:8`) yet appears as a `typedef` in the header today.
- Whether `ArrowSchema`/`ArrowArray` (from `polars_core::utils::arrow::ffi`, not this crate) stay
  as bare unresolved names covered by `includes = ["arrow.h"]`, or get emitted as duplicate structs.
- Peak memory of the check-build. `free -g` showed ~2 GB available when this was written, and this
  repo has a history of OOM-killing the VS Code host. **Every command below pins
  `CARGO_BUILD_JOBS=1`.**

## Decisions

| | choice |
|---|---|
| Driver | cbindgen **CLI** + `c-polars/cbindgen.toml`; `build.rs` deleted and the `cbindgen` build-dependency dropped (today it is compiled on every fresh build for a feature that is off) |
| Enforcement | Generated is **authoritative**; CI regenerates and `git diff --exit-code`s |
| `check_header_drift.py` | **Kept** as the fast, toolchain-free pre-gate in the `lint` job |

---

## Phase 0 — Spike: prove the expansion (no files changed)

Isolate expansion from cbindgen so a failure has one obvious cause.

```bash
cd c-polars
SP=<scratch dir>
RUSTC_BOOTSTRAP=1 CARGO_BUILD_JOBS=1 \
  cargo rustc --lib --profile=check -p c-polars -- -Zunpretty=expanded > $SP/expanded.rs
grep -c 'no_mangle' $SP/expanded.rs         # expect 297
```

Then let cbindgen consume it, still writing nowhere near the real header:

```bash
cargo install cbindgen --version 0.29.0 --locked
RUSTC_BOOTSTRAP=1 CARGO_BUILD_JOBS=1 CARGO_EXPAND_TARGET_DIR=$PWD/target/expand \
  cbindgen --config $SP/cbindgen.toml --crate c-polars --output $SP/polars.new.h
```

**Gate:** 296 `polars_*` prototypes in the output, `IOCallback` present, no duplicate
`ArrowSchema`/`ArrowArray` struct definitions. If any fails, fix `cbindgen.toml` and repeat — do
not proceed to Phase 1.

## Phase 1 — Land the generator

**New: `c-polars/cbindgen.toml`** — a direct translation of today's `build.rs` `Builder` calls plus
what the current header's shape implies. Line/tab settings match `.clang-format` to minimise
reformat churn:

```toml
language = "C"
pragma_once = true
includes = ["arrow.h"]
cpp_compat = false
documentation = true
documentation_style = "doxy"
documentation_length = "full"
line_length = 100          # .clang-format ColumnLimit
tab_width = 2              # .clang-format IndentWidth
autogen_warning = "/* GENERATED FILE -- do not edit. Regenerate with c-polars/regen_header.sh */"

[parse]
parse_deps = false

[parse.expand]
crates = ["c-polars"]
all_features = false
default_features = true    # keeps the `nightly`-gated symbol out, matching today's header
```

Leave `style` at its default (`both`) — that is what produces the existing
`typedef struct polars_dataframe_t polars_dataframe_t;` plus `struct polars_dataframe_t *` in
prototypes.

**New: `c-polars/regen_header.sh`** (executable) — the single documented entry point:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# RUSTC_BOOTSTRAP: cbindgen needs -Zunpretty=expanded to see the ~143 macro-generated
# #[no_mangle] fns. This keeps us on the pinned stable toolchain -- do NOT switch to
# `cargo +nightly`, which flips polars-ops into its unstable code path (see CLAUDE.md).
# CARGO_BUILD_JOBS=1: the check-build peaks hard; -j4 has OOM-killed this machine.
export RUSTC_BOOTSTRAP=1
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-1}"
export CARGO_EXPAND_TARGET_DIR="$PWD/target/expand"
cbindgen --config cbindgen.toml --crate c-polars --output include/polars.h
clang-format -i include/polars.h
```

**Modified: `c-polars/Cargo.toml`** — drop `[build-dependencies] cbindgen = "0.29.0"`.
**Deleted: `c-polars/build.rs`** — its only content was the opt-in generation branch.

Confirm `c-polars/.gitignore` covers `target/` (it should; `target/expand` lands inside it).

## Phase 2 — Adopt the regenerated header, prove it equivalent

Run `./regen_header.sh`, then **do not eyeball the diff** — reordering and doc-comment churn will
bury anything real. Write a throwaway comparison script (scratchpad, not committed) that parses
both the pre-change header (`git show HEAD:c-polars/include/polars.h`) and the new one into a
normalised set of `(name, return type, [arg types])` tuples, ignoring whitespace, argument names,
and comments, then diffs the two sets.

Three expected classes of difference, and what each means:

- **Reordering** — `lib.rs`'s 3 and `io.rs`'s 6 declarations relocate (finding 4). Benign.
- **Doc-comment expansion** — Rust docs become the source of truth and are supersets of the
  hand-trimmed header versions. Example: `polars_dataframe_new_from_carrow` gains three sentences
  of implementation detail present at `c-polars/src/dataframe.rs:34-43` but trimmed from the
  header. Benign and arguably an improvement.
- **Any signature difference at all** — this is a **real, pre-existing ABI bug** and the whole
  point of the exercise. Stop, investigate individually, and note it in the commit message. Do not
  assume the generator is wrong.

## Phase 3 — Propagate to the Julia side

```bash
julia --project=gen gen/generate.jl && runic -i src/api/generated.jl
```

If Phase 2 found zero signature differences, `git diff src/api/generated.jl` should be limited to
declaration order and docstrings. If it found a real one, the corresponding `@ccall` in
`src/api/generated.jl` changes — run the full Julia suite (see Verification) and treat any new
failure as the latent bug surfacing, not as regression from this work.

## Phase 4 — CI gate

In `.github/workflows/Tests.yml`, add to the **`rust`** job (it already has
`Swatinem/rust-cache@v2` with `shared-key: c-polars`, so the check-build is cached; the `lint` job
has no Rust toolchain at all):

```yaml
      - name: Install cbindgen
        run: cargo install cbindgen --version 0.29.0 --locked
      - name: Check include/polars.h is up to date
        run: |
          uvx --from clang-format==22.1.8 --with-executables-from=clang-format \
            bash -c './regen_header.sh'
          git diff --exit-code -- include/polars.h
        working-directory: ./c-polars
```

(Pin the clang-format version to the `.pre-commit-config.yaml` rev — a version mismatch produces a
permanently-red diff. If the `uvx` wrapper proves awkward, `pipx install clang-format==22.1.8` or
apt is equally fine; the requirement is only that the *same* formatter version runs.)

`CARGO_BUILD_JOBS=1` is a local-memory concern, not a CI one — let the script's default apply, or
override it to the runner's core count in the workflow `env:`.

Leave the existing `check_header_drift.py` step in the `lint` job untouched: it runs in ~1s with no
Rust toolchain and yields "you forgot symbol X" before the expensive job starts.

Do **not** add generation to `.pre-commit-config.yaml` — a check-build on every commit is far too
slow for a pre-commit hook.

## Phase 5 — Documentation

`CLAUDE.md` currently instructs the opposite of what will be true and must be corrected:

- The **"The header is hand-maintained; the Julia bindings are generated from it"** paragraph:
  retitle and rewrite. Both artifacts are now generated; the chain is
  Rust → (cbindgen) → `polars.h` → (Clang.jl) → `generated.jl`.
- **Workflow step 4** ("Hand-add the header prototype"): replace with `./c-polars/regen_header.sh`.
  Keep `check_header_drift.py` in the step as the fast sanity check.
- The **"Build environment"** section: add that header regeneration uses `RUSTC_BOOTSTRAP=1` on
  *stable* and explain why — this is precisely the kind of trap a future session would "fix" by
  reaching for `cargo +nightly` and silently re-arming the polars-ops unstable path.
- The `gen/` row of the "Where things live" table: note `cbindgen.toml`/`regen_header.sh` as the
  upstream half of the same pipeline.

Update this file's `## Status` to `Done` on landing.

---

## Verification

1. **Symbol parity** — `python3 c-polars/check_header_drift.py` reports `OK: 296 exported symbols
   match include/polars.h` plus the `polars_expr_str_to_titlecase` gated note. Unchanged from
   today; a different number means the generator dropped something.
2. **Signature equivalence** — the Phase 2 normalised-tuple diff is empty, or every entry is
   individually explained as a real pre-existing bug.
3. **Idempotence** — run `./regen_header.sh` twice; the second run leaves `git status` clean. This
   is what the CI gate actually asserts, so it must hold locally first.
4. **The C ABI still links and runs** — `cd c-polars && cargo build -j 4`, then restart the Julia
   session (a running session keeps the old `.so` mapped — Kaimon `manage_repl` `command="restart"`).
5. **Full Julia suite** in the scratch environment (`Pkg.develop(path=".")` +
   `Aqua, Test, Tables, TimeZones`):
   `JULIA_PROJECT=<scratch> julia -e 'include("test/runtests.jl")'`. This is the real ABI test — a
   corrupted signature shows up as a crash or garbage result, not a compile error.
6. **Rust side unaffected** — `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check`
   still pass after `build.rs` is deleted.
7. **Fresh-clone sanity** — `cargo build` in a clean checkout no longer compiles cbindgen at all
   (it is no longer a build-dependency).

## Risks and rollback

- **OOM during the check-build.** The dominant risk; ~2 GB free when this was written. Mitigated by
  `CARGO_BUILD_JOBS=1` everywhere, and by `CARGO_EXPAND_TARGET_DIR` making it a one-time cost.
  Watch the first run.
- **cbindgen fails to parse the expansion.** Caught in Phase 0 before anything is modified. Fallback
  if unfixable: abandon generation and instead extend `check_header_drift.py` to compare
  signatures using its existing macro-shape knowledge (the macros are highly regular — e.g.
  `gen_impl_expr!(polars_expr_sum, Expr::sum)` always means
  `*const polars_expr_t -> *const polars_expr_t`). Strictly worse, but it closes the same hole.
- **Generator output regresses the header.** Every phase is a separate commit and the header is in
  git; `git revert` restores hand-maintenance and the only loss is the tooling.
- **Feature-gated symbols.** The generated header describes a *default-feature* build, exactly as
  today. Anyone building `--features nightly` gets a symbol absent from the header — unchanged
  behaviour, but worth one sentence in the `cbindgen.toml` comment so it is not later mistaken for
  a generator bug.
