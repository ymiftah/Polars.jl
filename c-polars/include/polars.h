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
 * Zero-Julia-arg `DataTypeSelector` leaves. Includes four variants that are parametrized in Rust
 * but exposed "any unit/any tz"-only from Julia (`Datetime`/`Duration`/`List`/`Array`) -- see the
 * gap-closure plan's Phase 2 first-cut scope exclusions: no specific time-unit/zone matching, no
 * recursive List/Array inner-selector composition in this cut.
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

typedef enum polars_join_type_t {
  PolarsJoinTypeInner,
  PolarsJoinTypeLeft,
  PolarsJoinTypeRight,
  PolarsJoinTypeFull,
  PolarsJoinTypeSemi,
  PolarsJoinTypeAnti,
  PolarsJoinTypeCross,
} polars_join_type_t;

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
 * Deviates from every other opaque handle in this crate, which wrap a real polars type: this one
 * wraps the *unparsed* key/value option pairs, because `CloudOptions` cannot be constructed
 * without knowing the target cloud scheme (`CloudScheme::from_path`), and the scheme is only
 * known once the destination path is available -- i.e. at each scan/sink call site, not here.
 * Resolution therefore happens per call (see `polars_lazy_frame_scan_parquet` etc.).
 */
typedef struct polars_cloud_options_t polars_cloud_options_t;

typedef struct polars_dataframe_t polars_dataframe_t;

typedef struct polars_error_t polars_error_t;

typedef struct polars_expr_t polars_expr_t;

typedef struct polars_lazy_frame_t polars_lazy_frame_t;

typedef struct polars_lazy_group_by_t polars_lazy_group_by_t;

typedef struct polars_series_t polars_series_t;

/**
 * Borrows from its parent (a `Series`, or another `polars_value_t` for struct-field access via
 * `polars_value_struct_get`) rather than owning its data. The lifetime parameter enforces
 * nothing across the C boundary -- it is a caller invariant, not a compiler-checked one: the
 * caller must keep the parent alive for as long as this value is alive, and must destroy this
 * value before the parent. The Julia side roots the parent via `Value.parent` (`src/value.jl`).
 * See `polars_value_struct_get`'s `# Safety` doc for the struct-field case specifically.
 */
typedef struct polars_value_t polars_value_t;

/**
 * The callback provided for display functions, returns -1 on error.
 */
typedef intptr_t (*IOCallback)(const void *user, const uint8_t *data, uintptr_t len);

uintptr_t polars_version(const uint8_t **out);

/**
 * Borrowed pointer into the error's message, valid only as long as `err` is alive (same
 * convention as `polars_series_name`).
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
 * Attaches loose `Series` as new columns (unlike `concat`'s `:horizontal` mode, which joins two
 * full `DataFrame`s side by side -- this is the real value-add: no second `DataFrame` needed).
 * `hstack(&self, ...)` only reads `df`, so no clone/mutation is needed here. A length mismatch
 * between `series` and `df`'s existing height, or a name collision with an existing column (or
 * between two of the given `series` themselves), surfaces as a clean `PolarsError` from
 * `DataFrame::new`'s own validation (`validate_columns_slice`) -- not a panic (verified live, see
 * `plans/definitive_guide_gap_closure.md`).
 */
const struct polars_error_t *polars_dataframe_hstack(struct polars_dataframe_t *df,
                                                     struct polars_series_t *const *series,
                                                     uintptr_t n,
                                                     struct polars_dataframe_t **out);

/**
 * Stacks `other`'s rows beneath `df`'s. `vstack(&self, other: &DataFrame)` only reads both
 * inputs, so no clone/mutation is needed here. Unlike `concat`'s `:vertical_relaxed` mode,
 * `vstack` does no supertype casting -- a genuine column-count/dtype mismatch between `df` and
 * `other` surfaces as a clean `PolarsError`, not a panic (verified live).
 */
const struct polars_error_t *polars_dataframe_vstack(struct polars_dataframe_t *df,
                                                     struct polars_dataframe_t *other,
                                                     struct polars_dataframe_t **out);

