#![allow(non_camel_case_types)]
#![allow(clippy::missing_safety_doc)]
// The hand-written `#[repr(C)]` enum mirrors (see CLAUDE.md's "Rust enums crossing the
// boundary" convention) all share one prefix per type by design, and their `to_*` conversion
// methods take `self` by value since these are small Copy-able marker types -- both trip
// idioms clippy expects from ordinary Rust enums.
#![allow(clippy::enum_variant_names)]
#![allow(clippy::wrong_self_convention)]

use std::ffi::c_void;
use std::io::Write;
use std::num::NonZeroUsize;
use std::sync::Arc;

use crate::value::{polars_closed_window_t, polars_label_t, polars_start_by_t};
use polars::io::ipc::IpcScanOptions;
use polars::prelude::*;
use polars_core::frame::PivotColumnNaming;
use polars_core::utils::{
    arrow::{
        self,
        array::StructArray,
        ffi::{self, ArrowArray, ArrowSchema},
    },
    rayon::iter::{self, ParallelIterator},
};
use polars_plan::dsl::sink::{SinkDestination, SinkTarget, UnifiedSinkArgs};
use polars_plan::dsl::{FileWriteFormat, MissingColumnsPolicy, UnifiedScanArgs};
use polars_plan::utils::expr_output_name;
use polars_utils::compression::{BrotliLevel, GzipLevel, ZstdLevel};
use polars_utils::slice_enum::Slice;

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
type IOCallback = unsafe extern "C" fn(user: *const c_void, data: *const u8, len: usize) -> isize;

pub struct polars_error_t {
    msg: String,
}

fn make_error<E: ToString>(err: E) -> *const polars_error_t {
    Box::into_raw(Box::new(polars_error_t {
        msg: err.to_string(),
    }))
}

/// Reads a `(ptrs, lens, n)` triple of UTF-8 byte slices into a `Vec<PlSmallStr>`, the shared
/// convention for passing plain column-name lists (as opposed to `Vec<Expr>`) across the C ABI.
unsafe fn read_names(
    ptrs: *const *const u8,
    lens: *const usize,
    n: usize,
) -> Result<Vec<PlSmallStr>, std::str::Utf8Error> {
    let ptrs = std::slice::from_raw_parts(ptrs, n);
    let lens = std::slice::from_raw_parts(lens, n);
    ptrs.iter()
        .zip(lens.iter())
        .map(|(&p, &len)| {
            std::str::from_utf8(std::slice::from_raw_parts(p, len)).map(PlSmallStr::from_str)
        })
        .collect()
}

/// Reads an optional `(ptr, len)` string: a null pointer (or zero length) means `None`, the
/// shared convention for optional strings across the C ABI (mirroring the nullable-pointer
/// convention already used for optional scalars, e.g. `polars_expr_sample_n`'s `seed`).
unsafe fn read_opt_str(
    ptr: *const u8,
    len: usize,
) -> Result<Option<PlSmallStr>, std::str::Utf8Error> {
    if ptr.is_null() || len == 0 {
        return Ok(None);
    }
    std::str::from_utf8(std::slice::from_raw_parts(ptr, len)).map(|s| Some(PlSmallStr::from_str(s)))
}

