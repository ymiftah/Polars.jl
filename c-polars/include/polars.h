#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include "arrow.h"

typedef enum PolarsEngine {
  PolarsEngineInMemory,
  PolarsEngineStreaming,
} PolarsEngine;

typedef enum polars_time_unit_t {
  PolarsTimeUnitNanosecond,
  PolarsTimeUnitMicrosecond,
  PolarsTimeUnitMillisecond,
  PolarsTimeUnitInvalid,
} polars_time_unit_t;

typedef enum polars_closed_window_t {
  PolarsClosedWindowLeft,
  PolarsClosedWindowRight,
  PolarsClosedWindowBoth,
  PolarsClosedWindowNone,
} polars_closed_window_t;

typedef enum polars_label_t {
  PolarsLabelLeft,
  PolarsLabelRight,
  PolarsLabelDataPoint,
} polars_label_t;

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
  PolarsValueTypeUnknown,
} polars_value_type_t;

typedef enum polars_quantile_method_t {
  PolarsQuantileMethodNearest,
  PolarsQuantileMethodLower,
  PolarsQuantileMethodHigher,
  PolarsQuantileMethodMidpoint,
  PolarsQuantileMethodLinear,
  PolarsQuantileMethodEquiprobable,
} polars_quantile_method_t;

typedef enum polars_null_behavior_t {
  PolarsNullBehaviorDrop,
  PolarsNullBehaviorIgnore,
} polars_null_behavior_t;

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

typedef enum polars_non_existent_t {
  PolarsNonExistentRaise,
  PolarsNonExistentNull,
} polars_non_existent_t;

typedef enum polars_join_type_t {
  PolarsJoinTypeInner,
  PolarsJoinTypeLeft,
  PolarsJoinTypeRight,
  PolarsJoinTypeFull,
  PolarsJoinTypeSemi,
  PolarsJoinTypeAnti,
  PolarsJoinTypeCross,
} polars_join_type_t;

typedef enum polars_asof_strategy_t {
  PolarsAsofStrategyBackward,
  PolarsAsofStrategyForward,
  PolarsAsofStrategyNearest,
} polars_asof_strategy_t;

typedef enum polars_pivot_column_naming_t {
  PolarsPivotColumnNamingCombine,
  PolarsPivotColumnNamingAuto,
} polars_pivot_column_naming_t;

typedef enum polars_unique_keep_t {
  PolarsUniqueKeepFirst,
  PolarsUniqueKeepLast,
  PolarsUniqueKeepNone,
  PolarsUniqueKeepAny,
} polars_unique_keep_t;

typedef enum polars_csv_compression_t {
  PolarsCsvCompressionUncompressed,
  PolarsCsvCompressionGzip,
  PolarsCsvCompressionZstd,
} polars_csv_compression_t;

typedef enum polars_ipc_compression_t {
  PolarsIpcCompressionUncompressed,
  PolarsIpcCompressionLz4,
  PolarsIpcCompressionZstd,
} polars_ipc_compression_t;

typedef enum polars_quote_style_t {
  PolarsQuoteStyleNecessary,
  PolarsQuoteStyleAlways,
  PolarsQuoteStyleNonNumeric,
  PolarsQuoteStyleNever,
} polars_quote_style_t;

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

typedef struct polars_dataframe_t polars_dataframe_t;

typedef struct polars_error_t polars_error_t;

typedef struct polars_expr_t polars_expr_t;

typedef struct polars_lazy_frame_t polars_lazy_frame_t;

typedef struct polars_lazy_group_by_t polars_lazy_group_by_t;

typedef struct polars_series_t polars_series_t;

typedef struct polars_value_t polars_value_t;

/**
 * The callback provided for display functions, returns -1 on error.
 */
typedef intptr_t (*IOCallback)(const void *user, const uint8_t *data, uintptr_t len);

uintptr_t polars_version(const uint8_t **out);

uintptr_t polars_error_message(const struct polars_error_t *err, const uint8_t **data);

void polars_error_destroy(const struct polars_error_t *err);

void polars_dataframe_size(struct polars_dataframe_t *df, uintptr_t *rows, uintptr_t *cols);

/**
 * Creates a DataFrame from a series of ArrowArray and ArrowSchema compatible the arrow C-ABI.
 *
 * # Safety
 * The field array should be valid ArrowSchema according to the C Data Interface.
 * The array array should be valid ArrowArray according to the C Data Interface,
 * this means that the memory ownership is transferred in the created arrow::Array.
 * Therefore, the caller should *not* free the underlying memories for this arrow as this
 * will be done through the release field of the array.
 *
 * Returns null if something went wrong.
 */