/**
 * Transposes rows and columns. Upstream `transpose(&mut self, ...)` needs `&mut self` (it
 * rechunks/materializes `self` in place before transposing) -- unlike `hstack`/`vstack` above,
 * this repo's "no caller observes the mutation" convention means we operate on a clone
 * (`.inner.clone()`, a cheap Arc-level clone) rather than `&mut (*df).inner` directly.
 *
 * Only two of upstream's three `new_col_names` modes are supported here: omitted (`None`,
 * auto-generated `"column_N"` names) and an explicit `Vec<String>` (`Either::Right`) -- a
 * zero-length `new_col_names` array is treated as "omitted", the same "empty means None"
 * convention `selector_by_name_opt` already uses elsewhere in this file. py-polars' third mode
 * (`Either::Left`: an existing column's *values* become the new names) is a deliberate scope cut
 * for this first pass, not an oversight.
 *
 * A `new_col_names` of the wrong length (relative to the transposed frame's row count, i.e.
 * `df`'s original *column* count) surfaces as a clean `ShapeMismatch` `PolarsError` from
 * `transpose_impl`'s own `polars_ensure!` check, not an index-out-of-bounds panic (verified
 * live, despite looking like a real risk on paper -- see `plans/definitive_guide_gap_closure.md`).
 * The upstream `Object`-dtype `polars_bail!` arm is a non-issue here (the `object` Cargo feature
 * isn't enabled anywhere in this crate, so no `Object`-dtype column can ever exist to hit it);
 * Struct/List columns instead fall through to the generic supertype-cast path and surface a
 * clean `PolarsError` there (verified live).
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
 * `how` selects the concat mode. Vertical/relaxed/diagonal/relaxed-diagonal all go through the
 * already-used `concat` (upstream's `concat_lf_diagonal` convenience wrapper is just `concat`
 * with `diagonal: true` set -- reusing `concat` directly needs no extra Cargo feature, unlike
 * that wrapper, which is gated behind `diagonal_concat`). `Horizontal` goes through the
 * ungated `concat_lf_horizontal` instead -- a structurally different join, not a `UnionArgs`
 * variant, so it can't share the `concat` call.
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
 * Targeted cast to `Datetime(unit, tz)` -- `polars_value_type_t::to_dtype` deliberately rejects
 * this (it needs parameters a plain type code can't carry). `tz_len == 0` casts to a naive
 * (timezone-less) Datetime, matching `read_opt_str`'s null-means-None convention.
 */
const struct polars_error_t *polars_expr_cast_datetime(const struct polars_expr_t *expr,
                                                       enum polars_time_unit_t unit,
                                                       const uint8_t *tz,
                                                       uintptr_t tz_len,
                                                       const struct polars_expr_t **out);

/**
 * Targeted cast to `Duration(unit)` -- see `polars_expr_cast_datetime`'s doc for why this needs
 * its own entry point rather than going through the plain type-code `cast`.
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
 * Targeted cast to `Categorical`, using the global category registry (`Categories::global()`,
 * the same one every other Categorical column in a session shares -- matching py-polars'
 * default). Reading a Categorical column back already materializes it as `String` (see
 * `polars_value_type_t::from_dtype`), so no new read path is needed for the round trip.
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

const struct polars_expr_t *polars_expr_when_then_otherwise(const struct polars_expr_t *cond,
                                                            const struct polars_expr_t *then,
                                                            const struct polars_expr_t *otherwise);

/**
 * Chained `when(c1).then(v1).when(c2).then(v2)....otherwise(otherwise)`, flattened into two
 * parallel expr-slices (`conds`/`vals`) + a final `otherwise` -- no new builder-type FFI handle
 * is needed since `When`/`Then`/`ChainedWhen`/`ChainedThen` all fold to a single right-nested
 * `Expr::Ternary` chain, buildable directly with the existing `when`/`Then::otherwise` free
 * functions already used by `polars_expr_when_then_otherwise` above. `n == 0` degenerates to
 * `otherwise` unchanged.
 */
const struct polars_expr_t *polars_expr_when_then(const struct polars_expr_t *const *conds,
                                                  const struct polars_expr_t *const *vals,
                                                  uintptr_t n,
                                                  const struct polars_expr_t *otherwise);

/**
 * `order_by` is a single optional expr (null = none); `over_with_options` itself supports a
 * `Vec` of order-by columns (folding >1 into a struct key), but a single column covers the
 * common case and avoids pulling in that extra marshalling for now. `partition_by` and
 * `order_by` can't both be empty/null (upstream requires at least one).
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

const struct polars_expr_t *polars_expr_degrees(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_radians(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_sqrt(const struct polars_expr_t *expr);

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

/**
 * `limit` (Backward/Forward only, ignored otherwise -- see
 * `polars_fill_null_strategy_t::to_fill_null_strategy`) is the optional-scalar null-means-None
 * convention used elsewhere (e.g. `sample_n`'s `seed`).
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

const struct polars_expr_t *polars_expr_dt_date(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_time(const struct polars_expr_t *a);

const struct polars_expr_t *polars_expr_dt_truncate(const struct polars_expr_t *a,
                                                    const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_dt_round(const struct polars_expr_t *a,
                                                 const struct polars_expr_t *b);

const struct polars_expr_t *polars_expr_dt_offset_by(const struct polars_expr_t *a,
                                                     const struct polars_expr_t *b);

/**
 * `convert_time_zone`: re-labels the same instant into a different (mandatory) time zone,
 * e.g. UTC -> "America/New_York". Fails (via the out-param error convention) if `tz` is not a
 * valid IANA time zone name.
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

bool polars_expr_meta_is_column(const struct polars_expr_t *expr);

bool polars_expr_meta_is_literal(const struct polars_expr_t *expr, bool allow_aliasing);

bool polars_expr_meta_has_multiple_outputs(const struct polars_expr_t *expr);

const struct polars_expr_t *polars_expr_meta_undo_aliases(const struct polars_expr_t *expr);

/**
 * `output_name()` is fallible (`PolarsResult<PlSmallStr>`) -- e.g. a wildcard or a
 * selector-expanded expression has no single well-defined output name. Written back through the
 * shared `IOCallback` machinery, same convention as `polars_value_string_get`.
 */
