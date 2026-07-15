module API

using libpolars_jll
export libpolars_jll

using CEnum: CEnum, @cenum

const libpolars_local_dir = joinpath(@__DIR__, "../c-polars/target/debug/")
@static if isdir(libpolars_local_dir) && isfile(
        begin
            libpolars_local_file_path = joinpath(libpolars_local_dir, "libpolars" * (Sys.islinux() ? ".so" : ".dylib"))
        end
    )
    const libpolars = libpolars_local_file_path
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

@cenum PolarsEngine::UInt32 begin
    PolarsEngineInMemory = 0
    PolarsEngineStreaming = 1
end

@cenum polars_time_unit_t::UInt32 begin
    PolarsTimeUnitNanosecond = 0
    PolarsTimeUnitMicrosecond = 1
    PolarsTimeUnitMillisecond = 2
    PolarsTimeUnitInvalid = 3
end

@cenum polars_closed_window_t::UInt32 begin
    PolarsClosedWindowLeft = 0
    PolarsClosedWindowRight = 1
    PolarsClosedWindowBoth = 2
    PolarsClosedWindowNone = 3
end

@cenum polars_label_t::UInt32 begin
    PolarsLabelLeft = 0
    PolarsLabelRight = 1
    PolarsLabelDataPoint = 2
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
    PolarsValueTypeUnknown = 19
end

@cenum polars_quantile_method_t::UInt32 begin
    PolarsQuantileMethodNearest = 0
    PolarsQuantileMethodLower = 1
    PolarsQuantileMethodHigher = 2
    PolarsQuantileMethodMidpoint = 3
    PolarsQuantileMethodLinear = 4
    PolarsQuantileMethodEquiprobable = 5
end

@cenum polars_null_behavior_t::UInt32 begin
    PolarsNullBehaviorDrop = 0
    PolarsNullBehaviorIgnore = 1
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

@cenum polars_non_existent_t::UInt32 begin
    PolarsNonExistentRaise = 0
    PolarsNonExistentNull = 1
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

@cenum polars_asof_strategy_t::UInt32 begin
    PolarsAsofStrategyBackward = 0
    PolarsAsofStrategyForward = 1
    PolarsAsofStrategyNearest = 2
end

@cenum polars_pivot_column_naming_t::UInt32 begin
    PolarsPivotColumnNamingCombine = 0
    PolarsPivotColumnNamingAuto = 1
end

@cenum polars_interpolation_method_t::UInt32 begin
    PolarsInterpolationMethodLinear = 0
    PolarsInterpolationMethodNearest = 1
end

@cenum polars_unique_keep_t::UInt32 begin
    PolarsUniqueKeepFirst = 0
    PolarsUniqueKeepLast = 1
    PolarsUniqueKeepNone = 2
    PolarsUniqueKeepAny = 3
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
    polars_dataframe_new_from_carrow(cfield, carray)

Creates a DataFrame from a series of [`ArrowArray`](@ref) and [`ArrowSchema`](@ref) compatible the arrow C-ABI.

# Safety The field array should be valid [`ArrowSchema`](@ref) according to the C Data Interface. The array array should be valid [`ArrowArray`](@ref) according to the C Data Interface, this means that the memory ownership is transferred in the created arrow::Array. Therefore, the caller should *not* free the underlying memories for this arrow as this will be done through the release field of the array.

Returns null if something went wrong.
"""
function polars_dataframe_new_from_carrow(cfield, carray)
    return @ccall libpolars.polars_dataframe_new_from_carrow(cfield::Ptr{ArrowSchema}, carray::ArrowArray)::Ptr{polars_dataframe_t}
end

"""
    polars_dataframe_schema(df)