/// Builds a `Selector::ByName` from a name list, or `None` if the list is empty (matching the
/// "no subset specified" convention several LazyFrame methods use for `Option<Selector>`).
fn selector_by_name_opt(names: Vec<PlSmallStr>, strict: bool) -> Option<Selector> {
    if names.is_empty() {
        None
    } else {
        Some(Selector::ByName {
            names: names.into(),
            strict,
        })
    }
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
pub unsafe extern "C" fn polars_dataframe_new_from_carrow(
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
        arrow::datatypes::ArrowDataType::Struct(schema.iter_values().cloned().collect()),
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

#[repr(C)]
#[allow(dead_code)]
pub enum polars_csv_compression_t {
    PolarsCsvCompressionUncompressed,
    PolarsCsvCompressionGzip,
    PolarsCsvCompressionZstd,
}

impl polars_csv_compression_t {
    /// `compression_level` (null = unset) is only meaningful for gzip/zstd; ignored for
    /// uncompressed (matching `ExternalCompression`'s own shape -- unlike parquet's compression
    /// enum, there's no "level not supported for this algorithm" error case here since
    /// `Uncompressed` simply has no level field to set).
    fn to_external_compression(&self, level: Option<u32>) -> ExternalCompression {
        match self {
            Self::PolarsCsvCompressionUncompressed => ExternalCompression::Uncompressed,
            Self::PolarsCsvCompressionGzip => ExternalCompression::Gzip { level },
            Self::PolarsCsvCompressionZstd => ExternalCompression::Zstd { level },
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_ipc_compression_t {
    PolarsIpcCompressionUncompressed,
    PolarsIpcCompressionLz4,
    PolarsIpcCompressionZstd,
}

impl polars_ipc_compression_t {
    fn to_ipc_compression(&self, level: Option<i32>) -> PolarsResult<Option<IpcCompression>> {
        Ok(match self {
            Self::PolarsIpcCompressionUncompressed => None,
            Self::PolarsIpcCompressionLz4 => Some(IpcCompression::LZ4),
            Self::PolarsIpcCompressionZstd => Some(IpcCompression::ZSTD(
                level
                    .map(ZstdLevel::try_new)
                    .transpose()?
                    .unwrap_or_default(),
            )),
        })
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_quote_style_t {
    PolarsQuoteStyleNecessary,
    PolarsQuoteStyleAlways,
    PolarsQuoteStyleNonNumeric,
    PolarsQuoteStyleNever,
}

impl polars_quote_style_t {
    fn to_quote_style(&self) -> QuoteStyle {
        match self {
            Self::PolarsQuoteStyleNecessary => QuoteStyle::Necessary,
            Self::PolarsQuoteStyleAlways => QuoteStyle::Always,
            Self::PolarsQuoteStyleNonNumeric => QuoteStyle::NonNumeric,
            Self::PolarsQuoteStyleNever => QuoteStyle::Never,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_parquet_compression_t {
    PolarsParquetCompressionUncompressed,
    PolarsParquetCompressionSnappy,
    PolarsParquetCompressionGzip,
    PolarsParquetCompressionBrotli,
    PolarsParquetCompressionZstd,
    PolarsParquetCompressionLz4Raw,
}

/// Builds `ParquetWriteOptions` from the primitive knobs shared by `write_parquet` and
/// `sink_parquet`. `compression_level` (null = unset) is only meaningful for the leveled
/// algorithms (gzip/brotli/zstd) -- passing one for an algorithm that doesn't support levels is
/// an error, matching py-polars' own validation instead of silently ignoring it.
unsafe fn build_parquet_write_options(
    compression: polars_parquet_compression_t,
    compression_level: *const i32,
    statistics: bool,
    row_group_size: *const usize,
    data_page_size: *const usize,
) -> PolarsResult<ParquetWriteOptions> {
    use polars_parquet_compression_t::*;

    let level = compression_level.as_ref().copied();
    let no_level = |name: &str| -> PolarsResult<()> {
        if level.is_some() {
            return Err(PolarsError::InvalidOperation(
                format!("compression_level is not supported for {name} compression").into(),
            ));
        }
        Ok(())
    };

    let compression = match compression {
        PolarsParquetCompressionUncompressed => {
            no_level("uncompressed")?;
            ParquetCompression::Uncompressed
        }
        PolarsParquetCompressionSnappy => {
            no_level("snappy")?;
            ParquetCompression::Snappy
        }
        PolarsParquetCompressionLz4Raw => {
            no_level("lz4_raw")?;
            ParquetCompression::Lz4Raw
        }
        PolarsParquetCompressionGzip => {
            let level = level
                .map(|l| {
                    u8::try_from(l)
                        .map_err(|_| {
                            PolarsError::InvalidOperation(
                                format!("gzip compression_level must be between 0 and 9, got {l}")
                                    .into(),
                            )
                        })
                        .and_then(GzipLevel::try_new)
                })
                .transpose()?;
            ParquetCompression::Gzip(level)
        }
        PolarsParquetCompressionBrotli => {
            let level = level
                .map(|l| {
                    u32::try_from(l)
                        .map_err(|_| {
                            PolarsError::InvalidOperation(
                                format!(
                                    "brotli compression_level must be between 0 and 11, got {l}"
                                )
                                .into(),
                            )
                        })
                        .and_then(BrotliLevel::try_new)
                })
                .transpose()?;
            ParquetCompression::Brotli(level)
        }
        PolarsParquetCompressionZstd => {
            let level = level.map(ZstdLevel::try_new).transpose()?;
            ParquetCompression::Zstd(level)
        }
    };

    let statistics = if statistics {
        StatisticsOptions::default()
    } else {
        StatisticsOptions {
            min_value: false,
            max_value: false,
            distinct_count: false,
            null_count: false,
            binary_statistics_truncate_length: None,
        }
    };

    Ok(ParquetWriteOptions {
        compression,
        statistics,
        row_group_size: row_group_size.as_ref().copied(),
        data_page_size: data_page_size.as_ref().copied(),
        key_value_metadata: None,
        arrow_schema: None,
        compat_level: None,
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_write_parquet(
    df: *mut polars_dataframe_t,
    user: *const c_void,
    callback: IOCallback,
    compression: polars_parquet_compression_t,
    compression_level: *const i32,
    statistics: bool,
    row_group_size: *const usize,
    data_page_size: *const usize,
) -> *const polars_error_t {
    let options = match build_parquet_write_options(
        compression,
        compression_level,
        statistics,
        row_group_size,
        data_page_size,
    ) {
        Ok(options) => options,
        Err(err) => return make_error(err),
    };

    let df = &mut (*df).inner;
    let w = UserIOCallback(callback, user);
    if let Err(err) = ParquetWriter::new(w)
        .with_compression(options.compression)
        .with_statistics(options.statistics)
        .with_row_group_size(options.row_group_size)
        .with_data_page_size(options.data_page_size)
        .finish(df)
    {
        return make_error(err);
    }

    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_write_csv(
    df: *mut polars_dataframe_t,
    user: *const c_void,
    callback: IOCallback,
    include_header: bool,
    include_bom: bool,
    separator: u8,
    quote_char: u8,
    null_value: *const u8,
    null_value_len: usize,
    line_terminator: *const u8,
    line_terminator_len: usize,
    quote_style: polars_quote_style_t,
    date_format: *const u8,
    date_format_len: usize,
    time_format: *const u8,
    time_format_len: usize,
    datetime_format: *const u8,
    datetime_format_len: usize,
    float_precision: *const usize,
    decimal_comma: bool,
) -> *const polars_error_t {
    let df = &mut (*df).inner;

    let null_value = match read_opt_str(null_value, null_value_len) {
        Ok(v) => v,
        Err(err) => return make_error(err),
    };
    let line_terminator = match read_opt_str(line_terminator, line_terminator_len) {
        Ok(v) => v,
        Err(err) => return make_error(err),
    };
    let date_format = match read_opt_str(date_format, date_format_len) {
        Ok(v) => v,
        Err(err) => return make_error(err),
    };
    let time_format = match read_opt_str(time_format, time_format_len) {
        Ok(v) => v,
        Err(err) => return make_error(err),
    };
    let datetime_format = match read_opt_str(datetime_format, datetime_format_len) {
        Ok(v) => v,
        Err(err) => return make_error(err),
    };

    let w = UserIOCallback(callback, user);
    let mut writer = CsvWriter::new(w)
        .include_header(include_header)
        .include_bom(include_bom)
        .with_separator(separator)
        .with_quote_char(quote_char)
        .with_quote_style(quote_style.to_quote_style())
        .with_date_format(date_format)
        .with_time_format(time_format)
        .with_datetime_format(datetime_format)
        .with_float_precision(float_precision.as_ref().copied())
        .with_decimal_comma(decimal_comma);
    if let Some(null_value) = null_value {
        writer = writer.with_null_value(null_value);
    }
    if let Some(line_terminator) = line_terminator {
        writer = writer.with_line_terminator(line_terminator);
    }

    if let Err(err) = writer.finish(df) {
        return make_error(err);
    }

    std::ptr::null()
}

pub(crate) struct UserIOCallback(IOCallback, *const c_void);

impl std::io::Write for UserIOCallback {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let n = unsafe { self.0(self.1, buf.as_ptr(), buf.len()) };
        if n < 0 {
            Err(std::io::Error::other("user callback error"))
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
) -> *const polars_error_t {
    let df = &(*df).inner;
    let mut w = UserIOCallback(callback, user);
    if let Err(err) = write!(w, "{df}") {
        return make_error(err);
    }
    std::ptr::null()
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
pub unsafe extern "C" fn polars_dataframe_upsample(
    df: *mut polars_dataframe_t,
    by_names: *const *const u8,
    by_lens: *const usize,
    n_by: usize,
    time_column: *const u8,
    time_column_len: usize,
    every: *const u8,
    every_len: usize,
    stable: bool,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    let by = match read_names(by_names, by_lens, n_by) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let time_column =
        match std::str::from_utf8(std::slice::from_raw_parts(time_column, time_column_len)) {
            Ok(s) => s,
            Err(err) => return make_error(err),
        };
    let every_str = match std::str::from_utf8(std::slice::from_raw_parts(every, every_len)) {
        Ok(s) => s,
        Err(err) => return make_error(err),
    };
    let every = match Duration::try_parse(every_str) {
        Ok(d) => d,
        Err(err) => return make_error(err),
    };

    let result = if stable {
        (*df).inner.upsample_stable(by, time_column, every)
    } else {
        (*df).inner.upsample(by, time_column, every)
    };
    match result {
        Ok(result) => {
            *out = Box::into_raw(Box::new(polars_dataframe_t { inner: result }));
            std::ptr::null()
        }
        Err(err) => make_error(err),
    }
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

#[repr(C)]
#[allow(dead_code)]
pub enum polars_parquet_parallel_strategy_t {
    PolarsParquetParallelAuto,
    PolarsParquetParallelNone,
    PolarsParquetParallelColumns,
    PolarsParquetParallelRowGroups,
}

impl polars_parquet_parallel_strategy_t {
    fn to_parallel_strategy(&self) -> ParallelStrategy {
        match self {
            Self::PolarsParquetParallelAuto => ParallelStrategy::Auto,
            Self::PolarsParquetParallelNone => ParallelStrategy::None,
            Self::PolarsParquetParallelColumns => ParallelStrategy::Columns,
            Self::PolarsParquetParallelRowGroups => ParallelStrategy::RowGroups,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_scan_parquet(
    path: *const u8,
    pathlen: usize,
    n_rows: *const usize,
    row_index_name: *const u8,
    row_index_name_len: usize,
    row_index_offset: u32,
    parallel: polars_parquet_parallel_strategy_t,
    low_memory: bool,
    rechunk: bool,
    cache: bool,
    glob: bool,
    use_statistics: bool,
    allow_missing_columns: bool,
    include_file_paths: *const u8,
    include_file_paths_len: usize,
    hive_partitioning: *const bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let path = match std::str::from_utf8(std::slice::from_raw_parts(path, pathlen)) {
        Ok(p) => p,
        Err(err) => return make_error(err),
    };
    let row_index_name = match read_opt_str(row_index_name, row_index_name_len) {
        Ok(name) => name,
        Err(err) => return make_error(err),
    };
    let include_file_paths = match read_opt_str(include_file_paths, include_file_paths_len) {
        Ok(name) => name,
        Err(err) => return make_error(err),
    };

    let args = ScanArgsParquet {
        n_rows: n_rows.as_ref().copied(),
        parallel: parallel.to_parallel_strategy(),
        row_index: row_index_name.map(|name| RowIndex {
            name,
            offset: row_index_offset,
        }),
        cloud_options: None,
        hive_options: HiveOptions {
            enabled: hive_partitioning.as_ref().copied(),
            ..Default::default()
        },
        use_statistics,
        schema: None,
        low_memory,
        rechunk,
        cache,
        glob,
        include_file_paths,
        allow_missing_columns,
    };

    match LazyFrame::scan_parquet(PlRefPath::new(path), args) {
        Ok(lf) => {
            *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: lf }));
            std::ptr::null()
        }
        Err(err) => make_error(err),
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_scan_csv(
    path: *const u8,
    pathlen: usize,
    n_rows: *const usize,
    row_index_name: *const u8,
    row_index_name_len: usize,
    row_index_offset: u32,
    has_header: bool,
    separator: u8,
    quote_char: *const u8,
    comment_prefix: *const u8,
    comment_prefix_len: usize,
    skip_rows: usize,
    skip_rows_after_header: usize,
    null_value: *const u8,
    null_value_len: usize,
    missing_is_null: bool,
    truncate_ragged_lines: bool,
    try_parse_dates: bool,
    infer_schema_length: *const usize,
    ignore_errors: bool,
    low_memory: bool,
    rechunk: bool,
    cache: bool,
    glob: bool,
    include_file_paths: *const u8,
    include_file_paths_len: usize,
    allow_missing_columns: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let path = match std::str::from_utf8(std::slice::from_raw_parts(path, pathlen)) {
        Ok(p) => p,
        Err(err) => return make_error(err),
    };
    let row_index_name = match read_opt_str(row_index_name, row_index_name_len) {
        Ok(name) => name,
        Err(err) => return make_error(err),
    };
    let comment_prefix = match read_opt_str(comment_prefix, comment_prefix_len) {
        Ok(v) => v,
        Err(err) => return make_error(err),
    };
    let null_value = match read_opt_str(null_value, null_value_len) {
        Ok(v) => v,
        Err(err) => return make_error(err),
    };
    let include_file_paths = match read_opt_str(include_file_paths, include_file_paths_len) {
        Ok(name) => name,
        Err(err) => return make_error(err),
    };

    let reader = LazyCsvReader::new(PlRefPath::new(path))
        .with_n_rows(n_rows.as_ref().copied())
        .with_row_index(row_index_name.map(|name| RowIndex {
            name,
            offset: row_index_offset,
        }))
        .with_has_header(has_header)
        .with_separator(separator)
        .with_quote_char(quote_char.as_ref().copied())
        .with_comment_prefix(comment_prefix)
        .with_skip_rows(skip_rows)
        .with_skip_rows_after_header(skip_rows_after_header)
        .with_null_values(null_value.map(NullValues::AllColumnsSingle))
        .with_missing_is_null(missing_is_null)
        .with_truncate_ragged_lines(truncate_ragged_lines)
        .with_try_parse_dates(try_parse_dates)
        .with_infer_schema_length(infer_schema_length.as_ref().copied())
        .with_ignore_errors(ignore_errors)
        .with_low_memory(low_memory)
        .with_rechunk(rechunk)
        .with_cache(cache)
        .with_glob(glob)
        .with_include_file_paths(include_file_paths)
        .with_missing_columns_policy(Some(if allow_missing_columns {
            MissingColumnsPolicy::Insert
        } else {
            MissingColumnsPolicy::Raise
        }));

    let lf = match reader.finish() {
        Ok(lf) => lf,
        Err(err) => return make_error(err),
    };
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: lf }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_scan_ipc(
    path: *const u8,
    pathlen: usize,
    n_rows: *const usize,
    row_index_name: *const u8,
    row_index_name_len: usize,
    row_index_offset: u32,
    rechunk: bool,
    cache: bool,
    glob: bool,
    include_file_paths: *const u8,
    include_file_paths_len: usize,
    hive_partitioning: *const bool,
    allow_missing_columns: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let path = match std::str::from_utf8(std::slice::from_raw_parts(path, pathlen)) {
        Ok(p) => p,
        Err(err) => return make_error(err),
    };
    let row_index_name = match read_opt_str(row_index_name, row_index_name_len) {
        Ok(name) => name,
        Err(err) => return make_error(err),
    };
    let include_file_paths = match read_opt_str(include_file_paths, include_file_paths_len) {
        Ok(name) => name,
        Err(err) => return make_error(err),
    };

    let unified_scan_args = UnifiedScanArgs {
        hive_options: HiveOptions {
            enabled: hive_partitioning.as_ref().copied(),
            ..Default::default()
        },
        rechunk,
        cache,
        glob,
        row_index: row_index_name.map(|name| RowIndex {
            name,
            offset: row_index_offset,
        }),
        pre_slice: n_rows
            .as_ref()
            .map(|&len| Slice::Positive { offset: 0, len }),
        missing_columns_policy: if allow_missing_columns {
            MissingColumnsPolicy::Insert
        } else {
            MissingColumnsPolicy::Raise
        },
        include_file_paths,
        ..Default::default()
    };

    match LazyFrame::scan_ipc(
        PlRefPath::new(path),
        IpcScanOptions::default(),
        unified_scan_args,
    ) {
        Ok(lf) => {
            *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: lf }));
            std::ptr::null()
        }
        Err(err) => make_error(err),
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_sink_parquet(
    lf: *mut polars_lazy_frame_t,
    path: *const u8,
    pathlen: usize,
    compression: polars_parquet_compression_t,
    compression_level: *const i32,
    statistics: bool,
    row_group_size: *const usize,
    data_page_size: *const usize,
    mkdir: bool,
    maintain_order: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let path = match std::str::from_utf8(std::slice::from_raw_parts(path, pathlen)) {
        Ok(p) => p,
        Err(err) => return make_error(err),
    };
    let options = match build_parquet_write_options(
        compression,
        compression_level,
        statistics,
        row_group_size,
        data_page_size,
    ) {
        Ok(options) => options,
        Err(err) => return make_error(err),
    };
    let lf = (*lf).inner.clone();
    let sink_type = SinkDestination::File {
        target: SinkTarget::Path(PlRefPath::new(path)),
    };
    let file_format = FileWriteFormat::Parquet(Arc::new(options));
    let sink_args = UnifiedSinkArgs {
        mkdir,
        maintain_order,
        ..Default::default()
    };
    let sunk = match lf.sink(sink_type, file_format, sink_args) {
        Ok(sunk) => sunk,
        Err(err) => return make_error(err),
    };
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: sunk }));
    std::ptr::null()
}

/// Builds `CsvWriterOptions` from the primitive knobs shared by `sink_csv` (write_csv builds a
/// `CsvWriter` directly instead -- see its own doc comment for why: `CsvWriter` has no
/// `.with_compression()`, only the sink pipeline's `CsvWriterOptions.compression` supports it).
#[allow(clippy::too_many_arguments)]
unsafe fn build_csv_writer_options(
    include_header: bool,
    include_bom: bool,
    separator: u8,
    quote_char: u8,
    null_value: *const u8,
    null_value_len: usize,
    line_terminator: *const u8,
    line_terminator_len: usize,
    quote_style: polars_quote_style_t,
    date_format: *const u8,
    date_format_len: usize,
    time_format: *const u8,
    time_format_len: usize,
    datetime_format: *const u8,
    datetime_format_len: usize,
    float_precision: *const usize,
    decimal_comma: bool,
    compression: polars_csv_compression_t,
    compression_level: *const u32,
) -> PolarsResult<CsvWriterOptions> {
    let utf8_err = |e: std::str::Utf8Error| PolarsError::InvalidOperation(e.to_string().into());
    let null_value = read_opt_str(null_value, null_value_len).map_err(utf8_err)?;
    let line_terminator = read_opt_str(line_terminator, line_terminator_len).map_err(utf8_err)?;
    let date_format = read_opt_str(date_format, date_format_len).map_err(utf8_err)?;
    let time_format = read_opt_str(time_format, time_format_len).map_err(utf8_err)?;
    let datetime_format = read_opt_str(datetime_format, datetime_format_len).map_err(utf8_err)?;

    let serialize_options = SerializeOptions {
        date_format,
        time_format,
        datetime_format,
        float_scientific: None,
        float_precision: float_precision.as_ref().copied(),
        decimal_comma,
        separator,
        quote_char,
        null: null_value.unwrap_or_default(),
        line_terminator: line_terminator.unwrap_or_else(|| PlSmallStr::from_static("\n")),
        quote_style: quote_style.to_quote_style(),
    };

    Ok(CsvWriterOptions {
        include_bom,
        compression: compression.to_external_compression(compression_level.as_ref().copied()),
        check_extension: false,
        include_header,
        batch_size: NonZeroUsize::new(1024).unwrap(),
        serialize_options: Arc::new(serialize_options),
    })
}

/// Builds `IpcWriterOptions` from the primitive knobs shared by `write_ipc` (via
/// `IpcWriterOptions::to_writer`) and `sink_ipc`.
unsafe fn build_ipc_writer_options(
    compression: polars_ipc_compression_t,
    compression_level: *const i32,
    record_batch_size: *const usize,
) -> PolarsResult<IpcWriterOptions> {
    Ok(IpcWriterOptions {
        compression: compression.to_ipc_compression(compression_level.as_ref().copied())?,
        compat_level: CompatLevel::newest(),
        record_batch_size: record_batch_size.as_ref().copied(),
        record_batch_statistics: false,
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_write_ipc(
    df: *mut polars_dataframe_t,
    user: *const c_void,
    callback: IOCallback,
    compression: polars_ipc_compression_t,
    compression_level: *const i32,
    record_batch_size: *const usize,
) -> *const polars_error_t {
    let df = &mut (*df).inner;

    let options = match build_ipc_writer_options(compression, compression_level, record_batch_size)
    {
        Ok(options) => options,
        Err(err) => return make_error(err),
    };

    let w = UserIOCallback(callback, user);
    if let Err(err) = options.to_writer(w).finish(df) {
        return make_error(err);
    }

    std::ptr::null()
}

#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn polars_lazy_frame_sink_csv(
    lf: *mut polars_lazy_frame_t,
    path: *const u8,
    pathlen: usize,
    include_header: bool,
    include_bom: bool,
    separator: u8,
    quote_char: u8,
    null_value: *const u8,
    null_value_len: usize,
    line_terminator: *const u8,
    line_terminator_len: usize,
    quote_style: polars_quote_style_t,
    date_format: *const u8,
    date_format_len: usize,
    time_format: *const u8,
    time_format_len: usize,
    datetime_format: *const u8,
    datetime_format_len: usize,
    float_precision: *const usize,
    decimal_comma: bool,
    compression: polars_csv_compression_t,
    compression_level: *const u32,
    mkdir: bool,
    maintain_order: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let path = match std::str::from_utf8(std::slice::from_raw_parts(path, pathlen)) {
        Ok(p) => p,
        Err(err) => return make_error(err),
    };
    let options = match build_csv_writer_options(
        include_header,
        include_bom,
        separator,
        quote_char,
        null_value,
        null_value_len,
        line_terminator,
        line_terminator_len,
        quote_style,
        date_format,
        date_format_len,
        time_format,
        time_format_len,
        datetime_format,
        datetime_format_len,
        float_precision,
        decimal_comma,
        compression,
        compression_level,
    ) {
        Ok(options) => options,
        Err(err) => return make_error(err),
    };
    let lf = (*lf).inner.clone();
    let sink_type = SinkDestination::File {
        target: SinkTarget::Path(PlRefPath::new(path)),
    };
    let file_format = FileWriteFormat::Csv(options);
    let sink_args = UnifiedSinkArgs {
        mkdir,
        maintain_order,
        ..Default::default()
    };
    let sunk = match lf.sink(sink_type, file_format, sink_args) {
        Ok(sunk) => sunk,
        Err(err) => return make_error(err),
    };
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: sunk }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_sink_ipc(
    lf: *mut polars_lazy_frame_t,
    path: *const u8,
    pathlen: usize,
    compression: polars_ipc_compression_t,
    compression_level: *const i32,
    record_batch_size: *const usize,
    mkdir: bool,
    maintain_order: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let path = match std::str::from_utf8(std::slice::from_raw_parts(path, pathlen)) {
        Ok(p) => p,
        Err(err) => return make_error(err),
    };
    let options = match build_ipc_writer_options(compression, compression_level, record_batch_size)
    {
        Ok(options) => options,
        Err(err) => return make_error(err),
    };
    let lf = (*lf).inner.clone();
    let sink_type = SinkDestination::File {
        target: SinkTarget::Path(PlRefPath::new(path)),
    };
    let file_format = FileWriteFormat::Ipc(options);
    let sink_args = UnifiedSinkArgs {
        mkdir,
        maintain_order,
        ..Default::default()
    };
    let sunk = match lf.sink(sink_type, file_format, sink_args) {
        Ok(sunk) => sunk,
        Err(err) => return make_error(err),
    };
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: sunk }));
    std::ptr::null()
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
        arrow::datatypes::ArrowDataType::Struct(arrow_schema.iter_values().cloned().collect()),
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

    let every_str =
        std::str::from_utf8(std::slice::from_raw_parts(every, every_len)).unwrap_or_default();
    let period_str = if period_len == 0 {
        every_str
    } else {
        std::str::from_utf8(std::slice::from_raw_parts(period, period_len)).unwrap_or_default()
    };
    let offset_str =
        std::str::from_utf8(std::slice::from_raw_parts(offset, offset_len)).unwrap_or_default();

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

#[repr(C)]
#[allow(dead_code)]
pub enum polars_join_type_t {
    PolarsJoinTypeInner,
    PolarsJoinTypeLeft,
    PolarsJoinTypeRight,
    PolarsJoinTypeFull,
    PolarsJoinTypeSemi,
    PolarsJoinTypeAnti,
    PolarsJoinTypeCross,
}

impl polars_join_type_t {
    fn to_join_type(&self) -> JoinType {
        match self {
            polars_join_type_t::PolarsJoinTypeInner => JoinType::Inner,
            polars_join_type_t::PolarsJoinTypeLeft => JoinType::Left,
            polars_join_type_t::PolarsJoinTypeRight => JoinType::Right,
            polars_join_type_t::PolarsJoinTypeFull => JoinType::Full,
            polars_join_type_t::PolarsJoinTypeSemi => JoinType::Semi,
            polars_join_type_t::PolarsJoinTypeAnti => JoinType::Anti,
            polars_join_type_t::PolarsJoinTypeCross => JoinType::Cross,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_join(
    a: *mut polars_lazy_frame_t,
    b: *mut polars_lazy_frame_t,
    exprs_a: *const *const polars_expr_t,
    exprs_a_len: usize,
    exprs_b: *const *const polars_expr_t,
    exprs_b_len: usize,
    how: polars_join_type_t,
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
        JoinArgs::new(how.to_join_type()),
    );
    Box::into_raw(Box::new(polars_lazy_frame_t { inner: df }))
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_asof_strategy_t {
    PolarsAsofStrategyBackward,
    PolarsAsofStrategyForward,
    PolarsAsofStrategyNearest,
}

impl polars_asof_strategy_t {
    fn to_asof_strategy(&self) -> AsofStrategy {
        match self {
            polars_asof_strategy_t::PolarsAsofStrategyBackward => AsofStrategy::Backward,
            polars_asof_strategy_t::PolarsAsofStrategyForward => AsofStrategy::Forward,
            polars_asof_strategy_t::PolarsAsofStrategyNearest => AsofStrategy::Nearest,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_join_asof(
    a: *mut polars_lazy_frame_t,
    b: *mut polars_lazy_frame_t,
    on_a: *const polars_expr_t,
    on_b: *const polars_expr_t,
    by_a: *const *const u8,
    by_a_lens: *const usize,
    by_a_len: usize,
    by_b: *const *const u8,
    by_b_lens: *const usize,
    by_b_len: usize,
    strategy: polars_asof_strategy_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let left_by = match read_names(by_a, by_a_lens, by_a_len) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let right_by = match read_names(by_b, by_b_lens, by_b_len) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };

    let asof_options = AsOfOptions {
        strategy: strategy.to_asof_strategy(),
        tolerance: None,
        tolerance_str: None,
        left_by: if left_by.is_empty() {
            None
        } else {
            Some(left_by)
        },
        right_by: if right_by.is_empty() {
            None
        } else {
            Some(right_by)
        },
        allow_eq: true,
        check_sortedness: true,
    };

    let on_a = (*on_a).inner.clone();
    let on_b = (*on_b).inner.clone();
    let df = LazyFrame::join(
        (*a).inner.clone(),
        (*b).inner.clone(),
        vec![on_a],
        vec![on_b],
        JoinArgs::new(JoinType::AsOf(Box::new(asof_options))),
    );
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: df }));
    std::ptr::null()
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_unique_keep_t {
    PolarsUniqueKeepFirst,
    PolarsUniqueKeepLast,
    PolarsUniqueKeepNone,
    PolarsUniqueKeepAny,
}

impl polars_unique_keep_t {
    fn to_keep_strategy(&self) -> UniqueKeepStrategy {
        match self {
            polars_unique_keep_t::PolarsUniqueKeepFirst => UniqueKeepStrategy::First,
            polars_unique_keep_t::PolarsUniqueKeepLast => UniqueKeepStrategy::Last,
            polars_unique_keep_t::PolarsUniqueKeepNone => UniqueKeepStrategy::None,
            polars_unique_keep_t::PolarsUniqueKeepAny => UniqueKeepStrategy::Any,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_unique(
    lf: *mut polars_lazy_frame_t,
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    keep: polars_unique_keep_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let names = match read_names(names, lens, n) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let subset = selector_by_name_opt(names, true);
    let result = (*lf).inner.clone().unique(subset, keep.to_keep_strategy());
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: result }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_drop(
    lf: *mut polars_lazy_frame_t,
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let names = match read_names(names, lens, n) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let selector = Selector::ByName {
        names: names.into(),
        strict: true,
    };
    let result = (*lf).inner.clone().drop(selector);
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: result }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_rename(
    lf: *mut polars_lazy_frame_t,
    existing: *const *const u8,
    existing_lens: *const usize,
    new: *const *const u8,
    new_lens: *const usize,
    n: usize,
    strict: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let existing = match read_names(existing, existing_lens, n) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let new = match read_names(new, new_lens, n) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let result = (*lf).inner.clone().rename(existing, new, strict);
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: result }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_drop_nulls(
    lf: *mut polars_lazy_frame_t,
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let names = match read_names(names, lens, n) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let subset = selector_by_name_opt(names, true);
    let result = (*lf).inner.clone().drop_nulls(subset);
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: result }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_with_row_index(
    lf: *mut polars_lazy_frame_t,
    name: *const u8,
    name_len: usize,
    offset: i64,
    has_offset: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let name = match std::str::from_utf8(std::slice::from_raw_parts(name, name_len)) {
        Ok(name) => PlSmallStr::from_str(name),
        Err(err) => return make_error(err),
    };
    let offset = if has_offset {
        Some(offset as IdxSize)
    } else {
        None
    };
    let result = (*lf).inner.clone().with_row_index(name, offset);
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: result }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_explode(
    lf: *mut polars_lazy_frame_t,
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let names = match read_names(names, lens, n) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let selector = Selector::ByName {
        names: names.into(),
        strict: true,
    };
    let result = (*lf).inner.clone().explode(
        selector,
        ExplodeOptions {
            empty_as_null: true,
            keep_nulls: true,
        },
    );
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: result }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_unpivot(
    lf: *mut polars_lazy_frame_t,
    index_names: *const *const u8,
    index_lens: *const usize,
    n_index: usize,
    on_names: *const *const u8,
    on_lens: *const usize,
    n_on: usize,
    variable_name: *const u8,
    variable_name_len: usize,
    value_name: *const u8,
    value_name_len: usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let index_names = match read_names(index_names, index_lens, n_index) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let on_names = match read_names(on_names, on_lens, n_on) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let variable_name = if variable_name_len == 0 {
        None
    } else {
        match std::str::from_utf8(std::slice::from_raw_parts(variable_name, variable_name_len)) {
            Ok(s) => Some(PlSmallStr::from_str(s)),
            Err(err) => return make_error(err),
        }
    };
    let value_name = if value_name_len == 0 {
        None
    } else {
        match std::str::from_utf8(std::slice::from_raw_parts(value_name, value_name_len)) {
            Ok(s) => Some(PlSmallStr::from_str(s)),
            Err(err) => return make_error(err),
        }
    };

    let args = UnpivotArgsDSL {
        on: selector_by_name_opt(on_names, true),
        index: Selector::ByName {
            names: index_names.into(),
            strict: true,
        },
        variable_name,
        value_name,
    };
    let result = (*lf).inner.clone().unpivot(args);
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: result }));
    std::ptr::null()
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_pivot_column_naming_t {
    PolarsPivotColumnNamingCombine,
    PolarsPivotColumnNamingAuto,
}

impl polars_pivot_column_naming_t {
    fn to_pivot_column_naming(&self) -> PivotColumnNaming {
        match self {
            Self::PolarsPivotColumnNamingCombine => PivotColumnNaming::Combine,
            Self::PolarsPivotColumnNamingAuto => PivotColumnNaming::Auto,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_pivot(
    lf: *mut polars_lazy_frame_t,
    on_names: *const *const u8,
    on_lens: *const usize,
    n_on: usize,
    on_columns: *mut polars_dataframe_t,
    index_names: *const *const u8,
    index_lens: *const usize,
    n_index: usize,
    values_names: *const *const u8,
    values_lens: *const usize,
    n_values: usize,
    agg: *const polars_expr_t,
    maintain_order: bool,
    separator: *const u8,
    separator_len: usize,
    column_naming: polars_pivot_column_naming_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    let on_names = match read_names(on_names, on_lens, n_on) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let index_names = match read_names(index_names, index_lens, n_index) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let values_names = match read_names(values_names, values_lens, n_values) {
        Ok(names) => names,
        Err(err) => return make_error(err),
    };
    let separator = match std::str::from_utf8(std::slice::from_raw_parts(separator, separator_len))
    {
        Ok(s) => PlSmallStr::from_str(s),
        Err(err) => return make_error(err),
    };

    let on_columns = Arc::new((*on_columns).inner.clone());
    let agg = (*agg).inner.clone();
    let lf = (*lf).inner.clone();

    let result = lf.pivot(
        Selector::ByName {
            names: on_names.into(),
            strict: true,
        },
        on_columns,
        Selector::ByName {
            names: index_names.into(),
            strict: true,
        },
        Selector::ByName {
            names: values_names.into(),
            strict: true,
        },
        agg,
        maintain_order,
        separator,
        column_naming.to_pivot_column_naming(),
    );
    *out = Box::into_raw(Box::new(polars_lazy_frame_t { inner: result }));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_head(df: *mut polars_lazy_frame_t, n: usize) {
    let mut df = Box::from_raw(df);
    df.inner = df.inner.limit(n as IdxSize);
    std::mem::forget(df);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_tail(df: *mut polars_lazy_frame_t, n: usize) {
    let mut df = Box::from_raw(df);
    df.inner = df.inner.tail(n as IdxSize);
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
