#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# RUSTC_BOOTSTRAP: cbindgen needs -Zunpretty=expanded to see the macro-generated #[no_mangle]
# fns. This stays on the pinned stable toolchain; `cargo +nightly` would switch polars-ops onto
# its unstable code path.
# CARGO_BUILD_JOBS=1: the check-build has high peak memory use.
export RUSTC_BOOTSTRAP=1
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-1}"
export CARGO_EXPAND_TARGET_DIR="$PWD/target/expand"
cbindgen --config cbindgen.toml --crate c-polars --output include/polars.h
clang-format -i include/polars.h