Returns a [`ArrowSchema`](@ref) describing the dataframe's schema according to Arrow C Data interface.
"""
function polars_dataframe_schema(df)
    return @ccall libpolars.polars_dataframe_schema(df::Ptr{polars_dataframe_t})::ArrowSchema
end

function polars_dataframe_new_from_series(series, nseries, out)
    return @ccall libpolars.polars_dataframe_new_from_series(series::Ptr{Ptr{polars_series_t}}, nseries::Csize_t, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

function polars_dataframe_destroy(df)
    return @ccall libpolars.polars_dataframe_destroy(df::Ptr{polars_dataframe_t})::Cvoid
end

function polars_dataframe_write_parquet(
        df, user, callback, compression, compression_level, statistics, row_group_size,
        data_page_size
    )
    return @ccall libpolars.polars_dataframe_write_parquet(
        df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback,
        compression::polars_parquet_compression_t, compression_level::Ptr{Int32}, statistics::Bool,
        row_group_size::Ptr{Csize_t}, data_page_size::Ptr{Csize_t}
    )::Ptr{polars_error_t}
end

function polars_dataframe_write_csv(df, user, callback)
    return @ccall libpolars.polars_dataframe_write_csv(df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
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

function polars_dataframe_upsample(
        df, by_names, by_lens, n_by, time_column, time_column_len, every, every_len, stable, out
    )
    return @ccall libpolars.polars_dataframe_upsample(
        df::Ptr{polars_dataframe_t}, by_names::Ptr{Ptr{UInt8}}, by_lens::Ptr{Csize_t}, n_by::Csize_t,
        time_column::Ptr{UInt8}, time_column_len::Csize_t, every::Ptr{UInt8}, every_len::Csize_t,
        stable::Bool, out::Ptr{Ptr{polars_dataframe_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_destroy(df)
    return @ccall libpolars.polars_lazy_frame_destroy(df::Ptr{polars_lazy_frame_t})::Cvoid
end

function polars_lazy_frame_clone(df)
    return @ccall libpolars.polars_lazy_frame_clone(df::Ptr{polars_lazy_frame_t})::Ptr{polars_lazy_frame_t}
end

function polars_lazy_frame_scan_parquet(
        path, pathlen, n_rows, row_index_name, row_index_name_len, row_index_offset, parallel,
        low_memory, rechunk, cache, glob, use_statistics, allow_missing_columns,
        include_file_paths, include_file_paths_len, hive_partitioning, out
    )
    return @ccall libpolars.polars_lazy_frame_scan_parquet(
        path::Ptr{UInt8}, pathlen::Csize_t, n_rows::Ptr{Csize_t}, row_index_name::Ptr{UInt8},
        row_index_name_len::Csize_t, row_index_offset::UInt32,
        parallel::polars_parquet_parallel_strategy_t, low_memory::Bool, rechunk::Bool, cache::Bool,
        glob::Bool, use_statistics::Bool, allow_missing_columns::Bool,
        include_file_paths::Ptr{UInt8}, include_file_paths_len::Csize_t,
        hive_partitioning::Ptr{Bool}, out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_scan_csv(path, pathlen, out)
    return @ccall libpolars.polars_lazy_frame_scan_csv(path::Ptr{UInt8}, pathlen::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_scan_ipc(path, pathlen, out)
    return @ccall libpolars.polars_lazy_frame_scan_ipc(path::Ptr{UInt8}, pathlen::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_sink_parquet(
        lf, path, pathlen, compression, compression_level, statistics, row_group_size,
        data_page_size, mkdir, maintain_order, out
    )
    return @ccall libpolars.polars_lazy_frame_sink_parquet(
        lf::Ptr{polars_lazy_frame_t}, path::Ptr{UInt8}, pathlen::Csize_t,
        compression::polars_parquet_compression_t, compression_level::Ptr{Int32}, statistics::Bool,
        row_group_size::Ptr{Csize_t}, data_page_size::Ptr{Csize_t}, mkdir::Bool,
        maintain_order::Bool, out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_sink_csv(lf, path, pathlen, out)
    return @ccall libpolars.polars_lazy_frame_sink_csv(lf::Ptr{polars_lazy_frame_t}, path::Ptr{UInt8}, pathlen::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_sink_ipc(lf, path, pathlen, out)
    return @ccall libpolars.polars_lazy_frame_sink_ipc(lf::Ptr{polars_lazy_frame_t}, path::Ptr{UInt8}, pathlen::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_sort(df, exprs, nexprs, descending, nulls_last, maintain_order)
    return @ccall libpolars.polars_lazy_frame_sort(df::Ptr{polars_lazy_frame_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t, descending::Ptr{Bool}, nulls_last::Bool, maintain_order::Bool)::Cvoid
end

function polars_lazy_frame_concat(lfs, n, out)
    return @ccall libpolars.polars_lazy_frame_concat(lfs::Ptr{Ptr{polars_lazy_frame_t}}, n::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
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

function polars_lazy_frame_head(df, n)
    return @ccall libpolars.polars_lazy_frame_head(df::Ptr{polars_lazy_frame_t}, n::Csize_t)::Cvoid
end

function polars_lazy_frame_tail(df, n)
    return @ccall libpolars.polars_lazy_frame_tail(df::Ptr{polars_lazy_frame_t}, n::Csize_t)::Cvoid
end

function polars_lazy_frame_collect(df, engine, out)
    return @ccall libpolars.polars_lazy_frame_collect(df::Ptr{polars_lazy_frame_t}, engine::PolarsEngine, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

"""
    polars_lazy_frame_collect_schema(df, out)

