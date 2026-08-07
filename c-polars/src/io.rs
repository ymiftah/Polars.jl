use std::num::NonZeroUsize;
use std::sync::Arc;

use polars::io::cloud::CloudOptions;
use polars::io::ipc::IpcScanOptions;
use polars::prelude::*;
use polars_plan::dsl::sink::{PartitionStrategy, SinkDestination, SinkTarget, UnifiedSinkArgs};
use polars_plan::dsl::{FileWriteFormat, MissingColumnsPolicy, UnifiedScanArgs};
use polars_utils::compression::{BrotliLevel, GzipLevel, ZstdLevel};
use polars_utils::pl_path::CloudScheme;
use polars_utils::slice_enum::Slice;

use crate::ffi_util::*;
use crate::types::*;
use crate::{guard_error, make_error, polars_error_t};

/// `CsvWriterOptions::batch_size`, a fixed internal chunking knob this wrapper doesn't expose as
/// a user-facing option. `1024` is a compile-time-checked non-zero constant, so this can never
/// actually panic -- a plain `const` avoids a `.unwrap()` that reads as fallible but isn't.
const CSV_WRITER_BATCH_SIZE: NonZeroUsize = NonZeroUsize::new(1024).unwrap();

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
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    // `LazyFrame::scan_parquet` only builds a lazy DSL scan node (confirmed empirically in
    // `tests.rs`'s `scanning_and_collecting_a_malformed_file_returns_an_error_not_a_crash`: it
    // returns `Ok` even for a garbage-content path) -- the actual file read/validation is
    // deferred to schema resolution inside `collect`/`collect_schema`, which already carry
    // `guard_error` from an earlier hardening pass. This function is still guarded as
    // defense-in-depth: unlike a plain `col()`/`select()`-style DSL constructor, it *does*
    // resolve `hive_partitioning`/path arguments eagerly, and upstream's scan-builder chain is
    // less audited for panic-freedom than the simple expression constructors.
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let row_index_name = tri!(read_opt_str(row_index_name, row_index_name_len));
        let include_file_paths = tri!(read_opt_str(include_file_paths, include_file_paths_len));
        let cloud_options = tri!(resolve_cloud_options(path, cloud_options));

        let args = ScanArgsParquet {
            n_rows: n_rows.as_ref().copied(),
            parallel: parallel.to_parallel_strategy(),
            row_index: row_index_name.map(|name| RowIndex {
                name,
                offset: row_index_offset,
            }),
            cloud_options,
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
    })
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
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    // See the matching comment on `polars_lazy_frame_scan_parquet` above: `reader.finish()` is
    // also purely lazy DSL node construction (no file content is read yet), but is guarded as
    // defense-in-depth the same way.
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let row_index_name = tri!(read_opt_str(row_index_name, row_index_name_len));
        let comment_prefix = tri!(read_opt_str(comment_prefix, comment_prefix_len));
        let null_value = tri!(read_opt_str(null_value, null_value_len));
        let include_file_paths = tri!(read_opt_str(include_file_paths, include_file_paths_len));
        let cloud_options = tri!(resolve_cloud_options(path, cloud_options));

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
            }))
            .with_cloud_options(cloud_options);

        let lf = tri!(reader.finish());
        *out = make_lazy_frame(lf);
        std::ptr::null()
    })
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
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    // See the matching comment on `polars_lazy_frame_scan_parquet` above: `scan_ipc` is also
    // purely lazy DSL node construction, but is guarded as defense-in-depth the same way.
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let row_index_name = tri!(read_opt_str(row_index_name, row_index_name_len));
        let include_file_paths = tri!(read_opt_str(include_file_paths, include_file_paths_len));
        let cloud_options = tri!(resolve_cloud_options(path, cloud_options));

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
            cloud_options,
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
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_scan_ndjson(
    path: *const u8,
    pathlen: usize,
    n_rows: *const usize,
    row_index_name: *const u8,
    row_index_name_len: usize,
    row_index_offset: u32,
    infer_schema_length: *const usize,
    ignore_errors: bool,
    low_memory: bool,
    rechunk: bool,
    include_file_paths: *const u8,
    include_file_paths_len: usize,
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    // See the matching comment on `polars_lazy_frame_scan_parquet` above: `reader.finish()` is
    // also purely lazy DSL node construction, but is guarded as defense-in-depth the same way.
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let row_index_name = tri!(read_opt_str(row_index_name, row_index_name_len));
        let include_file_paths = tri!(read_opt_str(include_file_paths, include_file_paths_len));
        let cloud_options = tri!(resolve_cloud_options(path, cloud_options));
        let infer_schema_length = match infer_schema_length.as_ref().copied() {
            Some(n) => Some(tri!(NonZeroUsize::new(n).ok_or_else(|| {
                PolarsError::InvalidOperation("infer_schema_length must be positive".into())
            }))),
            None => None,
        };

        let reader = LazyJsonLineReader::new(PlRefPath::new(path))
            .with_n_rows(n_rows.as_ref().copied())
            .with_row_index(row_index_name.map(|name| RowIndex {
                name,
                offset: row_index_offset,
            }))
            .with_infer_schema_length(infer_schema_length)
            .with_ignore_errors(ignore_errors)
            .low_memory(low_memory)
            .with_rechunk(rechunk)
            .with_include_file_paths(include_file_paths)
            .with_cloud_options(cloud_options);

        let lf = tri!(reader.finish());
        *out = make_lazy_frame(lf);
        std::ptr::null()
    })
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
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let options = tri!(build_parquet_write_options(
            compression,
            compression_level,
            statistics,
            row_group_size,
            data_page_size,
        ));
        let cloud_options = tri!(resolve_cloud_options(path, cloud_options));
        let lf = (*lf).inner.clone();
        let sink_type = SinkDestination::File {
            target: SinkTarget::Path(PlRefPath::new(path)),
        };
        let file_format = FileWriteFormat::Parquet(Arc::new(options));
        let sink_args = UnifiedSinkArgs {
            mkdir,
            maintain_order,
            cloud_options: cloud_options.map(Arc::new),
            ..Default::default()
        };
        let sunk = tri!(lf.sink(sink_type, file_format, sink_args));
        *out = make_lazy_frame(sunk);
        std::ptr::null()
    })
}

