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
