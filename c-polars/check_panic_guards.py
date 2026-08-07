#!/usr/bin/env python3
"""Enforce that every fallible C ABI entry point is wrapped in `guard_error`.

A Rust panic unwinding out of an `extern "C"` function aborts the host process -- uncatchably,
taking the embedding Julia session with it. `guard_error` (see `src/lib.rs`) turns such a panic
into an ordinary `polars_error_t`, but only for functions that have somewhere to put one.

The rule this checks is deliberately mechanical: **if the function returns
`*const polars_error_t`, its body must call `guard_error`.** Not "if a panic looks likely there" --
that phrasing cannot be checked, and the coverage it produced was 3 of 142 functions in `expr.rs`
while `io.rs` had 8 of 9. Functions with no error channel (returning a handle, `usize`, `bool`, or
a `#[repr(C)]` enum by value, and the void in-place mutators) are out of scope: they cannot report
anything, so a panic there aborts and the fix is an ABI change, not a guard.

Run from anywhere:  python3 c-polars/check_panic_guards.py
Exits non-zero and lists offenders if any fallible entry point is unguarded.
"""

import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent / "src"
# `tests.rs` defines no entry points; `ffi_util.rs`/`types.rs` hold helpers, not `extern "C"` fns.
FILES = ["lib.rs", "dataframe.rs", "expr.rs", "io.rs", "series.rs", "value.rs"]

# Matches both plain definitions and the ones inside `macro_rules!` bodies, whose name is a
# metavariable (`fn $n(`) rather than an identifier -- those expand into real entry points too, and
# were the ones an earlier ad-hoc sweep missed.
FN = re.compile(r'^(\s*)pub (?:unsafe )?extern "C" fn (\$?\w+)(<[^>]*>)?\(')
FALLIBLE_RET = "-> *const polars_error_t"


def entry_points(lines):
    """Yield (line_number, name, signature, body) for each `extern "C"` fn in `lines`."""
    i = 0
    while i < len(lines):
        m = FN.match(lines[i])
        if not m:
            i += 1
            continue

        # The signature runs until parenthesis depth returns to zero on a line ending in `{`,
        # which is the body's opening brace (rustfmt splits long argument lists across lines).
        j, depth = i, 0
        while j < len(lines):
            depth += lines[j].count("(") - lines[j].count(")")
            if depth == 0 and lines[j].rstrip().endswith("{"):
                break
            j += 1
        if j >= len(lines):
            i += 1
            continue

        # The body runs to its matching close brace. Brace counting is safe here because no entry
        # point contains a brace inside a string or char literal.
        k, d = j + 1, 1
        while k < len(lines):
            d += lines[k].count("{") - lines[k].count("}")
            if d == 0:
                break
            k += 1

        yield i + 1, m.group(2), "\n".join(lines[i:j + 1]), "\n".join(lines[j + 1:k])
        i = k + 1


def main():
    unguarded = []
    fallible = 0
    total = 0

    for name in FILES:
        path = SRC / name
        if not path.exists():
            print(f"error: {path} not found", file=sys.stderr)
            return 2
        lines = path.read_text().split("\n")
        for lineno, fn, sig, body in entry_points(lines):
            total += 1
            if FALLIBLE_RET not in sig:
                continue
            fallible += 1
            if "guard_error(" not in body:
                unguarded.append(f"  {name}:{lineno}  {fn}")

    if unguarded:
        print(
            f"FAIL: {len(unguarded)} fallible entry point(s) not wrapped in `guard_error`:\n"
            + "\n".join(unguarded)
            + "\n\nEvery `extern \"C\"` fn returning *const polars_error_t must wrap its body in\n"
              "`guard_error(|| { ... })` so an upstream panic becomes a catchable error instead of\n"
              "aborting the host process. See the `guard_error` doc comment in src/lib.rs.",
            file=sys.stderr,
        )
        return 1

    print(f"OK: all {fallible} fallible entry points are guarded ({total} extern \"C\" fns total)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