#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn polars_lazy_frame_sink_parquet_partitioned(
    lf: *mut polars_lazy_frame_t,
    base_path: *const u8,
    base_pathlen: usize,
    keys: *const *const polars_expr_t,
    n_keys: usize,
    include_keys: bool,
    max_rows_per_file: *const u64,
    approximate_bytes_per_file: *const u64,
    compression: polars_parquet_compression_t,
    compression_level: *const i32,
    statistics: bool,
    row_group_size: *const usize,
    data_page_size: *const usize,
    maintain_order: bool,
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let base_path = tri!(read_str(base_path, base_pathlen));
        let keys = read_exprs(keys, n_keys);
        if keys.is_empty() {
            return make_error(PolarsError::InvalidOperation(
                "sink_parquet partitioned by keys requires at least one key".into(),
            ));
        }
        let options = tri!(build_parquet_write_options(
            compression,
            compression_level,
            statistics,
            row_group_size,
            data_page_size,
        ));
        let cloud_options = tri!(resolve_cloud_options(base_path, cloud_options));

        let max_rows_per_file = match max_rows_per_file.as_ref() {
            Some(&n) => tri!(
                IdxSize::try_from(n).map_err(|_| PolarsError::InvalidOperation(
                    format!("max_rows_per_file {n} exceeds the maximum representable row count")
                        .into()
                ))
            ),
            None => 0,
        };
        let approximate_bytes_per_file = approximate_bytes_per_file.as_ref().copied().unwrap_or(0);

        let lf = (*lf).inner.clone();
        let sink_type = SinkDestination::Partitioned {
            base_path: PlRefPath::new(base_path),
            file_path_provider: None,
            partition_strategy: PartitionStrategy::Keyed {
                keys,
                include_keys,
                keys_pre_grouped: false,
            },
            max_rows_per_file,
            approximate_bytes_per_file,
        };
        let file_format = FileWriteFormat::Parquet(Arc::new(options));
        let sink_args = UnifiedSinkArgs {
            // `mkdir` has no effect on partitioned sinks -- the partitioned file provider always
            // recursively creates each partition's parent directory regardless of this flag
            // (confirmed in polars-stream's `FileProvider::open_file`), so there is nothing
            // meaningful to thread through here.
            mkdir: false,
            maintain_order,
            cloud_options: cloud_options.map(Arc::new),
            ..Default::default()
        };
        let sunk = tri!(lf.sink(sink_type, file_format, sink_args));
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
        batch_size: CSV_WRITER_BATCH_SIZE,
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
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let options = tri!(build_csv_writer_options(
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
        ));
        let cloud_options = tri!(resolve_cloud_options(path, cloud_options));
        let lf = (*lf).inner.clone();
        let sink_type = SinkDestination::File {
            target: SinkTarget::Path(PlRefPath::new(path)),
        };
        let file_format = FileWriteFormat::Csv(options);
        let sink_args = UnifiedSinkArgs {
            mkdir,
            maintain_order,
            cloud_options: cloud_options.map(Arc::new),
            ..Default::default()
        };
        let sunk = tri!(lf.sink(sink_type, file_format, sink_args));
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
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let options = tri!(build_ipc_writer_options(
            compression,
            compression_level,
            record_batch_size
        ));
        let cloud_options = tri!(resolve_cloud_options(path, cloud_options));
        let lf = (*lf).inner.clone();
        let sink_type = SinkDestination::File {
            target: SinkTarget::Path(PlRefPath::new(path)),
        };
        let file_format = FileWriteFormat::Ipc(options);
        let sink_args = UnifiedSinkArgs {
            mkdir,
            maintain_order,
            cloud_options: cloud_options.map(Arc::new),
            ..Default::default()
        };
        let sunk = tri!(lf.sink(sink_type, file_format, sink_args));
        *out = make_lazy_frame(sunk);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_sink_ndjson(
    lf: *mut polars_lazy_frame_t,
    path: *const u8,
    pathlen: usize,
    mkdir: bool,
    maintain_order: bool,
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let cloud_options = tri!(resolve_cloud_options(path, cloud_options));
        let lf = (*lf).inner.clone();
        let sink_type = SinkDestination::File {
            target: SinkTarget::Path(PlRefPath::new(path)),
        };
        let file_format = FileWriteFormat::NDJson(NDJsonWriterOptions::default());
        let sink_args = UnifiedSinkArgs {
            mkdir,
            maintain_order,
            cloud_options: cloud_options.map(Arc::new),
            ..Default::default()
        };
        let sunk = tri!(lf.sink(sink_type, file_format, sink_args));
        *out = make_lazy_frame(sunk);
        std::ptr::null()
    })
}

