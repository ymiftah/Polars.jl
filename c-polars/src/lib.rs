#![allow(non_camel_case_types)]
#![allow(clippy::missing_safety_doc)]

use std::ffi::c_void;
use std::io::Write;

use polars::prelude::*;
use polars_core::utils::{
    arrow::{
        self,
        array::StructArray,
        ffi::{self, ArrowArray, ArrowSchema},
    },
    rayon::iter::{self, ParallelIterator},
};
use polars_plan::utils::expr_output_name;
use crate::value::{polars_closed_window_t, polars_label_t, polars_start_by_t};

mod expr;
mod series;
mod value;

#[no_mangle]
pub unsafe extern "C" fn polars_version(out: *mut *const u8) -> usize {
    let v = polars::VERSION;
    if !out.is_null() {
        *out = v.as_ptr();
    }
    v.len()
}

/// The callback provided for display functions, returns -1 on error.
type IOCallback =
    unsafe extern "C" fn(user: *const c_void, data: *const u8, len: usize) -> isize;

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
    return len;
}

#[no_mangle]
pub unsafe extern "C" fn polars_error_destroy(err: *const polars_error_t) {
    assert!(!err.is_null());
    let _ = Box::from_raw(err.cast_mut());
}

// TODO: investigate what the lifetime implies.
pub struct polars_value_t<'a> {
    inner: AnyValue<'a>,
}

pub struct polars_dataframe_t {
    inner: DataFrame,
}

pub struct polars_lazy_frame_t {
    inner: LazyFrame,
}

pub struct polars_lazy_group_by_t {
    inner: LazyGroupBy,
}

pub struct polars_series_t {
    inner: Series,
}

pub struct polars_expr_t {
    inner: Expr,
}

fn make_dataframe(df: DataFrame) -> *mut polars_dataframe_t {
    Box::into_raw(Box::new(polars_dataframe_t { inner: df }))
}

