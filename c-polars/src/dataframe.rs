use std::ffi::c_void;
use std::io::Write;
use std::num::NonZeroUsize;
use std::sync::Arc;

use polars::prelude::*;
use polars_core::query_result::QueryResult;
use polars_core::utils::arrow::{
    self,
    array::StructArray,
    ffi::{self, ArrowArray, ArrowSchema},
};
use polars_plan::utils::expr_output_name;
use polars_utils::either::Either;

use crate::ffi_util::*;
use crate::io::{build_ipc_writer_options, build_parquet_write_options};
use crate::series;
use crate::types::*;
use crate::value::{polars_closed_window_t, polars_label_t, polars_start_by_t};
use crate::{guard_error, make_error, polars_error_t};

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

/// Creates a DataFrame from an ArrowArray + ArrowSchema pair per the Arrow C Data Interface.
///
/// # Safety
/// `cfield` must be a valid `ArrowSchema` per the C Data Interface. `carray` must be a valid
/// `ArrowArray` per the C Data Interface, and **ownership of it transfers to this call**: the
/// caller must not release it. It is released either via the resulting DataFrame's destructor
/// (`polars_dataframe_destroy`) on success, or before returning on failure -- `carray` is an
/// owned by-value local and polars-arrow's `impl Drop for ArrowArray` invokes its `release`
/// callback, so every early return below releases rather than leaks it. On the success path it is
/// moved into `import_array_from_c`, which likewise takes it by value.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_new_from_carrow(
    cfield: *const ArrowSchema,
    carray: ArrowArray,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    guard_error(move || {
        // Safety: the field ptr is expected to be a valid pointer to an ArrowSchema according to
        // the C Data interface.
        let field = tri!(ffi::import_field_from_c(&*cfield));

        let array = tri!(ffi::import_array_from_c(carray, field.dtype.clone()));

        // The caller is expected to provide a struct array (arrow format "+s") whose fields are
        // the dataframe's columns.
        let Some(sarray) = array.as_any().downcast_ref::<StructArray>() else {
            return make_error(format!(
                "expected a struct array (arrow format \"+s\") whose fields are the dataframe's columns, got dtype {:?}",
                array.dtype()
            ));
        };

        let df = tri!(DataFrame::try_from(sarray.clone()));

        *out = make_dataframe(df);
        std::ptr::null()
    })
}

