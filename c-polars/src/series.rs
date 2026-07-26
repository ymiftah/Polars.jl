use polars::prelude::*;
use polars_core::utils::arrow::ffi::{self, ArrowArray, ArrowSchema};

use crate::{guard_error, make_error, polars_error_t, types::*, value::polars_value_type_t};

pub(crate) fn make_series(series: Series) -> *mut polars_series_t {
    Box::into_raw(Box::new(polars_series_t { inner: series }))
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_destroy(series: *mut polars_series_t) {
    assert!(!series.is_null());
    let _ = Box::from_raw(series);
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_type(series: *mut polars_series_t) -> polars_value_type_t {
    assert!(!series.is_null());
    polars_value_type_t::from_dtype((*series).inner.dtype())
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_length(series: *mut polars_series_t) -> usize {
    assert!(!series.is_null());
    (*series).inner.len()
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_null_count(series: *mut polars_series_t) -> usize {
    assert!(!series.is_null());
    (*series).inner.null_count()
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_schema(
    series: *mut polars_series_t,
    out: *mut ArrowSchema,
) -> *const polars_error_t {
    assert!(!series.is_null());
    guard_error(|| {
        out.write(ffi::export_field_to_c(
            &(*series).inner.field().to_arrow(CompatLevel::newest()),
        ));
        std::ptr::null()
    })
}

/// Exports the series' data as a single Arrow C Data Interface `ArrowArray`, collapsing the
/// series to one chunk first if necessary. The returned `ArrowArray` is self-contained (owns its
/// buffers via the release callback) and can outlive `series` -- the caller takes ownership and
/// must eventually invoke `.release` (directly or via a Julia-side keeper/finalizer) exactly
/// once.
///
/// `rechunk()` is a cheap Arc-clone when `series` is already single-chunk (the common case), but
/// a genuinely fragmented series (many small chunks, e.g. after repeated `concat`/streaming
/// appends without an explicit rechunk) pays a real one-time data copy here to produce the single
/// contiguous chunk the C Data Interface export needs.
#[no_mangle]
pub unsafe extern "C" fn polars_series_export_carray(
    series: *mut polars_series_t,
    out: *mut ArrowArray,
) -> *const polars_error_t {
    assert!(!series.is_null());
    guard_error(|| {
        let rechunked = (*series).inner.rechunk();
        let Some(chunk) = rechunked.chunks().first() else {
            return make_error("series has no chunks to export");
        };
        out.write(ffi::export_array_to_c(chunk.to_boxed()));
        std::ptr::null()
    })
}

/// Returns whether or not the value at index `index` is null, return false if the index is out of
/// bounds.
#[no_mangle]
pub unsafe extern "C" fn polars_series_is_null(series: *mut polars_series_t, index: usize) -> bool {
    assert!(!series.is_null());
    match (*series).inner.get(index) {
        Ok(AnyValue::Null) => true,
        Ok(_) => false,
        Err(_) => false,
    }
}

/// Returns a new owned series holding a zero-copy (Arc-refcount clone) slice of `length` elements
/// starting at `offset`.
#[no_mangle]
pub unsafe extern "C" fn polars_series_slice(
    series: *mut polars_series_t,
    offset: i64,
    length: usize,
) -> *mut polars_series_t {
    assert!(!series.is_null());
    make_series((*series).inner.slice(offset, length))
}

/// Borrowed pointer into the series' name, valid only as long as `series` is alive (the same
/// borrowed-pointer convention `polars_value_time_zone` cites this function as the reference for).
#[no_mangle]
pub unsafe extern "C" fn polars_series_name(
    series: *mut polars_series_t,
    out: *mut *const u8,
) -> usize {
    assert!(!series.is_null());
    let name = (*series).inner.name();
    *out = name.as_ptr();
    name.len()
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_get<'a>(
    series: *mut polars_series_t,
    index: usize,
    out: *mut *mut polars_value_t<'a>,
) -> *const polars_error_t {
    assert!(!series.is_null());
    let value = tri!((*series).inner.get(index));
    *out = Box::into_raw(Box::new(polars_value_t { inner: value }));
    std::ptr::null()
}

macro_rules! gen_series_get {
    ($n: ident, $t: ident, $rt: ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            series: *mut polars_series_t,
            index: usize,
            out: *mut $t,
        ) -> *const polars_error_t {
            assert!(!series.is_null());
            match (*series).inner.get(index) {
                Ok(AnyValue::$rt(value)) => {
                    *out = value;
                    std::ptr::null()
                }
                Ok(_) => make_error("series type is invalid"),
                Err(err) => make_error(err),
            }
        }
    };
}

gen_series_get!(polars_series_get_bool, bool, Boolean);
gen_series_get!(polars_series_get_u8, u8, UInt8);
gen_series_get!(polars_series_get_u16, u16, UInt16);
gen_series_get!(polars_series_get_u32, u32, UInt32);
gen_series_get!(polars_series_get_u64, u64, UInt64);
gen_series_get!(polars_series_get_i8, i8, Int8);
gen_series_get!(polars_series_get_i16, i16, Int16);
gen_series_get!(polars_series_get_i32, i32, Int32);
gen_series_get!(polars_series_get_i64, i64, Int64);
gen_series_get!(polars_series_get_f32, f32, Float32);
gen_series_get!(polars_series_get_f64, f64, Float64);
