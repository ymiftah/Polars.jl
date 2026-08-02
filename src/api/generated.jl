using CEnum: CEnum, @cenum

using Artifacts

# Resolve the native `libpolars` shared library.
#
# Priority: a local `cargo build` (the dev loop -- `release/` first, then `debug/`), then the
# prebuilt artifact published as a GitHub Release asset on this repo and pinned by the root
# `Artifacts.toml`.
#
# The registered `libpolars_jll` is deliberately NOT used. It is built from the original upstream
# repo (`Pangoraw/Polars.jl`) and exports ~153 symbols against the 298 this fork needs, so it fails
# at `ccall` time rather than at load time -- a late, confusing failure that only ever reached
# outside users, since every checkout and CI job here has a local build that shadowed it.
#
# Self-hosted artifacts work for an unregistered package because Pkg fetches artifacts by URL with
# no registry lookup; a package *dependency* could only ever be resolved through a registry.
const libpolars_artifacts_toml = joinpath(@__DIR__, "..", "..", "Artifacts.toml")
const libpolars_file_name = "libpolars" * (Sys.iswindows() ? ".dll" : Sys.isapple() ? ".dylib" : ".so")
const libpolars_local_release_path = joinpath(@__DIR__, "..", "..", "c-polars", "target", "release", libpolars_file_name)
const libpolars_local_debug_path = joinpath(@__DIR__, "..", "..", "c-polars", "target", "debug", libpolars_file_name)

@static if isfile(libpolars_local_release_path)
    const libpolars = libpolars_local_release_path
elseif isfile(libpolars_local_debug_path)
    const libpolars = libpolars_local_debug_path
elseif artifact_meta("libpolars", libpolars_artifacts_toml) !== nothing
    # This guard is load-bearing. Pkg silently skips a non-lazy artifact when no entry matches the
    # host platform, so without it an unsupported platform hits a bare `@artifact_str` failure
    # instead of the actionable message below.
    const libpolars = joinpath(artifact"libpolars", Sys.iswindows() ? "bin" : "lib", libpolars_file_name)
else
    error(
        "Polars.jl: no prebuilt `libpolars` is available for this platform ($(Sys.MACHINE)), " *
            "and no local build was found. Build one from source with " *
            "`cd c-polars && cargo build --release`."
    )
end


struct ArrowSchema
    format::Cstring
    name::Cstring
    metadata::Cstring
    flags::Int64
    n_children::Int64
    children::Ptr{Ptr{ArrowSchema}}
    dictionary::Ptr{ArrowSchema}
    release::Ptr{Cvoid}
    private_data::Ptr{Cvoid}
end

struct ArrowArray
    length::Int64
    null_count::Int64
    offset::Int64
    n_buffers::Int64
    n_children::Int64
    buffers::Ptr{Ptr{Cvoid}}
    children::Ptr{Ptr{ArrowArray}}
    dictionary::Ptr{ArrowArray}
    release::Ptr{Cvoid}
    private_data::Ptr{Cvoid}
end

@cenum polars_asof_strategy_t::UInt32 begin
    PolarsAsofStrategyBackward = 0
    PolarsAsofStrategyForward = 1
    PolarsAsofStrategyNearest = 2
end

@cenum polars_closed_interval_t::UInt32 begin
    PolarsClosedIntervalBoth = 0
    PolarsClosedIntervalLeft = 1
    PolarsClosedIntervalRight = 2
    PolarsClosedIntervalNone = 3
end

@cenum polars_closed_window_t::UInt32 begin
    PolarsClosedWindowLeft = 0
    PolarsClosedWindowRight = 1
    PolarsClosedWindowBoth = 2
    PolarsClosedWindowNone = 3
end

@cenum polars_concat_how_t::UInt32 begin
    PolarsConcatHowVertical = 0
    PolarsConcatHowVerticalRelaxed = 1
    PolarsConcatHowDiagonal = 2
    PolarsConcatHowDiagonalRelaxed = 3
    PolarsConcatHowHorizontal = 4
end

@cenum polars_csv_compression_t::UInt32 begin
    PolarsCsvCompressionUncompressed = 0
    PolarsCsvCompressionGzip = 1
    PolarsCsvCompressionZstd = 2
end

"""
    polars_dtype_selector_kind_t

Zero-argument `DataTypeSelector` leaves. `Datetime`/`Duration`/`List`/`Array` match any unit/timezone rather than a specific one; List/Array do not support inner-selector composition.
"""
@cenum polars_dtype_selector_kind_t::UInt32 begin
    PolarsDtypeSelectorKindNumeric = 0
    PolarsDtypeSelectorKindInteger = 1
    PolarsDtypeSelectorKindUnsignedInteger = 2
    PolarsDtypeSelectorKindSignedInteger = 3
    PolarsDtypeSelectorKindFloat = 4
    PolarsDtypeSelectorKindEnum = 5
    PolarsDtypeSelectorKindCategorical = 6
    PolarsDtypeSelectorKindNested = 7
    PolarsDtypeSelectorKindStruct = 8
    PolarsDtypeSelectorKindDecimal = 9
    PolarsDtypeSelectorKindTemporal = 10
    PolarsDtypeSelectorKindObject = 11
    PolarsDtypeSelectorKindDatetime = 12
    PolarsDtypeSelectorKindDuration = 13
    PolarsDtypeSelectorKindList = 14
    PolarsDtypeSelectorKindArray = 15
end

@cenum polars_engine_t::UInt32 begin
    PolarsEngineInMemory = 0
    PolarsEngineStreaming = 1
end

@cenum polars_fill_null_strategy_t::UInt32 begin
    PolarsFillNullStrategyBackward = 0
    PolarsFillNullStrategyForward = 1
    PolarsFillNullStrategyMean = 2
    PolarsFillNullStrategyMin = 3
    PolarsFillNullStrategyMax = 4
    PolarsFillNullStrategyZero = 5
    PolarsFillNullStrategyOne = 6
end

@cenum polars_interpolation_method_t::UInt32 begin
    PolarsInterpolationMethodLinear = 0
    PolarsInterpolationMethodNearest = 1
end

@cenum polars_ipc_compression_t::UInt32 begin
    PolarsIpcCompressionUncompressed = 0
    PolarsIpcCompressionLz4 = 1
    PolarsIpcCompressionZstd = 2
end

@cenum polars_join_type_t::UInt32 begin
    PolarsJoinTypeInner = 0
    PolarsJoinTypeLeft = 1
    PolarsJoinTypeRight = 2
    PolarsJoinTypeFull = 3
    PolarsJoinTypeSemi = 4
    PolarsJoinTypeAnti = 5
    PolarsJoinTypeCross = 6
end

@cenum polars_label_t::UInt32 begin
    PolarsLabelLeft = 0
    PolarsLabelRight = 1
    PolarsLabelDataPoint = 2
end

@cenum polars_non_existent_t::UInt32 begin
    PolarsNonExistentRaise = 0
    PolarsNonExistentNull = 1
end

@cenum polars_null_behavior_t::UInt32 begin
    PolarsNullBehaviorDrop = 0
    PolarsNullBehaviorIgnore = 1
end

@cenum polars_parquet_compression_t::UInt32 begin
    PolarsParquetCompressionUncompressed = 0
    PolarsParquetCompressionSnappy = 1
    PolarsParquetCompressionGzip = 2
    PolarsParquetCompressionBrotli = 3
    PolarsParquetCompressionZstd = 4
    PolarsParquetCompressionLz4Raw = 5
end

@cenum polars_parquet_parallel_strategy_t::UInt32 begin
    PolarsParquetParallelAuto = 0
    PolarsParquetParallelNone = 1
    PolarsParquetParallelColumns = 2
    PolarsParquetParallelRowGroups = 3
end

@cenum polars_pivot_column_naming_t::UInt32 begin
    PolarsPivotColumnNamingCombine = 0
    PolarsPivotColumnNamingAuto = 1
end

@cenum polars_quantile_method_t::UInt32 begin
    PolarsQuantileMethodNearest = 0
    PolarsQuantileMethodLower = 1
    PolarsQuantileMethodHigher = 2
    PolarsQuantileMethodMidpoint = 3
    PolarsQuantileMethodLinear = 4
    PolarsQuantileMethodEquiprobable = 5
end

@cenum polars_quote_style_t::UInt32 begin
    PolarsQuoteStyleNecessary = 0
    PolarsQuoteStyleAlways = 1
    PolarsQuoteStyleNonNumeric = 2
    PolarsQuoteStyleNever = 3
end

@cenum polars_rank_method_t::UInt32 begin
    PolarsRankMethodAverage = 0
    PolarsRankMethodMin = 1
    PolarsRankMethodMax = 2
    PolarsRankMethodDense = 3
    PolarsRankMethodOrdinal = 4
end

@cenum polars_round_mode_t::UInt32 begin
    PolarsRoundModeHalfToEven = 0
    PolarsRoundModeHalfAwayFromZero = 1
    PolarsRoundModeToZero = 2
end

@cenum polars_selector_match_kind_t::UInt32 begin
    PolarsSelectorMatchKindRegex = 0
    PolarsSelectorMatchKindStartsWith = 1
    PolarsSelectorMatchKindEndsWith = 2
    PolarsSelectorMatchKindContains = 3
end

@cenum polars_start_by_t::UInt32 begin
    PolarsStartByWindowBound = 0
    PolarsStartByDataPoint = 1
    PolarsStartByMonday = 2
    PolarsStartByTuesday = 3
    PolarsStartByWednesday = 4
    PolarsStartByThursday = 5
    PolarsStartByFriday = 6
    PolarsStartBySaturday = 7
    PolarsStartBySunday = 8
end

@cenum polars_time_unit_t::UInt32 begin
    PolarsTimeUnitNanosecond = 0
    PolarsTimeUnitMicrosecond = 1
    PolarsTimeUnitMillisecond = 2
    PolarsTimeUnitInvalid = 3
end

@cenum polars_unique_keep_t::UInt32 begin
    PolarsUniqueKeepFirst = 0
    PolarsUniqueKeepLast = 1
    PolarsUniqueKeepNone = 2
    PolarsUniqueKeepAny = 3
end

@cenum polars_value_type_t::UInt32 begin
    PolarsValueTypeNull = 0
    PolarsValueTypeBoolean = 1
    PolarsValueTypeUInt8 = 2
    PolarsValueTypeUInt16 = 3
    PolarsValueTypeUInt32 = 4
    PolarsValueTypeUInt64 = 5
    PolarsValueTypeInt8 = 6
    PolarsValueTypeInt16 = 7
    PolarsValueTypeInt32 = 8
    PolarsValueTypeInt64 = 9
    PolarsValueTypeFloat32 = 10
    PolarsValueTypeFloat64 = 11
    PolarsValueTypeList = 12
    PolarsValueTypeString = 13
    PolarsValueTypeStruct = 14
    PolarsValueTypeBinary = 15
    PolarsValueTypeDatetime = 16
    PolarsValueTypeDate = 17
    PolarsValueTypeDuration = 18
    PolarsValueTypeTime = 19
    PolarsValueTypeUnknown = 20
end

@cenum polars_window_mapping_t::UInt32 begin
    PolarsWindowMappingGroupsToRows = 0
    PolarsWindowMappingExplode = 1
    PolarsWindowMappingJoin = 2
end

mutable struct polars_cloud_options_t end

mutable struct polars_dataframe_t end

mutable struct polars_error_t end

mutable struct polars_expr_t end

mutable struct polars_lazy_frame_t end

mutable struct polars_lazy_group_by_t end

mutable struct polars_series_t end

mutable struct polars_value_t end

# typedef intptr_t ( * IOCallback ) ( const void * user , const uint8_t * data , uintptr_t len )
"""
The callback provided for display functions, returns -1 on error.
"""
const IOCallback = Ptr{Cvoid}

function polars_version(out)
    return @ccall libpolars.polars_version(out::Ptr{Ptr{UInt8}})::Csize_t
end

"""
    polars_error_message(err, data)

Borrowed pointer into the error's message, valid only as long as `err` is alive.
"""
function polars_error_message(err, data)
    return @ccall libpolars.polars_error_message(err::Ptr{polars_error_t}, data::Ptr{Ptr{UInt8}})::Csize_t
end

function polars_error_destroy(err)
    return @ccall libpolars.polars_error_destroy(err::Ptr{polars_error_t})::Cvoid
end

