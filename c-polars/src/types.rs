use polars::prelude::*;
use polars_core::frame::PivotColumnNaming;
use polars_utils::compression::ZstdLevel;

// TODO: investigate what the lifetime implies.
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

pub(crate) fn make_dataframe(df: DataFrame) -> *mut polars_dataframe_t {
    Box::into_raw(Box::new(polars_dataframe_t { inner: df }))
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
pub enum PolarsEngine {
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
