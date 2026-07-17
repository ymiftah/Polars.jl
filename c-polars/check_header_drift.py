#!/usr/bin/env python3
"""Guard against drift between the Rust FFI surface and the hand-maintained C header.

`include/polars.h` is hand-edited (see CLAUDE.md), and `src/api/generated.jl` is generated *from*
it -- so a symbol that exists in Rust but never makes it into the header is invisible to the Julia
side and silently untested, while a header declaration with no Rust definition is a link error
waiting to happen. CI already checks header -> generated.jl; this checks Rust -> header.

This caught `polars_dataframe_new`, which was additionally declared `#[no_mangle] pub fn` (Rust
ABI, not `extern "C"`) and referenced by nothing at all.

Run from anywhere:  python3 c-polars/check_header_drift.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
HEADER = ROOT / "include" / "polars.h"

# `#[no_mangle]`, optional other attributes, then `pub [unsafe] extern "C" fn name(`
NO_MANGLE_FN = re.compile(
    r'#\[no_mangle\]\s*(?:#\[[^\]]*\]\s*)*pub\s+(?:unsafe\s+)?extern\s+"C"\s+fn\s+(\w+)',
)
# Most of the expr/series/value surface is macro-generated (`gen_impl_expr!(polars_expr_abs, ...)`),
# so the symbol name only ever appears as a macro argument. Any `some_macro!(polars_xxx, ...)`
# invocation defines `polars_xxx`; the macro bodies themselves are matched by NO_MANGLE_FN above
# but with the literal `$n` placeholder, which never collides with a real symbol name.
MACRO_GENERATED_FN = re.compile(r"\b\w+!\(\s*(polars_\w+)")
# A `#[cfg(...)]`-gated symbol is absent from a default build, so the header -- which describes
# exactly that build -- legitimately omits it (e.g. `polars_expr_str_to_titlecase`, gated behind
# the `nightly` feature). Such symbols are exempt from the missing-from-header check, but are
# still reported so an intentional gate can't quietly hide a symbol nobody meant to gate.
CFG_GATED = re.compile(r'#\[cfg\((?!test\b)[^\]]*\)\]\s*(?:#\[[^\]]*\]\s*)*(?:pub\s+(?:unsafe\s+)?extern\s+"C"\s+fn\s+(\w+)|\w+!\(\s*(polars_\w+))')
# any `#[no_mangle]` fn that is *not* extern "C" -- exported with the Rust ABI, which is unsound
# to call from C even when it happens to work on a given target
NO_MANGLE_NON_EXTERN = re.compile(
    r'#\[no_mangle\]\s*(?:#\[[^\]]*\]\s*)*pub\s+(?!(?:unsafe\s+)?extern\s+"C")(?:unsafe\s+)?fn\s+(\w+)',
)


def main() -> int:
    rust_symbols: set[str] = set()
    cfg_gated: set[str] = set()
    rust_abi_exports: list[str] = []

    for path in sorted(SRC.glob("*.rs")):
        text = path.read_text()
        rust_symbols |= set(NO_MANGLE_FN.findall(text))
        rust_symbols |= set(MACRO_GENERATED_FN.findall(text))
        cfg_gated |= {name for pair in CFG_GATED.findall(text) for name in pair if name}
        rust_abi_exports += [f"{name} ({path.name})" for name in NO_MANGLE_NON_EXTERN.findall(text)]

    header_text = HEADER.read_text()
    header_symbols = set(re.findall(r"\b(polars_\w+)\s*\(", header_text))

    missing_from_header = sorted(rust_symbols - header_symbols - cfg_gated)
    missing_from_rust = sorted(header_symbols - rust_symbols)

    problems = False

    if rust_abi_exports:
        problems = True
        print("#[no_mangle] functions that are not `extern \"C\"` (exported with the Rust ABI):")
        for item in rust_abi_exports:
            print(f"  - {item}")

    if missing_from_header:
        problems = True
        print("Rust `extern \"C\"` symbols missing from include/polars.h:")
        for name in missing_from_header:
            print(f"  - {name}")

    if missing_from_rust:
        problems = True
        print("include/polars.h declarations with no Rust definition:")
        for name in missing_from_rust:
            print(f"  - {name}")

    if problems:
        print("\nHeader drift detected. Hand-edit include/polars.h to match, then regenerate:")
        print("  julia --project=gen gen/generate.jl && runic -i src/api/generated.jl")
        return 1

    gated = sorted(cfg_gated & rust_symbols)
    print(f"OK: {len(rust_symbols) - len(gated)} exported symbols match include/polars.h")
    if gated:
        print(
            "     (plus "
            + ", ".join(gated)
            + " -- #[cfg]-gated, absent from a default build and so from the header)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
