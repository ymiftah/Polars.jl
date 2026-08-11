#pragma once

/* GENERATED FILE -- do not edit. Regenerate with c-polars/regen_header.sh */

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include "arrow.h"

typedef enum polars_asof_strategy_t {
  PolarsAsofStrategyBackward,
  PolarsAsofStrategyForward,
  PolarsAsofStrategyNearest,
} polars_asof_strategy_t;

typedef enum polars_closed_interval_t {
  PolarsClosedIntervalBoth,
  PolarsClosedIntervalLeft,
  PolarsClosedIntervalRight,
  PolarsClosedIntervalNone,
} polars_closed_interval_t;

typedef enum polars_closed_window_t {
  PolarsClosedWindowLeft,
  PolarsClosedWindowRight,
  PolarsClosedWindowBoth,
  PolarsClosedWindowNone,
} polars_closed_window_t;

typedef enum polars_concat_how_t {
  PolarsConcatHowVertical,
  PolarsConcatHowVerticalRelaxed,
  PolarsConcatHowDiagonal,
  PolarsConcatHowDiagonalRelaxed,
  PolarsConcatHowHorizontal,
} polars_concat_how_t;

typedef enum polars_csv_compression_t {
  PolarsCsvCompressionUncompressed,
  PolarsCsvCompressionGzip,
  PolarsCsvCompressionZstd,
} polars_csv_compression_t;

/**
 * Zero-argument `DataTypeSelector` leaves. `Datetime`/`Duration`/`List`/`Array` match any
 * unit/timezone rather than a specific one; List/Array do not support inner-selector composition.
 */
typedef enum polars_dtype_selector_kind_t {
  PolarsDtypeSelectorKindNumeric,
  PolarsDtypeSelectorKindInteger,
  PolarsDtypeSelectorKindUnsignedInteger,
  PolarsDtypeSelectorKindSignedInteger,
  PolarsDtypeSelectorKindFloat,
  PolarsDtypeSelectorKindEnum,
  PolarsDtypeSelectorKindCategorical,
  PolarsDtypeSelectorKindNested,
  PolarsDtypeSelectorKindStruct,
  PolarsDtypeSelectorKindDecimal,
  PolarsDtypeSelectorKindTemporal,
  PolarsDtypeSelectorKindObject,
  PolarsDtypeSelectorKindDatetime,
  PolarsDtypeSelectorKindDuration,
  PolarsDtypeSelectorKindList,
  PolarsDtypeSelectorKindArray,
} polars_dtype_selector_kind_t;

typedef enum polars_engine_t {
  PolarsEngineInMemory,
  PolarsEngineStreaming,
} polars_engine_t;

typedef enum polars_fill_null_strategy_t {
  PolarsFillNullStrategyBackward,
  PolarsFillNullStrategyForward,
  PolarsFillNullStrategyMean,
  PolarsFillNullStrategyMin,
  PolarsFillNullStrategyMax,
  PolarsFillNullStrategyZero,
  PolarsFillNullStrategyOne,
} polars_fill_null_strategy_t;

typedef enum polars_interpolation_method_t {
  PolarsInterpolationMethodLinear,
  PolarsInterpolationMethodNearest,
} polars_interpolation_method_t;

typedef enum polars_ipc_compression_t {
  PolarsIpcCompressionUncompressed,
  PolarsIpcCompressionLz4,
  PolarsIpcCompressionZstd,
} polars_ipc_compression_t;

typedef enum polars_join_coalesce_t {
  PolarsJoinCoalesceJoinSpecific,
  PolarsJoinCoalesceCoalesceColumns,
  PolarsJoinCoalesceKeepColumns,
} polars_join_coalesce_t;

typedef enum polars_join_type_t {
  PolarsJoinTypeInner,
  PolarsJoinTypeLeft,
  PolarsJoinTypeRight,
  PolarsJoinTypeFull,
  PolarsJoinTypeSemi,
  PolarsJoinTypeAnti,
  PolarsJoinTypeCross,
} polars_join_type_t;

typedef enum polars_join_validation_t {
  PolarsJoinValidationManyToMany,
  PolarsJoinValidationManyToOne,
  PolarsJoinValidationOneToMany,
  PolarsJoinValidationOneToOne,
} polars_join_validation_t;

typedef enum polars_label_t {
  PolarsLabelLeft,
  PolarsLabelRight,
  PolarsLabelDataPoint,
} polars_label_t;

typedef enum polars_non_existent_t {
  PolarsNonExistentRaise,
  PolarsNonExistentNull,
} polars_non_existent_t;

typedef enum polars_null_behavior_t {
  PolarsNullBehaviorDrop,
  PolarsNullBehaviorIgnore,
} polars_null_behavior_t;

typedef enum polars_parquet_compression_t {
  PolarsParquetCompressionUncompressed,
  PolarsParquetCompressionSnappy,
  PolarsParquetCompressionGzip,
  PolarsParquetCompressionBrotli,
  PolarsParquetCompressionZstd,
  PolarsParquetCompressionLz4Raw,
} polars_parquet_compression_t;

typedef enum polars_parquet_parallel_strategy_t {
  PolarsParquetParallelAuto,
  PolarsParquetParallelNone,
  PolarsParquetParallelColumns,
  PolarsParquetParallelRowGroups,
} polars_parquet_parallel_strategy_t;

typedef enum polars_pivot_column_naming_t {
  PolarsPivotColumnNamingCombine,
  PolarsPivotColumnNamingAuto,
} polars_pivot_column_naming_t;

typedef enum polars_quantile_method_t {
  PolarsQuantileMethodNearest,
  PolarsQuantileMethodLower,
  PolarsQuantileMethodHigher,
  PolarsQuantileMethodMidpoint,
  PolarsQuantileMethodLinear,
  PolarsQuantileMethodEquiprobable,
} polars_quantile_method_t;

typedef enum polars_quote_style_t {
  PolarsQuoteStyleNecessary,
  PolarsQuoteStyleAlways,
  PolarsQuoteStyleNonNumeric,
  PolarsQuoteStyleNever,
} polars_quote_style_t;

typedef enum polars_rank_method_t {
  PolarsRankMethodAverage,
  PolarsRankMethodMin,
  PolarsRankMethodMax,
  PolarsRankMethodDense,
  PolarsRankMethodOrdinal,
} polars_rank_method_t;

typedef enum polars_round_mode_t {
  PolarsRoundModeHalfToEven,
  PolarsRoundModeHalfAwayFromZero,
  PolarsRoundModeToZero,
} polars_round_mode_t;

typedef enum polars_selector_match_kind_t {
  PolarsSelectorMatchKindRegex,
  PolarsSelectorMatchKindStartsWith,
  PolarsSelectorMatchKindEndsWith,
  PolarsSelectorMatchKindContains,
} polars_selector_match_kind_t;

typedef enum polars_start_by_t {
  PolarsStartByWindowBound,
  PolarsStartByDataPoint,
  PolarsStartByMonday,
  PolarsStartByTuesday,
  PolarsStartByWednesday,
  PolarsStartByThursday,
  PolarsStartByFriday,
  PolarsStartBySaturday,
  PolarsStartBySunday,
} polars_start_by_t;

typedef enum polars_time_unit_t {
  PolarsTimeUnitNanosecond,
  PolarsTimeUnitMicrosecond,
  PolarsTimeUnitMillisecond,
  PolarsTimeUnitInvalid,
} polars_time_unit_t;

typedef enum polars_unique_keep_t {
  PolarsUniqueKeepFirst,
  PolarsUniqueKeepLast,
  PolarsUniqueKeepNone,
  PolarsUniqueKeepAny,
} polars_unique_keep_t;

typedef enum polars_value_type_t {
  PolarsValueTypeNull,
  PolarsValueTypeBoolean,
  PolarsValueTypeUInt8,
  PolarsValueTypeUInt16,
  PolarsValueTypeUInt32,
  PolarsValueTypeUInt64,
  PolarsValueTypeInt8,
  PolarsValueTypeInt16,
  PolarsValueTypeInt32,
  PolarsValueTypeInt64,
  PolarsValueTypeFloat32,
  PolarsValueTypeFloat64,
  PolarsValueTypeList,
  PolarsValueTypeString,
  PolarsValueTypeStruct,
  PolarsValueTypeBinary,
  PolarsValueTypeDatetime,
  PolarsValueTypeDate,
  PolarsValueTypeDuration,
  PolarsValueTypeTime,
  PolarsValueTypeUnknown,
} polars_value_type_t;

typedef enum polars_window_mapping_t {
  PolarsWindowMappingGroupsToRows,
  PolarsWindowMappingExplode,
  PolarsWindowMappingJoin,
} polars_window_mapping_t;

/**
 * Holds unparsed cloud storage key/value option pairs (e.g. `aws_access_key_id`); resolved into
 * real cloud options once the destination path (and so its cloud scheme) is known.
 */
typedef struct polars_cloud_options_t polars_cloud_options_t;

typedef struct polars_dataframe_t polars_dataframe_t;

typedef struct polars_error_t polars_error_t;

typedef struct polars_expr_t polars_expr_t;

typedef struct polars_lazy_frame_t polars_lazy_frame_t;

typedef struct polars_lazy_group_by_t polars_lazy_group_by_t;

typedef struct polars_series_t polars_series_t;

/**
 * Owns its data: `make_value` calls `AnyValue::into_static` on the way in, so a value never
 * borrows from the `Series` (or parent `polars_value_t`) it came from. It can therefore outlive
 * its source and be destroyed in any order relative to it.
 *
 * A borrowed `AnyValue<'a>` would be the cheaper representation, but the lifetime cannot survive
 * the C boundary: `polars_series_get`'s `'a` would be chosen by the caller and inferred as
 * `'static`, so the compiler would check nothing and the "keep the parent alive" rule would rest
 * entirely on the Julia side rooting correctly -- with silent memory corruption as the failure
 * mode. Owning the data deletes the rule instead of documenting it.
 *
 * Note `into_static` also *normalizes the variant*: `Struct` becomes `StructOwned`, `Datetime`
 * becomes `DatetimeOwned`, `String`/`Binary` become their `*Owned` forms. Accessors in `value.rs`
 * match the owned variants accordingly.
 */
