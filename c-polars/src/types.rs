use polars::prelude::*;
use polars_core::frame::PivotColumnNaming;
use polars_core::utils::arrow::ffi::{ArrowArray, ArrowSchema};
use polars_utils::compression::ZstdLevel;

/// Pins the memory layout of the two Arrow C Data Interface structs that cross this boundary.
///
/// Unlike every other type here, `ArrowSchema`/`ArrowArray` are **not** ours -- they come from
/// polars-arrow, and the Rust side always uses polars-arrow's own definitions. Two hand-maintained
/// mirrors describe them to everyone downstream:
///
/// - `c-polars/include/arrow.h` -- the C declarations cbindgen's output `#include`s.
/// - the `ArrowSchema`/`ArrowArray` mirrors in `src/api/generated.jl` -- what Julia `unsafe_load`s.
///
/// Neither is checked against polars-arrow by anything else: `check_header_drift.py` matches
/// *function* symbols only, so it is structurally blind to struct layout, and the Rust side stays
/// self-consistent no matter what polars-arrow does. A layout change upstream would therefore
/// compile cleanly and silently corrupt memory at the FFI boundary. These assertions turn that
/// into a build failure.
///
/// Both structs are all-pointer-width fields on a 64-bit target, so the expected sizes fall
/// straight out of the field counts in `arrow.h`: `ArrowSchema` has 9 fields (72 bytes),
/// `ArrowArray` has 10 (80 bytes).
///
/// `size_of`/`align_of` need no field access, so this compiles regardless of whether polars-arrow
/// exposes the fields. That catches any field added, removed, or changed width. It does not catch
/// a pure reordering at constant size -- `check_header_drift.py --arrow` covers ordering across
/// the two mirrors, and `offset_of!` assertions could close it here too if polars-arrow's fields
/// are public.
const _: () = {
    assert!(std::mem::size_of::<ArrowSchema>() == 72);
    assert!(std::mem::align_of::<ArrowSchema>() == 8);
    assert!(std::mem::size_of::<ArrowArray>() == 80);
    assert!(std::mem::align_of::<ArrowArray>() == 8);
};

/// Owns its data: `make_value` calls `AnyValue::into_static` on the way in, so a value never
/// borrows from the `Series` (or parent `polars_value_t`) it came from. It can therefore outlive
/// its source and be destroyed in any order relative to it.
///
/// A borrowed `AnyValue<'a>` would be the cheaper representation, but the lifetime cannot survive
/// the C boundary: `polars_series_get`'s `'a` would be chosen by the caller and inferred as
/// `'static`, so the compiler would check nothing and the "keep the parent alive" rule would rest
/// entirely on the Julia side rooting correctly -- with silent memory corruption as the failure
/// mode. Owning the data deletes the rule instead of documenting it.
///
/// Note `into_static` also *normalizes the variant*: `Struct` becomes `StructOwned`, `Datetime`
/// becomes `DatetimeOwned`, `String`/`Binary` become their `*Owned` forms. Accessors in `value.rs`
/// match the owned variants accordingly.
pub struct polars_value_t {
    pub(crate) inner: AnyValue<'static>,
}

pub struct polars_dataframe_t {
    pub(crate) inner: DataFrame,
}

pub struct polars_lazy_frame_t {
    pub(crate) inner: LazyFrame,
}

pub struct polars_lazy_group_by_t {
    pub(crate) inner: LazyGroupBy,
}

pub struct polars_series_t {
    pub(crate) inner: Series,
}

pub struct polars_expr_t {
    pub(crate) inner: Expr,
}

/// Holds unparsed cloud storage key/value option pairs (e.g. `aws_access_key_id`); resolved into
/// real cloud options once the destination path (and so its cloud scheme) is known.
pub struct polars_cloud_options_t {
    pub(crate) pairs: Vec<(PlSmallStr, PlSmallStr)>,
}

