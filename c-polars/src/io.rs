use std::num::NonZeroUsize;
use std::sync::Arc;

use polars::io::ipc::IpcScanOptions;
use polars::prelude::*;
use polars_plan::dsl::sink::{SinkDestination, SinkTarget, UnifiedSinkArgs};
use polars_plan::dsl::{FileWriteFormat, MissingColumnsPolicy, UnifiedScanArgs};
use polars_utils::compression::{BrotliLevel, GzipLevel, ZstdLevel};
use polars_utils::slice_enum::Slice;

use crate::ffi_util::*;
use crate::types::*;
use crate::{guard_error, make_error, polars_error_t};

/// Builds `ParquetWriteOptions` from the primitive knobs shared by `write_parquet` and
/// `sink_parquet`. `compression_level` (null = unset) is only meaningful for the leveled
/// algorithms (gzip/brotli/zstd) -- passing one for an algorithm that doesn't support levels is
/// an error, matching py-polars' own validation instead of silently ignoring it.
pub(crate) unsafe fn build_parquet_write_options(
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
    let path = match read_str(path, pathlen) {
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
            *out = make_lazy_frame(lf);
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
    let path = match read_str(path, pathlen) {
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
    *out = make_lazy_frame(lf);
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
    let path = match read_str(path, pathlen) {
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
            *out = make_lazy_frame(lf);
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
    guard_error(|| {
        let path = match read_str(path, pathlen) {
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
        *out = make_lazy_frame(sunk);
        std::ptr::null()
    })
}

/// Builds `CsvWriterOptions` from the primitive knobs shared by `sink_csv` (write_csv builds a
/// `CsvWriter` directly instead -- see its own doc comment for why: `CsvWriter` has no
/// `.with_compression()`, only the sink pipeline's `CsvWriterOptions.compression` supports it).
#[allow(clippy::too_many_arguments)]
pub(crate) unsafe fn build_csv_writer_options(
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
pub(crate) unsafe fn build_ipc_writer_options(
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
    guard_error(|| {
        let path = match read_str(path, pathlen) {
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
        *out = make_lazy_frame(sunk);
        std::ptr::null()
    })
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
    guard_error(|| {
        let path = match read_str(path, pathlen) {
            Ok(p) => p,
            Err(err) => return make_error(err),
        };
        let options =
            match build_ipc_writer_options(compression, compression_level, record_batch_size) {
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
        *out = make_lazy_frame(sunk);
        std::ptr::null()
    })
}