typedef struct polars_value_t polars_value_t;

/**
 * The callback provided for display functions, returns -1 on error.
 */
typedef intptr_t (*IOCallback)(const void *user, const uint8_t *data, uintptr_t len);

/**
 * C-compatible mirror of polars_plan::dsl::CastColumnsPolicy
 * Controls how type mismatches are handled when reading parquet files with schema overrides.
 */
typedef struct polars_cast_columns_policy_t {
  bool integer_upcast;
  bool integer_to_float_cast;
  bool float_upcast;
  bool float_downcast;
  bool datetime_nanoseconds_downcast;
  bool datetime_microseconds_downcast;
  bool datetime_convert_timezone;
  bool null_upcast;
  bool categorical_to_string;
  bool missing_struct_fields_raise;
  bool extra_struct_fields_raise;
} polars_cast_columns_policy_t;

uintptr_t polars_version(const uint8_t **out);

/**
 * Borrowed pointer into the error's message, valid only as long as `err` is alive.
 */
uintptr_t polars_error_message(const struct polars_error_t *err, const uint8_t **data);

void polars_error_destroy(const struct polars_error_t *err);

void polars_dataframe_size(struct polars_dataframe_t *df, uintptr_t *rows, uintptr_t *cols);

/**
 * Creates a DataFrame from an ArrowArray + ArrowSchema pair per the Arrow C Data Interface.
 *
 * # Safety
 * `cfield` must be a valid `ArrowSchema` per the C Data Interface. `carray` must be a valid
 * `ArrowArray` per the C Data Interface, and **ownership of it transfers to this call**: the
 * caller must not release it. It is released either via the resulting DataFrame's destructor
 * (`polars_dataframe_destroy`) on success, or before returning on failure -- `carray` is an
 * owned by-value local and polars-arrow's `impl Drop for ArrowArray` invokes its `release`
 * callback, so every early return below releases rather than leaks it. On the success path it is
 * moved into `import_array_from_c`, which likewise takes it by value.
 */
const struct polars_error_t *polars_dataframe_new_from_carrow(const ArrowSchema *cfield,
                                                              ArrowArray carray,
                                                              struct polars_dataframe_t **out);

/**
 * Returns a ArrowSchema describing the dataframe's schema according to Arrow C Data interface.
 */
const struct polars_error_t *polars_dataframe_schema(struct polars_dataframe_t *df,
                                                     ArrowSchema *out);

const struct polars_error_t *polars_dataframe_new_from_series(struct polars_series_t *const *series,
                                                              uintptr_t nseries,
                                                              struct polars_dataframe_t **out);

void polars_dataframe_destroy(struct polars_dataframe_t *df);

const struct polars_error_t *polars_dataframe_write_parquet(
    struct polars_dataframe_t *df,
    const void *user,
    IOCallback callback,
    enum polars_parquet_compression_t compression,
    const int32_t *compression_level,
    bool statistics,
    const uintptr_t *row_group_size,
    const uintptr_t *data_page_size);

const struct polars_error_t *polars_dataframe_write_csv(struct polars_dataframe_t *df,
                                                        const void *user,
                                                        IOCallback callback,
                                                        bool include_header,
                                                        bool include_bom,
                                                        uint8_t separator,
                                                        uint8_t quote_char,
                                                        const uint8_t *null_value,
                                                        uintptr_t null_value_len,
                                                        const uint8_t *line_terminator,
                                                        uintptr_t line_terminator_len,
                                                        enum polars_quote_style_t quote_style,
                                                        const uint8_t *date_format,
                                                        uintptr_t date_format_len,
                                                        const uint8_t *time_format,
                                                        uintptr_t time_format_len,
                                                        const uint8_t *datetime_format,
                                                        uintptr_t datetime_format_len,
                                                        const uintptr_t *float_precision,
                                                        bool decimal_comma);

/**
 * Reads a JSON file (a single top-level array of objects -- upstream's `JsonFormat::Json`) from
 * `path` into a `DataFrame`. Unlike Parquet/CSV/IPC, plain JSON has no lazy scan counterpart
 * upstream either (the whole array must be parsed to know its shape), so this is eager-only --
 * there is no `polars_lazy_frame_scan_json` to pair it with.
 */
const struct polars_error_t *polars_dataframe_read_json(const uint8_t *path,
                                                        uintptr_t pathlen,
                                                        struct polars_dataframe_t **out);

/**
 * Reads a newline-delimited JSON file (upstream's `JsonFormat::JsonLines`) from `path` into a
 * `DataFrame`. `infer_schema_length` (null = default 100 rows, matching upstream) caps how many
 * leading rows are scanned to infer the schema; `ignore_errors` turns a per-row parse mismatch
 * into a `null` instead of a hard error.
 */
const struct polars_error_t *polars_dataframe_read_ndjson(const uint8_t *path,
                                                          uintptr_t pathlen,
                                                          const uintptr_t *infer_schema_length,
                                                          bool ignore_errors,
                                                          struct polars_dataframe_t **out);

/**
 * Writes `df` as a single top-level JSON array of objects (upstream's `JsonFormat::Json`), via
 * the same `IOCallback` shape as `polars_dataframe_write_csv`/`_write_parquet`.
 */
const struct polars_error_t *polars_dataframe_write_json(struct polars_dataframe_t *df,
                                                         const void *user,
                                                         IOCallback callback);

/**
 * Writes `df` as newline-delimited JSON (upstream's `JsonFormat::JsonLines`), via the same
 * `IOCallback` shape as `polars_dataframe_write_csv`/`_write_parquet`.
 */
const struct polars_error_t *polars_dataframe_write_ndjson(struct polars_dataframe_t *df,
                                                           const void *user,
                                                           IOCallback callback);

const struct polars_error_t *polars_dataframe_show(struct polars_dataframe_t *df,
                                                   const void *user,
                                                   IOCallback callback);

const struct polars_error_t *polars_dataframe_get(struct polars_dataframe_t *df,
                                                  const uint8_t *name,
                                                  uintptr_t len,
                                                  struct polars_series_t **out);

struct polars_lazy_frame_t *polars_dataframe_lazy(struct polars_dataframe_t *df);

const struct polars_error_t *polars_dataframe_upsample(struct polars_dataframe_t *df,
                                                       const uint8_t *const *by_names,
                                                       const uintptr_t *by_lens,
                                                       uintptr_t n_by,
                                                       const uint8_t *time_column,
                                                       uintptr_t time_column_len,
                                                       const uint8_t *every,
                                                       uintptr_t every_len,
                                                       bool stable,
                                                       struct polars_dataframe_t **out);

/**
 * Attaches loose `Series` as new columns. A length mismatch between `series` and `df`'s existing
 * height, or a name collision with an existing column (or between two of the given `series`
 * themselves), raises a `PolarsError`.
 */
const struct polars_error_t *polars_dataframe_hstack(struct polars_dataframe_t *df,
                                                     struct polars_series_t *const *series,
                                                     uintptr_t n,
                                                     struct polars_dataframe_t **out);

/**
 * Stacks `other`'s rows beneath `df`'s. Does no supertype casting: a column-count/dtype mismatch
 * between `df` and `other` raises a `PolarsError`.
 */
const struct polars_error_t *polars_dataframe_vstack(struct polars_dataframe_t *df,
                                                     struct polars_dataframe_t *other,
                                                     struct polars_dataframe_t **out);

/**
 * Transposes rows and columns. `keep_names_as`, if given, names a new first column holding the
 * original column names. `new_col_names`, if given (a zero-length array counts as omitted), sets
 * the transposed frame's column names explicitly; otherwise they are auto-generated
 * (`"column_N"`). Setting an existing column's *values* as the new names is not supported. A
 * `new_col_names` of the wrong length (relative to `df`'s original column count) raises a
 * `ShapeMismatch` `PolarsError`.
 */
const struct polars_error_t *polars_dataframe_transpose(struct polars_dataframe_t *df,
                                                        const uint8_t *keep_names_as,
                                                        uintptr_t keep_names_as_len,
                                                        const uint8_t *const *new_col_names,
                                                        const uintptr_t *new_col_names_lens,
                                                        uintptr_t n_new_col_names,
                                                        struct polars_dataframe_t **out);

void polars_lazy_frame_destroy(struct polars_lazy_frame_t *df);

struct polars_lazy_frame_t *polars_lazy_frame_clone(struct polars_lazy_frame_t *df);

const struct polars_error_t *polars_dataframe_write_ipc(struct polars_dataframe_t *df,
                                                        const void *user,
                                                        IOCallback callback,
                                                        enum polars_ipc_compression_t compression,
                                                        const int32_t *compression_level,
                                                        const uintptr_t *record_batch_size);

void polars_lazy_frame_sort(struct polars_lazy_frame_t *df,
                            const struct polars_expr_t *const *exprs,
                            uintptr_t nexprs,
                            const bool *descending,
                            bool nulls_last,
                            bool maintain_order);

/**
 * `how` selects the concat mode.
 */
const struct polars_error_t *polars_lazy_frame_concat(struct polars_lazy_frame_t *const *lfs,
                                                      uintptr_t n,
                                                      enum polars_concat_how_t how,
                                                      struct polars_lazy_frame_t **out);

void polars_lazy_frame_with_columns(struct polars_lazy_frame_t *df,
                                    const struct polars_expr_t *const *exprs,
                                    uintptr_t nexprs);

void polars_lazy_frame_select(struct polars_lazy_frame_t *df,
                              const struct polars_expr_t *const *exprs,
                              uintptr_t nexprs);

void polars_lazy_frame_filter(struct polars_lazy_frame_t *df, const struct polars_expr_t *expr);