Resolves the lazy frame's schema (without collecting it) and returns it through `out` as an
[`ArrowSchema`](@ref) according to the Arrow C Data interface, matching the shape of
`polars_dataframe_schema`.
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

function polars_lazy_frame_explode(lf, names, lens, n, out)
    return @ccall libpolars.polars_lazy_frame_explode(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_unpivot(lf, index_names, index_lens, n_index, on_names, on_lens, n_on, variable_name, variable_name_len, value_name, value_name_len, out)
    return @ccall libpolars.polars_lazy_frame_unpivot(lf::Ptr{polars_lazy_frame_t}, index_names::Ptr{Ptr{UInt8}}, index_lens::Ptr{Csize_t}, n_index::Csize_t, on_names::Ptr{Ptr{UInt8}}, on_lens::Ptr{Csize_t}, n_on::Csize_t, variable_name::Ptr{UInt8}, variable_name_len::Csize_t, value_name::Ptr{UInt8}, value_name_len::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_pivot(
        lf, on_names, on_lens, n_on, on_columns, index_names, index_lens, n_index, values_names,
        values_lens, n_values, agg, maintain_order, separator, separator_len, column_naming, out
    )
    return @ccall libpolars.polars_lazy_frame_pivot(
        lf::Ptr{polars_lazy_frame_t}, on_names::Ptr{Ptr{UInt8}}, on_lens::Ptr{Csize_t}, n_on::Csize_t,
        on_columns::Ptr{polars_dataframe_t}, index_names::Ptr{Ptr{UInt8}}, index_lens::Ptr{Csize_t},
        n_index::Csize_t, values_names::Ptr{Ptr{UInt8}}, values_lens::Ptr{Csize_t}, n_values::Csize_t,
        agg::Ptr{polars_expr_t}, maintain_order::Bool, separator::Ptr{UInt8}, separator_len::Csize_t,
        column_naming::polars_pivot_column_naming_t, out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
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

function polars_expr_cast(expr, dtype)
    return @ccall libpolars.polars_expr_cast(expr::Ptr{polars_expr_t}, dtype::polars_value_type_t)::Ptr{polars_expr_t}
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

function polars_expr_quantile(expr, quantile, method)
    return @ccall libpolars.polars_expr_quantile(expr::Ptr{polars_expr_t}, quantile::Ptr{polars_expr_t}, method::polars_quantile_method_t)::Ptr{polars_expr_t}
end

function polars_expr_over(expr, partition_by, n_partition_by, out)
    return @ccall libpolars.polars_expr_over(expr::Ptr{polars_expr_t}, partition_by::Ptr{Ptr{polars_expr_t}}, n_partition_by::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_sort_by(expr, by, n_by, descending, nulls_last, maintain_order)
    return @ccall libpolars.polars_expr_sort_by(expr::Ptr{polars_expr_t}, by::Ptr{Ptr{polars_expr_t}}, n_by::Csize_t, descending::Ptr{Bool}, nulls_last::Bool, maintain_order::Bool)::Ptr{polars_expr_t}
end

function polars_expr_when_then_otherwise(cond, then, otherwise)
    return @ccall libpolars.polars_expr_when_then_otherwise(cond::Ptr{polars_expr_t}, then::Ptr{polars_expr_t}, otherwise::Ptr{polars_expr_t})::Ptr{polars_expr_t}
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

function polars_expr_sqrt(expr)
    return @ccall libpolars.polars_expr_sqrt(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_sign(expr)
    return @ccall libpolars.polars_expr_sign(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_exp(expr)
    return @ccall libpolars.polars_expr_exp(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
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

function polars_expr_round(expr, decimals, mode)
    return @ccall libpolars.polars_expr_round(expr::Ptr{polars_expr_t}, decimals::UInt32, mode::polars_round_mode_t)::Ptr{polars_expr_t}
end

function polars_expr_clip(expr, min, max)
    return @ccall libpolars.polars_expr_clip(expr::Ptr{polars_expr_t}, min::Ptr{polars_expr_t}, max::Ptr{polars_expr_t})::Ptr{polars_expr_t}
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

function polars_expr_count(expr)
    return @ccall libpolars.polars_expr_count(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_first(expr)
    return @ccall libpolars.polars_expr_first(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_last(expr)
    return @ccall libpolars.polars_expr_last(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_not(expr)
    return @ccall libpolars.polars_expr_not(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
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

function polars_expr_flatten(expr)
    return @ccall libpolars.polars_expr_flatten(expr::Ptr{polars_expr_t})::Ptr{polars_expr_t}
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

function polars_expr_fill_null(a, b)
    return @ccall libpolars.polars_expr_fill_null(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_fill_nan(a, b)
    return @ccall libpolars.polars_expr_fill_nan(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
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

function polars_expr_list_first(a)
    return @ccall libpolars.polars_expr_list_first(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_last(a)
    return @ccall libpolars.polars_expr_list_last(a::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_list_get(a, index, null_on_oob)
    return @ccall libpolars.polars_expr_list_get(a::Ptr{polars_expr_t}, index::Ptr{polars_expr_t}, null_on_oob::Bool)::Ptr{polars_expr_t}
end

function polars_expr_list_head(a, b)
    return @ccall libpolars.polars_expr_list_head(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
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

function polars_expr_str_contains(a, pat, strict)
    return @ccall libpolars.polars_expr_str_contains(a::Ptr{polars_expr_t}, pat::Ptr{polars_expr_t}, strict::Bool)::Ptr{polars_expr_t}
end

function polars_expr_str_slice(a, offset, length)
    return @ccall libpolars.polars_expr_str_slice(a::Ptr{polars_expr_t}, offset::Ptr{polars_expr_t}, length::Ptr{polars_expr_t})::Ptr{polars_expr_t}
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

function polars_expr_dt_truncate(a, b)
    return @ccall libpolars.polars_expr_dt_truncate(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_round(a, b)
    return @ccall libpolars.polars_expr_dt_round(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_offset_by(a, b)
    return @ccall libpolars.polars_expr_dt_offset_by(a::Ptr{polars_expr_t}, b::Ptr{polars_expr_t})::Ptr{polars_expr_t}
end

function polars_expr_dt_convert_time_zone(expr, tz, tz_len, out)
    return @ccall libpolars.polars_expr_dt_convert_time_zone(expr::Ptr{polars_expr_t}, tz::Ptr{UInt8}, tz_len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_dt_replace_time_zone(expr, tz, tz_len, ambiguous, non_existent, out)
    return @ccall libpolars.polars_expr_dt_replace_time_zone(expr::Ptr{polars_expr_t}, tz::Ptr{UInt8}, tz_len::Csize_t, ambiguous::Ptr{polars_expr_t}, non_existent::polars_non_existent_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_dt_strftime(expr, format, len, out)
    return @ccall libpolars.polars_expr_dt_strftime(expr::Ptr{polars_expr_t}, format::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_expr_t}})::Ptr{polars_error_t}
end

function polars_expr_struct_field_by_name(a, name, len)
    return @ccall libpolars.polars_expr_struct_field_by_name(a::Ptr{polars_expr_t}, name::Ptr{UInt8}, len::Csize_t)::Ptr{polars_expr_t}
end

function polars_expr_struct_field_by_index(a, fieldidx)
    return @ccall libpolars.polars_expr_struct_field_by_index(a::Ptr{polars_expr_t}, fieldidx::Int64)::Ptr{polars_expr_t}
end

function polars_expr_struct_rename_fields(a, names, lens, num_names)
    return @ccall libpolars.polars_expr_struct_rename_fields(a::Ptr{polars_expr_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, num_names::Csize_t)::Ptr{polars_expr_t}
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

function polars_series_schema(series)
    return @ccall libpolars.polars_series_schema(series::Ptr{polars_series_t})::ArrowSchema
end

"""
    polars_series_is_null(series, index)

Returns whether or not the value at index `index` is null, return false if the index is out of bounds.
"""
function polars_series_is_null(series, index)
    return @ccall libpolars.polars_series_is_null(series::Ptr{polars_series_t}, index::Csize_t)::Bool
end

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

function polars_value_binary_get(value, user, callback)
    return @ccall libpolars.polars_value_binary_get(value::Ptr{polars_value_t}, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

"""
    polars_value_struct_get(value, fieldidx, out)

Used to get value of of a Struct value fields.

NOTE: The value producing the new value must outlive the value from the field.

Safety: Values lifetimes must be valid and only support physical dtypes for now.
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

end # module