#[no_mangle]
pub fn polars_dataframe_new() -> *mut polars_dataframe_t {
    make_dataframe(DataFrame::empty())
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_size(
    df: *mut polars_dataframe_t,
    rows: *mut usize,
    cols: *mut usize,
) {
    let df = &(*df).inner;
    *rows = df.height();
    *cols = df.width();
}

/// Creates a DataFrame from a series of ArrowArray and ArrowSchema compatible the arrow C-ABI.
///
/// # Safety
/// The field array should be valid ArrowSchema according to the C Data Interface.
/// The array array should be valid ArrowArray according to the C Data Interface,
/// this means that the memory ownership is transferred in the created arrow::Array.
/// Therefore, the caller should *not* free the underlying memories for this arrow as this
/// will be done through the release field of the array.
///
/// Returns null if something went wrong.
#[no_mangle]
pub extern "C" fn polars_dataframe_new_from_carrow(
    cfield: *const ArrowSchema,
    carray: ArrowArray,
) -> *mut polars_dataframe_t {
    // Safety: the field ptr is expected to be a valid pointer to an ArrowSchema according to
    // the C Data interface.
    let Ok(field) = (unsafe { ffi::import_field_from_c(&*cfield) }) else {
        return std::ptr::null_mut();
    };

    // Safety: carray will not be destroyed at the end of the function since import_array_from_c
    // takes ownership of it. Therefore, it should be destroyed once the dataframe is destroyed
    // using polars_dataframe_destroy.
    let Ok(array) = (unsafe { ffi::import_array_from_c(carray, field.dtype.clone()) }) else {
        return std::ptr::null_mut();
    };

    let Some(sarray) = array.as_any().downcast_ref::<StructArray>() else {
        // caller is expected to provide a struct array (encoding +s) with field
        // being the columns.
        return std::ptr::null_mut();
    };

    let Ok(df) = DataFrame::try_from(sarray.clone()) else {
        return std::ptr::null_mut();
    };

    make_dataframe(df)
}

/// Returns a ArrowSchema describing the dataframe's schema according to Arrow C Data interface.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_schema(df: *mut polars_dataframe_t) -> ArrowSchema {
    let schema = (*df).inner.schema().to_arrow(CompatLevel::newest());
    let structfield = arrow::datatypes::Field::new(
        "polars.dataframe".into(),
        arrow::datatypes::ArrowDataType::Struct(schema.iter_values().map(|c| c.clone()).collect()),
        false,
    );
    ffi::export_field_to_c(&structfield)
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_new_from_series(
    series: *const *mut polars_series_t,
    nseries: usize,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    let slice: &[*mut polars_series_t] = std::slice::from_raw_parts(series, nseries);
    let series: Vec<Column> = slice
        .iter()
        .enumerate()
        .map(|(i, s)| Column::new(format!("column_{i}").into(), (**s).inner.clone()))
        .collect();
    let height = series.first().map_or(0, |s| s.len());
    let df = match DataFrame::new(height, series) {
        Ok(df) => df,
        Err(err) => return make_error(err),
    };
    *out = make_dataframe(df);
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_destroy(df: *mut polars_dataframe_t) {
    let _ = Box::from_raw(df);
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_write_parquet(
    df: *mut polars_dataframe_t,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    let df = &mut (*df).inner;

    let w = UserIOCallback(callback, user);
    if let Err(err) = ParquetWriter::new(w).finish(df) {
        return make_error(err);
    }

    std::ptr::null()
}

#[no_mangle]
pub extern "C" fn polars_dataframe_read_parquet(
    path: *const u8,
    pathlen: usize,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    let path = unsafe { std::slice::from_raw_parts(path, pathlen) };
    let path = match std::str::from_utf8(path) {
        Ok(path) => path,
        Err(err) => return make_error(err),
    };

    let file = match std::fs::OpenOptions::new().read(true).open(path) {
        Ok(file) => file,
        Err(err) => return make_error(err),
    };

    match ParquetReader::new(file).finish() {
        Ok(df) => unsafe {
            *out = make_dataframe(df);
        },
        Err(err) => return make_error(err),
    }

    std::ptr::null()
}

pub(crate) struct UserIOCallback(IOCallback, *const c_void);

impl std::io::Write for UserIOCallback {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let n = unsafe { self.0(self.1, buf.as_ptr(), buf.len()) };
        if n < 0 {
            Err(std::io::Error::new(
                std::io::ErrorKind::Other,
                "user callback error",
            ))
        } else {
            Ok(n as usize)
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_show(
    df: *mut polars_dataframe_t,
    user: *const c_void,
    callback: IOCallback,
) {
    let df = &(*df).inner;
    let mut w = UserIOCallback(callback, user);
    write!(w, "{df}").expect("failed to show dataframe");
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_get(
    df: *mut polars_dataframe_t,
    name: *const u8,
    len: usize,
    out: *mut *mut polars_series_t,
) -> *const polars_error_t {
    let name = unsafe { std::slice::from_raw_parts(name, len) };
    let name = match std::str::from_utf8(name) {
        Ok(path) => path,
        Err(err) => return make_error(err),
    };

    let df = &(*df).inner;
    let column = match df.column(name) {
        Ok(column) => column,
        Err(err) => return make_error(err),
    };

    *out = series::make_series(column.as_materialized_series().clone());

    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_lazy(
    df: *mut polars_dataframe_t,
) -> *mut polars_lazy_frame_t {
    let df = &(*df).inner;
    Box::into_raw(Box::new(polars_lazy_frame_t {
        inner: df.clone().lazy(),
    }))
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_destroy(df: *mut polars_lazy_frame_t) {
    assert!(!df.is_null());
    let _ = Box::from_raw(df);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_clone(
    df: *mut polars_lazy_frame_t,
) -> *mut polars_lazy_frame_t {
    assert!(!df.is_null());
    Box::into_raw(Box::new(polars_lazy_frame_t {
        inner: (*df).inner.clone(),
    }))
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_scan_parquet(
    path: *const u8,
    pathlen: usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let path = match std::str::from_utf8(std::slice::from_raw_parts(path, pathlen)) {
        Ok(p) => p,
        Err(err) => return make_error(err),
    };

    match LazyFrame::scan_parquet(PlRefPath::new(path), ScanArgsParquet::default()) {
        Ok(lf) => {
            *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: lf }));
            std::ptr::null()
        }
        Err(err) => make_error(err),
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_sort(
    df: *mut polars_lazy_frame_t,
    exprs: *const *const polars_expr_t,
    nexprs: usize,
    descending: *const bool,
    nulls_last: bool,
    maintain_order: bool,
) {
    let exprs: Vec<Expr> = std::slice::from_raw_parts(exprs, nexprs)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();
    let descending = std::slice::from_raw_parts(descending, nexprs);
    let mut df = Box::from_raw(df);
    df.inner = df.inner.sort_by_exprs(
        &exprs,
        SortMultipleOptions {
            descending: descending.to_owned(),
            nulls_last: iter::repeat(nulls_last).take(descending.len()).collect(),
            maintain_order,
            multithreaded: true,
            limit: None,
        },
    );
    std::mem::forget(df);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_concat(
    lfs: *const *mut polars_lazy_frame_t,
    n: usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let frames: Vec<LazyFrame> = (0..n).map(|i| (**lfs.add(i)).inner.clone()).collect();

    let df = match concat(&frames, UnionArgs::default()) {
        Ok(df) => df,
        Err(err) => return make_error(err),
    };
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: df }));

    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_with_columns(
    df: *mut polars_lazy_frame_t,
    exprs: *const *const polars_expr_t,
    nexprs: usize,
) {
    let exprs: Vec<Expr> = std::slice::from_raw_parts(exprs, nexprs)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();
    let mut df = Box::from_raw(df);
    df.inner = df.inner.with_columns(&exprs);
    std::mem::forget(df);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_select(
    df: *mut polars_lazy_frame_t,
    exprs: *const *const polars_expr_t,
    nexprs: usize,
) {
    let exprs: Vec<Expr> = std::slice::from_raw_parts(exprs, nexprs)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();
    let mut df = Box::from_raw(df);
    df.inner = df.inner.select(&exprs);
    std::mem::forget(df);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_filter(
    df: *mut polars_lazy_frame_t,
    expr: *const polars_expr_t,
) {
    assert!(!df.is_null());
    assert!(!expr.is_null());
    let mut df = Box::from_raw(df);
    df.inner = df.inner.filter((*expr).inner.clone()); // NOTE: we clone the expr here, can we assume
                                                       // that the function takes ownership of it?
    std::mem::forget(df);
}

#[repr(C)]
pub enum PolarsEngine {
    PolarsEngineInMemory,
    PolarsEngineStreaming,
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_collect(
    df: *mut polars_lazy_frame_t,
    engine: PolarsEngine,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    let df = (*df).inner.clone();
    let engine = match engine {
        PolarsEngine::PolarsEngineInMemory => Engine::InMemory,
        PolarsEngine::PolarsEngineStreaming => Engine::Streaming,
    };
    *out = make_dataframe(match df.collect_with_engine(engine) {
        Ok(value) => value.unwrap_single(),
        Err(err) => return make_error(err),
    });
    std::ptr::null()
}

/// Resolves the lazy frame's schema (without collecting it) and returns it as an ArrowSchema
/// according to the Arrow C Data interface, matching the shape of `polars_dataframe_schema`.
#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_collect_schema(
    df: *mut polars_lazy_frame_t,
    out: *mut ArrowSchema,
) -> *const polars_error_t {
    let mut df = (*df).inner.clone();
    let schema = match df.collect_schema() {
        Ok(schema) => schema,
        Err(err) => return make_error(err),
    };
    let arrow_schema = schema.to_arrow(CompatLevel::newest());
    let structfield = arrow::datatypes::Field::new(
        "polars.dataframe".into(),
        arrow::datatypes::ArrowDataType::Struct(arrow_schema.iter_values().map(|c| c.clone()).collect()),
        false,
    );
    *out = ffi::export_field_to_c(&structfield);
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_group_by(
    df: *mut polars_lazy_frame_t,
    exprs: *const *const polars_expr_t,
    nexprs: usize,
) -> *mut polars_lazy_group_by_t {
    let exprs: Vec<Expr> = std::slice::from_raw_parts(exprs, nexprs)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();
    let gb = (*df).inner.clone().group_by(&exprs);
    Box::into_raw(Box::new(polars_lazy_group_by_t { inner: gb }))
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_group_by_dynamic(
    df: *mut polars_lazy_frame_t,
    index_expr: *const polars_expr_t,
    group_by_exprs: *const *const polars_expr_t,
    n_group_by: usize,
    every: *const u8,
    every_len: usize,
    period: *const u8,
    period_len: usize,
    offset: *const u8,
    offset_len: usize,
    label: polars_label_t,
    include_boundaries: bool,
    closed_window: polars_closed_window_t,
    start_by: polars_start_by_t,
    out: *mut *mut polars_lazy_group_by_t,
) -> *const polars_error_t {
    let group_by: Vec<Expr> = std::slice::from_raw_parts(group_by_exprs, n_group_by)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();

    let every_str = std::str::from_utf8(std::slice::from_raw_parts(every, every_len))
        .unwrap_or_default();
    let period_str = if period_len == 0 {
        every_str
    } else {
        std::str::from_utf8(std::slice::from_raw_parts(period, period_len)).unwrap_or_default()
    };
    let offset_str = std::str::from_utf8(std::slice::from_raw_parts(offset, offset_len))
        .unwrap_or_default();

    let every = match Duration::try_parse(every_str) {
        Ok(d) => d,
        Err(err) => return make_error(err),
    };
    let period = match Duration::try_parse(period_str) {
        Ok(d) => d,
        Err(err) => return make_error(err),
    };
    let offset = match Duration::try_parse(offset_str) {
        Ok(d) => d,
        Err(err) => return make_error(err),
    };

    let index_col_name = match expr_output_name(&(*index_expr).inner) {
        Ok(name) => name,
        Err(err) => return make_error(err),
    };

    let opts = DynamicGroupOptions {
        index_column: index_col_name,
        every,
        period,
        offset,
        label: label.to_label(),
        include_boundaries,
        closed_window: closed_window.to_closed_window(),
        start_by: start_by.to_start_by(),
    };

    let gb = (*df)
        .inner
        .clone()
        .group_by_dynamic((*index_expr).inner.clone(), &group_by, opts);
    *out = Box::into_raw(Box::new(polars_lazy_group_by_t { inner: gb }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_rolling(
    df: *mut polars_lazy_frame_t,
    index_expr: *const polars_expr_t,
    group_by_exprs: *const *const polars_expr_t,
    n_group_by: usize,
    period: *const u8,
    period_len: usize,
    offset: *const u8,
    offset_len: usize,
    closed_window: polars_closed_window_t,
    out: *mut *mut polars_lazy_group_by_t,
) -> *const polars_error_t {
    let group_by: Vec<Expr> = std::slice::from_raw_parts(group_by_exprs, n_group_by)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();

    let period_str =
        std::str::from_utf8(std::slice::from_raw_parts(period, period_len)).unwrap_or_default();
    let offset_str =
        std::str::from_utf8(std::slice::from_raw_parts(offset, offset_len)).unwrap_or_default();

    let period = match Duration::try_parse(period_str) {
        Ok(d) => d,
        Err(err) => return make_error(err),
    };
    let offset = match Duration::try_parse(offset_str) {
        Ok(d) => d,
        Err(err) => return make_error(err),
    };

    let index_col_name = match expr_output_name(&(*index_expr).inner) {
        Ok(name) => name,
        Err(err) => return make_error(err),
    };

    let opts = RollingGroupOptions {
        index_column: index_col_name,
        period,
        offset,
        closed_window: closed_window.to_closed_window(),
    };

    let gb = (*df)
        .inner
        .clone()
        .rolling((*index_expr).inner.clone(), &group_by, opts);
    *out = Box::into_raw(Box::new(polars_lazy_group_by_t { inner: gb }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_join_inner(
    a: *mut polars_lazy_frame_t,
    b: *mut polars_lazy_frame_t,
    exprs_a: *const *const polars_expr_t,
    exprs_a_len: usize,
    exprs_b: *const *const polars_expr_t,
    exprs_b_len: usize,
) -> *mut polars_lazy_frame_t {
    let exprs_a: Vec<Expr> = std::slice::from_raw_parts(exprs_a, exprs_a_len)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();
    let exprs_b: Vec<Expr> = std::slice::from_raw_parts(exprs_b, exprs_b_len)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();
    let df = LazyFrame::join(
        (*a).inner.clone(),
        (*b).inner.clone(),
        exprs_a,
        exprs_b,
        JoinArgs::new(JoinType::Inner),
    );
    Box::into_raw(Box::new(polars_lazy_frame_t { inner: df }))
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_head(df: *mut polars_lazy_frame_t, n: usize) {
    let mut df = Box::from_raw(df);
    df.inner = df.inner.limit(n as IdxSize);
    std::mem::forget(df);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_group_by_destroy(gb: *const polars_lazy_group_by_t) {
    assert!(!gb.is_null());
    let _ = Box::from_raw(gb.cast_mut());
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_group_by_agg(
    gb: *mut polars_lazy_group_by_t,
    exprs: *const *const polars_expr_t,
    nexprs: usize,
) -> *mut polars_lazy_frame_t {
    let exprs: Vec<Expr> = std::slice::from_raw_parts(exprs, nexprs)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();
    Box::into_raw(Box::new(polars_lazy_frame_t {
        inner: (*gb).inner.clone().agg(&exprs),
    }))
}