const struct polars_error_t *polars_lazy_frame_collect(struct polars_lazy_frame_t *df,
                                                       enum polars_engine_t engine,
                                                       struct polars_dataframe_t **out);

/**
 * Resolves the lazy frame's schema (without collecting it) and returns it as an ArrowSchema
 * according to the Arrow C Data interface, wrapping the columns in a struct field the same way
 * `polars_dataframe_schema` does. Unlike that function, this one is fallible (schema resolution
 * can fail on an unresolved lazy plan) and so returns via out-param + `polars_error_t` rather
 * than by value.
 */
const struct polars_error_t *polars_lazy_frame_collect_schema(struct polars_lazy_frame_t *df,
                                                              ArrowSchema *out);

struct polars_lazy_group_by_t *polars_lazy_frame_group_by(struct polars_lazy_frame_t *df,
                                                          const struct polars_expr_t *const *exprs,
                                                          uintptr_t nexprs,
                                                          bool maintain_order);

const struct polars_error_t *polars_lazy_frame_group_by_dynamic(
    struct polars_lazy_frame_t *df,
    const struct polars_expr_t *index_expr,
    const struct polars_expr_t *const *group_by_exprs,
    uintptr_t n_group_by,
    const uint8_t *every,
    uintptr_t every_len,
    const uint8_t *period,
    uintptr_t period_len,
    const uint8_t *offset,
    uintptr_t offset_len,
    enum polars_label_t label,
    bool include_boundaries,
    enum polars_closed_window_t closed_window,
    enum polars_start_by_t start_by,
    struct polars_lazy_group_by_t **out);

const struct polars_error_t *polars_lazy_frame_rolling(
    struct polars_lazy_frame_t *df,
    const struct polars_expr_t *index_expr,
    const struct polars_expr_t *const *group_by_exprs,
    uintptr_t n_group_by,
    const uint8_t *period,
    uintptr_t period_len,
    const uint8_t *offset,
    uintptr_t offset_len,
    enum polars_closed_window_t closed_window,
    struct polars_lazy_group_by_t **out);