/// Every opaque handle that crosses the C ABI (`polars_dataframe_t`, `polars_expr_t`,
/// `polars_error_t`, ...). Implementing it is the *only* way a handle should be allocated or
/// reclaimed, so the two contracts that govern every one of them live in exactly one place:
///
/// - **Allocator.** `into_handle` allocates with Rust's global allocator, so a handle must be
///   freed by its matching `polars_*_destroy` and *never* by C `free()`. The two are not
///   interchangeable and mixing them is undefined behavior.
/// - **Null.** `destroy` treats null as a no-op, matching C's `free(NULL)`. It is deliberately
///   *not* an `assert!`: a failed assertion panics, and a panic crossing `extern "C"` aborts the
///   host process (none of the destructors runs inside `guard_error`), so asserting here turned a
///   harmless `destroy(NULL)` into a hard crash of the embedding runtime.
///
/// Note this makes `destroy(NULL)` safe, *not* double-`destroy`: reclaiming the same non-null
/// pointer twice is still a double free. Only the caller can rule that out (the Julia side does,
/// via one finalizer per handle).
pub(crate) trait Opaque: Sized {
    /// Allocates `self` on the heap and transfers ownership to the caller across the C ABI.
    fn into_handle(self) -> *mut Self {
        Box::into_raw(Box::new(self))
    }

    /// Reclaims a handle produced by [`Opaque::into_handle`]. Null is a no-op.
    ///
    /// # Safety
    /// If non-null, `ptr` must have come from `into_handle` on this same type and must not have
    /// been destroyed already.
    unsafe fn destroy(ptr: *mut Self) {
        if !ptr.is_null() {
            drop(Box::from_raw(ptr));
        }
    }
}

impl Opaque for polars_value_t {}
impl Opaque for polars_dataframe_t {}
impl Opaque for polars_lazy_frame_t {}
impl Opaque for polars_lazy_group_by_t {}
impl Opaque for polars_series_t {}
impl Opaque for polars_expr_t {}
impl Opaque for polars_cloud_options_t {}

pub(crate) fn make_dataframe(df: DataFrame) -> *mut polars_dataframe_t {
    polars_dataframe_t { inner: df }.into_handle()
}

pub(crate) fn make_lazy_frame(lf: LazyFrame) -> *mut polars_lazy_frame_t {
    polars_lazy_frame_t { inner: lf }.into_handle()
}

pub(crate) fn make_lazy_group_by(gb: LazyGroupBy) -> *mut polars_lazy_group_by_t {
    polars_lazy_group_by_t { inner: gb }.into_handle()
}