/// Returns a ArrowSchema describing the dataframe's schema according to Arrow C Data interface.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_schema(
    df: *mut polars_dataframe_t,
    out: *mut ArrowSchema,
) -> *const polars_error_t {
    guard_error(|| {
        let schema = (*df).inner.schema().to_arrow(CompatLevel::newest());
        let structfield = arrow::datatypes::Field::new(
            "polars.dataframe".into(),
            arrow::datatypes::ArrowDataType::Struct(schema.iter_values().cloned().collect()),
            false,
        );
        out.write(ffi::export_field_to_c(&structfield));
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_new_from_series(
    series: *const *mut polars_series_t,
    nseries: usize,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    guard_error(|| {
        // `slice::from_raw_parts` requires a non-null aligned pointer even for len 0, and callers may
        // legitimately pass a null/dangling pointer for an empty list -- so short-circuit here (see
        // `ffi_util::read_names` for the same convention).
        let series: Vec<Column> = if nseries == 0 {
            Vec::new()
        } else {
            let slice: &[*mut polars_series_t] = std::slice::from_raw_parts(series, nseries);
            slice
                .iter()
                .enumerate()
                .map(|(i, s)| {
                    let s = (**s).inner.clone();
                    // Preserve the Series' own name; only synthesize `column_i` for genuinely unnamed
                    // inputs (duplicate names then surface as a `DataFrame::new` error, as they should).
                    if s.name().is_empty() {
                        Column::new(format!("column_{i}").into(), s)
                    } else {
                        s.into_column()
                    }
                })
                .collect()
        };
        let height = series.first().map_or(0, |s| s.len());
        let df = tri!(DataFrame::new(height, series));
        *out = make_dataframe(df);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_destroy(df: *mut polars_dataframe_t) {
    Opaque::destroy(df);
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
    guard_error(|| {
        let options = tri!(build_parquet_write_options(
            compression,
            compression_level,
            statistics,
            row_group_size,
            data_page_size,
        ));

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
    })
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
    guard_error(|| {
        let df = &mut (*df).inner;

        let null_value = tri!(read_opt_str(null_value, null_value_len));
        let line_terminator = tri!(read_opt_str(line_terminator, line_terminator_len));
        let date_format = tri!(read_opt_str(date_format, date_format_len));
        let time_format = tri!(read_opt_str(time_format, time_format_len));
        let datetime_format = tri!(read_opt_str(datetime_format, datetime_format_len));

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
    })
}

/// Reads a JSON file (a single top-level array of objects -- upstream's `JsonFormat::Json`) from
/// `path` into a `DataFrame`. Unlike Parquet/CSV/IPC, plain JSON has no lazy scan counterpart
/// upstream either (the whole array must be parsed to know its shape), so this is eager-only --
/// there is no `polars_lazy_frame_scan_json` to pair it with.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_read_json(
    path: *const u8,
    pathlen: usize,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let file = tri!(std::fs::File::open(path).map_err(|e| PolarsError::IO {
            error: Arc::new(e),
            msg: Some(format!("failed to open {path}").into()),
        }));
        let df = tri!(JsonReader::new(file)
            .with_json_format(JsonFormat::Json)
            .finish());
        *out = make_dataframe(df);
        std::ptr::null()
    })
}

/// Reads a newline-delimited JSON file (upstream's `JsonFormat::JsonLines`) from `path` into a
/// `DataFrame`. `infer_schema_length` (null = default 100 rows, matching upstream) caps how many
/// leading rows are scanned to infer the schema; `ignore_errors` turns a per-row parse mismatch
/// into a `null` instead of a hard error.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_read_ndjson(
    path: *const u8,
    pathlen: usize,
    infer_schema_length: *const usize,
    ignore_errors: bool,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    guard_error(|| {
        let path = tri!(read_str(path, pathlen));
        let file = tri!(std::fs::File::open(path).map_err(|e| PolarsError::IO {
            error: Arc::new(e),
            msg: Some(format!("failed to open {path}").into()),
        }));
        let infer_schema_len = match infer_schema_length.as_ref().copied() {
            Some(n) => Some(tri!(NonZeroUsize::new(n).ok_or_else(|| {
                PolarsError::InvalidOperation("infer_schema_length must be positive".into())
            }))),
            None => Some(NonZeroUsize::new(100).unwrap()),
        };
        let df = tri!(JsonReader::new(file)
            .with_json_format(JsonFormat::JsonLines)
            .infer_schema_len(infer_schema_len)
            .with_ignore_errors(ignore_errors)
            .finish());
        *out = make_dataframe(df);
        std::ptr::null()
    })
}

/// Writes `df` as a single top-level JSON array of objects (upstream's `JsonFormat::Json`), via
/// the same `IOCallback` shape as `polars_dataframe_write_csv`/`_write_parquet`.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_write_json(
    df: *mut polars_dataframe_t,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    guard_error(|| {
        let df = &mut (*df).inner;
        let w = UserIOCallback(callback, user);
        if let Err(err) = JsonWriter::new(w).with_json_format(JsonFormat::Json).finish(df) {
            return make_error(err);
        }
        std::ptr::null()
    })
}

/// Writes `df` as newline-delimited JSON (upstream's `JsonFormat::JsonLines`), via the same
/// `IOCallback` shape as `polars_dataframe_write_csv`/`_write_parquet`.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_write_ndjson(
    df: *mut polars_dataframe_t,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    guard_error(|| {
        let df = &mut (*df).inner;
        let w = UserIOCallback(callback, user);
        if let Err(err) =
            JsonWriter::new(w).with_json_format(JsonFormat::JsonLines).finish(df)
        {
            return make_error(err);
        }
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_show(
    df: *mut polars_dataframe_t,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    guard_error(|| {
        let df = &(*df).inner;
        let mut w = UserIOCallback(callback, user);
        if let Err(err) = write!(w, "{df}") {
            return make_error(err);
        }
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_get(
    df: *mut polars_dataframe_t,
    name: *const u8,
    len: usize,
    out: *mut *mut polars_series_t,
) -> *const polars_error_t {
    guard_error(|| {
        let name = tri!(read_str(name, len));

        let df = &(*df).inner;
        let column = tri!(df.column(name));

        *out = series::make_series(column.as_materialized_series().clone());

        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_lazy(
    df: *mut polars_dataframe_t,
) -> *mut polars_lazy_frame_t {
    let df = &(*df).inner;
    make_lazy_frame(df.clone().lazy())
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
    guard_error(|| {
        let by = tri!(read_names(by_names, by_lens, n_by));
        let time_column = tri!(read_str(time_column, time_column_len));
        let every_str = tri!(read_str(every, every_len));
        let every = tri!(Duration::try_parse(every_str));

        let result = if stable {
            (*df).inner.upsample_stable(by, time_column, every)
        } else {
            (*df).inner.upsample(by, time_column, every)
        };
        match result {
            Ok(result) => {
                *out = make_dataframe(result);
                std::ptr::null()
            }
            Err(err) => make_error(err),
        }
    })
}

/// Attaches loose `Series` as new columns. A length mismatch between `series` and `df`'s existing
/// height, or a name collision with an existing column (or between two of the given `series`
/// themselves), raises a `PolarsError`.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_hstack(
    df: *mut polars_dataframe_t,
    series: *const *mut polars_series_t,
    n: usize,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    guard_error(|| {
        let columns = read_series(series, n);
        let result = tri!((*df).inner.hstack(&columns));
        *out = make_dataframe(result);
        std::ptr::null()
    })
}

/// Stacks `other`'s rows beneath `df`'s. Does no supertype casting: a column-count/dtype mismatch
/// between `df` and `other` raises a `PolarsError`.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_vstack(
    df: *mut polars_dataframe_t,
    other: *mut polars_dataframe_t,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    guard_error(|| {
        let result = tri!((*df).inner.vstack(&(*other).inner));
        *out = make_dataframe(result);
        std::ptr::null()
    })
}

/// Transposes rows and columns. `keep_names_as`, if given, names a new first column holding the
/// original column names. `new_col_names`, if given (a zero-length array counts as omitted), sets
/// the transposed frame's column names explicitly; otherwise they are auto-generated
/// (`"column_N"`). Setting an existing column's *values* as the new names is not supported. A
/// `new_col_names` of the wrong length (relative to `df`'s original column count) raises a
/// `ShapeMismatch` `PolarsError`.
#[no_mangle]
pub unsafe extern "C" fn polars_dataframe_transpose(
    df: *mut polars_dataframe_t,
    keep_names_as: *const u8,
    keep_names_as_len: usize,
    new_col_names: *const *const u8,
    new_col_names_lens: *const usize,
    n_new_col_names: usize,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    guard_error(|| {
        let keep_names_as = tri!(read_opt_str(keep_names_as, keep_names_as_len));
        let names = tri!(read_names(
            new_col_names,
            new_col_names_lens,
            n_new_col_names
        ));
        let new_col_names = if names.is_empty() {
            None
        } else {
            Some(Either::Right(
                names.into_iter().map(|s| s.to_string()).collect(),
            ))
        };
        let result = tri!((*df)
            .inner
            .clone()
            .transpose(keep_names_as.as_deref(), new_col_names));
        *out = make_dataframe(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_destroy(df: *mut polars_lazy_frame_t) {
    Opaque::destroy(df);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_clone(
    df: *mut polars_lazy_frame_t,
) -> *mut polars_lazy_frame_t {
    make_lazy_frame((*df).inner.clone())
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
    guard_error(|| {
        let df = &mut (*df).inner;

        let options = tri!(build_ipc_writer_options(
            compression,
            compression_level,
            record_batch_size
        ));

        let w = UserIOCallback(callback, user);
        if let Err(err) = options.to_writer(w).finish(df) {
            return make_error(err);
        }

        std::ptr::null()
    })
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
    let exprs = read_exprs(exprs, nexprs);
    let descending = read_bool_mask(descending, nexprs);
    let df = &mut (*df).inner;
    // `sort_by_exprs` takes `self` by value; the caller cannot observe `*df` between this move
    // and the following assignment (single-threaded within one ccall), so moving the plan out via
    // `mem::take` (leaving a cheap `LazyFrame::default()` behind momentarily) avoids the otherwise
    // redundant plan clone -- the Julia-side eager wrappers already clone before calling in.
    //
    // **This soundness argument depends on the mutators staying unguarded.** The window is only
    // unobservable because a panic between the take and the assignment aborts the process. Wrap
    // one of these in `guard_error` and the caller gets back a handle silently holding an empty
    // `LazyFrame::default()` instead of its plan -- so any such change must restore `*df` on the
    // unwind path (or drop the take and clone) in the same edit. Adding an error channel here is
    // an ABI change and is tracked as follow-up work, not something to do piecemeal.
    *df = std::mem::take(df).sort_by_exprs(
        &exprs,
        SortMultipleOptions {
            descending,
            nulls_last: std::iter::repeat_n(nulls_last, nexprs).collect(),
            maintain_order,
            multithreaded: true,
            limit: None,
        },
    );
}

/// `how` selects the concat mode.
#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_concat(
    lfs: *const *mut polars_lazy_frame_t,
    n: usize,
    how: polars_concat_how_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let frames: Vec<LazyFrame> = (0..n).map(|i| (**lfs.add(i)).inner.clone()).collect();

        let df = match how {
            polars_concat_how_t::PolarsConcatHowHorizontal => {
                tri!(concat_lf_horizontal(&frames, HConcatOptions::default()))
            }
            polars_concat_how_t::PolarsConcatHowVertical => {
                tri!(concat(&frames, UnionArgs::default()))
            }
            polars_concat_how_t::PolarsConcatHowVerticalRelaxed => tri!(concat(
                &frames,
                UnionArgs {
                    to_supertypes: true,
                    ..Default::default()
                }
            )),
            polars_concat_how_t::PolarsConcatHowDiagonal => tri!(concat(
                &frames,
                UnionArgs {
                    diagonal: true,
                    ..Default::default()
                }
            )),
            polars_concat_how_t::PolarsConcatHowDiagonalRelaxed => tri!(concat(
                &frames,
                UnionArgs {
                    diagonal: true,
                    to_supertypes: true,
                    ..Default::default()
                }
            )),
        };
        *out = make_lazy_frame(df);

        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_with_columns(
    df: *mut polars_lazy_frame_t,
    exprs: *const *const polars_expr_t,
    nexprs: usize,
) {
    let exprs = read_exprs(exprs, nexprs);
    let df = &mut (*df).inner;
    // See the `mem::take` comment on `polars_lazy_frame_sort` above.
    *df = std::mem::take(df).with_columns(&exprs);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_select(
    df: *mut polars_lazy_frame_t,
    exprs: *const *const polars_expr_t,
    nexprs: usize,
) {
    let exprs = read_exprs(exprs, nexprs);
    let df = &mut (*df).inner;
    // See the `mem::take` comment on `polars_lazy_frame_sort` above.
    *df = std::mem::take(df).select(&exprs);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_filter(
    df: *mut polars_lazy_frame_t,
    expr: *const polars_expr_t,
) {
    // We clone the expr; `LazyFrame::filter` takes it by value but the caller retains ownership of
    // the `polars_expr_t` handle (destroyed separately via `polars_expr_destroy`).
    let predicate = (*expr).inner.clone();
    let df = &mut (*df).inner;
    // See the `mem::take` comment on `polars_lazy_frame_sort` above.
    *df = std::mem::take(df).filter(predicate);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_collect(
    df: *mut polars_lazy_frame_t,
    engine: polars_engine_t,
    out: *mut *mut polars_dataframe_t,
) -> *const polars_error_t {
    guard_error(|| {
        let df = (*df).inner.clone();
        let engine = match engine {
            polars_engine_t::PolarsEngineInMemory => Engine::InMemory,
            polars_engine_t::PolarsEngineStreaming => Engine::Streaming,
        };
        let result = tri!(df.collect_with_engine(engine));
        let df = match result {
            QueryResult::Single(df) => df,
            QueryResult::Multiple(_) => {
                return make_error("query produced multiple frames; expected a single result")
            }
        };
        *out = make_dataframe(df);
        std::ptr::null()
    })
}

/// Resolves the lazy frame's schema (without collecting it) and returns it as an ArrowSchema
/// according to the Arrow C Data interface, wrapping the columns in a struct field the same way
/// `polars_dataframe_schema` does. Unlike that function, this one is fallible (schema resolution
/// can fail on an unresolved lazy plan) and so returns via out-param + `polars_error_t` rather
/// than by value.
#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_collect_schema(
    df: *mut polars_lazy_frame_t,
    out: *mut ArrowSchema,
) -> *const polars_error_t {
    guard_error(|| {
        let mut df = (*df).inner.clone();
        let schema = tri!(df.collect_schema());
        let arrow_schema = schema.to_arrow(CompatLevel::newest());
        let structfield = arrow::datatypes::Field::new(
            "polars.dataframe".into(),
            arrow::datatypes::ArrowDataType::Struct(arrow_schema.iter_values().cloned().collect()),
            false,
        );
        // `out` points at caller-allocated but *uninitialized* memory (the Julia side passes
        // `Ref{ArrowSchema}()`, never an already-initialized schema) -- `*out = ...` would first run
        // `ArrowSchema`'s `Drop` impl (it has a `release` callback) on whatever garbage bytes are
        // already there before overwriting them, which is UB: on one allocator's leftover
        // garbage that's a harmless no-op, on another's it's a segfault deep in the drop glue.
        // `write` (aka `std::ptr::write`) stores the value without touching/dropping the
        // destination first, which is the correct way to populate caller-allocated-but-not-yet-
        // initialized memory.
        out.write(ffi::export_field_to_c(&structfield));
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_group_by(
    df: *mut polars_lazy_frame_t,
    exprs: *const *const polars_expr_t,
    nexprs: usize,
    maintain_order: bool,
) -> *mut polars_lazy_group_by_t {
    let exprs = read_exprs(exprs, nexprs);
    let df = (*df).inner.clone();
    let gb = if maintain_order {
        df.group_by_stable(&exprs)
    } else {
        df.group_by(&exprs)
    };
    make_lazy_group_by(gb)
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
    guard_error(|| {
        let group_by = read_exprs(group_by_exprs, n_group_by);

        let every_str = tri!(read_str(every, every_len));
        // A zero-length `period` deliberately defaults to `every` (a window as wide as its step).
        let period_str = if period_len == 0 {
            every_str
        } else {
            tri!(read_str(period, period_len))
        };
        let offset_str = tri!(read_str(offset, offset_len));

        let every = tri!(Duration::try_parse(every_str));
        let period = tri!(Duration::try_parse(period_str));
        let offset = tri!(Duration::try_parse(offset_str));

        let index_col_name = tri!(expr_output_name(&(*index_expr).inner));

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
        *out = make_lazy_group_by(gb);
        std::ptr::null()
    })
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
    guard_error(|| {
        let group_by = read_exprs(group_by_exprs, n_group_by);

        let period_str = tri!(read_str(period, period_len));
        let offset_str = tri!(read_str(offset, offset_len));

        let period = tri!(Duration::try_parse(period_str));
        let offset = tri!(Duration::try_parse(offset_str));

        let index_col_name = tri!(expr_output_name(&(*index_expr).inner));

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
        *out = make_lazy_group_by(gb);
        std::ptr::null()
    })
}

#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn polars_lazy_frame_join(
    a: *mut polars_lazy_frame_t,
    b: *mut polars_lazy_frame_t,
    exprs_a: *const *const polars_expr_t,
    exprs_a_len: usize,
    exprs_b: *const *const polars_expr_t,
    exprs_b_len: usize,
    how: polars_join_type_t,
    suffix: *const u8,
    suffix_len: usize,
    coalesce: polars_join_coalesce_t,
    validate: polars_join_validation_t,
    nulls_equal: bool,
    slice_offset: *const i64,
    slice_len: *const usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let exprs_a = read_exprs(exprs_a, exprs_a_len);
        let exprs_b = read_exprs(exprs_b, exprs_b_len);
        let suffix = tri!(read_opt_str(suffix, suffix_len));
        let slice = slice_offset
            .as_ref()
            .zip(slice_len.as_ref())
            .map(|(&offset, &len)| (offset, len));
        let args = JoinArgs {
            suffix,
            coalesce: coalesce.to_join_coalesce(),
            validation: validate.to_join_validation(),
            nulls_equal,
            slice,
            ..JoinArgs::new(how.to_join_type())
        };
        let df = LazyFrame::join((*a).inner.clone(), (*b).inner.clone(), exprs_a, exprs_b, args);
        *out = make_lazy_frame(df);
        std::ptr::null()
    })
}

#[no_mangle]
#[allow(clippy::too_many_arguments)]
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
    tolerance: *const u8,
    tolerance_len: usize,
    allow_eq: bool,
    check_sortedness: bool,
    suffix: *const u8,
    suffix_len: usize,
    nulls_equal: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let left_by = tri!(read_names(by_a, by_a_lens, by_a_len));
        let right_by = tri!(read_names(by_b, by_b_lens, by_b_len));
        let tolerance_str = tri!(read_opt_str(tolerance, tolerance_len));
        let suffix = tri!(read_opt_str(suffix, suffix_len));

        let asof_options = AsOfOptions {
            strategy: strategy.to_asof_strategy(),
            tolerance: None,
            tolerance_str,
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
            allow_eq,
            check_sortedness,
        };

        let on_a = (*on_a).inner.clone();
        let on_b = (*on_b).inner.clone();
        let args = JoinArgs {
            suffix,
            nulls_equal,
            ..JoinArgs::new(JoinType::AsOf(Box::new(asof_options)))
        };
        let df = LazyFrame::join((*a).inner.clone(), (*b).inner.clone(), vec![on_a], vec![on_b], args);
        *out = make_lazy_frame(df);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_unique(
    lf: *mut polars_lazy_frame_t,
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    keep: polars_unique_keep_t,
    maintain_order: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let names = tri!(read_names(names, lens, n));
        let subset = selector_by_name_opt(names, true);
        let lf = (*lf).inner.clone();
        let result = if maintain_order {
            lf.unique_stable(subset, keep.to_keep_strategy())
        } else {
            lf.unique(subset, keep.to_keep_strategy())
        };
        *out = make_lazy_frame(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_drop(
    lf: *mut polars_lazy_frame_t,
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let names = tri!(read_names(names, lens, n));
        let result = (*lf).inner.clone().drop(selector_by_name(names, true));
        *out = make_lazy_frame(result);
        std::ptr::null()
    })
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
    guard_error(|| {
        let existing = tri!(read_names(existing, existing_lens, n));
        let new = tri!(read_names(new, new_lens, n));
        let result = (*lf).inner.clone().rename(existing, new, strict);
        *out = make_lazy_frame(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_drop_nulls(
    lf: *mut polars_lazy_frame_t,
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let names = tri!(read_names(names, lens, n));
        let subset = selector_by_name_opt(names, true);
        let result = (*lf).inner.clone().drop_nulls(subset);
        *out = make_lazy_frame(result);
        std::ptr::null()
    })
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
    guard_error(|| {
        let name = PlSmallStr::from_str(tri!(read_str(name, name_len)));
        let offset = if has_offset {
            match IdxSize::try_from(offset) {
                Ok(o) => Some(o),
                Err(_) => {
                    return make_error(format!(
                        "row index offset must be between 0 and {}, got {offset}",
                        IdxSize::MAX
                    ))
                }
            }
        } else {
            None
        };
        let result = (*lf).inner.clone().with_row_index(name, offset);
        *out = make_lazy_frame(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_explode(
    lf: *mut polars_lazy_frame_t,
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    // `empty_as_null`: exploding an empty list produces one `null` row rather than disappearing
    // (row-count-preserving) when true. `keep_nulls`: exploding a `null` list entry produces one
    // `null` row rather than disappearing too, when true. Upstream's own default is `true`/`true`,
    // which the Julia side mirrors as its keyword default.
    empty_as_null: bool,
    keep_nulls: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let names = tri!(read_names(names, lens, n));
        let result = (*lf).inner.clone().explode(
            selector_by_name(names, true),
            ExplodeOptions {
                empty_as_null,
                keep_nulls,
            },
        );
        *out = make_lazy_frame(result);
        std::ptr::null()
    })
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
    guard_error(|| {
        let index_names = tri!(read_names(index_names, index_lens, n_index));
        let on_names = tri!(read_names(on_names, on_lens, n_on));
        let variable_name = tri!(read_opt_str(variable_name, variable_name_len));
        let value_name = tri!(read_opt_str(value_name, value_name_len));

        let args = UnpivotArgsDSL {
            on: selector_by_name_opt(on_names, true),
            index: selector_by_name(index_names, true),
            variable_name,
            value_name,
        };
        let result = (*lf).inner.clone().unpivot(args);
        *out = make_lazy_frame(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_unnest(
    lf: *mut polars_lazy_frame_t,
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    separator: *const u8,
    separator_len: usize,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t {
    guard_error(|| {
        let names = tri!(read_names(names, lens, n));
        let separator = tri!(read_opt_str(separator, separator_len));
        // `LazyFrame::unnest` is infallible (`-> Self`) -- the strict-by-name selector below still
        // surfaces a nonexistent-column or non-struct-dtype error, just deferred until `collect`
        // resolves the schema (see the `guard_error`-wrapped collect path).
        let result = (*lf)
            .inner
            .clone()
            .unnest(selector_by_name(names, true), separator);
        *out = make_lazy_frame(result);
        std::ptr::null()
    })
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
    guard_error(|| {
        let on_names = tri!(read_names(on_names, on_lens, n_on));
        let index_names = tri!(read_names(index_names, index_lens, n_index));
        let values_names = tri!(read_names(values_names, values_lens, n_values));
        let separator = PlSmallStr::from_str(tri!(read_str(separator, separator_len)));

        let on_columns = Arc::new((*on_columns).inner.clone());
        let agg = (*agg).inner.clone();
        let lf = (*lf).inner.clone();

        let result = lf.pivot(
            selector_by_name(on_names, true),
            on_columns,
            selector_by_name(index_names, true),
            selector_by_name(values_names, true),
            agg,
            maintain_order,
            separator,
            column_naming.to_pivot_column_naming(),
        );
        *out = make_lazy_frame(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_head(df: *mut polars_lazy_frame_t, n: usize) {
    let df = &mut (*df).inner;
    // See the `mem::take` comment on `polars_lazy_frame_sort` above.
    *df = std::mem::take(df).limit(n.min(IdxSize::MAX as usize) as IdxSize);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_tail(df: *mut polars_lazy_frame_t, n: usize) {
    let df = &mut (*df).inner;
    // See the `mem::take` comment on `polars_lazy_frame_sort` above.
    *df = std::mem::take(df).tail(n.min(IdxSize::MAX as usize) as IdxSize);
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_group_by_destroy(gb: *const polars_lazy_group_by_t) {
    Opaque::destroy(gb.cast_mut());
}

#[no_mangle]
pub unsafe extern "C" fn polars_lazy_group_by_agg(
    gb: *mut polars_lazy_group_by_t,
    exprs: *const *const polars_expr_t,
    nexprs: usize,
) -> *mut polars_lazy_frame_t {
    let exprs = read_exprs(exprs, nexprs);
    make_lazy_frame((*gb).inner.clone().agg(&exprs))
}
