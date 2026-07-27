# Developer

This page documents implementation details relevant to people extending or contributing to
Polars.jl itself. None of it is needed to *use* the package — see [Reference](@ref) for that. For
the full architecture and contribution workflow, see
[`CLAUDE.md`](https://github.com/ymiftah/Polars.jl/blob/main/CLAUDE.md) in the repository.

## Architecture

Polars.jl is a hand-written C ABI bridge over the upstream Rust `polars` crate, not a
reimplementation: all query logic runs inside polars itself, and the Julia side only marshals
expressions and frames across the FFI boundary. Eager `DataFrame` operations are implemented
internally as `collect ∘ op ∘ lazy` — i.e. every eager verb builds a one-step lazy query and
immediately collects it, which is why eager and lazy forms of the same operation always produce
identical results.

## Error handling

Fallible operations cross the FFI boundary through an out-parameter + error-pointer convention:
every fallible `ccall` returns a `*const polars_error_t` (null on success) alongside the real
result. On the Julia side, this is unwrapped into a single exception type — `PolarsError`, whose
`message` field is polars' own (Rust-side) error text, passed across the boundary unmodified.

## Cargo features & build configuration

Some polars capabilities are gated behind Cargo features that aren't enabled by default in
`c-polars/Cargo.toml`:

- `Strings.titlecase` requires an internal "nightly" Cargo feature this package deliberately
  doesn't enable — the binding exists but errors at runtime.
- `Array` (fixed-size list) support needs the `dtype-array` feature, which isn't enabled.
  Upstream's own `Array`-dtype selector matcher compiles to an always-`false` fallback when the
  feature is off, which would otherwise make `Selectors.array()` silently match zero columns
  rather than fail — this wrapper raises an explicit error instead to avoid that footgun.
- `Decimal` columns can be cast/queried but not materialized back into Julia — the Arrow C Data
  Interface format-string decoder (`parse_format` in `src/arrow/schema.jl`) doesn't yet handle the
  Decimal format code.

## Memory management & concurrency

`DataFrame`, `LazyFrame`, `Series`, `Expr`, and `Value` are thin, unsynchronized wrappers around a
raw pointer, with a Julia finalizer registered to free the underlying Rust allocation. None of them
are safe to share across Julia tasks/threads without external synchronization — give each
task/thread its own handle (`clone()` a `LazyFrame` to fan a query out), or synchronize access
yourself.

The only internal locks (`LIVE_SCHEMAS`/`LIVE_ARRAYS` in `src/arrow/schema.jl`/`src/arrow/array.jl`)
guard Arrow C Data Interface release-callback bookkeeping — Rust's release callback can fire on
whatever thread drops an imported/exported array, so that GC-keepalive bookkeeping needs its own
lock. This protects that bookkeeping only, not query data.

polars' own parallelism (rayon) is independent of Julia's thread pool: it's hard-enabled on the
Rust side for the operations that support it, runs on rayon's own pool sized by
`POLARS_MAX_THREADS` (or the CPU count if unset), and is unaffected by `JULIA_NUM_THREADS`. Running
many polars queries concurrently from separate Julia tasks can oversubscribe the machine.

`read_series(...; zerocopy=true)` returns a `Vector` that directly aliases the polars `Series`'
own memory (no copy) only when the column is fixed-width numeric with no nulls; the caller is
responsible for treating the result as read-only, since mutating it would corrupt the source
`Series`. Outside that precondition, `zerocopy` is silently not honored and a normal copy is
returned instead.

The write direction has its own, unconditional aliasing: `DataFrame(table)` hands polars raw
pointers into the caller's own column `Vector`s rather than copying them, for any column whose
`arrowvector` method reuses the input buffer directly — in practice, any fixed-width numeric
column (`Int64`, `Float64`, ..., including their `Union{T,Missing}` form). Mutating the source
`Vector` after constructing the `DataFrame` mutates the `DataFrame` too. `Bool`, `String`, `Date`,
`Time`, `DateTime`, `Duration`, and `List` columns are unaffected — their `arrowvector` methods
build a fresh buffer (bit-packing, offset encoding, or an epoch-relative transform), so those
always copy.

## I/O internals

CSV scanning has no `hive_partitioning` option, unlike parquet/IPC — not a scope choice but a real
upstream gap: the builder `scan_csv` uses (`polars_lazy::frame::LazyCsvReader`) hardcodes
hive-partitioning off internally with no way to override it.

`allow_missing_columns` (parquet/CSV/IPC scan options) only covers files *missing* a column present
in the reference schema, not files with an *extra* column beyond it — that's a separate
`ExtraColumnsPolicy` this wrapper doesn't expose. The reference schema is whichever file/fragment
gets scanned first, so ordering matters when relying on this option.

## API design rationale

`Base.lt` is bound under that qualified name because the bare `lt` collides with an *unexported*
internal `Base` binding. The product aggregation used to have the same problem
(`Base.product`/an unexported internal `Base` binding) but was renamed to `prod`, an exported
`Base` name, so it now resolves unqualified like `sum`/`mean`.

Most binary `Expr` functions have a curried form for pipe-based composition, but five —
`log`, `rem`, `replace`, `diff`, `round` — deliberately don't. These are `Base`-qualified names,
and a curry useful for plain numeric literals would need an untyped argument (e.g. a hypothetical
`log(2)` curry accepting a bare `Int`). Julia always prefers `Base`'s own concrete-type methods
over a package addition, so this wouldn't raise a dispatch *ambiguity* error — but it would still
be real type piracy, claiming argument combinations `Base` currently leaves undefined and silently
changing global `Base` behavior outside this package's own types. A curry typed narrowly to `Expr`
would avoid the piracy but would then only accept already-constructed `Expr`s, defeating the
ergonomic point of currying — so these five stay in their full, non-curried form.

`Polars.Meta` is never exported from `Polars`, unlike `Lists`/`Strings`/`Dt`/`Structs`/`Selectors`
— always reached fully qualified as `Polars.Meta.output_name(...)` etc. `Base.Meta` is itself an
*exported* Base submodule, so exporting `Meta` from `Polars` would make plain `using Polars`
immediately ambiguous-error on the bare name `Meta` in the importing module.

## Test coverage

The test suite has real gaps — some operations have shipped with zero automated coverage in the
past. When adding or modifying a wrapped operation, verify it end-to-end in a live Julia session
rather than assuming it works because it compiles and the happy path looks right.