struct polars_dataframe_t *polars_dataframe_new_from_carrow(const ArrowSchema *cfield,
                                                            ArrowArray carray);

/**
 * Returns a ArrowSchema describing the dataframe's schema according to Arrow C Data interface.
 */
ArrowSchema polars_dataframe_schema(struct polars_dataframe_t *df);

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

const struct polars_error_t *polars_dataframe_write_ipc(struct polars_dataframe_t *df,
                                                        const void *user,
                                                        IOCallback callback,
                                                        enum polars_ipc_compression_t compression,
                                                        const int32_t *compression_level,
                                                        const uintptr_t *record_batch_size);

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

void polars_lazy_frame_destroy(struct polars_lazy_frame_t *df);

struct polars_lazy_frame_t *polars_lazy_frame_clone(struct polars_lazy_frame_t *df);

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
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_scan_csv(const uint8_t *path,
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
                                                        struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_scan_ipc(const uint8_t *path,
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
    struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_sink_csv(struct polars_lazy_frame_t *lf,
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
                                                        struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_sink_ipc(struct polars_lazy_frame_t *lf,
                                                        const uint8_t *path,
                                                        uintptr_t pathlen,
                                                        enum polars_ipc_compression_t compression,
                                                        const int32_t *compression_level,
                                                        const uintptr_t *record_batch_size,
                                                        bool mkdir,
                                                        bool maintain_order,
                                                        struct polars_lazy_frame_t **out);

void polars_lazy_frame_sort(struct polars_lazy_frame_t *df,
                            const struct polars_expr_t *const *exprs,
                            uintptr_t nexprs,
                            const bool *descending,
                            bool nulls_last,
                            bool maintain_order);

const struct polars_error_t *polars_lazy_frame_concat(struct polars_lazy_frame_t *const *lfs,
                                                      uintptr_t n,
                                                      struct polars_lazy_frame_t **out);

void polars_lazy_frame_with_columns(struct polars_lazy_frame_t *df,
                                    const struct polars_expr_t *const *exprs,
                                    uintptr_t nexprs);

void polars_lazy_frame_select(struct polars_lazy_frame_t *df,
                              const struct polars_expr_t *const *exprs,
                              uintptr_t nexprs);

void polars_lazy_frame_filter(struct polars_lazy_frame_t *df, const struct polars_expr_t *expr);

void polars_lazy_frame_head(struct polars_lazy_frame_t *df, uintptr_t n);

const struct polars_error_t *polars_lazy_frame_collect(struct polars_lazy_frame_t *df,
                                                       enum PolarsEngine engine,
                                                       struct polars_dataframe_t **out);

/**
 * Resolves the lazy frame's schema (without collecting it) and returns it as an ArrowSchema
 * according to the Arrow C Data interface, matching the shape of `polars_dataframe_schema`.
 */
const struct polars_error_t *polars_lazy_frame_collect_schema(struct polars_lazy_frame_t *df,
                                                              ArrowSchema *out);

struct polars_lazy_group_by_t *polars_lazy_frame_group_by(struct polars_lazy_frame_t *df,
                                                          const struct polars_expr_t *const *exprs,
                                                          uintptr_t nexprs);

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
    polars_label_t label,
    bool include_boundaries,
    polars_closed_window_t closed_window,
    polars_start_by_t start_by,
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
    polars_closed_window_t closed_window,
    struct polars_lazy_group_by_t **out);

struct polars_lazy_frame_t *polars_lazy_frame_join(struct polars_lazy_frame_t *a,
                                                   struct polars_lazy_frame_t *b,
                                                   const struct polars_expr_t *const *exprs_a,
                                                   uintptr_t exprs_a_len,
                                                   const struct polars_expr_t *const *exprs_b,
                                                   uintptr_t exprs_b_len,
                                                   enum polars_join_type_t how);

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
                                                         struct polars_lazy_frame_t **out);

const struct polars_error_t *polars_lazy_frame_unique(struct polars_lazy_frame_t *lf,
                                                      const uint8_t *const *names,
                                                      const uintptr_t *lens,
                                                      uintptr_t n,
                                                      enum polars_unique_keep_t keep,
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

typedef enum polars_interpolation_method_t {
  PolarsInterpolationMethodLinear,
  PolarsInterpolationMethodNearest,
} polars_interpolation_method_t;

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

const struct polars_expr_t *polars_expr_cast(const struct polars_expr_t *expr,
                                             enum polars_value_type_t dtype);

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

const struct polars_expr_t *polars_expr_when_then_otherwise(const struct polars_expr_t *cond,
                                                            const struct polars_expr_t *then,
                                                            const struct polars_expr_t *otherwise);

const struct polars_error_t *polars_expr_over(const struct polars_expr_t *expr,
                                              const struct polars_expr_t *const *partition_by,
                                              uintptr_t n_partition_by,
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

const struct polars_expr_t *polars_expr_sqrt(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_sign(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_exp(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_log(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_rem(const struct polars_expr_t *a,
                                            const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_top_k(const struct polars_expr_t *a,
                                              const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_round(const struct polars_expr_t *expr,
                                              uint32_t decimals,
                                              enum polars_round_mode_t mode);

const struct polars_expr_t *polars_expr_clip(const struct polars_expr_t *expr,
                                             const struct polars_expr_t *min,
                                             const struct polars_expr_t *max);

const struct polars_expr_t *polars_expr_replace(const struct polars_expr_t *expr,
                                                const struct polars_expr_t *old,
                                                const struct polars_expr_t *new_);

const struct polars_expr_t *polars_expr_replace_strict(const struct polars_expr_t *expr,
                                                       const struct polars_expr_t *old,
                                                       const struct polars_expr_t *new_,
                                                       const struct polars_expr_t *default_);

const struct polars_expr_t *polars_expr_n_unique(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_unique(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_duplicated(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_is_unique(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_count(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_first(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_last(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_not(const struct polars_expr_t *expr);

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

const struct polars_expr_t *polars_expr_flatten(const struct polars_expr_t *expr);

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

const struct polars_expr_t *polars_expr_fill_null(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_fill_nan(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_is_in(const struct polars_expr_t *a,
                                              const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_shift(const struct polars_expr_t *a,
                                              const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_pct_change(const struct polars_expr_t *a,
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

const struct polars_expr_t *polars_expr_list_first(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_last(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_list_get(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *index,
                                                 bool null_on_oob);

const struct polars_expr_t *polars_expr_list_head(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *b);

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

const struct polars_expr_t *polars_expr_str_contains(const struct polars_expr_t *a,
                                                     const struct polars_expr_t *pat,
                                                     bool strict);

const struct polars_expr_t *polars_expr_str_slice(const struct polars_expr_t *a,
                                                  const struct polars_expr_t *offset,
                                                  const struct polars_expr_t *length);

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

const struct polars_expr_t *polars_expr_dt_truncate(const struct polars_expr_t *a,
                                                    const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_dt_round(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_dt_offset_by(const struct polars_expr_t *a,
                                                     const struct polars_expr_t *b);

const struct polars_error_t *polars_expr_dt_convert_time_zone(const struct polars_expr_t *expr,
                                                              const uint8_t *tz,
                                                              uintptr_t tz_len,
                                                              const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_dt_replace_time_zone(
    const struct polars_expr_t *expr,
    const uint8_t *tz,
    uintptr_t tz_len,
    const struct polars_expr_t *ambiguous,
    enum polars_non_existent_t non_existent,
    const struct polars_expr_t **out);

const struct polars_error_t *polars_expr_dt_strftime(const struct polars_expr_t *expr,
                                                     const uint8_t *format,
                                                     uintptr_t len,
                                                     const struct polars_expr_t **out);

const struct polars_expr_t *polars_expr_struct_field_by_name(const struct polars_expr_t *a,
                                                             const uint8_t *name,
                                                             uintptr_t len);

const struct polars_expr_t *polars_expr_struct_field_by_index(const struct polars_expr_t *a,
                                                              int64_t fieldidx);

const struct polars_expr_t *polars_expr_struct_rename_fields(const struct polars_expr_t *a,
                                                             const uint8_t *const *names,
                                                             const uintptr_t *lens,
                                                             uintptr_t num_names);

void polars_series_destroy(struct polars_series_t *series);

enum polars_value_type_t polars_series_type(struct polars_series_t *series);

uintptr_t polars_series_length(struct polars_series_t *series);

uintptr_t polars_series_null_count(struct polars_series_t *series);

ArrowSchema polars_series_schema(struct polars_series_t *series);

/**
 * Exports the series' data as a single Arrow C Data Interface `ArrowArray`, collapsing the
 * series to one chunk first if necessary. The returned `ArrowArray` is self-contained (owns its
 * buffers via the release callback) and can outlive `series` -- the caller takes ownership and
 * must eventually invoke `.release` (directly or via a Julia-side keeper/finalizer) exactly
 * once.
 */
ArrowArray polars_series_export_carray(struct polars_series_t *series);

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
                                                     void *user,
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

const struct polars_error_t *polars_value_binary_get(struct polars_value_t *value,
                                                     void *user,
                                                     IOCallback callback);

/**
 * Used to get value of of a Struct value fields.
 *
 * NOTE: The value producing the new value must outlive the value from the field.
 *
 * Safety: Values lifetimes must be valid and only support physical dtypes for now.
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