const struct polars_error_t *polars_expr_meta_output_name(const struct polars_expr_t *expr,
                                                          const void *user,
                                                          IOCallback callback);

/**
 * Backs both `tree_format` (`display_as_dot = false`) and `show_graph` (`true`) via the single
 * upstream `into_tree_formatter` code path. No schema is threaded through (`None`) -- unresolved
 * column types show as untyped; a schema-aware overload is a plausible future enhancement, not
 * blocking here.
 */
const struct polars_error_t *polars_expr_meta_tree_format(const struct polars_expr_t *expr,
                                                          bool display_as_dot,
                                                          const void *user,
                                                          IOCallback callback);

/**
 * `root_names()` count + per-index `IOCallback` loop below. `root_names()` itself recomputes a
 * fresh `Vec<PlSmallStr>` on every call (cheap, and the count is always small), so this pair
 * recomputes it N+1 times across a full `_len` + N x `_get` loop -- an accepted, documented
 * non-blocking perf micro-note from the gap-closure plan, not an oversight.
 */
uintptr_t polars_expr_meta_root_names_len(const struct polars_expr_t *expr);

const struct polars_error_t *polars_expr_meta_root_names_get(const struct polars_expr_t *expr,
                                                             uintptr_t index,
                                                             const void *user,
                                                             IOCallback callback);

const struct polars_expr_t *polars_expr_selector_all(void);

/**
 * `Selector::Empty` -- the identity element for the combinators below (`empty() | s == s`,
 * `empty() & s == empty()`). Not reachable from the public `Selectors` surface on the Julia side
 * in this first cut (see the gap-closure plan's Phase 2 scope note); kept here as a primitive
 * since it is the natural base case underlying `Selector`'s own algebra.
 */
const struct polars_expr_t *polars_expr_selector_empty(void);

const struct polars_error_t *polars_expr_selector_by_name(const uint8_t *const *names,
                                                          const uintptr_t *lens,
                                                          uintptr_t n,
                                                          bool strict,
                                                          const struct polars_expr_t **out);

/**
 * `Selector::ByIndex` -- 0-based upstream (negative indices already count back from the end via
 * `negative_to_usize` inside `into_columns`, so no extra Rust-side handling is needed here). The
 * Julia-facing `Selectors.by_index` is 1-based (matching this package's own `nth`) and converts
 * down to this 0-based primitive before calling in -- see that function's docstring.
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
 * must eventually invoke `.release` (directly or via a Julia-side keeper/finalizer) exactly
 * once.
 *
 * `rechunk()` is a cheap Arc-clone when `series` is already single-chunk (the common case), but
 * a genuinely fragmented series (many small chunks, e.g. after repeated `concat`/streaming
 * appends without an explicit rechunk) pays a real one-time data copy here to produce the single
 * contiguous chunk the C Data Interface export needs.
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
 * Borrowed pointer into the series' name, valid only as long as `series` is alive (the same
 * borrowed-pointer convention `polars_value_time_zone` cites this function as the reference for).
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
 * Borrowed pointer into this datetime value's timezone name, valid as long as `value` is alive
 * (same convention as `polars_series_name`). Returns 0 (and leaves `out` unwritten) for a naive
 * datetime or any non-datetime value.
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
 * Returns the value of struct field `fieldidx`.
 *
 * # Safety
 * The returned value borrows into the parent struct's backing memory (as every `polars_value_t`
 * does -- it wraps an `AnyValue<'a>`). Lifetime parameters on a `#[no_mangle] extern "C"` fn
 * enforce nothing across the C boundary, so this is a *caller invariant*, not a compiler-checked
 * one: **the caller must keep `value` (and its parent Series) alive until it is done with `*out`,
 * and must destroy `*out` before `value`.** The Julia side roots the parent accordingly.
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
