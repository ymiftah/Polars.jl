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
//! Handle pointers (`*const`/`*mut polars_foo_t`) are non-null unless a function's own doc
//! explicitly says otherwise -- e.g. `replace_strict`'s `default` handle and `sample_n`/
//! `sample_frac`'s `seed` pointer are the documented exceptions, where null means "argument
//! omitted". A null handle passed anywhere else is caller error, not a supported "optional" input.
//! The scattered `assert!(!x.is_null())` calls are a best-effort debug trap on that contract, not
//! an enforced one -- most call sites dereference the pointer directly with no check at all, and
//! even where an assert is present, a failed assertion still unwinds and aborts the process across
//! `extern "C"` just like any other panic (see `guard_error` below for where that unwind is
//! caught; the assert sites are not wrapped in it and so are not currently recoverable).
#![allow(non_camel_case_types)]
#![allow(clippy::missing_safety_doc)]
// The hand-written `#[repr(C)]` enum mirrors (see CLAUDE.md's "Rust enums crossing the
// boundary" convention) all share one prefix per type by design, and their `to_*` conversion
// methods take `self` by value since these are small Copy-able marker types -- both trip
// idioms clippy expects from ordinary Rust enums.
#![allow(clippy::enum_variant_names)]
#![allow(clippy::wrong_self_convention)]

mod dataframe;
mod expr;
mod ffi_util;
mod io;
mod series;
mod types;
mod value;

#[cfg(test)]
mod tests;

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

fn make_error<E: ToString>(err: E) -> *const polars_error_t {
    Box::into_raw(Box::new(polars_error_t {
        msg: err.to_string(),
    }))
}

/// Runs `f`, converting a Rust panic into a `polars_error_t` instead of letting it unwind across
/// the `extern "C"` boundary (which aborts the whole host process). Wrap the fallible entry points
/// where a panic can realistically originate -- query *execution* (`collect`, `sink_*`, `write_*`):
/// upstream polars still `panic!`s for some feature-gated / codec paths (see CLAUDE.md), and this
/// turns those into a catchable error on the Julia side rather than a hard crash.
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

/// Borrowed pointer into the error's message, valid only as long as `err` is alive (same
/// convention as `polars_series_name`).
#[no_mangle]
pub unsafe extern "C" fn polars_error_message(
    err: *const polars_error_t,
    data: *mut *const u8,
) -> usize {
    assert!(!err.is_null());
    assert!(!data.is_null());

    let str = &(*err).msg;
    let len = str.len();

    *data = str.as_ptr();
    len
}

#[no_mangle]
pub unsafe extern "C" fn polars_error_destroy(err: *const polars_error_t) {
    assert!(!err.is_null());
    let _ = Box::from_raw(err.cast_mut());
}
