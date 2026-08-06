//! # Ownership conventions
//!
//! Handles (`polars_dataframe_t`, `polars_lazy_frame_t`, `polars_expr_t`, ...) are opaque
//! `Box`-allocated pointers; the caller owns every handle it receives and frees it with the
//! matching `*_destroy`. Three shapes, applied consistently by category:
//!
//! - **Constructors** (`scan_parquet`, `group_by`, `clone`, `unique`, `drop`, ...) return a
//!   *fresh* handle -- directly when infallible, else via an `out` param with a
//!   `*const polars_error_t` return. Inputs are only read/cloned, never consumed.
//! - **In-place mutators** (`select`, `with_columns`, `sort`, `filter`, `head`, `tail`) mutate
//!   `(*handle).inner` through `&mut` and return void. They are deliberately *not* out-param
//!   constructors: the Julia wrapper clones first (`select(df) = _select!(clone(df), ...)`), so
//!   no caller ever observes the mutation and the value-semantics live one layer up. Handles
//!   never alias -- each mutator replaces `inner` wholesale, so a `polars_lazy_frame_clone`d
//!   sibling is unaffected.
//! - **Destructors** (`*_destroy`) reclaim the `Box` and drop it.
//!
//! Note that argument handles are always borrowed, never consumed: `polars_lazy_frame_filter`
//! clones the `Expr` it is given, and the caller still owns (and must destroy) that `Expr`.
//!
//! One further category takes `&mut (*handle).inner` without being an in-place mutator in the
//! sense above: `polars_dataframe_write_parquet`/`write_csv`/`write_ipc`. Upstream's writers take
//! `&mut DataFrame` and align/rechunk it as they serialize, so writing a frame can change its
//! *representation* (chunk layout) even though its value is untouched. No caller observes a
//! different result, but the handle is genuinely mutated -- it is not a read-only borrow.
//!
//! # C ABI trust boundary
//!
//! Every `#[repr(C)]` enum crossing this boundary is passed/returned by value and matched against
//! its declared variants. Rust considers an out-of-range discriminant (or a `bool` byte other than
//! `0`/`1`) to be undefined behavior *before* any `match` runs, so the Julia side is the single
//! source of truth for these values: the `@cenum` mirrors in `src/api/generated.jl` are generated
//! from `include/polars.h`, and callers must only ever pass in-range discriminants. Boolean *masks*
//! read from caller memory (e.g. `descending` arrays) are read as bytes and normalized rather than
//! reinterpreted as `&[bool]` (see `ffi_util::read_bool_mask`) precisely to avoid that UB.
//!
//! Handle pointers (`*const`/`*mut polars_foo_t`) are non-null, and **this is unchecked**: every
//! entry point dereferences its handle arguments directly, so passing null is undefined behavior,
//! not a reportable error. A `debug_assert`-style null trap is deliberately *not* used here -- it
//! would fire on well under half the surface, and a failed assertion aborts the process across
//! `extern "C"` anyway (see `guard_error`, which the destructors and the infallible entry points
//! do not run inside), so it neither enforces the contract nor degrades gracefully. The Julia
//! wrapper is the layer that guarantees non-null, via one finalizer-owned handle per object.
//!
//! Individual arguments *may* be nullable where a function's own doc says so -- optional scalars
//! (`sample_n`'s `seed`, `fill_null_with_strategy`'s `limit`, every `*const usize`/`*const i32`
//! knob in `io.rs`), optional handles (`replace_strict`'s `default`, `over`'s `order_by`,
//! `cloud_options`), and optional strings (null pointer or zero length; see
//! `ffi_util::read_opt_str`). That set is large and grows with the API, so each function documents
//! its own rather than this list trying to stay exhaustive: if a pointer's own doc does not call it
//! optional, it must be non-null.
#![allow(non_camel_case_types)]
#![allow(clippy::missing_safety_doc)]
// The hand-written `#[repr(C)]` enum mirrors (see CLAUDE.md's "Rust enums crossing the
// boundary" convention) all share one prefix per type by design, and their `to_*` conversion
// methods take `self` by value since these are small Copy-able marker types -- both trip
// idioms clippy expects from ordinary Rust enums.
#![allow(clippy::enum_variant_names)]
#![allow(clippy::wrong_self_convention)]