const struct polars_error_t *polars_lazy_frame_join(struct polars_lazy_frame_t *a,
                                                    struct polars_lazy_frame_t *b,
                                                    const struct polars_expr_t *const *exprs_a,
                                                    uintptr_t exprs_a_len,
                                                    const struct polars_expr_t *const *exprs_b,
                                                    uintptr_t exprs_b_len,
                                                    enum polars_join_type_t how,
                                                    const uint8_t *suffix,
                                                    uintptr_t suffix_len,
                                                    enum polars_join_coalesce_t coalesce,
                                                    enum polars_join_validation_t validate,
                                                    bool nulls_equal,
                                                    const int64_t *slice_offset,
                                                    const uintptr_t *slice_len,
                                                    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_join_asof(struct polars_lazy_frame_t *a,
                                                         struct polars_lazy_frame_t *b,
                                                         const struct polars_expr_t *on_a,
                                                         const struct polars_expr_t *on_b,
                                                         const uint8_t *const *by_a,
                                                         const uintptr_t *by_a_lens,
                                                         uintptr_t by_a_len,
                                                         const uint8_t *const *by_b,
                                                         const uintptr_t *by_b_lens,
                                                         uintptr_t by_b_len,
                                                         enum polars_asof_strategy_t strategy,
                                                         const uint8_t *tolerance,
                                                         uintptr_t tolerance_len,
                                                         bool allow_eq,
                                                         bool check_sortedness,
                                                         const uint8_t *suffix,
                                                         uintptr_t suffix_len,
                                                         bool nulls_equal,
                                                         struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_unique(struct polars_lazy_frame_t *lf,
                                                      const uint8_t *const *names,
                                                      const uintptr_t *lens,
                                                      uintptr_t n,
                                                      enum polars_unique_keep_t keep,
                                                      bool maintain_order,
                                                      struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_drop(struct polars_lazy_frame_t *lf,
                                                    const uint8_t *const *names,
                                                    const uintptr_t *lens,
                                                    uintptr_t n,
                                                    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_rename(struct polars_lazy_frame_t *lf,
                                                      const uint8_t *const *existing,
                                                      const uintptr_t *existing_lens,
                                                      const uint8_t *const *new_,
                                                      const uintptr_t *new_lens,
                                                      uintptr_t n,
                                                      bool strict,
                                                      struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_drop_nulls(struct polars_lazy_frame_t *lf,
                                                          const uint8_t *const *names,
                                                          const uintptr_t *lens,
                                                          uintptr_t n,
                                                          struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_with_row_index(struct polars_lazy_frame_t *lf,
                                                              const uint8_t *name,
                                                              uintptr_t name_len,
                                                              int64_t offset,
                                                              bool has_offset,
                                                              struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_explode(struct polars_lazy_frame_t *lf,
                                                       const uint8_t *const *names,
                                                       const uintptr_t *lens,
                                                       uintptr_t n,
                                                       bool empty_as_null,
                                                       bool keep_nulls,
                                                       struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_unpivot(struct polars_lazy_frame_t *lf,
                                                       const uint8_t *const *index_names,
                                                       const uintptr_t *index_lens,
                                                       uintptr_t n_index,
                                                       const uint8_t *const *on_names,
                                                       const uintptr_t *on_lens,
                                                       uintptr_t n_on,
                                                       const uint8_t *variable_name,
                                                       uintptr_t variable_name_len,
                                                       const uint8_t *value_name,
                                                       uintptr_t value_name_len,
                                                       struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_unnest(struct polars_lazy_frame_t *lf,
                                                      const uint8_t *const *names,
                                                      const uintptr_t *lens,
                                                      uintptr_t n,
                                                      const uint8_t *separator,
                                                      uintptr_t separator_len,
                                                      struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_pivot(
    struct polars_lazy_frame_t *lf,
    const uint8_t *const *on_names,
    const uintptr_t *on_lens,
    uintptr_t n_on,
    struct polars_dataframe_t *on_columns,
    const uint8_t *const *index_names,
    const uintptr_t *index_lens,
    uintptr_t n_index,
    const uint8_t *const *values_names,
    const uintptr_t *values_lens,
    uintptr_t n_values,
    const struct polars_expr_t *agg,
    bool maintain_order,
    const uint8_t *separator,
    uintptr_t separator_len,
    enum polars_pivot_column_naming_t column_naming,
    struct polars_lazy_frame_t **out);

void polars_lazy_frame_head(struct polars_lazy_frame_t *df, uintptr_t n);

void polars_lazy_frame_tail(struct polars_lazy_frame_t *df, uintptr_t n);

void polars_lazy_group_by_destroy(const struct polars_lazy_group_by_t *gb);

struct polars_lazy_frame_t *polars_lazy_group_by_agg(struct polars_lazy_group_by_t *gb,
                                                     const struct polars_expr_t *const *exprs,
                                                     uintptr_t nexprs);

void polars_expr_destroy(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_literal_bool(bool value);

const struct polars_expr_t *polars_expr_literal_i32(int32_t value);

const struct polars_expr_t *polars_expr_literal_i64(int64_t value);

const struct polars_expr_t *polars_expr_literal_u32(uint32_t value);

const struct polars_expr_t *polars_expr_literal_u64(uint64_t value);

const struct polars_expr_t *polars_expr_literal_f32(float value);

const struct polars_expr_t *polars_expr_literal_f64(double value);

const struct polars_expr_t *polars_expr_literal_null(void);

const struct polars_expr_t *polars_expr_lit_series(const struct polars_series_t *series);

const struct polars_error_t *polars_expr_literal_utf8(const uint8_t *s,
                                                      uintptr_t len,
                                                      const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_col(const uint8_t *name,
                                             uintptr_t len,
                                             const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_nth(int64_t n, const struct polars_expr_t **out);

/**
 * A placeholder for "the values in this group", used to build the `agg` expression passed to
 * `pivot` (e.g. `element().sum()`) -- substituted in-place with the actual value column filtered
 * to the current group at plan-build time.
 */
const struct polars_expr_t *polars_expr_element(void);

const struct polars_error_t *polars_expr_coalesce(const struct polars_expr_t *const *exprs,
                                                  uintptr_t n,
                                                  const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_as_struct(const struct polars_expr_t *const *exprs,
                                                   uintptr_t n,
                                                   const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_all_horizontal(const struct polars_expr_t *const *exprs,
                                                        uintptr_t n,
                                                        const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_any_horizontal(const struct polars_expr_t *const *exprs,
                                                        uintptr_t n,
                                                        const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_min_horizontal(const struct polars_expr_t *const *exprs,
                                                        uintptr_t n,
                                                        const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_max_horizontal(const struct polars_expr_t *const *exprs,
                                                        uintptr_t n,
                                                        const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_sum_horizontal(const struct polars_expr_t *const *exprs,
                                                        uintptr_t n,
                                                        bool ignore_nulls,
                                                        const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_mean_horizontal(const struct polars_expr_t *const *exprs,
                                                         uintptr_t n,
                                                         bool ignore_nulls,
                                                         const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_interpolate(const struct polars_expr_t *expr,
                                                    enum polars_interpolation_method_t method);

const struct polars_error_t *polars_expr_alias(const struct polars_expr_t *expr,
                                               const uint8_t *name,
                                               uintptr_t len,
                                               const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_prefix(const struct polars_expr_t *expr,
                                                const uint8_t *name,
                                                uintptr_t len,
                                                const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_suffix(const struct polars_expr_t *expr,
                                                const uint8_t *name,
                                                uintptr_t len,
                                                const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_keep_name(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_to_lowercase(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_to_uppercase(const struct polars_expr_t *expr);

const struct polars_error_t *polars_expr_cast(const struct polars_expr_t *expr,
                                              enum polars_value_type_t dtype,
                                              const struct polars_expr_t **out);

/**
 * Strict cast: raises on overflow/loss instead of `polars_expr_cast`'s non-strict "overflow
 * becomes null" behavior. The two modes are separate functions rather than one function with a
 * mode flag, mirroring upstream's own `Expr::strict_cast`/`Expr::cast` split (note upstream's
 * *Python* `Expr.cast(dtype, strict=True)` defaults to the strict branch, so `cast` here is the
 * non-default one).
 */
const struct polars_error_t *polars_expr_strict_cast(const struct polars_expr_t *expr,
                                                     enum polars_value_type_t dtype,
                                                     const struct polars_expr_t **out);

/**
 * Casts to `Datetime(unit, tz)`. `tz_len == 0` casts to a naive (timezone-less) Datetime.
 */
const struct polars_error_t *polars_expr_cast_datetime(const struct polars_expr_t *expr,
                                                       enum polars_time_unit_t unit,
                                                       const uint8_t *tz,
                                                       uintptr_t tz_len,
                                                       const struct polars_expr_t **out);

/**
 * Casts to `Duration(unit)`.
 */
const struct polars_error_t *polars_expr_cast_duration(const struct polars_expr_t *expr,
                                                       enum polars_time_unit_t unit,
                                                       const struct polars_expr_t **out);

/**
 * Targeted cast to `Decimal(precision, scale)` (`dtype-decimal` is already enabled). polars'
 * own invariant is `1 <= precision <= 38`; violating it surfaces as a normal cast error rather
 * than a panic (`DataType::Decimal` itself does not validate -- `cast` does, at execution time).
 */
const struct polars_expr_t *polars_expr_cast_decimal(const struct polars_expr_t *expr,
                                                     uintptr_t precision,
                                                     uintptr_t scale);

/**
 * Casts to `Categorical`, using the global category registry shared by every Categorical column
 * in the session.
 */
const struct polars_expr_t *polars_expr_cast_categorical(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_sum(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_product(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_mean(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_median(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_min(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_max(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_arg_min(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_arg_max(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_nan_min(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_nan_max(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_std(const struct polars_expr_t *expr, uint8_t ddof);

const struct polars_expr_t *polars_expr_var(const struct polars_expr_t *expr, uint8_t ddof);

const struct polars_expr_t *polars_expr_cov(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b,
                                            uint8_t ddof);

const struct polars_expr_t *polars_expr_pearson_corr(const struct polars_expr_t *a,
                                                     const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_spearman_rank_corr(const struct polars_expr_t *a,
                                                           const struct polars_expr_t *b,
                                                           bool propagate_nans);

const struct polars_expr_t *polars_expr_skew(const struct polars_expr_t *expr, bool bias);

const struct polars_expr_t *polars_expr_kurtosis(const struct polars_expr_t *expr,
                                                 bool fisher,
                                                 bool bias);

/**
 * Exponentially-weighted moving average. `alpha` must already be resolved to a concrete decay
 * factor in `(0, 1]` by the caller (the `com`/`span`/`half_life`/`alpha` parameterizations all
 * reduce to this single value client-side).
 */
const struct polars_expr_t *polars_expr_ewm_mean(const struct polars_expr_t *expr,
                                                 double alpha,
                                                 bool adjust,
                                                 uintptr_t min_samples,
                                                 bool ignore_nulls);

/**
 * Exponentially-weighted moving standard deviation. See `polars_expr_ewm_mean` for `alpha`.
 */
const struct polars_expr_t *polars_expr_ewm_std(const struct polars_expr_t *expr,
                                                double alpha,
                                                bool adjust,
                                                bool bias,
                                                uintptr_t min_samples,
                                                bool ignore_nulls);

/**
 * Exponentially-weighted moving variance. See `polars_expr_ewm_mean` for `alpha`.
 */
const struct polars_expr_t *polars_expr_ewm_var(const struct polars_expr_t *expr,
                                                double alpha,
                                                bool adjust,
                                                bool bias,
                                                uintptr_t min_samples,
                                                bool ignore_nulls);

/**
 * Bins continuous values into discrete categories given explicit breakpoints. `breaks` is a
 * plain array of cut points (not including the implicit `-inf`/`inf` ends); the result is a
 * labelled Enum column with one more category than there are breaks. `labels`, if given
 * (`n_labels > 0`), must have `breaks.len() + 1` entries; otherwise labels are generated as
 * interval strings, `"(-inf, b] "`/`"(b1, b2]"`/`"(bn, inf]"` (or `[...)"`-style if
 * `left_closed`). Raises if `breaks` contains `NaN`/duplicates/`inf`, or if `labels`' length
 * doesn't match.
 */
const struct polars_error_t *polars_expr_cut(const struct polars_expr_t *expr,
                                             const double *breaks,
                                             uintptr_t n_breaks,
                                             const uint8_t *const *labels,
                                             const uintptr_t *label_lens,
                                             uintptr_t n_labels,
                                             bool left_closed,
                                             const struct polars_expr_t **out);

/**
 * Bins continuous values into discrete categories based on their quantiles. `probs` are the
 * quantile cut points in `[0, 1]`; the result is a `Categorical` column. `allow_duplicates`
 * controls whether repeated quantile breakpoints (common with few distinct values) are silently
 * collapsed instead of raising. See `polars_expr_cut` for `labels`/error conditions.
 */
const struct polars_error_t *polars_expr_qcut(const struct polars_expr_t *expr,
                                              const double *probs,
                                              uintptr_t n_probs,
                                              const uint8_t *const *labels,
                                              const uintptr_t *label_lens,
                                              uintptr_t n_labels,
                                              bool left_closed,
                                              bool allow_duplicates,
                                              const struct polars_expr_t **out);

/**
 * Like `polars_expr_qcut`, but with `n_bins` uniformly-spaced quantile probabilities instead of
 * an explicit `probs` array.
 */
const struct polars_error_t *polars_expr_qcut_uniform(const struct polars_expr_t *expr,
                                                      uintptr_t n_bins,
                                                      const uint8_t *const *labels,
                                                      const uintptr_t *label_lens,
                                                      uintptr_t n_labels,
                                                      bool left_closed,
                                                      bool allow_duplicates,
                                                      const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_is_between(const struct polars_expr_t *expr,
                                                   const struct polars_expr_t *lower,
                                                   const struct polars_expr_t *upper,
                                                   enum polars_closed_interval_t closed);

const struct polars_expr_t *polars_expr_rolling_mean(const struct polars_expr_t *expr,
                                                     uintptr_t window_size,
                                                     uintptr_t min_periods,
                                                     bool center);

const struct polars_expr_t *polars_expr_rolling_sum(const struct polars_expr_t *expr,
                                                    uintptr_t window_size,
                                                    uintptr_t min_periods,
                                                    bool center);

const struct polars_expr_t *polars_expr_rolling_min(const struct polars_expr_t *expr,
                                                    uintptr_t window_size,
                                                    uintptr_t min_periods,
                                                    bool center);

const struct polars_expr_t *polars_expr_rolling_max(const struct polars_expr_t *expr,
                                                    uintptr_t window_size,
                                                    uintptr_t min_periods,
                                                    bool center);

const struct polars_expr_t *polars_expr_rolling_var(const struct polars_expr_t *expr,
                                                    uintptr_t window_size,
                                                    uintptr_t min_periods,
                                                    bool center,
                                                    uint8_t ddof);

const struct polars_expr_t *polars_expr_rolling_std(const struct polars_expr_t *expr,
                                                    uintptr_t window_size,
                                                    uintptr_t min_periods,
                                                    bool center,
                                                    uint8_t ddof);

const struct polars_expr_t *polars_expr_rolling_median(const struct polars_expr_t *expr,
                                                       uintptr_t window_size,
                                                       uintptr_t min_periods,
                                                       bool center);

const struct polars_expr_t *polars_expr_rolling_quantile(const struct polars_expr_t *expr,
                                                         uintptr_t window_size,
                                                         uintptr_t min_periods,
                                                         bool center,
                                                         double quantile,
                                                         enum polars_quantile_method_t method);

const struct polars_expr_t *polars_expr_when_then_otherwise(const struct polars_expr_t *cond,
                                                            const struct polars_expr_t *then,
                                                            const struct polars_expr_t *otherwise);

/**
 * Chained `when(c1).then(v1).when(c2).then(v2)....otherwise(otherwise)`, given as two parallel
 * expr-slices (`conds`/`vals`) plus a final `otherwise`. `n == 0` returns `otherwise` unchanged.
 */
const struct polars_expr_t *polars_expr_when_then(const struct polars_expr_t *const *conds,
                                                  const struct polars_expr_t *const *vals,
                                                  uintptr_t n,
                                                  const struct polars_expr_t *otherwise);

/**
 * `order_by` is a single optional expr (null = none). An empty `partition_by` with a null
 * `order_by` is valid -- the whole frame is treated as one group (see the whole-frame-sentinel
 * substitution below).
 */
const struct polars_error_t *polars_expr_over(const struct polars_expr_t *expr,
                                              const struct polars_expr_t *const *partition_by,
                                              uintptr_t n_partition_by,
                                              const struct polars_expr_t *order_by,
                                              bool descending,
                                              bool nulls_last,
                                              enum polars_window_mapping_t mapping,
                                              const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_sort_by(const struct polars_expr_t *expr,
                                                const struct polars_expr_t *const *by,
                                                uintptr_t n_by,
                                                const bool *descending,
                                                bool nulls_last,
                                                bool maintain_order);

const struct polars_expr_t *polars_expr_quantile(const struct polars_expr_t *expr,
                                                 const struct polars_expr_t *quantile,
                                                 enum polars_quantile_method_t method);

const struct polars_expr_t *polars_expr_floor(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_ceil(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_abs(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_cos(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_sin(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_tan(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_cosh(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_sinh(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_tanh(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_arccos(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_arcsin(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_arctan(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_arccosh(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_arcsinh(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_arctanh(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_cot(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_degrees(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_radians(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_sqrt(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_cbrt(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_sign(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_exp(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_log1p(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_rle(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_rle_id(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_round(const struct polars_expr_t *expr,
                                              uint32_t decimals,
                                              enum polars_round_mode_t mode);

const struct polars_expr_t *polars_expr_clip(const struct polars_expr_t *expr,
                                             const struct polars_expr_t *min,
                                             const struct polars_expr_t *max);

const struct polars_expr_t *polars_expr_neg(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_replace(const struct polars_expr_t *expr,
                                                const struct polars_expr_t *old,
                                                const struct polars_expr_t *new_);

const struct polars_expr_t *polars_expr_replace_strict(const struct polars_expr_t *expr,
                                                       const struct polars_expr_t *old,
                                                       const struct polars_expr_t *new_,
                                                       const struct polars_expr_t *default_);

const struct polars_expr_t *polars_expr_n_unique(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_unique(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_unique_stable(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_duplicated(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_unique(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_first_distinct(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_last_distinct(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_count(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_first(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_last(const struct polars_expr_t *expr);

/**
 * The aggregation form of `item()`: errors if the expression evaluates to `!= 1` values, unless
 * `allow_empty` is set, in which case zero values also succeeds (producing `null`). Distinct from
 * `DataFrame`/`Series` `item()`, which is a `(1,1)`-shape accessor, not an aggregation -- the two
 * share a name upstream but are different functions (see `plans/parity/batch-2-aggregation-
 * statistics.md`'s Step-9 finding).
 */
const struct polars_expr_t *polars_expr_item(const struct polars_expr_t *expr, bool allow_empty);

const struct polars_expr_t *polars_expr_not(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_all(const struct polars_expr_t *expr, bool ignore_nulls);

const struct polars_expr_t *polars_expr_any(const struct polars_expr_t *expr, bool ignore_nulls);

const struct polars_expr_t *polars_expr_is_finite(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_infinite(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_nan(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_null(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_not_null(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_null_count(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_drop_nans(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_drop_nulls(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_arg_sort(const struct polars_expr_t *expr,
                                                 bool descending,
                                                 bool nulls_last);

const struct polars_error_t *polars_expr_value_counts(const struct polars_expr_t *expr,
                                                      bool sort,
                                                      bool parallel,
                                                      const uint8_t *name,
                                                      uintptr_t name_len,
                                                      bool normalize,
                                                      const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_implode(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_flatten(const struct polars_expr_t *expr,
                                                bool empty_as_null,
                                                bool keep_nulls);

const struct polars_expr_t *polars_expr_reverse(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_eq(const struct polars_expr_t *a,
                                           const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_lt(const struct polars_expr_t *a,
                                           const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_gt(const struct polars_expr_t *a,
                                           const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_or(const struct polars_expr_t *a,
                                           const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_xor(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_and(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_pow(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_add(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_sub(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_mul(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_div(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_floor_div(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_clip_min(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_clip_max(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_bottom_k(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

/**
 * `shift(n, fill_value)` -- unlike the existing binary `shift(n)` (no fill), out-of-range rows
 * get `fill_value` instead of `null`.
 */
const struct polars_expr_t *polars_expr_shift_and_fill(const struct polars_expr_t *expr,
                                                       const struct polars_expr_t *n,
                                                       const struct polars_expr_t *fill_value);

const struct polars_expr_t *polars_expr_fill_null(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_fill_nan(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

/**
 * `limit` applies only to the `Backward`/`Forward` strategies and is ignored otherwise; a null
 * `limit` means unlimited.
 */
const struct polars_expr_t *polars_expr_fill_null_with_strategy(
    const struct polars_expr_t *expr,
    enum polars_fill_null_strategy_t strategy,
    const uint32_t *limit);

const struct polars_expr_t *polars_expr_is_in(const struct polars_expr_t *a,
                                              const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_shift(const struct polars_expr_t *a,
                                              const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_pct_change(const struct polars_expr_t *a,
                                                   const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_log(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_rem(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_top_k(const struct polars_expr_t *a,
                                              const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_cum_sum(const struct polars_expr_t *expr, bool reverse);

const struct polars_expr_t *polars_expr_cum_prod(const struct polars_expr_t *expr, bool reverse);

const struct polars_expr_t *polars_expr_cum_min(const struct polars_expr_t *expr, bool reverse);

const struct polars_expr_t *polars_expr_cum_max(const struct polars_expr_t *expr, bool reverse);

const struct polars_expr_t *polars_expr_cum_count(const struct polars_expr_t *expr, bool reverse);

const struct polars_expr_t *polars_expr_diff(const struct polars_expr_t *expr,
                                             const struct polars_expr_t *n,
                                             enum polars_null_behavior_t null_behavior);

const struct polars_expr_t *polars_expr_rank(const struct polars_expr_t *expr,
                                             enum polars_rank_method_t method,
                                             bool descending);

const struct polars_expr_t *polars_expr_sample_n(const struct polars_expr_t *expr,
                                                 const struct polars_expr_t *n,
                                                 bool with_replacement,
                                                 bool shuffle,
                                                 const uint64_t *seed);

const struct polars_expr_t *polars_expr_sample_frac(const struct polars_expr_t *expr,
                                                    const struct polars_expr_t *frac,
                                                    bool with_replacement,
                                                    bool shuffle,
                                                    const uint64_t *seed);

const struct polars_expr_t *polars_expr_gather(const struct polars_expr_t *expr,
                                               const struct polars_expr_t *idx,
                                               bool null_on_oob);

const struct polars_expr_t *polars_expr_gather_every(const struct polars_expr_t *expr,
                                                     uintptr_t n,
                                                     uintptr_t offset);

/**
 * `Expr::filter` -- filters `expr`'s own values by `predicate`, both evaluated in the same
 * context (typically inside `agg`, e.g. `col("x").filter(col("x") > 0).sum()`). Distinct from
 * `polars_lazy_frame_filter`, which filters a whole frame's rows.
 */
const struct polars_expr_t *polars_expr_filter(const struct polars_expr_t *expr,
                                               const struct polars_expr_t *predicate);

/**
 * `Expr::sort` -- sorts `expr`'s own values (as opposed to `polars_expr_sort_by`, which sorts by
 * a different key).
 */
const struct polars_expr_t *polars_expr_sort(const struct polars_expr_t *expr,
                                             bool descending,
                                             bool nulls_last,
                                             bool multithreaded,
                                             bool maintain_order);

/**
 * `Expr::head` -- the first `length` elements of `expr`'s result (`length: null` = upstream's
 * own default of 10).
 */
const struct polars_expr_t *polars_expr_head(const struct polars_expr_t *expr,
                                             const uintptr_t *length);

/**
 * `Expr::tail` -- the last `length` elements of `expr`'s result (`length: null` = upstream's own
 * default of 10).
 */
const struct polars_expr_t *polars_expr_tail(const struct polars_expr_t *expr,
                                             const uintptr_t *length);

/**
 * `Expr::slice` -- both `offset` and `length` are themselves expressions (typically `lit`s);
 * `offset` may be negative (counts from the end).
 */
const struct polars_expr_t *polars_expr_slice(const struct polars_expr_t *expr,
                                              const struct polars_expr_t *offset,
                                              const struct polars_expr_t *length);

/**
 * `Expr::get` -- a scalar counterpart to `polars_expr_gather` (which takes a vector of indices);
 * `index` is itself an expression (typically a `lit`), 0-based, and may be negative.
 */
const struct polars_expr_t *polars_expr_get(const struct polars_expr_t *expr,
                                            const struct polars_expr_t *index,
                                            bool null_on_oob);

const struct polars_expr_t *polars_expr_top_k_by(const struct polars_expr_t *expr,
                                                 const struct polars_expr_t *k,
                                                 const struct polars_expr_t *const *by,
                                                 uintptr_t n_by,
                                                 const bool *descending);

const struct polars_expr_t *polars_expr_bottom_k_by(const struct polars_expr_t *expr,
                                                    const struct polars_expr_t *k,
                                                    const struct polars_expr_t *const *by,
                                                    uintptr_t n_by,
                                                    const bool *descending);

const struct polars_expr_t *polars_expr_list_lengths(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_max(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_min(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_arg_max(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_arg_min(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_sum(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_mean(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_reverse(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_unique(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_unique_stable(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_n_unique(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_any(const struct polars_expr_t *a, bool ignore_nulls);

const struct polars_expr_t *polars_expr_list_all(const struct polars_expr_t *a, bool ignore_nulls);

const struct polars_expr_t *polars_expr_list_first(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_last(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_median(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_drop_nulls(const struct polars_expr_t *a);

/**
 * `Lists.eval`: runs `evaluation` once per row, with `element()` bound to that row's list values
 * -- the same primitive the crate already uses internally for `reverse`/`unique`/`unique_stable`
 * above, exposed directly. This is the multiplier for the "most of the list namespace is
 * missing" finding (`plans/parity/batch-9-lists-structs.md`): `all`/`any` have no dedicated
 * `ListNameSpace` method in this polars version at all and are *only* reachable this way
 * (`eval(element().all(ignore_nulls))`), and `n_unique`/`filter` compose the same way.
 */
const struct polars_expr_t *polars_expr_list_eval(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *evaluation);

/**
 * `Lists.agg`: like `eval`, but the per-row expression is expected to reduce to a single scalar
 * (`EvalVariant::ListAgg` instead of `::List`) -- needed for e.g. `n_unique` per row, which
 * `eval` alone cannot express (it stays list-shaped).
 */
const struct polars_expr_t *polars_expr_list_agg(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *evaluation);

const struct polars_expr_t *polars_expr_list_sort(const struct polars_expr_t *a,
                                                  bool descending,
                                                  bool nulls_last);

const struct polars_expr_t *polars_expr_list_get(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *index,
                                                 bool null_on_oob);

const struct polars_expr_t *polars_expr_list_head(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_list_tail(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_list_shift(const struct polars_expr_t *a,
                                                   const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_list_count_matches(const struct polars_expr_t *a,
                                                           const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_list_union(const struct polars_expr_t *a,
                                                   const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_list_set_difference(const struct polars_expr_t *a,
                                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_list_set_intersection(const struct polars_expr_t *a,
                                                              const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_list_set_symmetric_difference(
    const struct polars_expr_t *a, const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_list_std(const struct polars_expr_t *a, uint8_t ddof);

const struct polars_expr_t *polars_expr_list_var(const struct polars_expr_t *a, uint8_t ddof);

const struct polars_expr_t *polars_expr_list_join(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *separator,
                                                  bool ignore_nulls);

const struct polars_expr_t *polars_expr_list_slice(const struct polars_expr_t *a,
                                                   const struct polars_expr_t *offset,
                                                   const struct polars_expr_t *length);

const struct polars_expr_t *polars_expr_list_gather(const struct polars_expr_t *a,
                                                    const struct polars_expr_t *index,
                                                    bool null_on_oob);

const struct polars_expr_t *polars_expr_list_gather_every(const struct polars_expr_t *a,
                                                          const struct polars_expr_t *n,
                                                          const struct polars_expr_t *offset);

const struct polars_expr_t *polars_expr_list_diff(const struct polars_expr_t *a,
                                                  int64_t n,
                                                  enum polars_null_behavior_t null_behavior);

const struct polars_expr_t *polars_expr_list_sample_n(const struct polars_expr_t *a,
                                                      const struct polars_expr_t *n,
                                                      bool with_replacement,
                                                      bool shuffle,
                                                      const uint64_t *seed);

const struct polars_expr_t *polars_expr_list_sample_fraction(const struct polars_expr_t *a,
                                                             const struct polars_expr_t *fraction,
                                                             bool with_replacement,
                                                             bool shuffle,
                                                             const uint64_t *seed);

const struct polars_expr_t *polars_expr_list_to_array(const struct polars_expr_t *a,
                                                      uintptr_t width);

/**
 * Converts a `List` column to a `Struct` column, one field per list position, named `names[i]`.
 * `names.len()` fixes the field count (and so the schema) -- a row whose list is shorter gets
 * `null` for the missing trailing fields; longer is a runtime error (upstream's own behavior).
 */
const struct polars_error_t *polars_expr_list_to_struct(const struct polars_expr_t *a,
                                                        const uint8_t *const *names,
                                                        const uintptr_t *lens,
                                                        uintptr_t num_names,
                                                        const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_list_contains(const struct polars_expr_t *a,
                                                      const struct polars_expr_t *other,
                                                      bool nulls_equal);

const struct polars_expr_t *polars_expr_str_to_uppercase(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_str_to_lowercase(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_str_len_bytes(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_str_len_chars(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_str_starts_with(const struct polars_expr_t *a,
                                                        const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_ends_with(const struct polars_expr_t *a,
                                                      const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_contains_literal(const struct polars_expr_t *a,
                                                             const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_strip_chars(const struct polars_expr_t *a,
                                                        const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_strip_prefix(const struct polars_expr_t *a,
                                                         const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_strip_suffix(const struct polars_expr_t *a,
                                                         const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_split(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_extract_all(const struct polars_expr_t *a,
                                                        const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_zfill(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_head(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_tail(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_strip_chars_start(const struct polars_expr_t *a,
                                                              const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_strip_chars_end(const struct polars_expr_t *a,
                                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_str_replace_n(const struct polars_expr_t *a,
                                                      const struct polars_expr_t *pat,
                                                      const struct polars_expr_t *value,
                                                      bool literal,
                                                      int64_t n);

/**
 * Struct-typed split: exactly `n` fields, the remainder (if any) folded into the last one.
 * Distinct from `polars_expr_str_split` above, which produces a variable-length `List<String>`.
 */
const struct polars_expr_t *polars_expr_str_splitn(const struct polars_expr_t *a,
                                                   const struct polars_expr_t *by,
                                                   uintptr_t n);

const struct polars_expr_t *polars_expr_str_split_exact(const struct polars_expr_t *a,
                                                        const struct polars_expr_t *by,
                                                        uintptr_t n);

/**
 * Aggregating join-with-separator across *all* rows into a single value (upstream `str.join`,
 * the replacement for the deprecated `str.concat`) -- distinct from `Lists.join` above, which
 * joins each row's own list independently. `delimiter` is a plain string (not an `Expr`) because
 * the aggregation itself has no per-row context to evaluate a column expression against.
 */
const struct polars_error_t *polars_expr_str_join(const struct polars_expr_t *a,
                                                  const uint8_t *delimiter,
                                                  uintptr_t delimiter_len,
                                                  bool ignore_nulls,
                                                  const struct polars_expr_t **out);

/**
 * Named-capture-group regex extraction into a `Struct` column (one field per named group).
 * `pat` is a plain string, not an `Expr` -- upstream compiles the regex at plan time to
 * determine the output `Struct`'s schema (field names/count), so it cannot vary per row.
 */
const struct polars_error_t *polars_expr_str_extract_groups(const struct polars_expr_t *a,
                                                            const uint8_t *pat,
                                                            uintptr_t pat_len,
                                                            const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_str_contains(const struct polars_expr_t *a,
                                                     const struct polars_expr_t *pat,
                                                     bool strict);

const struct polars_expr_t *polars_expr_str_slice(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *offset,
                                                  const struct polars_expr_t *length);

/**
 * Position (not just presence, unlike `contains`) of the first regex match.
 */
const struct polars_expr_t *polars_expr_str_find(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *pat,
                                                 bool strict);

/**
 * `fill_char` crosses the FFI boundary as a `u32` codepoint (there is no C `char32_t` binding on
 * the Julia side) and is fallible since not every `u32` is a valid Unicode scalar value.
 */
const struct polars_error_t *polars_expr_str_pad_start(const struct polars_expr_t *a,
                                                       const struct polars_expr_t *length,
                                                       uint32_t fill_char,
                                                       const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_str_pad_end(const struct polars_expr_t *a,
                                                     const struct polars_expr_t *length,
                                                     uint32_t fill_char,
                                                     const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_str_replace(const struct polars_expr_t *a,
                                                    const struct polars_expr_t *pat,
                                                    const struct polars_expr_t *value,
                                                    bool literal);

const struct polars_expr_t *polars_expr_str_replace_all(const struct polars_expr_t *a,
                                                        const struct polars_expr_t *pat,
                                                        const struct polars_expr_t *value,
                                                        bool literal);

const struct polars_expr_t *polars_expr_str_extract(const struct polars_expr_t *a,
                                                    const struct polars_expr_t *pat,
                                                    uintptr_t group_index);

const struct polars_expr_t *polars_expr_str_count_matches(const struct polars_expr_t *a,
                                                          const struct polars_expr_t *pat,
                                                          bool literal);

const struct polars_error_t *polars_expr_str_to_date(const struct polars_expr_t *expr,
                                                     const uint8_t *format,
                                                     uintptr_t format_len,
                                                     bool strict,
                                                     bool exact,
                                                     const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_str_to_datetime(const struct polars_expr_t *expr,
                                                         const uint8_t *format,
                                                         uintptr_t format_len,
                                                         enum polars_time_unit_t time_unit,
                                                         bool strict,
                                                         bool exact,
                                                         const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_dt_year(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_month(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_day(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_hour(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_minute(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_second(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_weekday(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_ordinal_day(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_week(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_quarter(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_millisecond(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_microsecond(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_nanosecond(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_date(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_time(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_datetime(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_iso_year(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_is_leap_year(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_century(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_millennium(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_base_utc_offset(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_dst_offset(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_truncate(const struct polars_expr_t *a,
                                                    const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_dt_round(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_dt_offset_by(const struct polars_expr_t *a,
                                                     const struct polars_expr_t *b);

/**
 * `convert_time_zone`: re-labels the same instant into a different (mandatory) time zone,
 * e.g. UTC -> "America/New_York". Fails if `tz` is not a valid IANA time zone name.
 */
const struct polars_error_t *polars_expr_dt_convert_time_zone(const struct polars_expr_t *expr,
                                                              const uint8_t *tz,
                                                              uintptr_t tz_len,
                                                              const struct polars_expr_t **out);

/**
 * `replace_time_zone`: attaches/strips/re-attaches a time zone label to the *same* local
 * wall-clock values (unlike `convert_time_zone`, which preserves the instant).
 * `tz_len == 0` means "strip the time zone back to naive" (`time_zone = None`).
 */
const struct polars_error_t *polars_expr_dt_replace_time_zone(
    const struct polars_expr_t *expr,
    const uint8_t *tz,
    uintptr_t tz_len,
    const struct polars_expr_t *ambiguous,
    enum polars_non_existent_t non_existent,
    const struct polars_expr_t **out);

/**
 * Fallible since `polars_time_unit_t` mirrors a Julia-side `@cenum` and must reject an
 * out-of-range value rather than let `to_time_unit` panic across the FFI boundary.
 */
const struct polars_error_t *polars_expr_dt_timestamp(const struct polars_expr_t *expr,
                                                      enum polars_time_unit_t unit,
                                                      const struct polars_expr_t **out);

/**
 * Changes the underlying `TimeUnit` and rescales the data accordingly (e.g. `:ms` -> `:ns`
 * multiplies by 1e6). Compare [`polars_expr_dt_with_time_unit`], which relabels without rescaling.
 * Fallible for the same reason as [`polars_expr_dt_timestamp`] above.
 */
const struct polars_error_t *polars_expr_dt_cast_time_unit(const struct polars_expr_t *expr,
                                                           enum polars_time_unit_t unit,
                                                           const struct polars_expr_t **out);

/**
 * Relabels the underlying `TimeUnit` without touching the data (e.g. reinterpreting `:ms` values
 * as `:ns` without rescaling). Compare [`polars_expr_dt_cast_time_unit`], which rescales.
 * Fallible for the same reason as [`polars_expr_dt_timestamp`] above.
 */
const struct polars_error_t *polars_expr_dt_with_time_unit(const struct polars_expr_t *expr,
                                                           enum polars_time_unit_t unit,
                                                           const struct polars_expr_t **out);

/**
 * Combines a Date/Datetime `expr` with a Time `time`, producing a new Datetime at the given
 * `TimeUnit`. Fallible for the same reason as [`polars_expr_dt_timestamp`] above.
 */
const struct polars_error_t *polars_expr_dt_combine(const struct polars_expr_t *expr,
                                                    const struct polars_expr_t *time,
                                                    enum polars_time_unit_t unit,
                                                    const struct polars_expr_t **out);

/**
 * Replaces the named date/time components of a Date/Datetime `expr` with the values from the
 * given expressions (each may be a full column expression, not just a scalar). `ambiguous`
 * controls how a resulting local time that occurs twice (e.g. a DST fall-back) is resolved --
 * same string values as `polars_expr_dt_replace_time_zone`'s `ambiguous` parameter. Infallible:
 * unlike `combine`/`cast_time_unit`/`with_time_unit` above, every argument here is already an
 * `Expr`, with no C-enum conversion that could reject an out-of-range value.
 */
const struct polars_expr_t *polars_expr_dt_replace(const struct polars_expr_t *expr,
                                                   const struct polars_expr_t *year,
                                                   const struct polars_expr_t *month,
                                                   const struct polars_expr_t *day,
                                                   const struct polars_expr_t *hour,
                                                   const struct polars_expr_t *minute,
                                                   const struct polars_expr_t *second,
                                                   const struct polars_expr_t *microsecond,
                                                   const struct polars_expr_t *ambiguous);

const struct polars_error_t *polars_expr_dt_strftime(const struct polars_expr_t *expr,
                                                     const uint8_t *format,
                                                     uintptr_t len,
                                                     const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_dt_total_days(const struct polars_expr_t *a,
                                                      bool fractional);

const struct polars_expr_t *polars_expr_dt_total_hours(const struct polars_expr_t *a,
                                                       bool fractional);

const struct polars_expr_t *polars_expr_dt_total_minutes(const struct polars_expr_t *a,
                                                         bool fractional);

const struct polars_expr_t *polars_expr_dt_total_seconds(const struct polars_expr_t *a,
                                                         bool fractional);

const struct polars_expr_t *polars_expr_dt_total_milliseconds(const struct polars_expr_t *a,
                                                              bool fractional);

const struct polars_expr_t *polars_expr_dt_total_microseconds(const struct polars_expr_t *a,
                                                              bool fractional);

const struct polars_expr_t *polars_expr_dt_total_nanoseconds(const struct polars_expr_t *a,
                                                             bool fractional);

const struct polars_error_t *polars_expr_struct_field_by_name(const struct polars_expr_t *a,
                                                              const uint8_t *name,
                                                              uintptr_t len,
                                                              const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_struct_field_by_index(const struct polars_expr_t *a,
                                                              int64_t fieldidx);

const struct polars_error_t *polars_expr_struct_rename_fields(const struct polars_expr_t *a,
                                                              const uint8_t *const *names,
                                                              const uintptr_t *lens,
                                                              uintptr_t num_names,
                                                              const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_struct_json_encode(const struct polars_expr_t *expr);

/**
 * Applies each of `fields` to the struct's selected field(s) in place (via `pl.field("x")...`
 * inside each expression), leaving other fields untouched -- upstream `struct.with_fields`.
 */
const struct polars_expr_t *polars_expr_struct_with_fields(
    const struct polars_expr_t *a, const struct polars_expr_t *const *fields, uintptr_t n_fields);

bool polars_expr_meta_is_column(const struct polars_expr_t *expr);

bool polars_expr_meta_is_literal(const struct polars_expr_t *expr, bool allow_aliasing);

bool polars_expr_meta_has_multiple_outputs(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_meta_undo_aliases(const struct polars_expr_t *expr);

/**
 * Fails if the expression has no single well-defined output name (e.g. a wildcard or a
 * selector-expanded expression).
 */
const struct polars_error_t *polars_expr_meta_output_name(const struct polars_expr_t *expr,
                                                          const void *user,
                                                          IOCallback callback);

/**
 * Backs both `tree_format` (`display_as_dot = false`) and `show_graph` (`true`). No schema is
 * threaded through, so unresolved column types show as untyped.
 */
const struct polars_error_t *polars_expr_meta_tree_format(const struct polars_expr_t *expr,
                                                          bool display_as_dot,
                                                          const void *user,
                                                          IOCallback callback);

uintptr_t polars_expr_meta_root_names_len(const struct polars_expr_t *expr);

const struct polars_error_t *polars_expr_meta_root_names_get(const struct polars_expr_t *expr,
                                                             uintptr_t index,
                                                             const void *user,
                                                             IOCallback callback);

const struct polars_expr_t *polars_expr_selector_all(void);

/**
 * The identity element for selector combinators (`empty() | s == s`, `empty() & s == empty()`).
 */
const struct polars_expr_t *polars_expr_selector_empty(void);

const struct polars_error_t *polars_expr_selector_by_name(const uint8_t *const *names,
                                                          const uintptr_t *lens,
                                                          uintptr_t n,
                                                          bool strict,
                                                          const struct polars_expr_t **out);

/**
 * Selects columns by 0-based index; negative indices count back from the end.
 */
const struct polars_expr_t *polars_expr_selector_by_index(const int64_t *indices,
                                                          uintptr_t n,
                                                          bool strict);

/**
 * Backs `matches` (verbatim regex) and the regex-sugar `starts_with`/`ends_with`/`contains`
 * (anchored/escaped literal substrings) -- all four build a `Selector::Matches(pattern)`, differing
 * only in how `pattern` is derived from the caller's raw string. Anchoring and escaping happen
 * here, not on the Julia side: Julia has no built-in regex-metacharacter escaper (`escape_string`
 * escapes string *literals*, not regex syntax), so hand-rolling that table would otherwise have
 * to happen twice.
 */
const struct polars_error_t *polars_expr_selector_matches(enum polars_selector_match_kind_t kind,
                                                          const uint8_t *pattern,
                                                          uintptr_t len,
                                                          const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_selector_dtype_simple(
    enum polars_dtype_selector_kind_t kind);

/**
 * `ByDType(AnyOf([...]))` -- backs `string`/`boolean`/`binary`/`date`/`time` (dtypes with no
 * dedicated `DataTypeSelector` variant, so they must route through `AnyOf` rather than
 * `dtype_simple` above) and the explicit `by_dtype([...])`. Fallible per-element: `to_dtype`
 * rejects type codes that need parameters it can't carry (Datetime/Duration/Decimal/List/Struct)
 * -- see `polars_value_type_t::to_dtype`'s own doc. That is intentional here too: those
 * parametrized dtypes are reached via `dtype_simple` instead, so hitting this error path from
 * e.g. `by_dtype([Datetime])` is a real, expected error, not a bug.
 */
const struct polars_error_t *polars_expr_selector_dtype_any_of(
    const enum polars_value_type_t *value_types, uintptr_t n, const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_selector_union(const struct polars_expr_t *a,
                                                        const struct polars_expr_t *b,
                                                        const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_selector_difference(const struct polars_expr_t *a,
                                                             const struct polars_expr_t *b,
                                                             const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_selector_exclusive_or(const struct polars_expr_t *a,
                                                               const struct polars_expr_t *b,
                                                               const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_selector_intersect(const struct polars_expr_t *a,
                                                            const struct polars_expr_t *b,
                                                            const struct polars_expr_t **out);

const struct polars_error_t *polars_lazy_frame_scan_parquet(
    const uint8_t *path,
    uintptr_t pathlen,
    const uintptr_t *n_rows,
    const uint8_t *row_index_name,
    uintptr_t row_index_name_len,
    uint32_t row_index_offset,
    enum polars_parquet_parallel_strategy_t parallel,
    bool low_memory,
    bool rechunk,
    bool cache,
    bool glob,
    bool use_statistics,
    bool allow_missing_columns,
    const uint8_t *include_file_paths,
    uintptr_t include_file_paths_len,
    const bool *hive_partitioning,
    struct polars_cast_columns_policy_t cast_policy,
    const struct polars_cloud_options_t *cloud_options,
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_scan_csv(
    const uint8_t *path,
    uintptr_t pathlen,
    const uintptr_t *n_rows,
    const uint8_t *row_index_name,
    uintptr_t row_index_name_len,
    uint32_t row_index_offset,
    bool has_header,
    uint8_t separator,
    const uint8_t *quote_char,
    const uint8_t *comment_prefix,
    uintptr_t comment_prefix_len,
    uintptr_t skip_rows,
    uintptr_t skip_rows_after_header,
    const uint8_t *null_value,
    uintptr_t null_value_len,
    bool missing_is_null,
    bool truncate_ragged_lines,
    bool try_parse_dates,
    const uintptr_t *infer_schema_length,
    bool ignore_errors,
    bool low_memory,
    bool rechunk,
    bool cache,
    bool glob,
    const uint8_t *include_file_paths,
    uintptr_t include_file_paths_len,
    bool allow_missing_columns,
    const struct polars_cloud_options_t *cloud_options,
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_scan_ipc(
    const uint8_t *path,
    uintptr_t pathlen,
    const uintptr_t *n_rows,
    const uint8_t *row_index_name,
    uintptr_t row_index_name_len,
    uint32_t row_index_offset,
    bool rechunk,
    bool cache,
    bool glob,
    const uint8_t *include_file_paths,
    uintptr_t include_file_paths_len,
    const bool *hive_partitioning,
    bool allow_missing_columns,
    const struct polars_cloud_options_t *cloud_options,
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_scan_ndjson(
    const uint8_t *path,
    uintptr_t pathlen,
    const uintptr_t *n_rows,
    const uint8_t *row_index_name,
    uintptr_t row_index_name_len,
    uint32_t row_index_offset,
    const uintptr_t *infer_schema_length,
    bool ignore_errors,
    bool low_memory,
    bool rechunk,
    const uint8_t *include_file_paths,
    uintptr_t include_file_paths_len,
    const struct polars_cloud_options_t *cloud_options,
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_sink_parquet(
    struct polars_lazy_frame_t *lf,
    const uint8_t *path,
    uintptr_t pathlen,
    enum polars_parquet_compression_t compression,
    const int32_t *compression_level,
    bool statistics,
    const uintptr_t *row_group_size,
    const uintptr_t *data_page_size,
    bool mkdir,
    bool maintain_order,
    const struct polars_cloud_options_t *cloud_options,
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_sink_parquet_partitioned(
    struct polars_lazy_frame_t *lf,
    const uint8_t *base_path,
    uintptr_t base_pathlen,
    const struct polars_expr_t *const *keys,
    uintptr_t n_keys,
    bool include_keys,
    const uint64_t *max_rows_per_file,
    const uint64_t *approximate_bytes_per_file,
    enum polars_parquet_compression_t compression,
    const int32_t *compression_level,
    bool statistics,
    const uintptr_t *row_group_size,
    const uintptr_t *data_page_size,
    bool maintain_order,
    const struct polars_cloud_options_t *cloud_options,
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_sink_csv(
    struct polars_lazy_frame_t *lf,
    const uint8_t *path,
    uintptr_t pathlen,
    bool include_header,
    bool include_bom,
    uint8_t separator,
    uint8_t quote_char,
    const uint8_t *null_value,
    uintptr_t null_value_len,
    const uint8_t *line_terminator,
    uintptr_t line_terminator_len,
    enum polars_quote_style_t quote_style,
    const uint8_t *date_format,
    uintptr_t date_format_len,
    const uint8_t *time_format,
    uintptr_t time_format_len,
    const uint8_t *datetime_format,
    uintptr_t datetime_format_len,
    const uintptr_t *float_precision,
    bool decimal_comma,
    enum polars_csv_compression_t compression,
    const uint32_t *compression_level,
    bool mkdir,
    bool maintain_order,
    const struct polars_cloud_options_t *cloud_options,
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_sink_ipc(
    struct polars_lazy_frame_t *lf,
    const uint8_t *path,
    uintptr_t pathlen,
    enum polars_ipc_compression_t compression,
    const int32_t *compression_level,
    const uintptr_t *record_batch_size,
    bool mkdir,
    bool maintain_order,
    const struct polars_cloud_options_t *cloud_options,
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_sink_ndjson(
    struct polars_lazy_frame_t *lf,
    const uint8_t *path,
    uintptr_t pathlen,
    bool mkdir,
    bool maintain_order,
    const struct polars_cloud_options_t *cloud_options,
    struct polars_lazy_frame_t **out);

/**
 * Builds a `polars_cloud_options_t` from parallel `(ptr-array, len-array, n)` key/value pairs --
 * e.g. `("aws_access_key_id", "...")`. The pairs are stored unparsed (see the type's own doc
 * comment in `types.rs`); actual `CloudOptions` construction is deferred to each scan/sink call
 * site, once the destination path (and so the cloud scheme) is known.
 */
const struct polars_error_t *polars_cloud_options_new(const uint8_t *const *keys,
                                                      const uintptr_t *key_lens,
                                                      const uint8_t *const *values,
                                                      const uintptr_t *value_lens,
                                                      uintptr_t n,
                                                      struct polars_cloud_options_t **out);

void polars_cloud_options_destroy(struct polars_cloud_options_t *ptr);

void polars_series_destroy(struct polars_series_t *series);

enum polars_value_type_t polars_series_type(struct polars_series_t *series);

uintptr_t polars_series_length(struct polars_series_t *series);

uintptr_t polars_series_null_count(struct polars_series_t *series);

const struct polars_error_t *polars_series_schema(struct polars_series_t *series, ArrowSchema *out);

/**
 * Exports the series' data as a single Arrow C Data Interface `ArrowArray`, collapsing the
 * series to one chunk first if necessary. The returned `ArrowArray` is self-contained (owns its
 * buffers via the release callback) and can outlive `series` -- the caller takes ownership and
 * must eventually invoke `.release` exactly once.
 */
const struct polars_error_t *polars_series_export_carray(struct polars_series_t *series,
                                                         ArrowArray *out);

/**
 * Returns whether or not the value at index `index` is null, return false if the index is out of
 * bounds.
 */
bool polars_series_is_null(struct polars_series_t *series, uintptr_t index);

/**
 * Returns a new owned series holding a zero-copy (Arc-refcount clone) slice of `length` elements
 * starting at `offset`.
 */
struct polars_series_t *polars_series_slice(struct polars_series_t *series,
                                            int64_t offset,
                                            uintptr_t length);

/**
 * Borrowed pointer into the series' name, valid only as long as `series` is alive.
 */
uintptr_t polars_series_name(struct polars_series_t *series, const uint8_t **out);

const struct polars_error_t *polars_series_get(struct polars_series_t *series,
                                               uintptr_t index,
                                               struct polars_value_t **out);

const struct polars_error_t *polars_series_get_bool(struct polars_series_t *series,
                                                    uintptr_t index,
                                                    bool *out);

const struct polars_error_t *polars_series_get_u8(struct polars_series_t *series,
                                                  uintptr_t index,
                                                  uint8_t *out);

const struct polars_error_t *polars_series_get_u16(struct polars_series_t *series,
                                                   uintptr_t index,
                                                   uint16_t *out);

const struct polars_error_t *polars_series_get_u32(struct polars_series_t *series,
                                                   uintptr_t index,
                                                   uint32_t *out);

const struct polars_error_t *polars_series_get_u64(struct polars_series_t *series,
                                                   uintptr_t index,
                                                   uint64_t *out);

const struct polars_error_t *polars_series_get_i8(struct polars_series_t *series,
                                                  uintptr_t index,
                                                  int8_t *out);

const struct polars_error_t *polars_series_get_i16(struct polars_series_t *series,
                                                   uintptr_t index,
                                                   int16_t *out);

const struct polars_error_t *polars_series_get_i32(struct polars_series_t *series,
                                                   uintptr_t index,
                                                   int32_t *out);

const struct polars_error_t *polars_series_get_i64(struct polars_series_t *series,
                                                   uintptr_t index,
                                                   int64_t *out);

const struct polars_error_t *polars_series_get_f32(struct polars_series_t *series,
                                                   uintptr_t index,
                                                   float *out);

const struct polars_error_t *polars_series_get_f64(struct polars_series_t *series,
                                                   uintptr_t index,
                                                   double *out);

enum polars_time_unit_t polars_value_time_unit(struct polars_value_t *value);

/**
 * Borrowed pointer into this datetime value's timezone name, valid as long as `value` is alive.
 * Returns 0 (and leaves `out` unwritten) for a naive datetime or any non-datetime value.
 */
uintptr_t polars_value_time_zone(struct polars_value_t *value, const uint8_t **out);

enum polars_value_type_t polars_value_type(struct polars_value_t *value);

void polars_value_destroy(struct polars_value_t *value);

const struct polars_error_t *polars_value_get_bool(struct polars_value_t *value, bool *out);

const struct polars_error_t *polars_value_get_u8(struct polars_value_t *value, uint8_t *out);

const struct polars_error_t *polars_value_get_u16(struct polars_value_t *value, uint16_t *out);

const struct polars_error_t *polars_value_get_u32(struct polars_value_t *value, uint32_t *out);

const struct polars_error_t *polars_value_get_u64(struct polars_value_t *value, uint64_t *out);

const struct polars_error_t *polars_value_get_i8(struct polars_value_t *value, int8_t *out);

const struct polars_error_t *polars_value_get_i16(struct polars_value_t *value, int16_t *out);

const struct polars_error_t *polars_value_get_i32(struct polars_value_t *value, int32_t *out);

const struct polars_error_t *polars_value_get_i64(struct polars_value_t *value, int64_t *out);

const struct polars_error_t *polars_value_get_f32(struct polars_value_t *value, float *out);

const struct polars_error_t *polars_value_get_f64(struct polars_value_t *value, double *out);

/**
 * Returns the value as a Series when the dtype of the value is a list.
 */
const struct polars_error_t *polars_value_list_get(struct polars_value_t *value,
                                                   struct polars_series_t **out);

const struct polars_error_t *polars_value_string_get(struct polars_value_t *value,
                                                     const void *user,
                                                     IOCallback callback);

/**
 * Get the underlying int64 for this duration value.
 */
const struct polars_error_t *polars_value_duration_get(struct polars_value_t *value, int64_t *out);

/**
 * Get the underlying int64 for this datetime value.
 */
const struct polars_error_t *polars_value_datetime_get(struct polars_value_t *value, int64_t *out);

/**
 * Get the underlying int32 (days since UNIX epoch) for this date value.
 */
const struct polars_error_t *polars_value_date_get(struct polars_value_t *value, int32_t *out);

/**
 * Get the underlying int64 for this time value. `DataType::Time` is always nanoseconds since
 * midnight (unlike Datetime/Duration, it carries no `TimeUnit`), so there is no companion
 * `polars_value_time_unit`-style call for it.
 */
const struct polars_error_t *polars_value_time_get(struct polars_value_t *value, int64_t *out);

const struct polars_error_t *polars_value_binary_get(struct polars_value_t *value,
                                                     const void *user,
                                                     IOCallback callback);

/**
 * Returns the value of struct field `fieldidx`. The result owns its data (see `polars_value_t`),
 * so it may outlive `value` and be destroyed in any order relative to it.
 */
const struct polars_error_t *polars_value_struct_get(struct polars_value_t *value,
                                                     uintptr_t fieldidx,
                                                     struct polars_value_t **out);

/**
 * Returns the element type of the provided value which must be a list.
 * The value type is PolarsValueTypeUnknown if the value is not a list
 * so makes sure it is one otherwise, you cannot differentiate between list<unkown>
 * and unkown.
 */
enum polars_value_type_t polars_value_list_type(struct polars_value_t *value);