function polars_dataframe_size(df, rows, cols)
    return @ccall libpolars.polars_dataframe_size(df::Ptr{polars_dataframe_t}, rows::Ptr{Csize_t}, cols::Ptr{Csize_t})::Cvoid
end

"""
    polars_dataframe_new_from_carrow(cfield, carray, out)

Creates a DataFrame from an [`ArrowArray`](@ref) + [`ArrowSchema`](@ref) pair per the Arrow C Data Interface.

# Safety `cfield` must be a valid [`ArrowSchema`](@ref) per the C Data Interface. `carray` must be a valid [`ArrowArray`](@ref) per the C Data Interface, and **ownership of it transfers to this call**: the caller must not release it. It is released either via the resulting DataFrame's destructor ([`polars_dataframe_destroy`](@ref)) on success, or before returning on failure -- `carray` is an owned by-value local and polars-arrow's `impl Drop for [`ArrowArray`](@ref)` invokes its `release` callback, so every early return below releases rather than leaks it. On the success path it is moved into `import_array_from_c`, which likewise takes it by value.
"""
function polars_dataframe_new_from_carrow(cfield, carray, out)
    return @ccall libpolars.polars_dataframe_new_from_carrow(cfield::Ptr{ArrowSchema}, carray::ArrowArray, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

"""
    polars_dataframe_schema(df, out)

Returns a [`ArrowSchema`](@ref) describing the dataframe's schema according to Arrow C Data interface.
"""
function polars_dataframe_schema(df, out)
    return @ccall libpolars.polars_dataframe_schema(df::Ptr{polars_dataframe_t}, out::Ptr{ArrowSchema})::Ptr{polars_error_t}
end

function polars_dataframe_new_from_series(series, nseries, out)
    return @ccall libpolars.polars_dataframe_new_from_series(series::Ptr{Ptr{polars_series_t}}, nseries::Csize_t, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

function polars_dataframe_destroy(df)
    return @ccall libpolars.polars_dataframe_destroy(df::Ptr{polars_dataframe_t})::Cvoid
end

function polars_dataframe_write_parquet(df, user, callback, compression, compression_level, statistics, row_group_size, data_page_size)
    return @ccall libpolars.polars_dataframe_write_parquet(df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback, compression::polars_parquet_compression_t, compression_level::Ptr{Int32}, statistics::Bool, row_group_size::Ptr{Csize_t}, data_page_size::Ptr{Csize_t})::Ptr{polars_error_t}
end

function polars_dataframe_write_csv(df, user, callback, include_header, include_bom, separator, quote_char, null_value, null_value_len, line_terminator, line_terminator_len, quote_style, date_format, date_format_len, time_format, time_format_len, datetime_format, datetime_format_len, float_precision, decimal_comma)
    return @ccall libpolars.polars_dataframe_write_csv(df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback, include_header::Bool, include_bom::Bool, separator::UInt8, quote_char::UInt8, null_value::Ptr{UInt8}, null_value_len::Csize_t, line_terminator::Ptr{UInt8}, line_terminator_len::Csize_t, quote_style::polars_quote_style_t, date_format::Ptr{UInt8}, date_format_len::Csize_t, time_format::Ptr{UInt8}, time_format_len::Csize_t, datetime_format::Ptr{UInt8}, datetime_format_len::Csize_t, float_precision::Ptr{Csize_t}, decimal_comma::Bool)::Ptr{polars_error_t}
end

function polars_dataframe_show(df, user, callback)
    return @ccall libpolars.polars_dataframe_show(df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

function polars_dataframe_get(df, name, len, out)
    return @ccall libpolars.polars_dataframe_get(df::Ptr{polars_dataframe_t}, name::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_series_t}})::Ptr{polars_error_t}
end

function polars_dataframe_lazy(df)
    return @ccall libpolars.polars_dataframe_lazy(df::Ptr{polars_dataframe_t})::Ptr{polars_lazy_frame_t}
end

function polars_dataframe_upsample(df, by_names, by_lens, n_by, time_column, time_column_len, every, every_len, stable, out)
    return @ccall libpolars.polars_dataframe_upsample(df::Ptr{polars_dataframe_t}, by_names::Ptr{Ptr{UInt8}}, by_lens::Ptr{Csize_t}, n_by::Csize_t, time_column::Ptr{UInt8}, time_column_len::Csize_t, every::Ptr{UInt8}, every_len::Csize_t, stable::Bool, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

"""
    polars_dataframe_hstack(df, series, n, out)

Attaches loose `Series` as new columns. A length mismatch between `series` and `df`'s existing height, or a name collision with an existing column (or between two of the given `series` themselves), raises a `PolarsError`.
"""
function polars_dataframe_hstack(df, series, n, out)
    return @ccall libpolars.polars_dataframe_hstack(df::Ptr{polars_dataframe_t}, series::Ptr{Ptr{polars_series_t}}, n::Csize_t, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

"""
    polars_dataframe_vstack(df, other, out)

Stacks `other`'s rows beneath `df`'s. Does no supertype casting: a column-count/dtype mismatch between `df` and `other` raises a `PolarsError`.
"""
function polars_dataframe_vstack(df, other, out)
    return @ccall libpolars.polars_dataframe_vstack(df::Ptr{polars_dataframe_t}, other::Ptr{polars_dataframe_t}, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

"""
    polars_dataframe_transpose(df, keep_names_as, keep_names_as_len, new_col_names, new_col_names_lens, n_new_col_names, out)

Transposes rows and columns. `keep_names_as`, if given, names a new first column holding the original column names. `new_col_names`, if given (a zero-length array counts as omitted), sets the transposed frame's column names explicitly; otherwise they are auto-generated (`"column\\_N"`). Setting an existing column's *values* as the new names is not supported. A `new_col_names` of the wrong length (relative to `df`'s original column count) raises a `ShapeMismatch` `PolarsError`.
"""
function polars_dataframe_transpose(df, keep_names_as, keep_names_as_len, new_col_names, new_col_names_lens, n_new_col_names, out)
    return @ccall libpolars.polars_dataframe_transpose(df::Ptr{polars_dataframe_t}, keep_names_as::Ptr{UInt8}, keep_names_as_len::Csize_t, new_col_names::Ptr{Ptr{UInt8}}, new_col_names_lens::Ptr{Csize_t}, n_new_col_names::Csize_t, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_destroy(df)
    return @ccall libpolars.polars_lazy_frame_destroy(df::Ptr{polars_lazy_frame_t})::Cvoid
end

function polars_lazy_frame_clone(df)
    return @ccall libpolars.polars_lazy_frame_clone(df::Ptr{polars_lazy_frame_t})::Ptr{polars_lazy_frame_t}
end

function polars_dataframe_write_ipc(df, user, callback, compression, compression_level, record_batch_size)
    return @ccall libpolars.polars_dataframe_write_ipc(df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback, compression::polars_ipc_compression_t, compression_level::Ptr{Int32}, record_batch_size::Ptr{Csize_t})::Ptr{polars_error_t}
end

function polars_lazy_frame_sort(df, exprs, nexprs, descending, nulls_last, maintain_order)
    return @ccall libpolars.polars_lazy_frame_sort(df::Ptr{polars_lazy_frame_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t, descending::Ptr{Bool}, nulls_last::Bool, maintain_order::Bool)::Cvoid
end

"""
    polars_lazy_frame_concat(lfs, n, how, out)

`how` selects the concat mode.
"""
function polars_lazy_frame_concat(lfs, n, how, out)
    return @ccall libpolars.polars_lazy_frame_concat(lfs::Ptr{Ptr{polars_lazy_frame_t}}, n::Csize_t, how::polars_concat_how_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_with_columns(df, exprs, nexprs)
    return @ccall libpolars.polars_lazy_frame_with_columns(df::Ptr{polars_lazy_frame_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t)::Cvoid
end

function polars_lazy_frame_select(df, exprs, nexprs)
    return @ccall libpolars.polars_lazy_frame_select(df::Ptr{polars_lazy_frame_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t)::Cvoid
end

function polars_lazy_frame_filter(df, expr)
    return @ccall libpolars.polars_lazy_frame_filter(df::Ptr{polars_lazy_frame_t}, expr::Ptr{polars_expr_t})::Cvoid
end

function polars_lazy_frame_collect(df, engine, out)
    return @ccall libpolars.polars_lazy_frame_collect(df::Ptr{polars_lazy_frame_t}, engine::polars_engine_t, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

"""
    polars_lazy_frame_collect_schema(df, out)

Resolves the lazy frame's schema (without collecting it) and returns it as an [`ArrowSchema`](@ref) according to the Arrow C Data interface, wrapping the columns in a struct field the same way [`polars_dataframe_schema`](@ref) does. Unlike that function, this one is fallible (schema resolution can fail on an unresolved lazy plan) and so returns via out-param + [`polars_error_t`](@ref) rather than by value.
"""
function polars_lazy_frame_collect_schema(df, out)
    return @ccall libpolars.polars_lazy_frame_collect_schema(df::Ptr{polars_lazy_frame_t}, out::Ptr{ArrowSchema})::Ptr{polars_error_t}
end

function polars_lazy_frame_group_by(df, exprs, nexprs)
    return @ccall libpolars.polars_lazy_frame_group_by(df::Ptr{polars_lazy_frame_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t)::Ptr{polars_lazy_group_by_t}
end

function polars_lazy_frame_group_by_dynamic(df, index_expr, group_by_exprs, n_group_by, every, every_len, period, period_len, offset, offset_len, label, include_boundaries, closed_window, start_by, out)
    return @ccall libpolars.polars_lazy_frame_group_by_dynamic(df::Ptr{polars_lazy_frame_t}, index_expr::Ptr{polars_expr_t}, group_by_exprs::Ptr{Ptr{polars_expr_t}}, n_group_by::Csize_t, every::Ptr{UInt8}, every_len::Csize_t, period::Ptr{UInt8}, period_len::Csize_t, offset::Ptr{UInt8}, offset_len::Csize_t, label::polars_label_t, include_boundaries::Bool, closed_window::polars_closed_window_t, start_by::polars_start_by_t, out::Ptr{Ptr{polars_lazy_group_by_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_rolling(df, index_expr, group_by_exprs, n_group_by, period, period_len, offset, offset_len, closed_window, out)
    return @ccall libpolars.polars_lazy_frame_rolling(df::Ptr{polars_lazy_frame_t}, index_expr::Ptr{polars_expr_t}, group_by_exprs::Ptr{Ptr{polars_expr_t}}, n_group_by::Csize_t, period::Ptr{UInt8}, period_len::Csize_t, offset::Ptr{UInt8}, offset_len::Csize_t, closed_window::polars_closed_window_t, out::Ptr{Ptr{polars_lazy_group_by_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_join(a, b, exprs_a, exprs_a_len, exprs_b, exprs_b_len, how)
    return @ccall libpolars.polars_lazy_frame_join(a::Ptr{polars_lazy_frame_t}, b::Ptr{polars_lazy_frame_t}, exprs_a::Ptr{Ptr{polars_expr_t}}, exprs_a_len::Csize_t, exprs_b::Ptr{Ptr{polars_expr_t}}, exprs_b_len::Csize_t, how::polars_join_type_t)::Ptr{polars_lazy_frame_t}
end

function polars_lazy_frame_join_asof(a, b, on_a, on_b, by_a, by_a_lens, by_a_len, by_b, by_b_lens, by_b_len, strategy, out)
    return @ccall libpolars.polars_lazy_frame_join_asof(a::Ptr{polars_lazy_frame_t}, b::Ptr{polars_lazy_frame_t}, on_a::Ptr{polars_expr_t}, on_b::Ptr{polars_expr_t}, by_a::Ptr{Ptr{UInt8}}, by_a_lens::Ptr{Csize_t}, by_a_len::Csize_t, by_b::Ptr{Ptr{UInt8}}, by_b_lens::Ptr{Csize_t}, by_b_len::Csize_t, strategy::polars_asof_strategy_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_unique(lf, names, lens, n, keep, out)
    return @ccall libpolars.polars_lazy_frame_unique(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, keep::polars_unique_keep_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_drop(lf, names, lens, n, out)
    return @ccall libpolars.polars_lazy_frame_drop(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_rename(lf, existing, existing_lens, new_, new_lens, n, strict, out)
    return @ccall libpolars.polars_lazy_frame_rename(lf::Ptr{polars_lazy_frame_t}, existing::Ptr{Ptr{UInt8}}, existing_lens::Ptr{Csize_t}, new_::Ptr{Ptr{UInt8}}, new_lens::Ptr{Csize_t}, n::Csize_t, strict::Bool, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_drop_nulls(lf, names, lens, n, out)
    return @ccall libpolars.polars_lazy_frame_drop_nulls(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_with_row_index(lf, name, name_len, offset, has_offset, out)
    return @ccall libpolars.polars_lazy_frame_with_row_index(lf::Ptr{polars_lazy_frame_t}, name::Ptr{UInt8}, name_len::Csize_t, offset::Int64, has_offset::Bool, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_explode(lf, names, lens, n, empty_as_null, keep_nulls, out)
    return @ccall libpolars.polars_lazy_frame_explode(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, empty_as_null::Bool, keep_nulls::Bool, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_unpivot(lf, index_names, index_lens, n_index, on_names, on_lens, n_on, variable_name, variable_name_len, value_name, value_name_len, out)
    return @ccall libpolars.polars_lazy_frame_unpivot(lf::Ptr{polars_lazy_frame_t}, index_names::Ptr{Ptr{UInt8}}, index_lens::Ptr{Csize_t}, n_index::Csize_t, on_names::Ptr{Ptr{UInt8}}, on_lens::Ptr{Csize_t}, n_on::Csize_t, variable_name::Ptr{UInt8}, variable_name_len::Csize_t, value_name::Ptr{UInt8}, value_name_len::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_unnest(lf, names, lens, n, separator, separator_len, out)
    return @ccall libpolars.polars_lazy_frame_unnest(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, separator::Ptr{UInt8}, separator_len::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_pivot(lf, on_names, on_lens, n_on, on_columns, index_names, index_lens, n_index, values_names, values_lens, n_values, agg, maintain_order, separator, separator_len, column_naming, out)
    return @ccall libpolars.polars_lazy_frame_pivot(lf::Ptr{polars_lazy_frame_t}, on_names::Ptr{Ptr{UInt8}}, on_lens::Ptr{Csize_t}, n_on::Csize_t, on_columns::Ptr{polars_dataframe_t}, index_names::Ptr{Ptr{UInt8}}, index_lens::Ptr{Csize_t}, n_index::Csize_t, values_names::Ptr{Ptr{UInt8}}, values_lens::Ptr{Csize_t}, n_values::Csize_t, agg::Ptr{polars_expr_t}, maintain_order::Bool, separator::Ptr{UInt8}, separator_len::Csize_t, column_naming::polars_pivot_column_naming_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_head(df, n)
    return @ccall libpolars.polars_lazy_frame_head(df::Ptr{polars_lazy_frame_t}, n::Csize_t)::Cvoid
end

function polars_lazy_frame_tail(df, n)
    return @ccall libpolars.polars_lazy_frame_tail(df::Ptr{polars_lazy_frame_t}, n::Csize_t)::Cvoid
end

function polars_lazy_group_by_destroy(gb)
    return @ccall libpolars.polars_lazy_group_by_destroy(gb::Ptr{polars_lazy_group_by_t})::Cvoid
end

function polars_lazy_group_by_agg(gb, exprs, nexprs)
    return @ccall libpolars.polars_lazy_group_by_agg(gb::Ptr{polars_lazy_group_by_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t)::Ptr{polars_lazy_frame_t}
end

function polars_expr_destroy(expr)
    return @ccall libpolars.polars_expr_destroy(expr::Ptr{polars_expr_t})::Cvoid
end

function polars_expr_literal_bool(value)
    return @ccall libpolars.polars_expr_literal_bool(value::Bool)::Ptr{polars_expr_t}
end

function polars_expr_literal_i32(value)
    return @ccall libpolars.polars_expr_literal_i32(value::Int32)::Ptr{polars_expr_t}
end

function polars_expr_literal_i64(value)
    return @ccall libpolars.polars_expr_literal_i64(value::Int64)::Ptr{polars_expr_t}
end

function polars_expr_literal_u32(value)
    return @ccall libpolars.polars_expr_literal_u32(value::UInt32)::Ptr{polars_expr_t}
end

function polars_expr_literal_u64(value)
    return @ccall libpolars.polars_expr_literal_u64(value::UInt64)::Ptr{polars_expr_t}
end

function polars_expr_literal_f32(value)
    return @ccall libpolars.polars_expr_literal_f32(value::Cfloat)::Ptr{polars_expr_t}
end

function polars_expr_literal_f64(value)
    return @ccall libpolars.polars_expr_literal_f64(value::Cdouble)::Ptr{polars_expr_t}
end

function polars_expr_literal_null()
    return @ccall libpolars.polars_expr_literal_null()::Ptr{polars_expr_t}
end

function polars_expr_lit_series(series)
    return @ccall libpolars.polars_expr_lit_series(series::Ptr{polars_series_t})::Ptr{polars_expr_t}
end

function polars_expr_literal_utf8(s, len, out)
    return @ccall libpolars.polars_expr_literal_utf8(s::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_col(name, len, out)
    return @ccall libpolars.polars_expr_col(name::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_nth(n, out)
    return @ccall libpolars.polars_expr_nth(n::Int64, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_element()

A placeholder for "the values in this group", used to build the `agg` expression passed to `pivot` (e.g. `element().sum()`) -- substituted in-place with the actual value column filtered to the current group at plan-build time.
"""
function polars_expr_element()
    return @ccall libpolars.polars_expr_element()::Ptr{polars_expr_t}
end

function polars_expr_coalesce(exprs, n, out)
    return @ccall libpolars.polars_expr_coalesce(exprs::Ptr{Ptr{polars_expr_t}}, n::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_as_struct(exprs, n, out)
    return @ccall libpolars.polars_expr_as_struct(exprs::Ptr{Ptr{polars_expr_t}}, n::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_all_horizontal(exprs, n, out)
    return @ccall libpolars.polars_expr_all_horizontal(exprs::Ptr{Ptr{polars_expr_t}}, n::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_any_horizontal(exprs, n, out)
    return @ccall libpolars.polars_expr_any_horizontal(exprs::Ptr{Ptr{polars_expr_t}}, n::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_min_horizontal(exprs, n, out)
    return @ccall libpolars.polars_expr_min_horizontal(exprs::Ptr{Ptr{polars_expr_t}}, n::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_max_horizontal(exprs, n, out)
    return @ccall libpolars.polars_expr_max_horizontal(exprs::Ptr{Ptr{polars_expr_t}}, n::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_sum_horizontal(exprs, n, ignore_nulls, out)
    return @ccall libpolars.polars_expr_sum_horizontal(exprs::Ptr{Ptr{polars_expr_t}}, n::Csize_t, ignore_nulls::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_mean_horizontal(exprs, n, ignore_nulls, out)
    return @ccall libpolars.polars_expr_mean_horizontal(exprs::Ptr{Ptr{polars_expr_t}}, n::Csize_t, ignore_nulls::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_interpolate(expr, method)
    return @ccall libpolars.polars_expr_interpolate(expr::Ptr{polars_expr_t}, method::polars_interpolation_method_t)::Ptr{polars_expr_t}
end

function polars_expr_alias(expr, name, len, out)
    return @ccall libpolars.polars_expr_alias(expr::Ptr{polars_expr_t}, name::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_prefix(expr, name, len, out)
    return @ccall libpolars.polars_expr_prefix(expr::Ptr{polars_expr_t}, name::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_suffix(expr, name, len, out)
    return @ccall libpolars.polars_expr_suffix(expr::Ptr{polars_expr_t}, name::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_keep_name(expr)
    return @ccall libpolars.polars_expr_keep_name(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_to_lowercase(expr)
    return @ccall libpolars.polars_expr_to_lowercase(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_to_uppercase(expr)
    return @ccall libpolars.polars_expr_to_uppercase(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_cast(expr, dtype, out)
    return @ccall libpolars.polars_expr_cast(expr::Ptr{polars_expr_t}, dtype::polars_value_type_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_strict_cast(expr, dtype, out)

Strict cast: raises on overflow/loss instead of [`polars_expr_cast`](@ref)'s non-strict "overflow becomes null" behavior (our `cast()` was hardwired non-strict; upstream `Expr.cast(dtype, strict=True)` defaults to strict -- this exposes the other branch as an explicit function rather than a mode switch on `cast` itself, matching `Expr::strict\\_cast`/`Expr::cast`'s own split upstream).
"""
function polars_expr_strict_cast(expr, dtype, out)
    return @ccall libpolars.polars_expr_strict_cast(expr::Ptr{polars_expr_t}, dtype::polars_value_type_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_cast_datetime(expr, unit, tz, tz_len, out)

Casts to `Datetime(unit, tz)`. `tz\\_len == 0` casts to a naive (timezone-less) Datetime.
"""
function polars_expr_cast_datetime(expr, unit, tz, tz_len, out)
    return @ccall libpolars.polars_expr_cast_datetime(expr::Ptr{polars_expr_t}, unit::polars_time_unit_t, tz::Ptr{UInt8}, tz_len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_cast_duration(expr, unit, out)

Casts to `Duration(unit)`.
"""
function polars_expr_cast_duration(expr, unit, out)
    return @ccall libpolars.polars_expr_cast_duration(expr::Ptr{polars_expr_t}, unit::polars_time_unit_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_cast_decimal(expr, precision, scale)

Targeted cast to `Decimal(precision, scale)` (`dtype-decimal` is already enabled). polars' own invariant is `1 <= precision <= 38`; violating it surfaces as a normal cast error rather than a panic (`DataType::Decimal` itself does not validate -- `cast` does, at execution time).
"""
function polars_expr_cast_decimal(expr, precision, scale)
    return @ccall libpolars.polars_expr_cast_decimal(expr::Ptr{polars_expr_t}, precision::Csize_t, scale::Csize_t)::Ptr{polars_expr_t}
end

"""
    polars_expr_cast_categorical(expr)

Casts to `Categorical`, using the global category registry shared by every Categorical column in the session.
"""
function polars_expr_cast_categorical(expr)
    return @ccall libpolars.polars_expr_cast_categorical(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_sum(expr)
    return @ccall libpolars.polars_expr_sum(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_product(expr)
    return @ccall libpolars.polars_expr_product(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_mean(expr)
    return @ccall libpolars.polars_expr_mean(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_median(expr)
    return @ccall libpolars.polars_expr_median(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_min(expr)
    return @ccall libpolars.polars_expr_min(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_max(expr)
    return @ccall libpolars.polars_expr_max(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_arg_min(expr)
    return @ccall libpolars.polars_expr_arg_min(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_arg_max(expr)
    return @ccall libpolars.polars_expr_arg_max(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_nan_min(expr)
    return @ccall libpolars.polars_expr_nan_min(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_nan_max(expr)
    return @ccall libpolars.polars_expr_nan_max(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_std(expr, ddof)
    return @ccall libpolars.polars_expr_std(expr::Ptr{polars_expr_t}, ddof::UInt8)::Ptr{polars_expr_t}
end

function polars_expr_var(expr, ddof)
    return @ccall libpolars.polars_expr_var(expr::Ptr{polars_expr_t}, ddof::UInt8)::Ptr{polars_expr_t}
end

function polars_expr_cov(a, b, ddof)
    return @ccall libpolars.polars_expr_cov(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t}, ddof::UInt8)::Ptr{polars_expr_t}
end

function polars_expr_pearson_corr(a, b)
    return @ccall libpolars.polars_expr_pearson_corr(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_spearman_rank_corr(a, b, propagate_nans)
    return @ccall libpolars.polars_expr_spearman_rank_corr(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t}, propagate_nans::Bool)::Ptr{polars_expr_t}
end

function polars_expr_skew(expr, bias)
    return @ccall libpolars.polars_expr_skew(expr::Ptr{polars_expr_t}, bias::Bool)::Ptr{polars_expr_t}
end

function polars_expr_kurtosis(expr, fisher, bias)
    return @ccall libpolars.polars_expr_kurtosis(expr::Ptr{polars_expr_t}, fisher::Bool, bias::Bool)::Ptr{polars_expr_t}
end

"""
    polars_expr_ewm_mean(expr, alpha, adjust, min_samples, ignore_nulls)

Exponentially-weighted moving average. `alpha` must already be resolved to a concrete decay factor in `(0, 1]` by the caller (the `com`/`span`/`half_life`/`alpha` parameterizations all reduce to this single value client-side).
"""
function polars_expr_ewm_mean(expr, alpha, adjust, min_samples, ignore_nulls)
    return @ccall libpolars.polars_expr_ewm_mean(expr::Ptr{polars_expr_t}, alpha::Cdouble, adjust::Bool, min_samples::Csize_t, ignore_nulls::Bool)::Ptr{polars_expr_t}
end

"""
    polars_expr_ewm_std(expr, alpha, adjust, bias, min_samples, ignore_nulls)

Exponentially-weighted moving standard deviation. See [`polars_expr_ewm_mean`](@ref) for `alpha`.
"""
function polars_expr_ewm_std(expr, alpha, adjust, bias, min_samples, ignore_nulls)
    return @ccall libpolars.polars_expr_ewm_std(expr::Ptr{polars_expr_t}, alpha::Cdouble, adjust::Bool, bias::Bool, min_samples::Csize_t, ignore_nulls::Bool)::Ptr{polars_expr_t}
end

"""
    polars_expr_ewm_var(expr, alpha, adjust, bias, min_samples, ignore_nulls)

Exponentially-weighted moving variance. See [`polars_expr_ewm_mean`](@ref) for `alpha`.
"""
function polars_expr_ewm_var(expr, alpha, adjust, bias, min_samples, ignore_nulls)
    return @ccall libpolars.polars_expr_ewm_var(expr::Ptr{polars_expr_t}, alpha::Cdouble, adjust::Bool, bias::Bool, min_samples::Csize_t, ignore_nulls::Bool)::Ptr{polars_expr_t}
end

"""
    polars_expr_cut(expr, breaks, n_breaks, labels, label_lens, n_labels, left_closed, out)

Bins continuous values into discrete categories given explicit breakpoints. `breaks` is a plain array of cut points (not including the implicit `-inf`/`inf` ends); the result is a labelled Enum column with one more category than there are breaks. `labels`, if given (`n\\_labels > 0`), must have `breaks.len() + 1` entries; otherwise labels are generated as interval strings, `"(-inf, b] "`/`"(b1, b2]"`/`"(bn, inf]"` (or `[...)"`-style if `left_closed`). Raises if `breaks` contains `NaN`/duplicates/`inf`, or if `labels`' length doesn't match.
"""
function polars_expr_cut(expr, breaks, n_breaks, labels, label_lens, n_labels, left_closed, out)
    return @ccall libpolars.polars_expr_cut(expr::Ptr{polars_expr_t}, breaks::Ptr{Cdouble}, n_breaks::Csize_t, labels::Ptr{Ptr{UInt8}}, label_lens::Ptr{Csize_t}, n_labels::Csize_t, left_closed::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_qcut(expr, probs, n_probs, labels, label_lens, n_labels, left_closed, allow_duplicates, out)

Bins continuous values into discrete categories based on their quantiles. `probs` are the quantile cut points in `[0, 1]`; the result is a `Categorical` column. `allow_duplicates` controls whether repeated quantile breakpoints (common with few distinct values) are silently collapsed instead of raising. See [`polars_expr_cut`](@ref) for `labels`/error conditions.
"""
function polars_expr_qcut(expr, probs, n_probs, labels, label_lens, n_labels, left_closed, allow_duplicates, out)
    return @ccall libpolars.polars_expr_qcut(expr::Ptr{polars_expr_t}, probs::Ptr{Cdouble}, n_probs::Csize_t, labels::Ptr{Ptr{UInt8}}, label_lens::Ptr{Csize_t}, n_labels::Csize_t, left_closed::Bool, allow_duplicates::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_qcut_uniform(expr, n_bins, labels, label_lens, n_labels, left_closed, allow_duplicates, out)

Like [`polars_expr_qcut`](@ref), but with `n_bins` uniformly-spaced quantile probabilities instead of an explicit `probs` array.
"""
function polars_expr_qcut_uniform(expr, n_bins, labels, label_lens, n_labels, left_closed, allow_duplicates, out)
    return @ccall libpolars.polars_expr_qcut_uniform(expr::Ptr{polars_expr_t}, n_bins::Csize_t, labels::Ptr{Ptr{UInt8}}, label_lens::Ptr{Csize_t}, n_labels::Csize_t, left_closed::Bool, allow_duplicates::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_is_between(expr, lower, upper, closed)
    return @ccall libpolars.polars_expr_is_between(expr::Ptr{polars_expr_t}, lower::Ptr{polars_expr_t}, upper::Ptr{polars_expr_t}, closed::polars_closed_interval_t)::Ptr{polars_expr_t}
end

function polars_expr_rolling_mean(expr, window_size, min_periods, center)
    return @ccall libpolars.polars_expr_rolling_mean(expr::Ptr{polars_expr_t}, window_size::Csize_t, min_periods::Csize_t, center::Bool)::Ptr{polars_expr_t}
end

function polars_expr_rolling_sum(expr, window_size, min_periods, center)
    return @ccall libpolars.polars_expr_rolling_sum(expr::Ptr{polars_expr_t}, window_size::Csize_t, min_periods::Csize_t, center::Bool)::Ptr{polars_expr_t}
end

function polars_expr_rolling_min(expr, window_size, min_periods, center)
    return @ccall libpolars.polars_expr_rolling_min(expr::Ptr{polars_expr_t}, window_size::Csize_t, min_periods::Csize_t, center::Bool)::Ptr{polars_expr_t}
end

function polars_expr_rolling_max(expr, window_size, min_periods, center)
    return @ccall libpolars.polars_expr_rolling_max(expr::Ptr{polars_expr_t}, window_size::Csize_t, min_periods::Csize_t, center::Bool)::Ptr{polars_expr_t}
end

function polars_expr_rolling_var(expr, window_size, min_periods, center, ddof)
    return @ccall libpolars.polars_expr_rolling_var(expr::Ptr{polars_expr_t}, window_size::Csize_t, min_periods::Csize_t, center::Bool, ddof::UInt8)::Ptr{polars_expr_t}
end

function polars_expr_rolling_std(expr, window_size, min_periods, center, ddof)
    return @ccall libpolars.polars_expr_rolling_std(expr::Ptr{polars_expr_t}, window_size::Csize_t, min_periods::Csize_t, center::Bool, ddof::UInt8)::Ptr{polars_expr_t}
end

function polars_expr_rolling_median(expr, window_size, min_periods, center)
    return @ccall libpolars.polars_expr_rolling_median(expr::Ptr{polars_expr_t}, window_size::Csize_t, min_periods::Csize_t, center::Bool)::Ptr{polars_expr_t}
end

function polars_expr_rolling_quantile(expr, window_size, min_periods, center, quantile, method)
    return @ccall libpolars.polars_expr_rolling_quantile(expr::Ptr{polars_expr_t}, window_size::Csize_t, min_periods::Csize_t, center::Bool, quantile::Cdouble, method::polars_quantile_method_t)::Ptr{polars_expr_t}
end

function polars_expr_when_then_otherwise(cond, then, otherwise)
    return @ccall libpolars.polars_expr_when_then_otherwise(cond::Ptr{polars_expr_t}, then::Ptr{polars_expr_t}, otherwise::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_when_then(conds, vals, n, otherwise)

Chained `when(c1).then(v1).when(c2).then(v2)....otherwise(otherwise)`, given as two parallel expr-slices (`conds`/`vals`) plus a final `otherwise`. `n == 0` returns `otherwise` unchanged.
"""
function polars_expr_when_then(conds, vals, n, otherwise)
    return @ccall libpolars.polars_expr_when_then(conds::Ptr{Ptr{polars_expr_t}}, vals::Ptr{Ptr{polars_expr_t}}, n::Csize_t, otherwise::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_over(expr, partition_by, n_partition_by, order_by, descending, nulls_last, mapping, out)

`order_by` is a single optional expr (null = none). An empty `partition_by` with a null `order_by` is valid -- the whole frame is treated as one group (see the whole-frame-sentinel substitution below).
"""
function polars_expr_over(expr, partition_by, n_partition_by, order_by, descending, nulls_last, mapping, out)
    return @ccall libpolars.polars_expr_over(expr::Ptr{polars_expr_t}, partition_by::Ptr{Ptr{polars_expr_t}}, n_partition_by::Csize_t, order_by::Ptr{polars_expr_t}, descending::Bool, nulls_last::Bool, mapping::polars_window_mapping_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_sort_by(expr, by, n_by, descending, nulls_last, maintain_order)
    return @ccall libpolars.polars_expr_sort_by(expr::Ptr{polars_expr_t}, by::Ptr{Ptr{polars_expr_t}}, n_by::Csize_t, descending::Ptr{Bool}, nulls_last::Bool, maintain_order::Bool)::Ptr{polars_expr_t}
end

function polars_expr_quantile(expr, quantile, method)
    return @ccall libpolars.polars_expr_quantile(expr::Ptr{polars_expr_t}, quantile::Ptr{polars_expr_t}, method::polars_quantile_method_t)::Ptr{polars_expr_t}
end

function polars_expr_floor(expr)
    return @ccall libpolars.polars_expr_floor(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_ceil(expr)
    return @ccall libpolars.polars_expr_ceil(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_abs(expr)
    return @ccall libpolars.polars_expr_abs(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_cos(expr)
    return @ccall libpolars.polars_expr_cos(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_sin(expr)
    return @ccall libpolars.polars_expr_sin(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_tan(expr)
    return @ccall libpolars.polars_expr_tan(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_cosh(expr)
    return @ccall libpolars.polars_expr_cosh(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_sinh(expr)
    return @ccall libpolars.polars_expr_sinh(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_tanh(expr)
    return @ccall libpolars.polars_expr_tanh(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_arccos(expr)
    return @ccall libpolars.polars_expr_arccos(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_arcsin(expr)
    return @ccall libpolars.polars_expr_arcsin(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_arctan(expr)
    return @ccall libpolars.polars_expr_arctan(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_degrees(expr)
    return @ccall libpolars.polars_expr_degrees(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_radians(expr)
    return @ccall libpolars.polars_expr_radians(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_sqrt(expr)
    return @ccall libpolars.polars_expr_sqrt(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_sign(expr)
    return @ccall libpolars.polars_expr_sign(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_exp(expr)
    return @ccall libpolars.polars_expr_exp(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_log1p(expr)
    return @ccall libpolars.polars_expr_log1p(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_rle(expr)
    return @ccall libpolars.polars_expr_rle(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_rle_id(expr)
    return @ccall libpolars.polars_expr_rle_id(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_round(expr, decimals, mode)
    return @ccall libpolars.polars_expr_round(expr::Ptr{polars_expr_t}, decimals::UInt32, mode::polars_round_mode_t)::Ptr{polars_expr_t}
end

function polars_expr_clip(expr, min, max)
    return @ccall libpolars.polars_expr_clip(expr::Ptr{polars_expr_t}, min::Ptr{polars_expr_t}, max::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_neg(expr)
    return @ccall libpolars.polars_expr_neg(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_replace(expr, old, new_)
    return @ccall libpolars.polars_expr_replace(expr::Ptr{polars_expr_t}, old::Ptr{polars_expr_t}, new_::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_replace_strict(expr, old, new_, default_)
    return @ccall libpolars.polars_expr_replace_strict(expr::Ptr{polars_expr_t}, old::Ptr{polars_expr_t}, new_::Ptr{polars_expr_t}, default_::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_n_unique(expr)
    return @ccall libpolars.polars_expr_n_unique(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_unique(expr)
    return @ccall libpolars.polars_expr_unique(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_is_duplicated(expr)
    return @ccall libpolars.polars_expr_is_duplicated(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_is_unique(expr)
    return @ccall libpolars.polars_expr_is_unique(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_is_first_distinct(expr)
    return @ccall libpolars.polars_expr_is_first_distinct(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_is_last_distinct(expr)
    return @ccall libpolars.polars_expr_is_last_distinct(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_count(expr)
    return @ccall libpolars.polars_expr_count(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_first(expr)
    return @ccall libpolars.polars_expr_first(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_last(expr)
    return @ccall libpolars.polars_expr_last(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_item(expr, allow_empty)

The aggregation form of `item()`: errors if the expression evaluates to `!= 1` values, unless `allow_empty` is set, in which case zero values also succeeds (producing `null`). Distinct from `DataFrame`/`Series` `item()`, which is a `(1,1)`-shape accessor, not an aggregation -- the two share a name upstream but are different functions (see `plans/parity/batch-2-aggregation- statistics.md`'s Step-9 finding).
"""
function polars_expr_item(expr, allow_empty)
    return @ccall libpolars.polars_expr_item(expr::Ptr{polars_expr_t}, allow_empty::Bool)::Ptr{polars_expr_t}
end

function polars_expr_not(expr)
    return @ccall libpolars.polars_expr_not(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_all(expr, ignore_nulls)
    return @ccall libpolars.polars_expr_all(expr::Ptr{polars_expr_t}, ignore_nulls::Bool)::Ptr{polars_expr_t}
end

function polars_expr_any(expr, ignore_nulls)
    return @ccall libpolars.polars_expr_any(expr::Ptr{polars_expr_t}, ignore_nulls::Bool)::Ptr{polars_expr_t}
end

function polars_expr_is_finite(expr)
    return @ccall libpolars.polars_expr_is_finite(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_is_infinite(expr)
    return @ccall libpolars.polars_expr_is_infinite(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_is_nan(expr)
    return @ccall libpolars.polars_expr_is_nan(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_is_null(expr)
    return @ccall libpolars.polars_expr_is_null(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_is_not_null(expr)
    return @ccall libpolars.polars_expr_is_not_null(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_null_count(expr)
    return @ccall libpolars.polars_expr_null_count(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_drop_nans(expr)
    return @ccall libpolars.polars_expr_drop_nans(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_drop_nulls(expr)
    return @ccall libpolars.polars_expr_drop_nulls(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_arg_sort(expr, descending, nulls_last)
    return @ccall libpolars.polars_expr_arg_sort(expr::Ptr{polars_expr_t}, descending::Bool, nulls_last::Bool)::Ptr{polars_expr_t}
end

function polars_expr_value_counts(expr, sort, parallel, name, name_len, normalize, out)
    return @ccall libpolars.polars_expr_value_counts(expr::Ptr{polars_expr_t}, sort::Bool, parallel::Bool, name::Ptr{UInt8}, name_len::Csize_t, normalize::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_implode(expr)
    return @ccall libpolars.polars_expr_implode(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_flatten(expr, empty_as_null, keep_nulls)
    return @ccall libpolars.polars_expr_flatten(expr::Ptr{polars_expr_t}, empty_as_null::Bool, keep_nulls::Bool)::Ptr{polars_expr_t}
end

function polars_expr_reverse(expr)
    return @ccall libpolars.polars_expr_reverse(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_eq(a, b)
    return @ccall libpolars.polars_expr_eq(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_lt(a, b)
    return @ccall libpolars.polars_expr_lt(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_gt(a, b)
    return @ccall libpolars.polars_expr_gt(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_or(a, b)
    return @ccall libpolars.polars_expr_or(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_xor(a, b)
    return @ccall libpolars.polars_expr_xor(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_and(a, b)
    return @ccall libpolars.polars_expr_and(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_pow(a, b)
    return @ccall libpolars.polars_expr_pow(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_add(a, b)
    return @ccall libpolars.polars_expr_add(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_sub(a, b)
    return @ccall libpolars.polars_expr_sub(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_mul(a, b)
    return @ccall libpolars.polars_expr_mul(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_div(a, b)
    return @ccall libpolars.polars_expr_div(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_floor_div(a, b)
    return @ccall libpolars.polars_expr_floor_div(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_clip_min(a, b)
    return @ccall libpolars.polars_expr_clip_min(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_clip_max(a, b)
    return @ccall libpolars.polars_expr_clip_max(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_bottom_k(a, b)
    return @ccall libpolars.polars_expr_bottom_k(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_shift_and_fill(expr, n, fill_value)

`shift(n, fill\\_value)` -- unlike the existing binary `shift(n)` (no fill), out-of-range rows get `fill_value` instead of `null`.
"""
function polars_expr_shift_and_fill(expr, n, fill_value)
    return @ccall libpolars.polars_expr_shift_and_fill(expr::Ptr{polars_expr_t}, n::Ptr{polars_expr_t}, fill_value::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_fill_null(a, b)
    return @ccall libpolars.polars_expr_fill_null(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_fill_nan(a, b)
    return @ccall libpolars.polars_expr_fill_nan(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_fill_null_with_strategy(expr, strategy, limit)

`limit` applies only to the `Backward`/`Forward` strategies and is ignored otherwise; a null `limit` means unlimited.
"""
function polars_expr_fill_null_with_strategy(expr, strategy, limit)
    return @ccall libpolars.polars_expr_fill_null_with_strategy(expr::Ptr{polars_expr_t}, strategy::polars_fill_null_strategy_t, limit::Ptr{UInt32})::Ptr{polars_expr_t}
end

function polars_expr_is_in(a, b)
    return @ccall libpolars.polars_expr_is_in(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_shift(a, b)
    return @ccall libpolars.polars_expr_shift(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_pct_change(a, b)
    return @ccall libpolars.polars_expr_pct_change(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_log(a, b)
    return @ccall libpolars.polars_expr_log(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_rem(a, b)
    return @ccall libpolars.polars_expr_rem(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_top_k(a, b)
    return @ccall libpolars.polars_expr_top_k(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_cum_sum(expr, reverse)
    return @ccall libpolars.polars_expr_cum_sum(expr::Ptr{polars_expr_t}, reverse::Bool)::Ptr{polars_expr_t}
end

function polars_expr_cum_prod(expr, reverse)
    return @ccall libpolars.polars_expr_cum_prod(expr::Ptr{polars_expr_t}, reverse::Bool)::Ptr{polars_expr_t}
end

function polars_expr_cum_min(expr, reverse)
    return @ccall libpolars.polars_expr_cum_min(expr::Ptr{polars_expr_t}, reverse::Bool)::Ptr{polars_expr_t}
end

function polars_expr_cum_max(expr, reverse)
    return @ccall libpolars.polars_expr_cum_max(expr::Ptr{polars_expr_t}, reverse::Bool)::Ptr{polars_expr_t}
end

function polars_expr_cum_count(expr, reverse)
    return @ccall libpolars.polars_expr_cum_count(expr::Ptr{polars_expr_t}, reverse::Bool)::Ptr{polars_expr_t}
end

function polars_expr_diff(expr, n, null_behavior)
    return @ccall libpolars.polars_expr_diff(expr::Ptr{polars_expr_t}, n::Ptr{polars_expr_t}, null_behavior::polars_null_behavior_t)::Ptr{polars_expr_t}
end

function polars_expr_rank(expr, method, descending)
    return @ccall libpolars.polars_expr_rank(expr::Ptr{polars_expr_t}, method::polars_rank_method_t, descending::Bool)::Ptr{polars_expr_t}
end

function polars_expr_sample_n(expr, n, with_replacement, shuffle, seed)
    return @ccall libpolars.polars_expr_sample_n(expr::Ptr{polars_expr_t}, n::Ptr{polars_expr_t}, with_replacement::Bool, shuffle::Bool, seed::Ptr{UInt64})::Ptr{polars_expr_t}
end

function polars_expr_sample_frac(expr, frac, with_replacement, shuffle, seed)
    return @ccall libpolars.polars_expr_sample_frac(expr::Ptr{polars_expr_t}, frac::Ptr{polars_expr_t}, with_replacement::Bool, shuffle::Bool, seed::Ptr{UInt64})::Ptr{polars_expr_t}
end

function polars_expr_gather(expr, idx, null_on_oob)
    return @ccall libpolars.polars_expr_gather(expr::Ptr{polars_expr_t}, idx::Ptr{polars_expr_t}, null_on_oob::Bool)::Ptr{polars_expr_t}
end

function polars_expr_gather_every(expr, n, offset)
    return @ccall libpolars.polars_expr_gather_every(expr::Ptr{polars_expr_t}, n::Csize_t, offset::Csize_t)::Ptr{polars_expr_t}
end

function polars_expr_list_lengths(a)
    return @ccall libpolars.polars_expr_list_lengths(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_max(a)
    return @ccall libpolars.polars_expr_list_max(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_min(a)
    return @ccall libpolars.polars_expr_list_min(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_arg_max(a)
    return @ccall libpolars.polars_expr_list_arg_max(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_arg_min(a)
    return @ccall libpolars.polars_expr_list_arg_min(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_sum(a)
    return @ccall libpolars.polars_expr_list_sum(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_mean(a)
    return @ccall libpolars.polars_expr_list_mean(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_reverse(a)
    return @ccall libpolars.polars_expr_list_reverse(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_unique(a)
    return @ccall libpolars.polars_expr_list_unique(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_unique_stable(a)
    return @ccall libpolars.polars_expr_list_unique_stable(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_n_unique(a)
    return @ccall libpolars.polars_expr_list_n_unique(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_any(a, ignore_nulls)
    return @ccall libpolars.polars_expr_list_any(a::Ptr{polars_expr_t}, ignore_nulls::Bool)::Ptr{polars_expr_t}
end

function polars_expr_list_all(a, ignore_nulls)
    return @ccall libpolars.polars_expr_list_all(a::Ptr{polars_expr_t}, ignore_nulls::Bool)::Ptr{polars_expr_t}
end

function polars_expr_list_first(a)
    return @ccall libpolars.polars_expr_list_first(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_last(a)
    return @ccall libpolars.polars_expr_list_last(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_median(a)
    return @ccall libpolars.polars_expr_list_median(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_drop_nulls(a)
    return @ccall libpolars.polars_expr_list_drop_nulls(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_list_eval(a, evaluation)

`Lists.eval`: runs `evaluation` once per row, with `element()` bound to that row's list values -- the same primitive the crate already uses internally for `reverse`/`unique`/`unique_stable` above, exposed directly. This is the multiplier for the "most of the list namespace is missing" finding (`plans/parity/batch-9-lists-structs.md`): `all`/`any` have no dedicated `ListNameSpace` method in this polars version at all and are *only* reachable this way (`eval(element().all(ignore\\_nulls))`), and `n_unique`/`filter` compose the same way.
"""
function polars_expr_list_eval(a, evaluation)
    return @ccall libpolars.polars_expr_list_eval(a::Ptr{polars_expr_t}, evaluation::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_list_agg(a, evaluation)

`Lists.agg`: like `eval`, but the per-row expression is expected to reduce to a single scalar (`EvalVariant::ListAgg` instead of `::List`) -- needed for e.g. `n_unique` per row, which `eval` alone cannot express (it stays list-shaped).
"""
function polars_expr_list_agg(a, evaluation)
    return @ccall libpolars.polars_expr_list_agg(a::Ptr{polars_expr_t}, evaluation::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_sort(a, descending, nulls_last)
    return @ccall libpolars.polars_expr_list_sort(a::Ptr{polars_expr_t}, descending::Bool, nulls_last::Bool)::Ptr{polars_expr_t}
end

function polars_expr_list_get(a, index, null_on_oob)
    return @ccall libpolars.polars_expr_list_get(a::Ptr{polars_expr_t}, index::Ptr{polars_expr_t}, null_on_oob::Bool)::Ptr{polars_expr_t}
end

function polars_expr_list_head(a, b)
    return @ccall libpolars.polars_expr_list_head(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_tail(a, b)
    return @ccall libpolars.polars_expr_list_tail(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_shift(a, b)
    return @ccall libpolars.polars_expr_list_shift(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_count_matches(a, b)
    return @ccall libpolars.polars_expr_list_count_matches(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_union(a, b)
    return @ccall libpolars.polars_expr_list_union(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_set_difference(a, b)
    return @ccall libpolars.polars_expr_list_set_difference(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_set_intersection(a, b)
    return @ccall libpolars.polars_expr_list_set_intersection(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_set_symmetric_difference(a, b)
    return @ccall libpolars.polars_expr_list_set_symmetric_difference(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_std(a, ddof)
    return @ccall libpolars.polars_expr_list_std(a::Ptr{polars_expr_t}, ddof::UInt8)::Ptr{polars_expr_t}
end

function polars_expr_list_var(a, ddof)
    return @ccall libpolars.polars_expr_list_var(a::Ptr{polars_expr_t}, ddof::UInt8)::Ptr{polars_expr_t}
end

function polars_expr_list_join(a, separator, ignore_nulls)
    return @ccall libpolars.polars_expr_list_join(a::Ptr{polars_expr_t}, separator::Ptr{polars_expr_t}, ignore_nulls::Bool)::Ptr{polars_expr_t}
end

function polars_expr_list_slice(a, offset, length)
    return @ccall libpolars.polars_expr_list_slice(a::Ptr{polars_expr_t}, offset::Ptr{polars_expr_t}, length::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_gather(a, index, null_on_oob)
    return @ccall libpolars.polars_expr_list_gather(a::Ptr{polars_expr_t}, index::Ptr{polars_expr_t}, null_on_oob::Bool)::Ptr{polars_expr_t}
end

function polars_expr_list_gather_every(a, n, offset)
    return @ccall libpolars.polars_expr_list_gather_every(a::Ptr{polars_expr_t}, n::Ptr{polars_expr_t}, offset::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_diff(a, n, null_behavior)
    return @ccall libpolars.polars_expr_list_diff(a::Ptr{polars_expr_t}, n::Int64, null_behavior::polars_null_behavior_t)::Ptr{polars_expr_t}
end

function polars_expr_list_sample_n(a, n, with_replacement, shuffle, seed)
    return @ccall libpolars.polars_expr_list_sample_n(a::Ptr{polars_expr_t}, n::Ptr{polars_expr_t}, with_replacement::Bool, shuffle::Bool, seed::Ptr{UInt64})::Ptr{polars_expr_t}
end

function polars_expr_list_sample_fraction(a, fraction, with_replacement, shuffle, seed)
    return @ccall libpolars.polars_expr_list_sample_fraction(a::Ptr{polars_expr_t}, fraction::Ptr{polars_expr_t}, with_replacement::Bool, shuffle::Bool, seed::Ptr{UInt64})::Ptr{polars_expr_t}
end

function polars_expr_list_to_array(a, width)
    return @ccall libpolars.polars_expr_list_to_array(a::Ptr{polars_expr_t}, width::Csize_t)::Ptr{polars_expr_t}
end

"""
    polars_expr_list_to_struct(a, names, lens, num_names, out)

Converts a `List` column to a `Struct` column, one field per list position, named `names[i]`. `names.len()` fixes the field count (and so the schema) -- a row whose list is shorter gets `null` for the missing trailing fields; longer is a runtime error (upstream's own behavior).
"""
function polars_expr_list_to_struct(a, names, lens, num_names, out)
    return @ccall libpolars.polars_expr_list_to_struct(a::Ptr{polars_expr_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, num_names::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_list_contains(a, other, nulls_equal)
    return @ccall libpolars.polars_expr_list_contains(a::Ptr{polars_expr_t}, other::Ptr{polars_expr_t}, nulls_equal::Bool)::Ptr{polars_expr_t}
end

function polars_expr_str_to_uppercase(a)
    return @ccall libpolars.polars_expr_str_to_uppercase(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_to_lowercase(a)
    return @ccall libpolars.polars_expr_str_to_lowercase(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_len_bytes(a)
    return @ccall libpolars.polars_expr_str_len_bytes(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_len_chars(a)
    return @ccall libpolars.polars_expr_str_len_chars(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_starts_with(a, b)
    return @ccall libpolars.polars_expr_str_starts_with(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_ends_with(a, b)
    return @ccall libpolars.polars_expr_str_ends_with(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_contains_literal(a, b)
    return @ccall libpolars.polars_expr_str_contains_literal(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_strip_chars(a, b)
    return @ccall libpolars.polars_expr_str_strip_chars(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_strip_prefix(a, b)
    return @ccall libpolars.polars_expr_str_strip_prefix(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_strip_suffix(a, b)
    return @ccall libpolars.polars_expr_str_strip_suffix(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_split(a, b)
    return @ccall libpolars.polars_expr_str_split(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_extract_all(a, b)
    return @ccall libpolars.polars_expr_str_extract_all(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_zfill(a, b)
    return @ccall libpolars.polars_expr_str_zfill(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_head(a, b)
    return @ccall libpolars.polars_expr_str_head(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_tail(a, b)
    return @ccall libpolars.polars_expr_str_tail(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_strip_chars_start(a, b)
    return @ccall libpolars.polars_expr_str_strip_chars_start(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_strip_chars_end(a, b)
    return @ccall libpolars.polars_expr_str_strip_chars_end(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_str_replace_n(a, pat, value, literal, n)
    return @ccall libpolars.polars_expr_str_replace_n(a::Ptr{polars_expr_t}, pat::Ptr{polars_expr_t}, value::Ptr{polars_expr_t}, literal::Bool, n::Int64)::Ptr{polars_expr_t}
end

"""
    polars_expr_str_splitn(a, by, n)

Struct-typed split: exactly `n` fields, the remainder (if any) folded into the last one. Distinct from [`polars_expr_str_split`](@ref) above, which produces a variable-length `List<String>`.
"""
function polars_expr_str_splitn(a, by, n)
    return @ccall libpolars.polars_expr_str_splitn(a::Ptr{polars_expr_t}, by::Ptr{polars_expr_t}, n::Csize_t)::Ptr{polars_expr_t}
end

function polars_expr_str_split_exact(a, by, n)
    return @ccall libpolars.polars_expr_str_split_exact(a::Ptr{polars_expr_t}, by::Ptr{polars_expr_t}, n::Csize_t)::Ptr{polars_expr_t}
end

"""
    polars_expr_str_join(a, delimiter, delimiter_len, ignore_nulls, out)

Aggregating join-with-separator across *all* rows into a single value (upstream `str.join`, the replacement for the deprecated `str.concat`) -- distinct from `Lists.join` above, which joins each row's own list independently. `delimiter` is a plain string (not an `Expr`) because the aggregation itself has no per-row context to evaluate a column expression against.
"""
function polars_expr_str_join(a, delimiter, delimiter_len, ignore_nulls, out)
    return @ccall libpolars.polars_expr_str_join(a::Ptr{polars_expr_t}, delimiter::Ptr{UInt8}, delimiter_len::Csize_t, ignore_nulls::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_str_extract_groups(a, pat, pat_len, out)

Named-capture-group regex extraction into a `Struct` column (one field per named group). `pat` is a plain string, not an `Expr` -- upstream compiles the regex at plan time to determine the output `Struct`'s schema (field names/count), so it cannot vary per row.
"""
function polars_expr_str_extract_groups(a, pat, pat_len, out)
    return @ccall libpolars.polars_expr_str_extract_groups(a::Ptr{polars_expr_t}, pat::Ptr{UInt8}, pat_len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_str_contains(a, pat, strict)
    return @ccall libpolars.polars_expr_str_contains(a::Ptr{polars_expr_t}, pat::Ptr{polars_expr_t}, strict::Bool)::Ptr{polars_expr_t}
end

function polars_expr_str_slice(a, offset, length)
    return @ccall libpolars.polars_expr_str_slice(a::Ptr{polars_expr_t}, offset::Ptr{polars_expr_t}, length::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_str_find(a, pat, strict)

Position (not just presence, unlike `contains`) of the first regex match.
"""
function polars_expr_str_find(a, pat, strict)
    return @ccall libpolars.polars_expr_str_find(a::Ptr{polars_expr_t}, pat::Ptr{polars_expr_t}, strict::Bool)::Ptr{polars_expr_t}
end

"""
    polars_expr_str_pad_start(a, length, fill_char, out)

`fill_char` crosses the FFI boundary as a `u32` codepoint (there is no C `char32_t` binding on the Julia side) and is fallible since not every `u32` is a valid Unicode scalar value.
"""
function polars_expr_str_pad_start(a, length, fill_char, out)
    return @ccall libpolars.polars_expr_str_pad_start(a::Ptr{polars_expr_t}, length::Ptr{polars_expr_t}, fill_char::UInt32, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_str_pad_end(a, length, fill_char, out)
    return @ccall libpolars.polars_expr_str_pad_end(a::Ptr{polars_expr_t}, length::Ptr{polars_expr_t}, fill_char::UInt32, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_str_replace(a, pat, value, literal)
    return @ccall libpolars.polars_expr_str_replace(a::Ptr{polars_expr_t}, pat::Ptr{polars_expr_t}, value::Ptr{polars_expr_t}, literal::Bool)::Ptr{polars_expr_t}
end

function polars_expr_str_replace_all(a, pat, value, literal)
    return @ccall libpolars.polars_expr_str_replace_all(a::Ptr{polars_expr_t}, pat::Ptr{polars_expr_t}, value::Ptr{polars_expr_t}, literal::Bool)::Ptr{polars_expr_t}
end

function polars_expr_str_extract(a, pat, group_index)
    return @ccall libpolars.polars_expr_str_extract(a::Ptr{polars_expr_t}, pat::Ptr{polars_expr_t}, group_index::Csize_t)::Ptr{polars_expr_t}
end

function polars_expr_str_count_matches(a, pat, literal)
    return @ccall libpolars.polars_expr_str_count_matches(a::Ptr{polars_expr_t}, pat::Ptr{polars_expr_t}, literal::Bool)::Ptr{polars_expr_t}
end

function polars_expr_str_to_date(expr, format, format_len, strict, exact, out)
    return @ccall libpolars.polars_expr_str_to_date(expr::Ptr{polars_expr_t}, format::Ptr{UInt8}, format_len::Csize_t, strict::Bool, exact::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_str_to_datetime(expr, format, format_len, time_unit, strict, exact, out)
    return @ccall libpolars.polars_expr_str_to_datetime(expr::Ptr{polars_expr_t}, format::Ptr{UInt8}, format_len::Csize_t, time_unit::polars_time_unit_t, strict::Bool, exact::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_dt_year(a)
    return @ccall libpolars.polars_expr_dt_year(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_month(a)
    return @ccall libpolars.polars_expr_dt_month(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_day(a)
    return @ccall libpolars.polars_expr_dt_day(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_hour(a)
    return @ccall libpolars.polars_expr_dt_hour(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_minute(a)
    return @ccall libpolars.polars_expr_dt_minute(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_second(a)
    return @ccall libpolars.polars_expr_dt_second(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_weekday(a)
    return @ccall libpolars.polars_expr_dt_weekday(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_ordinal_day(a)
    return @ccall libpolars.polars_expr_dt_ordinal_day(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_week(a)
    return @ccall libpolars.polars_expr_dt_week(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_quarter(a)
    return @ccall libpolars.polars_expr_dt_quarter(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_date(a)
    return @ccall libpolars.polars_expr_dt_date(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_time(a)
    return @ccall libpolars.polars_expr_dt_time(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_truncate(a, b)
    return @ccall libpolars.polars_expr_dt_truncate(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_round(a, b)
    return @ccall libpolars.polars_expr_dt_round(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_offset_by(a, b)
    return @ccall libpolars.polars_expr_dt_offset_by(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_dt_convert_time_zone(expr, tz, tz_len, out)

`convert_time_zone`: re-labels the same instant into a different (mandatory) time zone, e.g. UTC -> "America/New\\_York". Fails if `tz` is not a valid IANA time zone name.
"""
function polars_expr_dt_convert_time_zone(expr, tz, tz_len, out)
    return @ccall libpolars.polars_expr_dt_convert_time_zone(expr::Ptr{polars_expr_t}, tz::Ptr{UInt8}, tz_len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_dt_replace_time_zone(expr, tz, tz_len, ambiguous, non_existent, out)

`replace_time_zone`: attaches/strips/re-attaches a time zone label to the *same* local wall-clock values (unlike `convert_time_zone`, which preserves the instant). `tz\\_len == 0` means "strip the time zone back to naive" (`time\\_zone = None`).
"""
function polars_expr_dt_replace_time_zone(expr, tz, tz_len, ambiguous, non_existent, out)
    return @ccall libpolars.polars_expr_dt_replace_time_zone(expr::Ptr{polars_expr_t}, tz::Ptr{UInt8}, tz_len::Csize_t, ambiguous::Ptr{polars_expr_t}, non_existent::polars_non_existent_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_dt_timestamp(expr, unit, out)

Fallible since [`polars_time_unit_t`](@ref) mirrors a Julia-side `

`` and must reject an`

out-of-range value rather than let `to_time_unit` panic across the FFI boundary.
"""
function polars_expr_dt_timestamp(expr, unit, out)
    return @ccall libpolars.polars_expr_dt_timestamp(expr::Ptr{polars_expr_t}, unit::polars_time_unit_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_dt_strftime(expr, format, len, out)
    return @ccall libpolars.polars_expr_dt_strftime(expr::Ptr{polars_expr_t}, format::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_dt_total_days(a, fractional)
    return @ccall libpolars.polars_expr_dt_total_days(a::Ptr{polars_expr_t}, fractional::Bool)::Ptr{polars_expr_t}
end

function polars_expr_dt_total_hours(a, fractional)
    return @ccall libpolars.polars_expr_dt_total_hours(a::Ptr{polars_expr_t}, fractional::Bool)::Ptr{polars_expr_t}
end

function polars_expr_dt_total_minutes(a, fractional)
    return @ccall libpolars.polars_expr_dt_total_minutes(a::Ptr{polars_expr_t}, fractional::Bool)::Ptr{polars_expr_t}
end

function polars_expr_dt_total_seconds(a, fractional)
    return @ccall libpolars.polars_expr_dt_total_seconds(a::Ptr{polars_expr_t}, fractional::Bool)::Ptr{polars_expr_t}
end

function polars_expr_dt_total_milliseconds(a, fractional)
    return @ccall libpolars.polars_expr_dt_total_milliseconds(a::Ptr{polars_expr_t}, fractional::Bool)::Ptr{polars_expr_t}
end

function polars_expr_dt_total_microseconds(a, fractional)
    return @ccall libpolars.polars_expr_dt_total_microseconds(a::Ptr{polars_expr_t}, fractional::Bool)::Ptr{polars_expr_t}
end

function polars_expr_dt_total_nanoseconds(a, fractional)
    return @ccall libpolars.polars_expr_dt_total_nanoseconds(a::Ptr{polars_expr_t}, fractional::Bool)::Ptr{polars_expr_t}
end

function polars_expr_struct_field_by_name(a, name, len, out)
    return @ccall libpolars.polars_expr_struct_field_by_name(a::Ptr{polars_expr_t}, name::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_struct_field_by_index(a, fieldidx)
    return @ccall libpolars.polars_expr_struct_field_by_index(a::Ptr{polars_expr_t}, fieldidx::Int64)::Ptr{polars_expr_t}
end

function polars_expr_struct_rename_fields(a, names, lens, num_names, out)
    return @ccall libpolars.polars_expr_struct_rename_fields(a::Ptr{polars_expr_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, num_names::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_struct_json_encode(expr)
    return @ccall libpolars.polars_expr_struct_json_encode(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_struct_with_fields(a, fields, n_fields)

Applies each of `fields` to the struct's selected field(s) in place (via `pl.field("x")...` inside each expression), leaving other fields untouched -- upstream `struct.with\\_fields`.
"""
function polars_expr_struct_with_fields(a, fields, n_fields)
    return @ccall libpolars.polars_expr_struct_with_fields(a::Ptr{polars_expr_t}, fields::Ptr{Ptr{polars_expr_t}}, n_fields::Csize_t)::Ptr{polars_expr_t}
end

function polars_expr_meta_is_column(expr)
    return @ccall libpolars.polars_expr_meta_is_column(expr::Ptr{polars_expr_t})::Bool
end

function polars_expr_meta_is_literal(expr, allow_aliasing)
    return @ccall libpolars.polars_expr_meta_is_literal(expr::Ptr{polars_expr_t}, allow_aliasing::Bool)::Bool
end

function polars_expr_meta_has_multiple_outputs(expr)
    return @ccall libpolars.polars_expr_meta_has_multiple_outputs(expr::Ptr{polars_expr_t})::Bool
end

function polars_expr_meta_undo_aliases(expr)
    return @ccall libpolars.polars_expr_meta_undo_aliases(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

"""
    polars_expr_meta_output_name(expr, user, callback)

Fails if the expression has no single well-defined output name (e.g. a wildcard or a selector-expanded expression).
"""
function polars_expr_meta_output_name(expr, user, callback)
    return @ccall libpolars.polars_expr_meta_output_name(expr::Ptr{polars_expr_t}, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

"""
    polars_expr_meta_tree_format(expr, display_as_dot, user, callback)

Backs both `tree_format` (`display\\_as\\_dot = false`) and `show_graph` (`true`). No schema is threaded through, so unresolved column types show as untyped.
"""
function polars_expr_meta_tree_format(expr, display_as_dot, user, callback)
    return @ccall libpolars.polars_expr_meta_tree_format(expr::Ptr{polars_expr_t}, display_as_dot::Bool, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

function polars_expr_meta_root_names_len(expr)
    return @ccall libpolars.polars_expr_meta_root_names_len(expr::Ptr{polars_expr_t})::Csize_t
end

function polars_expr_meta_root_names_get(expr, index, user, callback)
    return @ccall libpolars.polars_expr_meta_root_names_get(expr::Ptr{polars_expr_t}, index::Csize_t, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

function polars_expr_selector_all()
    return @ccall libpolars.polars_expr_selector_all()::Ptr{polars_expr_t}
end

"""
    polars_expr_selector_empty()

The identity element for selector combinators (`empty() | s == s`, `empty() & s == empty()`).
"""
function polars_expr_selector_empty()
    return @ccall libpolars.polars_expr_selector_empty()::Ptr{polars_expr_t}
end

function polars_expr_selector_by_name(names, lens, n, strict, out)
    return @ccall libpolars.polars_expr_selector_by_name(names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, strict::Bool, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

"""
    polars_expr_selector_by_index(indices, n, strict)

Selects columns by 0-based index; negative indices count back from the end.
"""
function polars_expr_selector_by_index(indices, n, strict)
    return @ccall libpolars.polars_expr_selector_by_index(indices::Ptr{Int64}, n::Csize_t, strict::Bool)::Ptr{polars_expr_t}
end

"""
    polars_expr_selector_matches(kind, pattern, len, out)

Backs `matches` (verbatim regex) and the regex-sugar `starts_with`/`ends_with`/`contains` (anchored/escaped literal substrings) -- all four build a `Selector::Matches(pattern)`, differing only in how `pattern` is derived from the caller's raw string. Anchoring and escaping happen here, not on the Julia side: Julia has no built-in regex-metacharacter escaper (`escape_string` escapes string *literals*, not regex syntax), so hand-rolling that table would otherwise have to happen twice.
"""
function polars_expr_selector_matches(kind, pattern, len, out)
    return @ccall libpolars.polars_expr_selector_matches(kind::polars_selector_match_kind_t, pattern::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_selector_dtype_simple(kind)
    return @ccall libpolars.polars_expr_selector_dtype_simple(kind::polars_dtype_selector_kind_t)::Ptr{polars_expr_t}
end

"""
    polars_expr_selector_dtype_any_of(value_types, n, out)

`ByDType(AnyOf([...]))` -- backs `string`/`boolean`/`binary`/`date`/`time` (dtypes with no dedicated `DataTypeSelector` variant, so they must route through `AnyOf` rather than `dtype_simple` above) and the explicit `by\\_dtype([...])`. Fallible per-element: `to_dtype` rejects type codes that need parameters it can't carry (Datetime/Duration/Decimal/List/Struct) -- see `[`polars_value_type_t`](@ref)::to\\_dtype`'s own doc. That is intentional here too: those parametrized dtypes are reached via `dtype_simple` instead, so hitting this error path from e.g. `by\\_dtype([Datetime])` is a real, expected error, not a bug.
"""
function polars_expr_selector_dtype_any_of(value_types, n, out)
    return @ccall libpolars.polars_expr_selector_dtype_any_of(value_types::Ptr{polars_value_type_t}, n::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_selector_union(a, b, out)
    return @ccall libpolars.polars_expr_selector_union(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t}, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_selector_difference(a, b, out)
    return @ccall libpolars.polars_expr_selector_difference(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t}, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_selector_exclusive_or(a, b, out)
    return @ccall libpolars.polars_expr_selector_exclusive_or(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t}, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_selector_intersect(a, b, out)
    return @ccall libpolars.polars_expr_selector_intersect(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t}, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_scan_parquet(path, pathlen, n_rows, row_index_name, row_index_name_len, row_index_offset, parallel, low_memory, rechunk, cache, glob, use_statistics, allow_missing_columns, include_file_paths, include_file_paths_len, hive_partitioning, cloud_options, out)
    return @ccall libpolars.polars_lazy_frame_scan_parquet(path::Ptr{UInt8}, pathlen::Csize_t, n_rows::Ptr{Csize_t}, row_index_name::Ptr{UInt8}, row_index_name_len::Csize_t, row_index_offset::UInt32, parallel::polars_parquet_parallel_strategy_t, low_memory::Bool, rechunk::Bool, cache::Bool, glob::Bool, use_statistics::Bool, allow_missing_columns::Bool, include_file_paths::Ptr{UInt8}, include_file_paths_len::Csize_t, hive_partitioning::Ptr{Bool}, cloud_options::Ptr{polars_cloud_options_t}, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_scan_csv(path, pathlen, n_rows, row_index_name, row_index_name_len, row_index_offset, has_header, separator, quote_char, comment_prefix, comment_prefix_len, skip_rows, skip_rows_after_header, null_value, null_value_len, missing_is_null, truncate_ragged_lines, try_parse_dates, infer_schema_length, ignore_errors, low_memory, rechunk, cache, glob, include_file_paths, include_file_paths_len, allow_missing_columns, cloud_options, out)
    return @ccall libpolars.polars_lazy_frame_scan_csv(path::Ptr{UInt8}, pathlen::Csize_t, n_rows::Ptr{Csize_t}, row_index_name::Ptr{UInt8}, row_index_name_len::Csize_t, row_index_offset::UInt32, has_header::Bool, separator::UInt8, quote_char::Ptr{UInt8}, comment_prefix::Ptr{UInt8}, comment_prefix_len::Csize_t, skip_rows::Csize_t, skip_rows_after_header::Csize_t, null_value::Ptr{UInt8}, null_value_len::Csize_t, missing_is_null::Bool, truncate_ragged_lines::Bool, try_parse_dates::Bool, infer_schema_length::Ptr{Csize_t}, ignore_errors::Bool, low_memory::Bool, rechunk::Bool, cache::Bool, glob::Bool, include_file_paths::Ptr{UInt8}, include_file_paths_len::Csize_t, allow_missing_columns::Bool, cloud_options::Ptr{polars_cloud_options_t}, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_scan_ipc(path, pathlen, n_rows, row_index_name, row_index_name_len, row_index_offset, rechunk, cache, glob, include_file_paths, include_file_paths_len, hive_partitioning, allow_missing_columns, cloud_options, out)
    return @ccall libpolars.polars_lazy_frame_scan_ipc(path::Ptr{UInt8}, pathlen::Csize_t, n_rows::Ptr{Csize_t}, row_index_name::Ptr{UInt8}, row_index_name_len::Csize_t, row_index_offset::UInt32, rechunk::Bool, cache::Bool, glob::Bool, include_file_paths::Ptr{UInt8}, include_file_paths_len::Csize_t, hive_partitioning::Ptr{Bool}, allow_missing_columns::Bool, cloud_options::Ptr{polars_cloud_options_t}, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_sink_parquet(lf, path, pathlen, compression, compression_level, statistics, row_group_size, data_page_size, mkdir, maintain_order, cloud_options, out)
    return @ccall libpolars.polars_lazy_frame_sink_parquet(lf::Ptr{polars_lazy_frame_t}, path::Ptr{UInt8}, pathlen::Csize_t, compression::polars_parquet_compression_t, compression_level::Ptr{Int32}, statistics::Bool, row_group_size::Ptr{Csize_t}, data_page_size::Ptr{Csize_t}, mkdir::Bool, maintain_order::Bool, cloud_options::Ptr{polars_cloud_options_t}, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_sink_csv(lf, path, pathlen, include_header, include_bom, separator, quote_char, null_value, null_value_len, line_terminator, line_terminator_len, quote_style, date_format, date_format_len, time_format, time_format_len, datetime_format, datetime_format_len, float_precision, decimal_comma, compression, compression_level, mkdir, maintain_order, cloud_options, out)
    return @ccall libpolars.polars_lazy_frame_sink_csv(lf::Ptr{polars_lazy_frame_t}, path::Ptr{UInt8}, pathlen::Csize_t, include_header::Bool, include_bom::Bool, separator::UInt8, quote_char::UInt8, null_value::Ptr{UInt8}, null_value_len::Csize_t, line_terminator::Ptr{UInt8}, line_terminator_len::Csize_t, quote_style::polars_quote_style_t, date_format::Ptr{UInt8}, date_format_len::Csize_t, time_format::Ptr{UInt8}, time_format_len::Csize_t, datetime_format::Ptr{UInt8}, datetime_format_len::Csize_t, float_precision::Ptr{Csize_t}, decimal_comma::Bool, compression::polars_csv_compression_t, compression_level::Ptr{UInt32}, mkdir::Bool, maintain_order::Bool, cloud_options::Ptr{polars_cloud_options_t}, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_sink_ipc(lf, path, pathlen, compression, compression_level, record_batch_size, mkdir, maintain_order, cloud_options, out)
    return @ccall libpolars.polars_lazy_frame_sink_ipc(lf::Ptr{polars_lazy_frame_t}, path::Ptr{UInt8}, pathlen::Csize_t, compression::polars_ipc_compression_t, compression_level::Ptr{Int32}, record_batch_size::Ptr{Csize_t}, mkdir::Bool, maintain_order::Bool, cloud_options::Ptr{polars_cloud_options_t}, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

"""
    polars_cloud_options_new(keys, key_lens, values, value_lens, n, out)

Builds a [`polars_cloud_options_t`](@ref) from parallel `(ptr-array, len-array, n)` key/value pairs -- e.g. `("aws\\_access\\_key\\_id", "...")`. The pairs are stored unparsed (see the type's own doc comment in `types.rs`); actual `CloudOptions` construction is deferred to each scan/sink call site, once the destination path (and so the cloud scheme) is known.
"""
function polars_cloud_options_new(keys, key_lens, values, value_lens, n, out)
    return @ccall libpolars.polars_cloud_options_new(keys::Ptr{Ptr{UInt8}}, key_lens::Ptr{Csize_t}, values::Ptr{Ptr{UInt8}}, value_lens::Ptr{Csize_t}, n::Csize_t, out::Ptr{Ptr{polars_cloud_options_t}})::Ptr{polars_error_t}
end

function polars_cloud_options_destroy(ptr)
    return @ccall libpolars.polars_cloud_options_destroy(ptr::Ptr{polars_cloud_options_t})::Cvoid
end

function polars_series_destroy(series)
    return @ccall libpolars.polars_series_destroy(series::Ptr{polars_series_t})::Cvoid
end

function polars_series_type(series)
    return @ccall libpolars.polars_series_type(series::Ptr{polars_series_t})::polars_value_type_t
end

function polars_series_length(series)
    return @ccall libpolars.polars_series_length(series::Ptr{polars_series_t})::Csize_t
end

function polars_series_null_count(series)
    return @ccall libpolars.polars_series_null_count(series::Ptr{polars_series_t})::Csize_t
end

function polars_series_schema(series, out)
    return @ccall libpolars.polars_series_schema(series::Ptr{polars_series_t}, out::Ptr{ArrowSchema})::Ptr{polars_error_t}
end

"""
    polars_series_export_carray(series, out)

Exports the series' data as a single Arrow C Data Interface [`ArrowArray`](@ref), collapsing the series to one chunk first if necessary. The returned [`ArrowArray`](@ref) is self-contained (owns its buffers via the release callback) and can outlive `series` -- the caller takes ownership and must eventually invoke `.release` exactly once.
"""
function polars_series_export_carray(series, out)
    return @ccall libpolars.polars_series_export_carray(series::Ptr{polars_series_t}, out::Ptr{ArrowArray})::Ptr{polars_error_t}
end

"""
    polars_series_is_null(series, index)

Returns whether or not the value at index `index` is null, return false if the index is out of bounds.
"""
function polars_series_is_null(series, index)
    return @ccall libpolars.polars_series_is_null(series::Ptr{polars_series_t}, index::Csize_t)::Bool
end

"""
    polars_series_slice(series, offset, length)

Returns a new owned series holding a zero-copy (Arc-refcount clone) slice of `length` elements starting at `offset`.
"""
function polars_series_slice(series, offset, length)
    return @ccall libpolars.polars_series_slice(series::Ptr{polars_series_t}, offset::Int64, length::Csize_t)::Ptr{polars_series_t}
end

"""
    polars_series_name(series, out)

Borrowed pointer into the series' name, valid only as long as `series` is alive.
"""
function polars_series_name(series, out)
    return @ccall libpolars.polars_series_name(series::Ptr{polars_series_t}, out::Ptr{Ptr{UInt8}})::Csize_t
end

function polars_series_get(series, index, out)
    return @ccall libpolars.polars_series_get(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{Ptr{polars_value_t}})::Ptr{polars_error_t}
end

function polars_series_get_bool(series, index, out)
    return @ccall libpolars.polars_series_get_bool(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{Bool})::Ptr{polars_error_t}
end

function polars_series_get_u8(series, index, out)
    return @ccall libpolars.polars_series_get_u8(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{UInt8})::Ptr{polars_error_t}
end

function polars_series_get_u16(series, index, out)
    return @ccall libpolars.polars_series_get_u16(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{UInt16})::Ptr{polars_error_t}
end

function polars_series_get_u32(series, index, out)
    return @ccall libpolars.polars_series_get_u32(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{UInt32})::Ptr{polars_error_t}
end

function polars_series_get_u64(series, index, out)
    return @ccall libpolars.polars_series_get_u64(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{UInt64})::Ptr{polars_error_t}
end

function polars_series_get_i8(series, index, out)
    return @ccall libpolars.polars_series_get_i8(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{Int8})::Ptr{polars_error_t}
end

function polars_series_get_i16(series, index, out)
    return @ccall libpolars.polars_series_get_i16(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{Int16})::Ptr{polars_error_t}
end

function polars_series_get_i32(series, index, out)
    return @ccall libpolars.polars_series_get_i32(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{Int32})::Ptr{polars_error_t}
end

function polars_series_get_i64(series, index, out)
    return @ccall libpolars.polars_series_get_i64(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{Int64})::Ptr{polars_error_t}
end

function polars_series_get_f32(series, index, out)
    return @ccall libpolars.polars_series_get_f32(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{Cfloat})::Ptr{polars_error_t}
end

function polars_series_get_f64(series, index, out)
    return @ccall libpolars.polars_series_get_f64(series::Ptr{polars_series_t}, index::Csize_t, out::Ptr{Cdouble})::Ptr{polars_error_t}
end

function polars_value_time_unit(value)
    return @ccall libpolars.polars_value_time_unit(value::Ptr{polars_value_t})::polars_time_unit_t
end

"""
    polars_value_time_zone(value, out)

Borrowed pointer into this datetime value's timezone name, valid as long as `value` is alive. Returns 0 (and leaves `out` unwritten) for a naive datetime or any non-datetime value.
"""
function polars_value_time_zone(value, out)
    return @ccall libpolars.polars_value_time_zone(value::Ptr{polars_value_t}, out::Ptr{Ptr{UInt8}})::Csize_t
end

function polars_value_type(value)
    return @ccall libpolars.polars_value_type(value::Ptr{polars_value_t})::polars_value_type_t
end

function polars_value_destroy(value)
    return @ccall libpolars.polars_value_destroy(value::Ptr{polars_value_t})::Cvoid
end

function polars_value_get_bool(value, out)
    return @ccall libpolars.polars_value_get_bool(value::Ptr{polars_value_t}, out::Ptr{Bool})::Ptr{polars_error_t}
end

function polars_value_get_u8(value, out)
    return @ccall libpolars.polars_value_get_u8(value::Ptr{polars_value_t}, out::Ptr{UInt8})::Ptr{polars_error_t}
end

function polars_value_get_u16(value, out)
    return @ccall libpolars.polars_value_get_u16(value::Ptr{polars_value_t}, out::Ptr{UInt16})::Ptr{polars_error_t}
end

function polars_value_get_u32(value, out)
    return @ccall libpolars.polars_value_get_u32(value::Ptr{polars_value_t}, out::Ptr{UInt32})::Ptr{polars_error_t}
end

function polars_value_get_u64(value, out)
    return @ccall libpolars.polars_value_get_u64(value::Ptr{polars_value_t}, out::Ptr{UInt64})::Ptr{polars_error_t}
end

function polars_value_get_i8(value, out)
    return @ccall libpolars.polars_value_get_i8(value::Ptr{polars_value_t}, out::Ptr{Int8})::Ptr{polars_error_t}
end

function polars_value_get_i16(value, out)
    return @ccall libpolars.polars_value_get_i16(value::Ptr{polars_value_t}, out::Ptr{Int16})::Ptr{polars_error_t}
end

function polars_value_get_i32(value, out)
    return @ccall libpolars.polars_value_get_i32(value::Ptr{polars_value_t}, out::Ptr{Int32})::Ptr{polars_error_t}
end

function polars_value_get_i64(value, out)
    return @ccall libpolars.polars_value_get_i64(value::Ptr{polars_value_t}, out::Ptr{Int64})::Ptr{polars_error_t}
end

function polars_value_get_f32(value, out)
    return @ccall libpolars.polars_value_get_f32(value::Ptr{polars_value_t}, out::Ptr{Cfloat})::Ptr{polars_error_t}
end

function polars_value_get_f64(value, out)
    return @ccall libpolars.polars_value_get_f64(value::Ptr{polars_value_t}, out::Ptr{Cdouble})::Ptr{polars_error_t}
end

"""
    polars_value_list_get(value, out)

Returns the value as a Series when the dtype of the value is a list.
"""
function polars_value_list_get(value, out)
    return @ccall libpolars.polars_value_list_get(value::Ptr{polars_value_t}, out::Ptr{Ptr{polars_series_t}})::Ptr{polars_error_t}
end

function polars_value_string_get(value, user, callback)
    return @ccall libpolars.polars_value_string_get(value::Ptr{polars_value_t}, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

"""
    polars_value_duration_get(value, out)

Get the underlying int64 for this duration value.
"""
function polars_value_duration_get(value, out)
    return @ccall libpolars.polars_value_duration_get(value::Ptr{polars_value_t}, out::Ptr{Int64})::Ptr{polars_error_t}
end

"""
    polars_value_datetime_get(value, out)

Get the underlying int64 for this datetime value.
"""
function polars_value_datetime_get(value, out)
    return @ccall libpolars.polars_value_datetime_get(value::Ptr{polars_value_t}, out::Ptr{Int64})::Ptr{polars_error_t}
end

"""
    polars_value_date_get(value, out)

Get the underlying int32 (days since UNIX epoch) for this date value.
"""
function polars_value_date_get(value, out)
    return @ccall libpolars.polars_value_date_get(value::Ptr{polars_value_t}, out::Ptr{Int32})::Ptr{polars_error_t}
end

"""
    polars_value_time_get(value, out)

Get the underlying int64 for this time value. `DataType::Time` is always nanoseconds since midnight (unlike Datetime/Duration, it carries no `TimeUnit`), so there is no companion [`polars_value_time_unit`](@ref)-style call for it.
"""
function polars_value_time_get(value, out)
    return @ccall libpolars.polars_value_time_get(value::Ptr{polars_value_t}, out::Ptr{Int64})::Ptr{polars_error_t}
end

function polars_value_binary_get(value, user, callback)
    return @ccall libpolars.polars_value_binary_get(value::Ptr{polars_value_t}, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

"""
    polars_value_struct_get(value, fieldidx, out)

Returns the value of struct field `fieldidx`.

# Safety The returned value borrows into the parent struct's backing memory (as every [`polars_value_t`](@ref) does -- it wraps an `AnyValue<'a>`). Lifetime parameters on a `#[no\\_mangle] extern "C"` fn enforce nothing across the C boundary, so this is a *caller invariant*, not a compiler-checked one: **the caller must keep `value` (and its parent Series) alive until it is done with `*out`, and must destroy `*out` before `value`.** The Julia side roots the parent accordingly.
"""
function polars_value_struct_get(value, fieldidx, out)
    return @ccall libpolars.polars_value_struct_get(value::Ptr{polars_value_t}, fieldidx::Csize_t, out::Ptr{Ptr{polars_value_t}})::Ptr{polars_error_t}
end

"""
    polars_value_list_type(value)

Returns the element type of the provided value which must be a list. The value type is PolarsValueTypeUnknown if the value is not a list so makes sure it is one otherwise, you cannot differentiate between list<unkown> and unkown.
"""
function polars_value_list_type(value)
    return @ccall libpolars.polars_value_list_type(value::Ptr{polars_value_t})::polars_value_type_t
end

const ARROW_FLAG_DICTIONARY_ORDERED = 1

const ARROW_FLAG_NULLABLE = 2

const ARROW_FLAG_MAP_KEYS_SORTED = 4

# exports
const PREFIXES = ["polars_", "Polars"]
for name in names(@__MODULE__; all = true), prefix in PREFIXES
    if startswith(string(name), prefix)
        @eval export $name
    end
end
