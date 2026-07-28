use polars::prelude::*;
use polars_core::frame::PivotColumnNaming;
use polars_utils::compression::ZstdLevel;

/// Borrows from its parent (a `Series`, or another `polars_value_t` for struct-field access via
/// `polars_value_struct_get`) rather than owning its data. The lifetime parameter enforces
/// nothing across the C boundary -- it is a caller invariant, not a compiler-checked one: the
/// caller must keep the parent alive for as long as this value is alive, and must destroy this
/// value before the parent. The Julia side roots the parent via `Value.parent` (`src/value.jl`).
/// See `polars_value_struct_get`'s `# Safety` doc for the struct-field case specifically.
pub struct polars_value_t<'a> {
    pub(crate) inner: AnyValue<'a>,
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

/// Deviates from every other opaque handle in this crate, which wrap a real polars type: this one
/// wraps the *unparsed* key/value option pairs, because `CloudOptions` cannot be constructed
/// without knowing the target cloud scheme (`CloudScheme::from_path`), and the scheme is only
/// known once the destination path is available -- i.e. at each scan/sink call site, not here.
/// Resolution therefore happens per call (see `polars_lazy_frame_scan_parquet` etc.).
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

impl Opaque for polars_value_t<'_> {}
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

/// Counterpart to `make_dataframe`/`make_series`/... for the one handle that had no factory --
/// `polars_value_t` was constructed inline at its two call sites (`polars_series_get`,
/// `polars_value_struct_get`). See the type's own docs for the borrow contract it carries.
pub(crate) fn make_value(value: AnyValue<'_>) -> *mut polars_value_t<'_> {
    polars_value_t { inner: value }.into_handle()
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