/// Resolves a (possibly null) `polars_cloud_options_t` handle into a real `CloudOptions`, given
/// the destination `path`. `CloudOptions` cannot be constructed without knowing the target cloud
/// scheme, which is why the handle only stores unparsed key/value pairs (see its own doc comment
/// in `types.rs`) -- resolution happens here, per call, once `path` is available. A null handle
/// (the common case: no `storage_options` given) yields `None`, which is what every scan/sink
/// function expects when no cloud configuration applies.
unsafe fn resolve_cloud_options(
    path: &str,
    cloud_options: *const polars_cloud_options_t,
) -> PolarsResult<Option<CloudOptions>> {
    if cloud_options.is_null() {
        Ok(None)
    } else {
        Ok(Some(CloudOptions::from_untyped_config(
            CloudScheme::from_path(path),
            (*cloud_options).pairs.iter().cloned(),
        )?))
    }
}

/// Builds a `polars_cloud_options_t` from parallel `(ptr-array, len-array, n)` key/value pairs --
/// e.g. `("aws_access_key_id", "...")`. The pairs are stored unparsed (see the type's own doc
/// comment in `types.rs`); actual `CloudOptions` construction is deferred to each scan/sink call
/// site, once the destination path (and so the cloud scheme) is known.
#[no_mangle]
pub unsafe extern "C" fn polars_cloud_options_new(
    keys: *const *const u8,
    key_lens: *const usize,
    values: *const *const u8,
    value_lens: *const usize,
    n: usize,
    out: *mut *mut polars_cloud_options_t,
) -> *const polars_error_t {
    guard_error(|| {
        let keys = tri!(read_names(keys, key_lens, n));
        let values = tri!(read_names(values, value_lens, n));
        let pairs = keys.into_iter().zip(values).collect();
        *out = polars_cloud_options_t { pairs }.into_handle();
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_cloud_options_destroy(ptr: *mut polars_cloud_options_t) {
    Opaque::destroy(ptr);
}
