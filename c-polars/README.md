# c-polars: Rust/C ABI bridge to upstream polars

`c-polars/` is the hand-written C ABI layer wrapping the upstream Rust `polars` crate. It exports a minimal, safe set of `extern "C"` functions that Julia calls via `@ccall`. The workflow is: write/edit Rust code → regenerate the C header and Julia bindings → build the shared library → test.

## When to regenerate

Regenerate after any change to `c-polars/src/*.rs`:
- Adding a new operation
- Fixing a bug or panic path
- Changing a function signature or ownership convention

**Do not** edit `c-polars/include/polars.h` or `src/api/generated.jl` by hand — they are generated; hand-edits will be overwritten and lost.

## Prerequisites

- **Rust**: stable toolchain only (see `c-polars/rust-toolchain`). Do NOT use `cargo +nightly` — polars-ops has nightly feature detection that breaks on stable-impersonating nightly, and the `RUSTC_BOOTSTRAP=1` used by the regen script is deliberately narrow.
- **cbindgen**: used to generate the C header from Rust (installed as a dev dependency in `c-polars/Cargo.toml`).
- **Julia**: for binding generation (see `gen/` directory).
- **Python 3**: for pre-checks (`check_header_drift.py`, `check_panic_guards.py`).
- **rustup**: `rustup update stable` if you haven't updated in a while. Some operations (`std::hint::cold_path`, `AtomicU64::try_update` in `polars-ooc`) require a recent-enough stable (≥ 1.95); an old stable fails with cryptic `E0658 use of unstable library feature` errors with no toolchain hint.

## Regeneration workflow

**1. Edit Rust code** in `c-polars/src/*.rs`, following FFI conventions in the project's [CLAUDE.md](../CLAUDE.md) (outparam + error-pointer for fallible functions, `guard_error` on every fallible entry point that returns `*const polars_error_t`, no `.unwrap()` on reachable-from-input operations).

**2. Regenerate the header and bindings:**

```bash
cd c-polars
bash regen_header.sh
```

This runs cbindgen to produce `include/polars.h` from Rust source (including any `///` doc comments).

**3. Regenerate the Julia bindings:**

```bash
julia --project=gen gen/generate.jl
```

This reads `c-polars/include/polars.h` and produces `src/api/generated.jl` via Clang.jl.

**4. Format the generated Julia bindings:**

```bash
runic -i src/api/generated.jl
```

**5. (Optional) Quick pre-check:**

```bash
python3 c-polars/check_header_drift.py
```

This verifies the header hasn't drifted from the Rust source (runs before full compilation).

**6. Build the shared library:**

```bash
cd c-polars
cargo build
```

**⚠️ Memory warning:** For any full dependency rebuild (fresh clone, `Cargo.toml` change, toolchain update), use:

```bash
cargo build -j 1
```

A 16-way or even 4-way parallel build of deps will OOM-kill this machine, taking the VS Code host with it. Single-threaded is slow (~5-8 min on first build) but stable. Once deps are cached, `-j 4` is safe for incremental builds.

**7. Restart the Julia REPL:**

The `.so` is memory-mapped; a running Julia session won't pick up the new binary. You must restart the REPL (in Kaimon: `manage_repl command="restart"`; in a plain session: close and reopen).

**8. Verify:**

```bash
# In Julia
using Polars
df = read_parquet("some.parquet")  # or similar
```

Or run the test suite:

```bash
julia test/runtests.jl
```

## Panic safety check (CI automated)

```bash
python3 c-polars/check_panic_guards.py
```

This checks that every fallible entry point (returning `*const polars_error_t`) is wrapped in `guard_error`. Exits non-zero if any are missing. Runs in CI; recommended before pushing.

## Troubleshooting

**`cargo build` fails with "activate X feature"**
  - A polars function you're calling requires a feature. Check `~/.cargo/registry/src/*/polars-*-<version>/src/` for the feature gating, and enable it in `c-polars/Cargo.toml`. Or check `cargo tree -e features -i <crate>` to see which features are actually enabled on the sub-crate involved.

**`cargo build` succeeds but Julia tests crash or fail**
  - Restart the Julia REPL — the old `.so` is still mapped.
  - Check that `.unwrap()` / `.expect()` aren't on reachable operations. A panic here is uncatchable and kills the process.

**`julia --project=gen gen/generate.jl` fails with "path not in Artifacts.toml"**
  - The generated bindings expect the built `libpolars.so` to be in Artifacts; usually this is automatic, but if artifacts are missing or outdated, ensure `Artifacts.toml` matches a recent `cargo build` output.

**"E0658 use of unstable library feature" in polars-ooc**
  - Your stable toolchain is too old. Run `rustup update stable && cargo clean && cargo build -j 1`.

## Deep dive

- FFI conventions, error handling, ownership, memory safety, and Cargo-feature hazards: see [CLAUDE.md](../CLAUDE.md), section "C ABI conventions" and "Build environment".
- Panic-safety incidents and `guard_error` design: [plans/ffi_panic_safety.md](../plans/ffi_panic_safety.md).
- C ABI review checklist: use the `reviewing-rust-julia-abi` skill.
- Generated-file guarantees: [plans/cbindgen_header_generation.md](../plans/cbindgen_header_generation.md).
