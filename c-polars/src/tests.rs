//! Rust-side smoke tests for the C ABI surface.
//!
//! These are deliberately about *safety*, not feature coverage (that lives in the Julia suite):
//! every case here exercises a path that previously invoked undefined behaviour or aborted the
//! process. `cargo test` compiles the crate with the unit-test harness even though it is a
//! `cdylib`, so the `extern "C"` entry points are callable directly by their module paths.
#![allow(clippy::undocumented_unsafe_blocks)]

use std::ffi::c_void;

use polars::prelude::*;

use crate::dataframe::{
    polars_dataframe_lazy, polars_dataframe_show, polars_dataframe_size, polars_lazy_frame_collect,
    polars_lazy_frame_select,
};
use crate::expr::{polars_expr_col, polars_expr_sum_horizontal};
use crate::ffi_util::{read_bool_mask, read_exprs, read_names, read_opt_str, read_str};
use crate::types::*;
use crate::value::polars_value_type_t;
use crate::{guard_error, make_error, polars_error_message, polars_error_t};

/// A C-ABI write callback that appends into the `Vec<u8>` passed as `user`.
unsafe extern "C" fn collect_into_vec(user: *const c_void, data: *const u8, len: usize) -> isize {
    let buf = &mut *(user as *mut Vec<u8>);
    buf.extend_from_slice(std::slice::from_raw_parts(data, len));
    len as isize
}

unsafe fn error_message(err: *const polars_error_t) -> String {
    let mut data: *const u8 = std::ptr::null();
    let len = polars_error_message(err, &mut data);
    String::from_utf8_lossy(std::slice::from_raw_parts(data, len)).into_owned()
}

fn sample_frame() -> *mut polars_dataframe_t {
    let s = Column::new("x".into(), &[1i64, 2, 3]);
    make_dataframe(DataFrame::new(s.len(), vec![s]).unwrap())
}

#[test]
fn guard_error_turns_a_panic_into_an_error() {
    // The whole point of the panic guard: a panic inside must not unwind across `extern "C"`.
    let err = guard_error(|| panic!("boom from inside"));
    assert!(!err.is_null());
    unsafe {
        assert!(error_message(err).contains("boom from inside"));
        crate::polars_error_destroy(err);
    }

    // The success path passes its return value straight through.
    let ok = guard_error(std::ptr::null);
    assert!(ok.is_null());
}

#[test]
fn empty_slices_with_null_pointers_do_not_ub() {
    // `slice::from_raw_parts` requires a non-null aligned pointer even for len 0; the Julia side
    // may pass null/dangling for an empty list. These must short-circuit, not dereference.
    unsafe {
        assert!(read_exprs(std::ptr::null(), 0).is_empty());
        assert!(read_bool_mask(std::ptr::null(), 0).is_empty());
        assert_eq!(
            read_names(std::ptr::null(), std::ptr::null(), 0)
                .unwrap()
                .len(),
            0
        );
        assert_eq!(read_str(std::ptr::null(), 0).unwrap(), "");

        // ...and the same null/0 straight through a real entry point.
        let mut out: *const polars_expr_t = std::ptr::null();
        let err = polars_expr_sum_horizontal(std::ptr::null(), 0, true, &mut out);
        // polars rejects an empty horizontal fold -- but returns an error rather than crashing.
        assert!(!err.is_null());
        crate::polars_error_destroy(err);
    }
}

#[test]
fn read_str_rejects_invalid_utf8() {
    unsafe {
        let bad = [0xff_u8, 0xfe];
        assert!(read_str(bad.as_ptr(), bad.len()).is_err());
    }
}

#[test]
fn read_bool_mask_normalizes_non_0_1_bytes() {
    // Rust considers any byte other than 0/1 in a `bool` to be UB; `read_bool_mask` reads the
    // buffer as `u8` and normalizes via `!= 0` rather than reinterpreting it as `&[bool]`.
    unsafe {
        let bytes = [0u8, 1, 2, 255];
        let mask = read_bool_mask(bytes.as_ptr().cast::<bool>(), bytes.len());
        assert_eq!(mask, vec![false, true, true, true]);
    }
}

#[test]
fn read_opt_str_null_or_zero_len_is_none() {
    unsafe {
        assert_eq!(read_opt_str(std::ptr::null(), 0).unwrap(), None);
        let s = b"hi";
        assert_eq!(read_opt_str(s.as_ptr(), 0).unwrap(), None);
    }
}

#[test]
fn read_opt_str_rejects_invalid_utf8() {
    unsafe {
        let bad = [0xff_u8, 0xfe];
        assert!(read_opt_str(bad.as_ptr(), bad.len()).is_err());
    }
}

#[test]
fn to_dtype_is_fallible_for_unencodable_types() {
    use polars_value_type_t::*;

    // encodable: a plain type code round-trips
    for code in [
        PolarsValueTypeInt64,
        PolarsValueTypeFloat64,
        PolarsValueTypeString,
        PolarsValueTypeBinary,
        PolarsValueTypeDate,
        PolarsValueTypeTime,
    ] {
        assert!(code.to_dtype().is_ok(), "{code:?} should be encodable");
    }

    // unencodable: needs parameters this enum cannot carry -> error, not a silent Unknown cast
    for code in [
        PolarsValueTypeDatetime,
        PolarsValueTypeDuration,
        PolarsValueTypeList,
        PolarsValueTypeStruct,
        PolarsValueTypeUnknown,
    ] {
        assert!(
            code.to_dtype().is_err(),
            "{code:?} must not silently cast to Unknown"
        );
    }
}

#[test]
fn end_to_end_select_collect_through_the_c_abi() {
    unsafe {
        let df = sample_frame();
        let lf = polars_dataframe_lazy(df);

        let mut col: *const polars_expr_t = std::ptr::null();
        let err = polars_expr_col(b"x".as_ptr(), 1, &mut col);
        assert!(err.is_null());

        let exprs = [col];
        polars_lazy_frame_select(lf, exprs.as_ptr(), exprs.len());

        let mut out: *mut polars_dataframe_t = std::ptr::null_mut();
        let err = polars_lazy_frame_collect(lf, PolarsEngine::PolarsEngineInMemory, &mut out);
        assert!(err.is_null());

        let (mut rows, mut cols) = (0usize, 0usize);
        polars_dataframe_size(out, &mut rows, &mut cols);
        assert_eq!((rows, cols), (3, 1));

        crate::dataframe::polars_dataframe_destroy(df);
        crate::dataframe::polars_lazy_frame_destroy(lf);
        crate::dataframe::polars_dataframe_destroy(out);
        crate::expr::polars_expr_destroy(col);
    }
}

#[test]
fn write_callback_receives_the_full_output() {
    unsafe {
        let df = sample_frame();
        let mut buf: Vec<u8> = Vec::new();
        let err = polars_dataframe_show(
            df,
            &mut buf as *mut Vec<u8> as *const c_void,
            collect_into_vec,
        );
        assert!(err.is_null());
        // the Display of the frame must have reached the callback in full
        assert!(String::from_utf8_lossy(&buf).contains('x'));
        assert!(!buf.is_empty());
        crate::dataframe::polars_dataframe_destroy(df);
    }
}

#[test]
fn make_error_round_trips_through_the_accessor() {
    unsafe {
        let err = make_error("a specific message");
        assert_eq!(error_message(err), "a specific message");
        crate::polars_error_destroy(err);
    }
}
