#!/usr/bin/env python3
"""Guard against drift between the Rust FFI surface, the C header, and a built library.

`include/polars.h` is hand-edited (see CLAUDE.md), and `src/api/generated.jl` is generated *from*
it -- so a symbol that exists in Rust but never makes it into the header is invisible to the Julia
side and silently untested, while a header declaration with no Rust definition is a link error
waiting to happen. CI already checks header -> generated.jl; this checks Rust -> header.

This caught `polars_dataframe_new`, which was additionally declared `#[no_mangle] pub fn` (Rust
ABI, not `extern "C"`) and referenced by nothing at all.

Two modes:

    python3 c-polars/check_header_drift.py
        Rust source -> include/polars.h. The default.

    python3 c-polars/check_header_drift.py --lib path/to/libpolars.so
        include/polars.h -> a built shared library's dynamic symbol table.

The second mode exists because the distributed binary and the bindings are versioned separately:
`Artifacts.toml` pins a fixed release tag, so a change under `c-polars/` reaches nobody until a new
release is cut. A stale artifact produces exactly the failure that made the registered
`libpolars_jll` useless -- an undefined symbol at first `ccall`, long after load, rather than
anything a clean build would catch.

Header -> library is the right comparison rather than Rust -> library: `#[cfg]`-gated symbols
(e.g. `polars_expr_str_to_titlecase`, behind the `nightly` feature) are legitimately absent from
both a default build and the header, so they drop out on their own.
"""

from __future__ import annotations

import argparse
import re
import subprocess
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


def header_symbols() -> set[str]:
    return set(re.findall(r"\b(polars_\w+)\s*\(", HEADER.read_text()))


def library_symbols(lib: Path) -> set[str]:
    """Exported `polars_*` symbols in a built shared library.

    `nm` needs different flags per platform, and getting this wrong fails open -- an empty symbol
    set would make every check trivially pass. On Linux the release artifacts are stripped
    (`strip = "symbols"` in Cargo.toml), so only the *dynamic* symbol table survives and plain
    `nm -g` reports "no symbols"; `-D` is mandatory. macOS keeps exports in the regular table, and
    Mach-O prefixes C symbols with an underscore.
    """
    if sys.platform == "darwin":
        argv = ["nm", "-gU", str(lib)]
    else:
        argv = ["nm", "-D", "--defined-only", str(lib)]

    try:
        out = subprocess.run(argv, capture_output=True, text=True, check=True).stdout
    except FileNotFoundError:
        sys.exit("error: `nm` not found; it ships with binutils (Linux) or Xcode CLT (macOS)")
    except subprocess.CalledProcessError as exc:
        sys.exit(f"error: {' '.join(argv)} failed:\n{exc.stderr.strip()}")

    symbols = {
        name.lstrip("_")
        for name in re.findall(r"\b_?(polars_\w+)\b", out)
    }
    if not symbols:
        # Fail loudly rather than reporting a vacuous pass.
        sys.exit(f"error: no polars_* symbols found in {lib} -- wrong file, or stripped too far?")
    return symbols


def check_library(lib: Path) -> int:
    declared = header_symbols()
    exported = library_symbols(lib)

    missing = sorted(declared - exported)
    extra = sorted(exported - declared)

    if missing:
        print(f"include/polars.h declares {len(missing)} symbol(s) absent from {lib}:")
        for name in missing:
            print(f"  - {name}")
        print(
            "\nThe library is stale relative to the bindings. Every one of these is an undefined"
            "\nsymbol at first `ccall`. If this is the published artifact, cut a new release:"
            "\nbump c-polars/Cargo.toml, then run the `Release libpolars` workflow."
        )
        return 1

    if extra:
        # Not fatal: a non-default build (e.g. --features nightly) legitimately exports more than
        # the header, which describes the default build.
        print(f"note: {len(extra)} symbol(s) exported but not declared in the header: {', '.join(extra)}")

    print(f"OK: all {len(declared)} header-declared symbols are exported by {lib}")
    return 0


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

    declared = header_symbols()

    missing_from_header = sorted(rust_symbols - declared - cfg_gated)
    missing_from_rust = sorted(declared - rust_symbols)

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
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--lib",
        type=Path,
        metavar="PATH",
        help="check a built shared library's exports against include/polars.h instead of "
        "checking the Rust source against the header",
    )
    args = parser.parse_args()
    sys.exit(check_library(args.lib) if args.lib else main())
