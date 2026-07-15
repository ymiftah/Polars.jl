using libpolars_jll
export libpolars_jll

using CEnum: CEnum, @cenum

const libpolars_local_dir = joinpath(@__DIR__, "../../c-polars/target/debug/")
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

const ARROW_FLAG_DICTIONARY_ORDERED = 1

const ARROW_FLAG_NULLABLE = 2

const ARROW_FLAG_MAP_KEYS_SORTED = 4
