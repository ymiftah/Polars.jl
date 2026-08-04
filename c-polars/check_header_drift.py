#!/usr/bin/env python3
"""Guard against drift between the Rust FFI surface, the C header, and a built library.

`include/polars.h` is generated from the Rust source by cbindgen, and `src/api/generated.jl` is
generated *from* it (see CLAUDE.md -- never hand-edit either end). Generation is not automatic
though: it runs via `regen_header.sh`, and cbindgen can only see the ~143 macro-generated
`#[no_mangle]` functions through `-Zunpretty=expanded`. So a symbol that exists in Rust but never
makes it into the header -- because regeneration was skipped, or the expansion silently missed it
-- is invisible to the Julia side and untested, while a header declaration with no Rust definition
is a link error waiting to happen. CI already checks header -> generated.jl; this checks
Rust -> header.

This caught `polars_dataframe_new`, which was additionally declared `#[no_mangle] pub fn` (Rust
ABI, not `extern "C"`) and referenced by nothing at all.

Three modes:

    python3 c-polars/check_header_drift.py
        Rust source -> include/polars.h. The default.

    python3 c-polars/check_header_drift.py --lib path/to/libpolars.so
        include/polars.h -> a built shared library's dynamic symbol table.

    python3 c-polars/check_header_drift.py --arrow
        include/arrow.h -> the ArrowSchema/ArrowArray mirrors in src/api/generated.jl.

The second mode exists because the distributed binary and the bindings are versioned separately:
`Artifacts.toml` pins a fixed release tag, so a change under `c-polars/` reaches nobody until a new
release is cut. A stale artifact produces exactly the failure that made the registered
`libpolars_jll` useless -- an undefined symbol at first `ccall`, long after load, rather than
anything a clean build would catch.

Header -> library is the right comparison rather than Rust -> library: `#[cfg]`-gated symbols
(e.g. `polars_expr_str_to_titlecase`, behind the `nightly` feature) are legitimately absent from
both a default build and the header, so they drop out on their own.

The `--arrow` mode covers a gap the other two structurally cannot: they match *function* symbols,
so nothing here ever looked at struct layout. `ArrowSchema`/`ArrowArray` are polars-arrow's types,
mirrored by hand in both `include/arrow.h` and `src/api/generated.jl`; a mismatch between those two
mirrors is silent memory corruption at the FFI boundary, not a link error. (Drift of *both* mirrors
away from polars-arrow itself is caught separately, by the `size_of`/`align_of` const assertions in
`src/types.rs`.)
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
ARROW_HEADER = ROOT / "include" / "arrow.h"
GENERATED_JL = ROOT.parent / "src" / "api" / "generated.jl"

# The Arrow C Data Interface structs mirrored on both sides, checked by `--arrow`.
ARROW_STRUCTS = ("ArrowSchema", "ArrowArray")
# A C struct *definition* (`struct Name {...};`), as opposed to the trailing `typedef struct Name
# Name;` lines, which have no brace and so never match.
C_STRUCT_BODY = r"struct\s+{name}\s*\{{(.*?)\}}\s*;"
# A Julia `struct Name ... end` block.
JL_STRUCT_BODY = r"^struct\s+{name}\s*$(.*?)^end\s*$"
# A C function-pointer member: `void (*release)(struct ArrowSchema *)`. The member name sits inside
# the parens, so the generic "last identifier wins" rule below would pick up the parameter instead.
C_FN_PTR_MEMBER = re.compile(r"\(\s*\*\s*(\w+)\s*\)")
C_MEMBER_NAME = re.compile(r"(\w+)\s*$")
JL_FIELD = re.compile(r"^\s*(\w+)\s*::\s*(.+?)\s*$", re.MULTILINE)

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


def _struct_body(text: str, pattern: str, name: str, source: Path) -> str:
    match = re.search(pattern.format(name=name), text, re.DOTALL | re.MULTILINE)
    if match is None:
        sys.exit(f"error: could not find `{name}` in {source}")
    return match.group(1)


def _show(field: tuple[str, str] | None) -> str:
    return f"{field[0]}: {field[1]}" if field else "<missing>"


def c_fields(name: str) -> list[tuple[str, str]]:
    """`[(field_name, kind)]` for a struct in include/arrow.h, in declaration order.

    `kind` is coarse on purpose -- "ptr" or "i64". Both structs are entirely pointer-width fields
    on a 64-bit target, so this is enough to catch a field whose width changed, without dragging in
    a full C type model that would be fragile for no added coverage.
    """
    body = _struct_body(ARROW_HEADER.read_text(), C_STRUCT_BODY, name, ARROW_HEADER)
    body = re.sub(r"//[^\n]*", "", body)  # strip line comments

    fields = []
    for decl in body.split(";"):
        decl = decl.strip()
        if not decl:
            continue
        fn_ptr = C_FN_PTR_MEMBER.search(decl)
        if fn_ptr:
            fields.append((fn_ptr.group(1), "ptr"))
            continue
        member = C_MEMBER_NAME.search(decl)
        if member is None:
            sys.exit(f"error: could not parse member `{decl}` of {name} in {ARROW_HEADER}")
        if "*" in decl:
            kind = "ptr"
        elif "int64_t" in decl:
            kind = "i64"
        else:
            sys.exit(f"error: unrecognized member type `{decl}` of {name} in {ARROW_HEADER}")
        fields.append((member.group(1), kind))
    return fields


def julia_fields(name: str) -> list[tuple[str, str]]:
    """`[(field_name, kind)]` for a struct mirror in src/api/generated.jl, in declaration order."""
    body = _struct_body(GENERATED_JL.read_text(), JL_STRUCT_BODY, name, GENERATED_JL)

    fields = []
    for field, ty in JL_FIELD.findall(body):
        if ty.startswith("Ptr{") or ty == "Cstring":
            kind = "ptr"
        elif ty == "Int64":
            kind = "i64"
        else:
            sys.exit(f"error: unrecognized field type `{field}::{ty}` of {name} in {GENERATED_JL}")
        fields.append((field, kind))
    return fields


def check_arrow() -> int:
    problems = False

    for name in ARROW_STRUCTS:
        c = c_fields(name)
        jl = julia_fields(name)

        if c == jl:
            print(f"OK: {name} matches across include/arrow.h and src/api/generated.jl ({len(c)} fields)")
            continue

        problems = True
        print(f"{name} differs between include/arrow.h and src/api/generated.jl:")
        # Pad the shorter side so an added/removed field shows up as a positional mismatch rather
        # than silently truncating the comparison.
        for i in range(max(len(c), len(jl))):
            lhs = c[i] if i < len(c) else None
            rhs = jl[i] if i < len(jl) else None
            if lhs != rhs:
                print(f"  [{i}] arrow.h: {_show(lhs):<28} generated.jl: {_show(rhs)}")

    if problems:
        print(
            "\nArrow struct drift detected. These two mirrors describe the same polars-arrow"
            "\nstructs to C and to Julia; a mismatch is silent memory corruption at the FFI"
            "\nboundary. Fix include/arrow.h, then regenerate the Julia side:"
            "\n  julia --project=gen gen/generate.jl && runic -i src/api/generated.jl"
        )
        return 1

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
        print("\nHeader drift detected. Both ends are generated -- never hand-edit them. Fix the")
        print("Rust (or gen/generator.toml), then regenerate the whole pipeline:")
        print("  c-polars/regen_header.sh")
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
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--lib",
        type=Path,
        metavar="PATH",
        help="check a built shared library's exports against include/polars.h instead of "
        "checking the Rust source against the header",
    )
    mode.add_argument(
        "--arrow",
        action="store_true",
        help="check the ArrowSchema/ArrowArray declarations in include/arrow.h against their "
        "mirrors in src/api/generated.jl instead of checking function symbols",
    )
    args = parser.parse_args()
    if args.lib:
        sys.exit(check_library(args.lib))
    sys.exit(check_arrow() if args.arrow else main())
