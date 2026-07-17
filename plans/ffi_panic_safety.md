# Fix panic-across-FFI risks: `polars_series_get` and `polars_dataframe_show`

## Status
Done. Both items implemented, live-verified (out-of-bounds now raises a catchable Julia error for
String/Date/List/Struct series; in-bounds access and `polars_dataframe_show` both still correct),
regression test added, full suite passes (594/594, 3 pre-existing broken unrelated to this fix).

Found during a memory-safety review of `src/API.jl` / `c-polars/src/*.rs` on the
`scan-parquet` branch. Two Rust `extern "C"` functions panicked instead of returning a catchable
error, violating the convention `CLAUDE.md` documents explicitly: "a Rust panic unwinding across
`extern "C"` is UB... any fallible parse *must* go through this out-param + error-pointer
convention instead of an API that panics."

## Findings recap

### F1 — `polars_series_get` ([series.rs:60-67](c-polars/src/series.rs#L60-L67)): unwrap panic on out-of-bounds index — crashes the process, reachable from ordinary user code
```rust
let value = (*series).inner.get(index).unwrap();
```
`Series::get` returns `PolarsResult`; `.unwrap()` panics if `index` is out of bounds. Every
`gen_series_get!`-generated getter (`polars_series_get_i32` etc., backing numeric/bool `Series`
indexing) already matches `Ok`/`Err` and returns `*const polars_error_t` correctly — this is the
one getter that doesn't. It backs `Base.getindex` for every non-numeric `Series` element type
(Date, DateTime, Duration, String, Binary, List, Struct — [series.jl:33-45](src/series.jl#L33-L45)
and [:48-60](src/series.jl#L48-L60)), so today `s = Series("x", [Date(2024,1,1)]); s[5]`
segfaults/aborts the whole Julia process instead of raising a catchable error.

### F2 — `polars_dataframe_show` ([lib.rs:306-314](c-polars/src/lib.rs#L306-L314)): `.expect()` on write failure
```rust
write!(w, "{df}").expect("failed to show dataframe");
```
Its two siblings, `polars_dataframe_write_parquet`/`write_csv` ([lib.rs:226-254](c-polars/src/lib.rs#L226-L254)),
correctly return `make_error(err)` on the identical failure mode (the I/O callback signaling `-1`).
`show` panics instead. Smaller blast radius than F1 — `Base.show(io, df)`
([Polars.jl:335](src/Polars.jl#L335)) is pure-Julia (`PrettyTables`) and never calls this C ABI
function; confirmed no in-tree caller exists today (only the `API.jl` wrapper defines it). Still
worth fixing: it's exported public API surface (`Polars.API.polars_dataframe_show`) and should
follow the same convention as the two functions next to it.

## Non-goal (bundled as a one-line fix, not a separate item)
`Value{T}(ptr, parent = nothing)` in [Polars.jl:65](src/Polars.jl#L65) has a default arg that
doesn't type-check against the `parent::Union{Series,Value}` field (would throw a `TypeError`
immediately if ever invoked with one argument). Dead code — no current call site uses the
one-arg form — not a live safety issue, but touched by Item 1's file so fix it in passing.

## Items

### Item 1 (F1 fix) — make `polars_series_get` fallible
- **Rust** (`c-polars/src/series.rs`): change the signature from
  `fn polars_series_get<'a>(series, index) -> *const polars_value_t<'a>` to
  `fn polars_series_get<'a>(series, index, out: *mut *mut polars_value_t<'a>) -> *const polars_error_t`,
  matching `gen_series_get!`'s `Ok`/`Err` -> `make_error` shape:
  ```rust
  pub unsafe extern "C" fn polars_series_get<'a>(
      series: *mut polars_series_t,
      index: usize,
      out: *mut *mut polars_value_t<'a>,
  ) -> *const polars_error_t {
      assert!(!series.is_null());
      let value = match (*series).inner.get(index) {
          Ok(v) => v,
          Err(err) => return make_error(err),
      };
      *out = Box::into_raw(Box::new(polars_value_t { inner: value }));
      std::ptr::null()
  }
  ```
- **Header** ([polars.h:919](c-polars/include/polars.h#L919)): update the prototype to
  `const struct polars_error_t *polars_series_get(struct polars_series_t *series, uintptr_t index, struct polars_value_t **out);`
- **API.jl** ([API.jl:1102-1104](src/API.jl#L1102-L1104)): update the ccall wrapper to the
  out-param + error-pointer shape, matching a neighboring fallible wrapper such as
  `polars_dataframe_get`.
- **Julia call sites** ([series.jl:42](src/series.jl#L42) and [:57](src/series.jl#L57), inside the
  `Date`/`DateTime`/`Duration` and `String`/`List`/`Struct`/`Binary` `getindex` methods): change
  ```julia
  value_at_index = Value{T}(polars_series_get(series, index), series)
  ```
  to
  ```julia
  out = Ref{Ptr{polars_value_t}}()
  err = polars_series_get(series, index, out)
  polars_error(err)
  value_at_index = Value{T}(out[], series)
  ```
- **Bundled minor fix**: [Polars.jl:65](src/Polars.jl#L65) — drop the `parent = nothing` default
  (every real call site already passes `parent` explicitly, so dropping the default is the smaller
  change vs. widening the field type).

### Item 2 (F2 fix) — make `polars_dataframe_show` propagate write errors
- **Rust** ([lib.rs:306-314](c-polars/src/lib.rs#L306-L314)): change the return type from `()` to
  `*const polars_error_t`, replacing `.expect(...)` with the same `if let Err(err) = ... { return
  make_error(err); }` shape used immediately above it by `write_parquet`/`write_csv`:
  ```rust
  pub unsafe extern "C" fn polars_dataframe_show(
      df: *mut polars_dataframe_t,
      user: *const c_void,
      callback: IOCallback,
  ) -> *const polars_error_t {
      let df = &(*df).inner;
      let mut w = UserIOCallback(callback, user);
      if let Err(err) = write!(w, "{df}") {
          return make_error(err);
      }
      std::ptr::null()
  }
  ```
- **Header** ([polars.h:195](c-polars/include/polars.h#L195)): update the prototype's return type
  to `const struct polars_error_t *`.
- **API.jl** ([API.jl:247-248](src/API.jl#L247-L248)): update the ccall return type from `::Cvoid`
  to `::Ptr{polars_error_t}`.
- No Julia call-site update needed beyond `API.jl` itself — confirmed no in-tree caller today (see
  Findings recap) — but keep the signature change since this is exported public API surface.

## Verification
Build (`cd c-polars && cargo build` — stable toolchain per `rust-toolchain`), then restart the
Julia session (the native `.so` reload requires a fresh session, not just re-running `using
Polars`) before exercising anything live:
- **F1**: `s = Series("x", [Date(2024,1,1)]); s[5]` should now raise a catchable Julia `error()`
  (polars' own out-of-bounds message) instead of crashing the process. Repeat for a `String`
  series and a list-valued (`Vector{Int}`) series to cover both `getindex` branches that call this
  function. Also re-check the *in-bounds* path still returns the correct value for each of Date,
  String, List, and Struct — that's the actual hot path, don't just test the crash case.
- **F2**: harder to trigger a genuine I/O failure through `_write_callback`; sufficient to confirm
  (a) the normal case (`Polars.API.polars_dataframe_show(df, Ref(IOBuffer()), callback)`) still
  prints correctly, and (b) the new signature compiles and type-checks end-to-end through
  `API.jl`. Not worth engineering an artificial I/O failure just to exercise the new error path —
  the goal is parity with `write_parquet`/`write_csv`'s already-tested error handling, not new
  coverage of a scenario nothing in-tree triggers.

## Tests
Add a case under wherever `Series` indexing is currently tested (likely `test/dataframe/` or
`test/operations/`) asserting an out-of-bounds index on a non-numeric `Series` raises a Julia
error rather than crashing. This is the regression test for F1, and the reason this bug shipped
silently in the first place — per `CLAUDE.md`, "this repo's existing test suite has gaps — whole
operations have shipped with zero coverage before."

## Suggested order
Item 1 (F1) first — it's the one with real user-facing blast radius (a segfault reachable from a
plain Julia index expression) and touches Rust + header + API.jl + two Julia call sites + a new
test. Item 2 (F2) second — smaller, lower urgency (no reachable caller in-tree today), no Julia
call-site changes needed.
