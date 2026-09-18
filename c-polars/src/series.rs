use polars::prelude::*;
use polars_core::utils::arrow::ffi::{self, ArrowArray, ArrowSchema};

use crate::{guard_error, make_error, polars_error_t, types::*, value::polars_value_type_t};

pub(crate) fn make_series(series: Series) -> *mut polars_series_t {
    polars_series_t { inner: series }.into_handle()
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_destroy(series: *mut polars_series_t) {
    Opaque::destroy(series);
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_type(series: *mut polars_series_t) -> polars_value_type_t {
    polars_value_type_t::from_dtype((*series).inner.dtype())
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_length(series: *mut polars_series_t) -> usize {
    (*series).inner.len()
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_null_count(series: *mut polars_series_t) -> usize {
    (*series).inner.null_count()
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_schema(
    series: *mut polars_series_t,
    out: *mut ArrowSchema,
) -> *const polars_error_t {
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
/// must eventually invoke `.release` exactly once.
#[no_mangle]
pub unsafe extern "C" fn polars_series_export_carray(
    series: *mut polars_series_t,
    out: *mut ArrowArray,
) -> *const polars_error_t {
    guard_error(|| {
        let rechunked = (*series).inner.rechunk();
        let Some(chunk) = rechunked.chunks().first() else {
            return make_error("series has no chunks to export");
        };
        out.write(ffi::export_array_to_c(chunk.to_boxed()));
        std::ptr::null()
    })
}

/// Exports a dictionary-encoded (Categorical/Enum) series' data as a single Arrow C Data
/// Interface `ArrowArray`, collapsing the series to one chunk first if necessary -- like
/// `polars_series_export_carray`, but goes through `Series::to_arrow` (which honors the series'
/// logical dtype) instead of exporting the raw physical chunk directly. For a Categorical/Enum
/// series, the raw physical chunk is a plain integer index array with no dictionary attached, so
/// `polars_series_export_carray`'s `ArrowArray.dictionary` field comes back null even though
/// `polars_series_schema` correctly reports a dictionary-typed schema for the same column; this
/// function produces a genuine `DictionaryArray` whose `.dictionary` field is populated,
/// matching the schema. Errors if `series` is not Categorical/Enum-typed -- use
/// `polars_series_export_carray` for every other dtype.
#[no_mangle]
pub unsafe extern "C" fn polars_series_export_carray_dictionary(
    series: *mut polars_series_t,
    out: *mut ArrowArray,
) -> *const polars_error_t {
    guard_error(|| {
        match (*series).inner.dtype() {
            DataType::Categorical(_, _) | DataType::Enum(_, _) => {}
            other => {
                return make_error(format!(
                    "polars_series_export_carray_dictionary expects a Categorical/Enum series, got {other:?}"
                ));
            }
        }
        let rechunked = (*series).inner.rechunk();
        if rechunked.chunks().is_empty() {
            return make_error("series has no chunks to export");
        }
        let arr = rechunked.to_arrow(0, CompatLevel::newest());
        out.write(ffi::export_array_to_c(arr));
        std::ptr::null()
    })
}

/// Returns whether or not the value at index `index` is null, return false if the index is out of
/// bounds.
#[no_mangle]
pub unsafe extern "C" fn polars_series_is_null(series: *mut polars_series_t, index: usize) -> bool {
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
    make_series((*series).inner.slice(offset, length))
}

/// Borrowed pointer into the series' name, valid only as long as `series` is alive.
#[no_mangle]
pub unsafe extern "C" fn polars_series_name(
    series: *mut polars_series_t,
    out: *mut *const u8,
) -> usize {
    let name = (*series).inner.name();
    *out = name.as_ptr();
    name.len()
}

#[no_mangle]
pub unsafe extern "C" fn polars_series_get(
    series: *mut polars_series_t,
    index: usize,
    out: *mut *mut polars_value_t,
) -> *const polars_error_t {
    guard_error(|| {
        let value = tri!((*series).inner.get(index));
        *out = make_value(value);
        std::ptr::null()
    })
}

macro_rules! gen_series_get {
    ($n: ident, $t: ident, $rt: ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            series: *mut polars_series_t,
            index: usize,
            out: *mut $t,
        ) -> *const polars_error_t {
            guard_error(|| match (*series).inner.get(index) {
                Ok(AnyValue::$rt(value)) => {
                    *out = value;
                    std::ptr::null()
                }
                // Reached both when the element's dtype is not `$rt` and when it is null (the
                // Julia side checks `polars_series_is_null` first, so the latter is a direct-ABI
                // caller's path) -- name both the expectation and what was actually there.
                Ok(other) => make_error(format!(
                    "expected a {} value at index {index}, got {:?}",
                    stringify!($rt),
                    other
                )),
                Err(err) => make_error(err),
            })
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
