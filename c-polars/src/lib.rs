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