/// Counterpart to `make_dataframe`/`make_series`/... for `polars_value_t`, which is built at two
/// call sites (`polars_series_get`, `polars_value_struct_get`).
///
/// `into_static` is what makes the handle self-contained -- see the type's own docs. For a struct
/// value it materializes every field once here, which also makes per-field access O(1) rather than
/// a fresh walk of the field list per call.
pub(crate) fn make_value(value: AnyValue<'_>) -> *mut polars_value_t {
    polars_value_t {
        inner: value.into_static(),
    }
    .into_handle()
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
    pub(crate) fn to_external_compression(&self, level: Option<u32>) -> ExternalCompression {
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
    pub(crate) fn to_ipc_compression(
        &self,
        level: Option<i32>,
    ) -> PolarsResult<Option<IpcCompression>> {
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
    pub(crate) fn to_quote_style(&self) -> QuoteStyle {
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

#[repr(C)]
#[allow(dead_code)]
pub enum polars_parquet_parallel_strategy_t {
    PolarsParquetParallelAuto,
    PolarsParquetParallelNone,
    PolarsParquetParallelColumns,
    PolarsParquetParallelRowGroups,
}

impl polars_parquet_parallel_strategy_t {
    pub(crate) fn to_parallel_strategy(&self) -> ParallelStrategy {
        match self {
            Self::PolarsParquetParallelAuto => ParallelStrategy::Auto,
            Self::PolarsParquetParallelNone => ParallelStrategy::None,
            Self::PolarsParquetParallelColumns => ParallelStrategy::Columns,
            Self::PolarsParquetParallelRowGroups => ParallelStrategy::RowGroups,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_engine_t {
    PolarsEngineInMemory,
    PolarsEngineStreaming,
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
    pub(crate) fn to_join_type(&self) -> JoinType {
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

#[repr(C)]
#[allow(dead_code)]
pub enum polars_asof_strategy_t {
    PolarsAsofStrategyBackward,
    PolarsAsofStrategyForward,
    PolarsAsofStrategyNearest,
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_join_coalesce_t {
    PolarsJoinCoalesceJoinSpecific,
    PolarsJoinCoalesceCoalesceColumns,
    PolarsJoinCoalesceKeepColumns,
}

impl polars_join_coalesce_t {
    pub(crate) fn to_join_coalesce(&self) -> JoinCoalesce {
        match self {
            polars_join_coalesce_t::PolarsJoinCoalesceJoinSpecific => JoinCoalesce::JoinSpecific,
            polars_join_coalesce_t::PolarsJoinCoalesceCoalesceColumns => {
                JoinCoalesce::CoalesceColumns
            }
            polars_join_coalesce_t::PolarsJoinCoalesceKeepColumns => JoinCoalesce::KeepColumns,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_join_validation_t {
    PolarsJoinValidationManyToMany,
    PolarsJoinValidationManyToOne,
    PolarsJoinValidationOneToMany,
    PolarsJoinValidationOneToOne,
}

impl polars_join_validation_t {
    pub(crate) fn to_join_validation(&self) -> JoinValidation {
        match self {
            polars_join_validation_t::PolarsJoinValidationManyToMany => JoinValidation::ManyToMany,
            polars_join_validation_t::PolarsJoinValidationManyToOne => JoinValidation::ManyToOne,
            polars_join_validation_t::PolarsJoinValidationOneToMany => JoinValidation::OneToMany,
            polars_join_validation_t::PolarsJoinValidationOneToOne => JoinValidation::OneToOne,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_maintain_order_join_t {
    PolarsMaintainOrderJoinNone,
    PolarsMaintainOrderJoinLeft,
    PolarsMaintainOrderJoinRight,
    PolarsMaintainOrderJoinLeftRight,
    PolarsMaintainOrderJoinRightLeft,
}

impl polars_maintain_order_join_t {
    pub(crate) fn to_maintain_order_join(&self) -> MaintainOrderJoin {
        match self {
            polars_maintain_order_join_t::PolarsMaintainOrderJoinNone => MaintainOrderJoin::None,
            polars_maintain_order_join_t::PolarsMaintainOrderJoinLeft => MaintainOrderJoin::Left,
            polars_maintain_order_join_t::PolarsMaintainOrderJoinRight => MaintainOrderJoin::Right,
            polars_maintain_order_join_t::PolarsMaintainOrderJoinLeftRight => {
                MaintainOrderJoin::LeftRight
            }
            polars_maintain_order_join_t::PolarsMaintainOrderJoinRightLeft => {
                MaintainOrderJoin::RightLeft
            }
        }
    }
}

impl polars_asof_strategy_t {
    pub(crate) fn to_asof_strategy(&self) -> AsofStrategy {
        match self {
            polars_asof_strategy_t::PolarsAsofStrategyBackward => AsofStrategy::Backward,
            polars_asof_strategy_t::PolarsAsofStrategyForward => AsofStrategy::Forward,
            polars_asof_strategy_t::PolarsAsofStrategyNearest => AsofStrategy::Nearest,
        }
    }
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
    pub(crate) fn to_keep_strategy(&self) -> UniqueKeepStrategy {
        match self {
            polars_unique_keep_t::PolarsUniqueKeepFirst => UniqueKeepStrategy::First,
            polars_unique_keep_t::PolarsUniqueKeepLast => UniqueKeepStrategy::Last,
            polars_unique_keep_t::PolarsUniqueKeepNone => UniqueKeepStrategy::None,
            polars_unique_keep_t::PolarsUniqueKeepAny => UniqueKeepStrategy::Any,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_pivot_column_naming_t {
    PolarsPivotColumnNamingCombine,
    PolarsPivotColumnNamingAuto,
}

impl polars_pivot_column_naming_t {
    pub(crate) fn to_pivot_column_naming(&self) -> PivotColumnNaming {
        match self {
            Self::PolarsPivotColumnNamingCombine => PivotColumnNaming::Combine,
            Self::PolarsPivotColumnNamingAuto => PivotColumnNaming::Auto,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_fill_null_strategy_t {
    PolarsFillNullStrategyBackward,
    PolarsFillNullStrategyForward,
    PolarsFillNullStrategyMean,
    PolarsFillNullStrategyMin,
    PolarsFillNullStrategyMax,
    PolarsFillNullStrategyZero,
    PolarsFillNullStrategyOne,
}

impl polars_fill_null_strategy_t {
    /// `limit` only applies to `Backward`/`Forward` -- ignored for the other variants, matching
    /// `FillNullStrategy`'s own shape (only those two carry a `FillNullLimit = Option<IdxSize>`).
    pub(crate) fn to_fill_null_strategy(&self, limit: Option<IdxSize>) -> FillNullStrategy {
        match self {
            Self::PolarsFillNullStrategyBackward => FillNullStrategy::Backward(limit),
            Self::PolarsFillNullStrategyForward => FillNullStrategy::Forward(limit),
            Self::PolarsFillNullStrategyMean => FillNullStrategy::Mean,
            Self::PolarsFillNullStrategyMin => FillNullStrategy::Min,
            Self::PolarsFillNullStrategyMax => FillNullStrategy::Max,
            Self::PolarsFillNullStrategyZero => FillNullStrategy::Zero,
            Self::PolarsFillNullStrategyOne => FillNullStrategy::One,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_concat_how_t {
    PolarsConcatHowVertical,
    PolarsConcatHowVerticalRelaxed,
    PolarsConcatHowDiagonal,
    PolarsConcatHowDiagonalRelaxed,
    PolarsConcatHowHorizontal,
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_window_mapping_t {
    PolarsWindowMappingGroupsToRows,
    PolarsWindowMappingExplode,
    PolarsWindowMappingJoin,
}

impl polars_window_mapping_t {
    pub(crate) fn to_window_mapping(&self) -> WindowMapping {
        match self {
            Self::PolarsWindowMappingGroupsToRows => WindowMapping::GroupsToRows,
            Self::PolarsWindowMappingExplode => WindowMapping::Explode,
            Self::PolarsWindowMappingJoin => WindowMapping::Join,
        }
    }
}

/// C-compatible mirror of polars_plan::dsl::CastColumnsPolicy
/// Controls how type mismatches are handled when reading parquet files with schema overrides.
#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct polars_cast_columns_policy_t {
    pub integer_upcast: bool,
    pub integer_to_float_cast: bool,
    pub float_upcast: bool,
    pub float_downcast: bool,
    pub datetime_nanoseconds_downcast: bool,
    pub datetime_microseconds_downcast: bool,
    pub datetime_milliseconds_upcast: bool,
    pub datetime_microseconds_upcast: bool,
    pub datetime_convert_timezone: bool,
    pub null_upcast: bool,
    pub categorical_to_string: bool,
    pub missing_struct_fields_raise: bool, // true = Raise, false = Insert
    pub extra_struct_fields_raise: bool,   // true = Raise, false = Ignore
}

impl Default for polars_cast_columns_policy_t {
    fn default() -> Self {
        // ERROR_ON_MISMATCH configuration from upstream
        Self {
            integer_upcast: false,
            integer_to_float_cast: false,
            float_upcast: false,
            float_downcast: false,
            datetime_nanoseconds_downcast: false,
            datetime_microseconds_downcast: false,
            datetime_milliseconds_upcast: false,
            datetime_microseconds_upcast: false,
            datetime_convert_timezone: false,
            null_upcast: true,
            categorical_to_string: false,
            missing_struct_fields_raise: true,
            extra_struct_fields_raise: true,
        }
    }
}

impl polars_cast_columns_policy_t {
    /// Convert to Rust CastColumnsPolicy for use in scan operations
    pub(crate) fn to_cast_columns_policy(self) -> polars_plan::dsl::CastColumnsPolicy {
        use polars_plan::dsl::{CastColumnsPolicy, ExtraColumnsPolicy, MissingColumnsPolicy};

        CastColumnsPolicy {
            integer_upcast: self.integer_upcast,
            integer_to_float_cast: self.integer_to_float_cast,
            float_upcast: self.float_upcast,
            float_downcast: self.float_downcast,
            datetime_nanoseconds_downcast: self.datetime_nanoseconds_downcast,
            datetime_microseconds_downcast: self.datetime_microseconds_downcast,
            datetime_milliseconds_upcast: self.datetime_milliseconds_upcast,
            datetime_microseconds_upcast: self.datetime_microseconds_upcast,
            datetime_convert_timezone: self.datetime_convert_timezone,
            null_upcast: self.null_upcast,
            categorical_to_string: self.categorical_to_string,
            missing_struct_fields: if self.missing_struct_fields_raise {
                MissingColumnsPolicy::Raise
            } else {
                MissingColumnsPolicy::Insert
            },
            extra_struct_fields: if self.extra_struct_fields_raise {
                ExtraColumnsPolicy::Raise
            } else {
                ExtraColumnsPolicy::Ignore
            },
        }
    }
}