/// Unwraps a `Result`, or early-returns a boxed `polars_error_t` from the enclosing function
/// (or `guard_error` closure) on `Err` -- both return `*const polars_error_t`, so the same
/// `return make_error(err)` is valid in either context. Collapses the ~58 hand-written
/// `match read_str(...) { Ok(v) => v, Err(err) => return make_error(err) }` blocks across
/// `dataframe`/`expr`/`io`. Defined here, before the `mod` declarations, so textual macro
/// scoping makes it visible in every submodule; uses `$crate::make_error` for hygiene.
macro_rules! tri {
    ($e:expr) => {
        match $e {
            Ok(v) => v,
            Err(err) => return $crate::make_error(err),
        }
    };
}

mod dataframe;
mod expr;
mod ffi_util;
mod io;
mod series;
mod types;
mod value;

#[cfg(test)]
mod tests;

use types::Opaque;

#[no_mangle]
pub unsafe extern "C" fn polars_version(out: *mut *const u8) -> usize {
    let v = polars::VERSION;
    if !out.is_null() {
        *out = v.as_ptr();
    }
    v.len()
}

pub struct polars_error_t {
    msg: String,
}

impl types::Opaque for polars_error_t {}

fn make_error<E: ToString>(err: E) -> *const polars_error_t {
    polars_error_t {
        msg: err.to_string(),
    }
    .into_handle()
    .cast_const()
}

/// Runs `f`, converting a Rust panic into a `polars_error_t` instead of letting it unwind across
/// the `extern "C"` boundary (which aborts the whole host process). Upstream polars still
/// `panic!`s for some feature-gated / codec paths (see CLAUDE.md), and this turns those into a
/// catchable error on the Julia side rather than a hard crash.
///
/// **Every entry point returning `*const polars_error_t` is wrapped in this** -- the rule is the
/// signature, not a per-function judgement about which upstream calls look risky. `catch_unwind`
/// costs nothing when nothing panics, so there is no reason to spend judgement here, and a rule
/// stated as "wherever a panic seems likely" is not one anybody can check. `check_panic_guards.py`
/// enforces the signature rule in CI.
///
/// What this *cannot* cover is the entry points with no error channel: those returning a handle,
/// `usize`, `bool`, or a `#[repr(C)]` enum by value, plus the void in-place mutators. A panic in
/// any of those still aborts the host process. That is why `polars_value_type_t::from_any_value`
/// and `polars_value_list_type` guard `AnyValue::dtype()`'s known Categorical/Enum panic by hand:
/// both return an enum by value, so there is nothing to report an error through. Giving such a
/// function an error channel is an ABI change -- until then, an operation known to be able to
/// panic must not be exposed through an infallible signature.
pub(crate) fn guard_error<F>(f: F) -> *const polars_error_t
where
    F: FnOnce() -> *const polars_error_t,
{
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(ret) => ret,
        Err(payload) => {
            let msg = payload
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| payload.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "unknown cause".to_string());
            make_error(format!("internal panic in polars: {msg}"))
        }
    }
}

/// Borrowed pointer into the error's message, valid only as long as `err` is alive.
#[no_mangle]
pub unsafe extern "C" fn polars_error_message(
    err: *const polars_error_t,
    data: *mut *const u8,
) -> usize {
    let str = &(*err).msg;
    let len = str.len();

    *data = str.as_ptr();
    len
}

#[no_mangle]
pub unsafe extern "C" fn polars_error_destroy(err: *const polars_error_t) {
    Opaque::destroy(err.cast_mut());
}
