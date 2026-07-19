//! Rust-side smoke tests for the C ABI surface.
//!
//! These are deliberately about *safety*, not feature coverage (that lives in the Julia suite):
//! every case here exercises a path that previously invoked undefined behaviour or aborted the
//! process. `cargo test` compiles the crate with the unit-test harness even though it is a
//! `cdylib`, so the `extern "C"` entry points are callable directly by their module paths.
#![allow(clippy::undocumented_unsafe_blocks)]

use std::ffi::c_void;

use polars::prelude::*;
use polars_core::utils::arrow::ffi::{ArrowArray, ArrowSchema};

use crate::dataframe::{
    polars_dataframe_lazy, polars_dataframe_show, polars_dataframe_size, polars_lazy_frame_collect,
    polars_lazy_frame_select,
};
use crate::expr::{polars_expr_col, polars_expr_sum_horizontal};
use crate::ffi_util::{
    read_bool_mask, read_exprs, read_names, read_opt_str, read_str, UserIOCallback,
};
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
        let err = polars_lazy_frame_collect(lf, polars_engine_t::PolarsEngineInMemory, &mut out);
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

#[test]
fn read_str_accepts_valid_multi_byte_utf8() {
    // The historical bug class here was byte-length *truncation* for non-ASCII input (a caller
    // passing a character count instead of a byte count) -- `read_opt_str_rejects_invalid_utf8`
    // above only covers outright invalid bytes, not a correctly-encoded multi-byte string.
    unsafe {
        let s = "café 日本語 π_test";
        assert_eq!(read_str(s.as_ptr(), s.len()).unwrap(), s);
    }
}

unsafe extern "C" fn always_fails(_user: *const c_void, _data: *const u8, _len: usize) -> isize {
    -1
}

unsafe extern "C" fn claims_an_overlong_write(
    _user: *const c_void,
    _data: *const u8,
    _len: usize,
) -> isize {
    isize::MAX
}

#[test]
fn user_io_callback_propagates_a_negative_return_as_an_error() {
    use std::io::Write;
    let mut cb = UserIOCallback(always_fails, std::ptr::null());
    let err = cb.write(b"hello").unwrap_err();
    assert!(err.to_string().contains("user callback error"));
}

#[test]
fn user_io_callback_rejects_an_overlong_reported_write() {
    // A callback claiming to have written more than it was given violates `Write`'s contract; the
    // adapter must reject this rather than returning an out-of-range write count that could
    // desynchronize the caller (e.g. `write_all`'s internal bookkeeping).
    use std::io::Write;
    let mut cb = UserIOCallback(claims_an_overlong_write, std::ptr::null());
    let err = cb.write(b"hello").unwrap_err();
    assert!(err.to_string().contains("longer than the buffer"));
}

#[test]
fn export_carray_and_schema_handle_a_multi_chunk_series() {
    // `polars_series_export_carray` rechunks internally (see its doc comment) -- exercise that
    // path for real with a genuinely multi-chunk series, not just the common single-chunk case
    // the Julia-side read tests already cover extensively.
    unsafe {
        let mut s = Series::new("x".into(), &[1i64, 2, 3]);
        s.append(&Series::new("x".into(), &[4i64, 5])).unwrap();
        assert!(
            s.n_chunks() > 1,
            "test setup must produce a genuinely multi-chunk series"
        );
        let ptr = crate::series::make_series(s);

        let mut schema_out = std::mem::MaybeUninit::<ArrowSchema>::uninit();
        let err = crate::series::polars_series_schema(ptr, schema_out.as_mut_ptr());
        assert!(err.is_null());
        drop(schema_out.assume_init()); // `ArrowSchema: Drop` invokes the release callback

        let mut array_out = std::mem::MaybeUninit::<ArrowArray>::uninit();
        let err = crate::series::polars_series_export_carray(ptr, array_out.as_mut_ptr());
        assert!(err.is_null());
        drop(array_out.assume_init()); // `ArrowArray: Drop` invokes the release callback

        crate::series::polars_series_destroy(ptr);
    }
}

#[test]
fn scanning_and_collecting_a_malformed_file_returns_an_error_not_a_crash() {
    // `scan_parquet` itself only builds a lazy DSL scan node -- confirmed empirically (this test
    // originally asserted `scan_parquet` itself would error on bad content, and that assertion
    // failed: it returns `Ok` for any path, valid or not). The actual file read/validation is
    // deferred to schema resolution inside `collect`, which already carries `guard_error` from an
    // earlier hardening pass. This test exercises the real user-facing property: the full
    // scan-then-collect pipeline on a malformed file surfaces a clean `PolarsError`, not a crash.
    // `guard_error` was still extended to `scan_parquet`/`scan_csv`/`scan_ipc` themselves as
    // defense-in-depth for whatever those builder chains *do* resolve eagerly (e.g. hive/cloud
    // options), even though plain file-content validation isn't part of that for parquet.
    unsafe {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "polars_jl_malformed_test_{}_{}.parquet",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::write(&path, b"this is not a real parquet file").unwrap();
        let path_str = path.to_str().unwrap();

        let mut lf: *mut polars_lazy_frame_t = std::ptr::null_mut();
        let err = crate::io::polars_lazy_frame_scan_parquet(
            path_str.as_ptr(),
            path_str.len(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            0,
            polars_parquet_parallel_strategy_t::PolarsParquetParallelAuto,
            false,
            false,
            false,
            false,
            false,
            false,
            std::ptr::null(),
            0,
            std::ptr::null(),
            &mut lf,
        );
        assert!(err.is_null(), "scan_parquet itself is purely lazy plan construction and must not error on file content");

        let mut out: *mut polars_dataframe_t = std::ptr::null_mut();
        let err = polars_lazy_frame_collect(lf, polars_engine_t::PolarsEngineInMemory, &mut out);
        assert!(
            !err.is_null(),
            "collecting a scan of a malformed parquet file must produce an error, not silently succeed"
        );
        crate::polars_error_destroy(err);

        crate::dataframe::polars_lazy_frame_destroy(lf);
        let _ = std::fs::remove_file(&path);
    }
}
