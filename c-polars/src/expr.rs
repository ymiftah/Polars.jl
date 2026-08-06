use std::ffi::c_void;
use std::io::Write;
use std::ops::Neg;
use std::sync::Arc;

use polars::{lazy::dsl::string::StringNameSpace, lazy::dsl::ListNameSpace, prelude::*};
use polars_compute::ewm::EWMOptions;
use polars_core::series::ops::NullBehavior;
use polars_ops::series::round::RoundMode;
use polars_ops::series::InterpolationMethod;
use polars_plan::dsl::dt::DateLikeNameSpace;
use polars_plan::dsl::functions::{
    all_horizontal, any_horizontal, as_struct, coalesce, cov, max_horizontal, mean_horizontal,
    min_horizontal, pearson_corr, spearman_rank_corr, sum_horizontal,
};
use polars_plan::dsl::DataTypeExpr;
use polars_plan::prelude::Literal;

use crate::{
    ffi_util::{
        read_bool_mask, read_exprs, read_f64_array, read_i64_array, read_names, read_opt_str,
        read_str, selector_by_name, IOCallback, UserIOCallback,
    },
    guard_error, make_error, polars_error_t,
    types::*,
    value::{polars_time_unit_t, polars_value_type_t},
};

fn make_expr(expr: Expr) -> *const polars_expr_t {
    polars_expr_t { inner: expr }.into_handle().cast_const()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_destroy(expr: *const polars_expr_t) {
    Opaque::destroy(expr.cast_mut());
}

macro_rules! gen_literal_get {
    ($n: ident, $t: ident, $v: ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(value: $v) -> *const polars_expr_t {
            make_expr(Expr::Literal(LiteralValue::Scalar(Scalar::new(
                DataType::$t,
                value.into(),
            ))))
        }
    };
}

gen_literal_get!(polars_expr_literal_bool, Boolean, bool);
gen_literal_get!(polars_expr_literal_i32, Int32, i32);
gen_literal_get!(polars_expr_literal_i64, Int64, i64);
gen_literal_get!(polars_expr_literal_u32, UInt32, u32);
gen_literal_get!(polars_expr_literal_u64, UInt64, u64);
gen_literal_get!(polars_expr_literal_f32, Float32, f32);
gen_literal_get!(polars_expr_literal_f64, Float64, f64);

#[no_mangle]
pub unsafe extern "C" fn polars_expr_literal_null() -> *const polars_expr_t {
    make_expr(Expr::Literal(LiteralValue::untyped_null()))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_lit_series(
    series: *const polars_series_t,
) -> *const polars_expr_t {
    let series = (*series).inner.clone();
    make_expr(series.lit())
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_literal_utf8(
    s: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let value = tri!(read_str(s, len));
        *out = make_expr(Expr::Literal(LiteralValue::Scalar(Scalar::new(
            DataType::String,
            AnyValue::StringOwned(PlSmallStr::from_str(value)),
        ))));
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_col(
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let name = tri!(read_str(name, len));
        let expr = col(name);
        *out = make_expr(expr);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_nth(
    n: i64,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        *out = make_expr(Expr::Selector(nth(n)));
        std::ptr::null()
    })
}

/// A placeholder for "the values in this group", used to build the `agg` expression passed to
/// `pivot` (e.g. `element().sum()`) -- substituted in-place with the actual value column filtered
/// to the current group at plan-build time.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_element() -> *const polars_expr_t {
    make_expr(element())
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_coalesce(
    exprs: *const *const polars_expr_t,
    n: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        if n == 0 {
            return make_error("coalesce requires at least one expression");
        }
        let exprs = read_exprs(exprs, n);
        *out = make_expr(coalesce(&exprs));
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_as_struct(
    exprs: *const *const polars_expr_t,
    n: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        if n == 0 {
            return make_error("as_struct requires at least one field");
        }
        let exprs = read_exprs(exprs, n);
        *out = make_expr(as_struct(exprs));
        std::ptr::null()
    })
}

/// `all/any/min/max_horizontal`: fallible reductions over a `Vec<Expr>` with no extra options.
macro_rules! gen_horizontal {
    ($n:ident, $f:path) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            exprs: *const *const polars_expr_t,
            n: usize,
            out: *mut *const polars_expr_t,
        ) -> *const polars_error_t {
            guard_error(|| {
                let exprs = read_exprs(exprs, n);
                match $f(&exprs) {
                    Ok(result) => {
                        *out = make_expr(result);
                        std::ptr::null()
                    }
                    Err(err) => make_error(err),
                }
            })
        }
    };
}

/// `sum/mean_horizontal`: same, but carrying the extra `ignore_nulls` flag.
macro_rules! gen_horizontal_ignore_nulls {
    ($n:ident, $f:path) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            exprs: *const *const polars_expr_t,
            n: usize,
            ignore_nulls: bool,
            out: *mut *const polars_expr_t,
        ) -> *const polars_error_t {
            guard_error(|| {
                let exprs = read_exprs(exprs, n);
                match $f(&exprs, ignore_nulls) {
                    Ok(result) => {
                        *out = make_expr(result);
                        std::ptr::null()
                    }
                    Err(err) => make_error(err),
                }
            })
        }
    };
}

gen_horizontal!(polars_expr_all_horizontal, all_horizontal);
gen_horizontal!(polars_expr_any_horizontal, any_horizontal);
gen_horizontal!(polars_expr_min_horizontal, min_horizontal);
gen_horizontal!(polars_expr_max_horizontal, max_horizontal);
gen_horizontal_ignore_nulls!(polars_expr_sum_horizontal, sum_horizontal);
gen_horizontal_ignore_nulls!(polars_expr_mean_horizontal, mean_horizontal);

#[repr(C)]
#[allow(dead_code)]
pub enum polars_interpolation_method_t {
    PolarsInterpolationMethodLinear,
    PolarsInterpolationMethodNearest,
}

impl polars_interpolation_method_t {
    fn to_interpolation_method(&self) -> InterpolationMethod {
        match self {
            Self::PolarsInterpolationMethodLinear => InterpolationMethod::Linear,
            Self::PolarsInterpolationMethodNearest => InterpolationMethod::Nearest,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_interpolate(
    expr: *const polars_expr_t,
    method: polars_interpolation_method_t,
) -> *const polars_expr_t {
    make_expr(
        (*expr)
            .inner
            .clone()
            .interpolate(method.to_interpolation_method()),
    )
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_alias(
    expr: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let name = tri!(read_str(name, len));
        let aliased = (*expr).inner.clone().alias(name);
        *out = make_expr(aliased);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_prefix(
    expr: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let name = tri!(read_str(name, len));
        let aliased = (*expr).inner.clone().name().prefix(name);
        *out = make_expr(aliased);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_suffix(
    expr: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let name = tri!(read_str(name, len));
        let aliased = (*expr).inner.clone().name().suffix(name);
        *out = make_expr(aliased);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_keep_name(expr: *const polars_expr_t) -> *const polars_expr_t {
    let aliased = (*expr).inner.clone().name().keep();
    make_expr(aliased)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_to_lowercase(
    expr: *const polars_expr_t,
) -> *const polars_expr_t {
    let aliased = (*expr).inner.clone().name().to_lowercase();
    make_expr(aliased)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_to_uppercase(
    expr: *const polars_expr_t,
) -> *const polars_expr_t {
    let aliased = (*expr).inner.clone().name().to_uppercase();
    make_expr(aliased)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_cast(
    expr: *const polars_expr_t,
    dtype: polars_value_type_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        // Fallible since `to_dtype` rejects type codes it cannot encode, rather than silently
        // producing a cast to `Unknown` (see `polars_value_type_t::to_dtype`).
        let dtype = tri!(dtype.to_dtype());
        *out = make_expr(cast((*expr).inner.clone(), dtype));
        std::ptr::null()
    })
}

/// Strict cast: raises on overflow/loss instead of `polars_expr_cast`'s non-strict "overflow
/// becomes null" behavior. The two modes are separate functions rather than one function with a
/// mode flag, mirroring upstream's own `Expr::strict_cast`/`Expr::cast` split (note upstream's
/// *Python* `Expr.cast(dtype, strict=True)` defaults to the strict branch, so `cast` here is the
/// non-default one).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_strict_cast(
    expr: *const polars_expr_t,
    dtype: polars_value_type_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let dtype = tri!(dtype.to_dtype());
        *out = make_expr((*expr).inner.clone().strict_cast(dtype));
        std::ptr::null()
    })
}

/// Casts to `Datetime(unit, tz)`. `tz_len == 0` casts to a naive (timezone-less) Datetime.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_cast_datetime(
    expr: *const polars_expr_t,
    unit: polars_time_unit_t,
    tz: *const u8,
    tz_len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let unit = tri!(unit.to_time_unit());
        let tz = tri!(read_opt_str(tz, tz_len));
        let time_zone = tri!(TimeZone::opt_try_new(tz));
        let dtype = DataType::Datetime(unit, time_zone);
        *out = make_expr(cast((*expr).inner.clone(), dtype));
        std::ptr::null()
    })
}

/// Casts to `Duration(unit)`.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_cast_duration(
    expr: *const polars_expr_t,
    unit: polars_time_unit_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let unit = tri!(unit.to_time_unit());
        let dtype = DataType::Duration(unit);
        *out = make_expr(cast((*expr).inner.clone(), dtype));
        std::ptr::null()
    })
}

/// Targeted cast to `Decimal(precision, scale)` (`dtype-decimal` is already enabled). polars'
/// own invariant is `1 <= precision <= 38`; violating it surfaces as a normal cast error rather
/// than a panic (`DataType::Decimal` itself does not validate -- `cast` does, at execution time).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_cast_decimal(
    expr: *const polars_expr_t,
    precision: usize,
    scale: usize,
) -> *const polars_expr_t {
    let dtype = DataType::Decimal(precision, scale);
    make_expr(cast((*expr).inner.clone(), dtype))
}

/// Casts to `Categorical`, using the global category registry shared by every Categorical column
/// in the session.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_cast_categorical(
    expr: *const polars_expr_t,
) -> *const polars_expr_t {
    let dtype = DataType::from_categories(Categories::global());
    make_expr(cast((*expr).inner.clone(), dtype))
}

macro_rules! gen_impl_expr {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(expr: *const polars_expr_t) -> *const polars_expr_t {
            let expr = &(*expr).inner;
            let out_expr = $t(expr.clone());
            make_expr(out_expr)
        }
    };
}

gen_impl_expr!(polars_expr_sum, Expr::sum);
gen_impl_expr!(polars_expr_product, Expr::product);
gen_impl_expr!(polars_expr_mean, Expr::mean);
gen_impl_expr!(polars_expr_median, Expr::median);
gen_impl_expr!(polars_expr_min, Expr::min);
gen_impl_expr!(polars_expr_max, Expr::max);
gen_impl_expr!(polars_expr_arg_min, Expr::arg_min);
gen_impl_expr!(polars_expr_arg_max, Expr::arg_max);
gen_impl_expr!(polars_expr_nan_min, Expr::nan_min);
gen_impl_expr!(polars_expr_nan_max, Expr::nan_max);

#[no_mangle]
pub unsafe extern "C" fn polars_expr_std(
    expr: *const polars_expr_t,
    ddof: u8,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    make_expr(expr.std(ddof))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_var(
    expr: *const polars_expr_t,
    ddof: u8,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    make_expr(expr.var(ddof))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_cov(
    a: *const polars_expr_t,
    b: *const polars_expr_t,
    ddof: u8,
) -> *const polars_expr_t {
    let a = (*a).inner.clone();
    let b = (*b).inner.clone();
    make_expr(cov(a, b, ddof))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_pearson_corr(
    a: *const polars_expr_t,
    b: *const polars_expr_t,
) -> *const polars_expr_t {
    let a = (*a).inner.clone();
    let b = (*b).inner.clone();
    make_expr(pearson_corr(a, b))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_spearman_rank_corr(
    a: *const polars_expr_t,
    b: *const polars_expr_t,
    propagate_nans: bool,
) -> *const polars_expr_t {
    let a = (*a).inner.clone();
    let b = (*b).inner.clone();
    make_expr(spearman_rank_corr(a, b, propagate_nans))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_skew(
    expr: *const polars_expr_t,
    bias: bool,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    make_expr(expr.skew(bias))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_kurtosis(
    expr: *const polars_expr_t,
    fisher: bool,
    bias: bool,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    make_expr(expr.kurtosis(fisher, bias))
}

/// Exponentially-weighted moving average. `alpha` must already be resolved to a concrete decay
/// factor in `(0, 1]` by the caller (the `com`/`span`/`half_life`/`alpha` parameterizations all
/// reduce to this single value client-side).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_ewm_mean(
    expr: *const polars_expr_t,
    alpha: f64,
    adjust: bool,
    min_samples: usize,
    ignore_nulls: bool,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let options = EWMOptions {
        alpha,
        adjust,
        bias: false,
        min_periods: min_samples,
        ignore_nulls,
    };
    make_expr(expr.ewm_mean(options))
}

/// Exponentially-weighted moving standard deviation. See `polars_expr_ewm_mean` for `alpha`.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_ewm_std(
    expr: *const polars_expr_t,
    alpha: f64,
    adjust: bool,
    bias: bool,
    min_samples: usize,
    ignore_nulls: bool,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let options = EWMOptions {
        alpha,
        adjust,
        bias,
        min_periods: min_samples,
        ignore_nulls,
    };
    make_expr(expr.ewm_std(options))
}

/// Exponentially-weighted moving variance. See `polars_expr_ewm_mean` for `alpha`.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_ewm_var(
    expr: *const polars_expr_t,
    alpha: f64,
    adjust: bool,
    bias: bool,
    min_samples: usize,
    ignore_nulls: bool,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let options = EWMOptions {
        alpha,
        adjust,
        bias,
        min_periods: min_samples,
        ignore_nulls,
    };
    make_expr(expr.ewm_var(options))
}

/// Reads an optional label list: `n == 0` means `None` (the caller lets the engine generate
/// interval-string labels), matching the `read_names`-style `(ptrs, lens, n)` convention used
/// elsewhere for plain name lists.
unsafe fn read_opt_labels(
    labels: *const *const u8,
    label_lens: *const usize,
    n_labels: usize,
) -> Result<Option<Vec<PlSmallStr>>, std::str::Utf8Error> {
    if n_labels == 0 {
        Ok(None)
    } else {
        Ok(Some(read_names(labels, label_lens, n_labels)?))
    }
}

/// Bins continuous values into discrete categories given explicit breakpoints. `breaks` is a
/// plain array of cut points (not including the implicit `-inf`/`inf` ends); the result is a
/// labelled Enum column with one more category than there are breaks. `labels`, if given
/// (`n_labels > 0`), must have `breaks.len() + 1` entries; otherwise labels are generated as
/// interval strings, `"(-inf, b] "`/`"(b1, b2]"`/`"(bn, inf]"` (or `[...)"`-style if
/// `left_closed`). Raises if `breaks` contains `NaN`/duplicates/`inf`, or if `labels`' length
/// doesn't match.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_cut(
    expr: *const polars_expr_t,
    breaks: *const f64,
    n_breaks: usize,
    labels: *const *const u8,
    label_lens: *const usize,
    n_labels: usize,
    left_closed: bool,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let expr = (*expr).inner.clone();
        let breaks = read_f64_array(breaks, n_breaks);
        let labels = tri!(read_opt_labels(labels, label_lens, n_labels));
        *out = make_expr(expr.cut(breaks, labels, left_closed, false));
        std::ptr::null()
    })
}

/// Bins continuous values into discrete categories based on their quantiles. `probs` are the
/// quantile cut points in `[0, 1]`; the result is a `Categorical` column. `allow_duplicates`
/// controls whether repeated quantile breakpoints (common with few distinct values) are silently
/// collapsed instead of raising. See `polars_expr_cut` for `labels`/error conditions.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_qcut(
    expr: *const polars_expr_t,
    probs: *const f64,
    n_probs: usize,
    labels: *const *const u8,
    label_lens: *const usize,
    n_labels: usize,
    left_closed: bool,
    allow_duplicates: bool,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let expr = (*expr).inner.clone();
        let probs = read_f64_array(probs, n_probs);
        let labels = tri!(read_opt_labels(labels, label_lens, n_labels));
        *out = make_expr(expr.qcut(probs, labels, left_closed, allow_duplicates, false));
        std::ptr::null()
    })
}

/// Like `polars_expr_qcut`, but with `n_bins` uniformly-spaced quantile probabilities instead of
/// an explicit `probs` array.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_qcut_uniform(
    expr: *const polars_expr_t,
    n_bins: usize,
    labels: *const *const u8,
    label_lens: *const usize,
    n_labels: usize,
    left_closed: bool,
    allow_duplicates: bool,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let expr = (*expr).inner.clone();
        let labels = tri!(read_opt_labels(labels, label_lens, n_labels));
        *out = make_expr(expr.qcut_uniform(n_bins, labels, left_closed, allow_duplicates, false));
        std::ptr::null()
    })
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_closed_interval_t {
    PolarsClosedIntervalBoth,
    PolarsClosedIntervalLeft,
    PolarsClosedIntervalRight,
    PolarsClosedIntervalNone,
}

impl polars_closed_interval_t {
    fn to_closed_interval(&self) -> ClosedInterval {
        match self {
            polars_closed_interval_t::PolarsClosedIntervalBoth => ClosedInterval::Both,
            polars_closed_interval_t::PolarsClosedIntervalLeft => ClosedInterval::Left,
            polars_closed_interval_t::PolarsClosedIntervalRight => ClosedInterval::Right,
            polars_closed_interval_t::PolarsClosedIntervalNone => ClosedInterval::None,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_is_between(
    expr: *const polars_expr_t,
    lower: *const polars_expr_t,
    upper: *const polars_expr_t,
    closed: polars_closed_interval_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let lower = (*lower).inner.clone();
    let upper = (*upper).inner.clone();
    make_expr(expr.is_between(lower, upper, closed.to_closed_interval()))
}

/// Builds the shared fixed-window options for `rolling_mean`/`rolling_sum`/`rolling_min`/
/// `rolling_max`. `rolling_var`/`rolling_std` build their own (see below) to additionally set
/// `fn_params` for `ddof`.
fn read_rolling_options(
    window_size: usize,
    min_periods: usize,
    center: bool,
) -> RollingOptionsFixedWindow {
    RollingOptionsFixedWindow {
        window_size,
        min_periods,
        weights: None,
        center,
        fn_params: None,
    }
}

macro_rules! gen_rolling {
    ($n: ident, $f: ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            expr: *const polars_expr_t,
            window_size: usize,
            min_periods: usize,
            center: bool,
        ) -> *const polars_expr_t {
            let expr = (*expr).inner.clone();
            let options = read_rolling_options(window_size, min_periods, center);
            make_expr(expr.$f(options))
        }
    };
}

gen_rolling!(polars_expr_rolling_mean, rolling_mean);
gen_rolling!(polars_expr_rolling_sum, rolling_sum);
gen_rolling!(polars_expr_rolling_min, rolling_min);
gen_rolling!(polars_expr_rolling_max, rolling_max);

macro_rules! gen_rolling_var {
    ($n: ident, $f: ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            expr: *const polars_expr_t,
            window_size: usize,
            min_periods: usize,
            center: bool,
            ddof: u8,
        ) -> *const polars_expr_t {
            let expr = (*expr).inner.clone();
            let mut options = read_rolling_options(window_size, min_periods, center);
            options.fn_params = Some(RollingFnParams::Var(RollingVarParams { ddof }));
            make_expr(expr.$f(options))
        }
    };
}

gen_rolling_var!(polars_expr_rolling_var, rolling_var);
gen_rolling_var!(polars_expr_rolling_std, rolling_std);

gen_rolling!(polars_expr_rolling_median, rolling_median);

#[repr(C)]
#[allow(dead_code)]
pub enum polars_quantile_method_t {
    PolarsQuantileMethodNearest,
    PolarsQuantileMethodLower,
    PolarsQuantileMethodHigher,
    PolarsQuantileMethodMidpoint,
    PolarsQuantileMethodLinear,
    PolarsQuantileMethodEquiprobable,
}

impl polars_quantile_method_t {
    fn to_quantile_method(&self) -> polars_compute::rolling::QuantileMethod {
        use polars_compute::rolling::QuantileMethod::*;
        match self {
            polars_quantile_method_t::PolarsQuantileMethodNearest => Nearest,
            polars_quantile_method_t::PolarsQuantileMethodLower => Lower,
            polars_quantile_method_t::PolarsQuantileMethodHigher => Higher,
            polars_quantile_method_t::PolarsQuantileMethodMidpoint => Midpoint,
            polars_quantile_method_t::PolarsQuantileMethodLinear => Linear,
            polars_quantile_method_t::PolarsQuantileMethodEquiprobable => Equiprobable,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_rolling_quantile(
    expr: *const polars_expr_t,
    window_size: usize,
    min_periods: usize,
    center: bool,
    quantile: f64,
    method: polars_quantile_method_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let options = read_rolling_options(window_size, min_periods, center);
    make_expr(expr.rolling_quantile(method.to_quantile_method(), quantile, options))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_when_then_otherwise(
    cond: *const polars_expr_t,
    then: *const polars_expr_t,
    otherwise: *const polars_expr_t,
) -> *const polars_expr_t {
    let cond = (*cond).inner.clone();
    let then = (*then).inner.clone();
    let otherwise = (*otherwise).inner.clone();
    make_expr(when(cond).then(then).otherwise(otherwise))
}

/// Chained `when(c1).then(v1).when(c2).then(v2)....otherwise(otherwise)`, given as two parallel
/// expr-slices (`conds`/`vals`) plus a final `otherwise`. `n == 0` returns `otherwise` unchanged.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_when_then(
    conds: *const *const polars_expr_t,
    vals: *const *const polars_expr_t,
    n: usize,
    otherwise: *const polars_expr_t,
) -> *const polars_expr_t {
    let conds = read_exprs(conds, n);
    let vals = read_exprs(vals, n);
    let mut acc = (*otherwise).inner.clone();
    for i in (0..n).rev() {
        acc = when(conds[i].clone()).then(vals[i].clone()).otherwise(acc);
    }
    make_expr(acc)
}

/// `order_by` is a single optional expr (null = none). An empty `partition_by` with a null
/// `order_by` is valid -- the whole frame is treated as one group (see the whole-frame-sentinel
/// substitution below).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_over(
    expr: *const polars_expr_t,
    partition_by: *const *const polars_expr_t,
    n_partition_by: usize,
    order_by: *const polars_expr_t,
    descending: bool,
    nulls_last: bool,
    mapping: polars_window_mapping_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let mut partition_by = read_exprs(partition_by, n_partition_by);
        // An empty partition list is a real, meaningful window spec (the whole frame as one group),
        // but `over_with_options` does not treat `Some(vec![])` that way -- only its own `None` branch
        // substitutes the whole-frame sentinel `vec![lit(1)]` (upstream `dsl/mod.rs`); `Some(vec![])`
        // is passed straight through as zero actual group-by keys, which polars-core's group-by
        // execution then rejects at *run* time ("at least one key is required in a group_by
        // operation") even though building the `Expr` itself succeeds. Passing `None` outright doesn't
        // work either -- `over_with_options`'s own `polars_ensure!` then requires `order_by` to be set.
        // So: replicate upstream's `None`-branch substitution ourselves whenever the caller passed an
        // empty list, keeping `Some(..)` (which upstream's ensure is satisfied by) either way.
        if partition_by.is_empty() {
            partition_by.push(lit(1));
        }
        let partition_by = Some(partition_by);
        let order_by = if order_by.is_null() {
            None
        } else {
            Some((
                vec![(*order_by).inner.clone()],
                SortOptions {
                    descending,
                    nulls_last,
                    ..Default::default()
                },
            ))
        };
        let expr = (*expr).inner.clone();
        let result =
            tri!(expr.over_with_options(partition_by, order_by, mapping.to_window_mapping()));
        *out = make_expr(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_sort_by(
    expr: *const polars_expr_t,
    by: *const *const polars_expr_t,
    n_by: usize,
    descending: *const bool,
    nulls_last: bool,
    maintain_order: bool,
) -> *const polars_expr_t {
    let by = read_exprs(by, n_by);
    let descending = read_bool_mask(descending, n_by);
    let expr = (*expr).inner.clone();
    let result = expr.sort_by(
        by,
        SortMultipleOptions {
            descending,
            nulls_last: std::iter::repeat_n(nulls_last, n_by).collect(),
            maintain_order,
            multithreaded: true,
            limit: None,
        },
    );
    make_expr(result)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_quantile(
    expr: *const polars_expr_t,
    quantile: *const polars_expr_t,
    method: polars_quantile_method_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let quantile = (*quantile).inner.clone();
    make_expr(expr.quantile(quantile, method.to_quantile_method()))
}

gen_impl_expr!(polars_expr_floor, Expr::floor);
gen_impl_expr!(polars_expr_ceil, Expr::ceil);
gen_impl_expr!(polars_expr_abs, Expr::abs);
gen_impl_expr!(polars_expr_cos, Expr::cos);
gen_impl_expr!(polars_expr_sin, Expr::sin);
gen_impl_expr!(polars_expr_tan, Expr::tan);
gen_impl_expr!(polars_expr_cosh, Expr::cosh);
gen_impl_expr!(polars_expr_sinh, Expr::sinh);
gen_impl_expr!(polars_expr_tanh, Expr::tanh);
gen_impl_expr!(polars_expr_arccos, Expr::arccos);
gen_impl_expr!(polars_expr_arcsin, Expr::arcsin);
gen_impl_expr!(polars_expr_arctan, Expr::arctan);
gen_impl_expr!(polars_expr_degrees, Expr::degrees);
gen_impl_expr!(polars_expr_radians, Expr::radians);

gen_impl_expr!(polars_expr_sqrt, Expr::sqrt);
gen_impl_expr!(polars_expr_sign, Expr::sign);
gen_impl_expr!(polars_expr_exp, Expr::exp);
gen_impl_expr!(polars_expr_log1p, Expr::log1p);

gen_impl_expr!(polars_expr_rle, Expr::rle);
gen_impl_expr!(polars_expr_rle_id, Expr::rle_id);

#[repr(C)]
#[allow(dead_code)]
pub enum polars_round_mode_t {
    PolarsRoundModeHalfToEven,
    PolarsRoundModeHalfAwayFromZero,
    PolarsRoundModeToZero,
}

impl polars_round_mode_t {
    fn to_round_mode(&self) -> RoundMode {
        match self {
            polars_round_mode_t::PolarsRoundModeHalfToEven => RoundMode::HalfToEven,
            polars_round_mode_t::PolarsRoundModeHalfAwayFromZero => RoundMode::HalfAwayFromZero,
            polars_round_mode_t::PolarsRoundModeToZero => RoundMode::ToZero,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_round(
    expr: *const polars_expr_t,
    decimals: u32,
    mode: polars_round_mode_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    make_expr(expr.round(decimals, mode.to_round_mode()))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_clip(
    expr: *const polars_expr_t,
    min: *const polars_expr_t,
    max: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let min = (*min).inner.clone();
    let max = (*max).inner.clone();
    make_expr(expr.clip(min, max))
}

// Unary negation (`-expr`). Not reachable by composing `0 .- expr` from the existing binary
// `sub` -- that silently wraps on an unsigned column (e.g. `UInt8` `0-1` -> `255`) where
// `Expr::neg` (via `FunctionExpr::Negate`) has its own per-dtype validation and correctly raises
// instead (upstream `test_neg_unsigned_int`, live-verified both directions before writing this).
gen_impl_expr!(polars_expr_neg, Neg::neg);

#[no_mangle]
pub unsafe extern "C" fn polars_expr_replace(
    expr: *const polars_expr_t,
    old: *const polars_expr_t,
    new: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let old = (*old).inner.clone();
    let new = (*new).inner.clone();
    make_expr(expr.replace(old, new))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_replace_strict(
    expr: *const polars_expr_t,
    old: *const polars_expr_t,
    new: *const polars_expr_t,
    default: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let old = (*old).inner.clone();
    let new = (*new).inner.clone();
    let default = if default.is_null() {
        None
    } else {
        Some((*default).inner.clone())
    };
    make_expr(expr.replace_strict(old, new, default, Option::<DataTypeExpr>::None))
}

gen_impl_expr!(polars_expr_n_unique, Expr::n_unique);
gen_impl_expr!(polars_expr_unique, Expr::unique);
gen_impl_expr!(polars_expr_is_duplicated, Expr::is_duplicated);
gen_impl_expr!(polars_expr_is_unique, Expr::is_unique);
gen_impl_expr!(polars_expr_is_first_distinct, Expr::is_first_distinct);
gen_impl_expr!(polars_expr_is_last_distinct, Expr::is_last_distinct);
gen_impl_expr!(polars_expr_count, Expr::count);
gen_impl_expr!(polars_expr_first, Expr::first);
gen_impl_expr!(polars_expr_last, Expr::last);

/// The aggregation form of `item()`: errors if the expression evaluates to `!= 1` values, unless
/// `allow_empty` is set, in which case zero values also succeeds (producing `null`). Distinct from
/// `DataFrame`/`Series` `item()`, which is a `(1,1)`-shape accessor, not an aggregation -- the two
/// share a name upstream but are different functions (see `plans/parity/batch-2-aggregation-
/// statistics.md`'s Step-9 finding).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_item(
    expr: *const polars_expr_t,
    allow_empty: bool,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().item(allow_empty))
}

gen_impl_expr!(polars_expr_not, Expr::not);

#[no_mangle]
pub unsafe extern "C" fn polars_expr_all(
    expr: *const polars_expr_t,
    ignore_nulls: bool,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().all(ignore_nulls))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_any(
    expr: *const polars_expr_t,
    ignore_nulls: bool,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().any(ignore_nulls))
}

gen_impl_expr!(polars_expr_is_finite, Expr::is_finite);
gen_impl_expr!(polars_expr_is_infinite, Expr::is_infinite);
gen_impl_expr!(polars_expr_is_nan, Expr::is_nan);
gen_impl_expr!(polars_expr_is_null, Expr::is_null);
gen_impl_expr!(polars_expr_is_not_null, Expr::is_not_null);
gen_impl_expr!(polars_expr_null_count, Expr::null_count);
gen_impl_expr!(polars_expr_drop_nans, Expr::drop_nans);
gen_impl_expr!(polars_expr_drop_nulls, Expr::drop_nulls);

#[no_mangle]
pub unsafe extern "C" fn polars_expr_arg_sort(
    expr: *const polars_expr_t,
    descending: bool,
    nulls_last: bool,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().arg_sort(descending, nulls_last))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_value_counts(
    expr: *const polars_expr_t,
    sort: bool,
    parallel: bool,
    name: *const u8,
    name_len: usize,
    normalize: bool,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let name = tri!(read_str(name, name_len));
        let result = (*expr)
            .inner
            .clone()
            .value_counts(sort, parallel, name, normalize);
        *out = make_expr(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_implode(expr: *const polars_expr_t) -> *const polars_expr_t {
    let expr = &(*expr).inner;
    // The `true` is `implode`'s `maintain_order` flag (same knob `explode`'s `ExplodeOptions`
    // exposes below) -- an order-agnostic implode could be faster in a grouped context, but this
    // wrapper always preserves input order rather than exposing the tradeoff as a parameter.
    make_expr(expr.clone().implode(true))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_flatten(
    expr: *const polars_expr_t,
    empty_as_null: bool,
    keep_nulls: bool,
) -> *const polars_expr_t {
    let expr = &(*expr).inner;
    make_expr(expr.clone().explode(ExplodeOptions {
        empty_as_null,
        keep_nulls,
    }))
}

gen_impl_expr!(polars_expr_reverse, Expr::reverse);

macro_rules! gen_impl_expr_binary {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            b: *const polars_expr_t,
        ) -> *const polars_expr_t {
            let a = &(*a).inner;
            let b = &(*b).inner;
            let out_expr = $t(a.clone(), b.clone());
            make_expr(out_expr)
        }
    };
}

gen_impl_expr_binary!(polars_expr_eq, Expr::eq);
gen_impl_expr_binary!(polars_expr_lt, Expr::lt);
gen_impl_expr_binary!(polars_expr_gt, Expr::gt);
gen_impl_expr_binary!(polars_expr_or, Expr::or);
gen_impl_expr_binary!(polars_expr_xor, Expr::xor);
gen_impl_expr_binary!(polars_expr_and, Expr::and);

gen_impl_expr_binary!(polars_expr_pow, Expr::pow);
gen_impl_expr_binary!(polars_expr_add, core::ops::Add::add);
gen_impl_expr_binary!(polars_expr_sub, core::ops::Sub::sub);
gen_impl_expr_binary!(polars_expr_mul, core::ops::Mul::mul);
gen_impl_expr_binary!(polars_expr_div, core::ops::Div::div);
// Floors toward negative infinity; for float operands this differs from `polars_expr_div`'s
// `RustDivide` (the exact quotient) -- needed by `Dt.epoch`'s `:s`/`:d` units, which must match
// Python polars' `//` for pre-1970 (negative) timestamps.
gen_impl_expr_binary!(polars_expr_floor_div, Expr::floor_div);

// Single-sided clip -- the existing `polars_expr_clip` above only wraps the two-sided form.
gen_impl_expr_binary!(polars_expr_clip_min, Expr::clip_min);
gen_impl_expr_binary!(polars_expr_clip_max, Expr::clip_max);

gen_impl_expr_binary!(polars_expr_bottom_k, Expr::bottom_k);

/// `shift(n, fill_value)` -- unlike the existing binary `shift(n)` (no fill), out-of-range rows
/// get `fill_value` instead of `null`.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_shift_and_fill(
    expr: *const polars_expr_t,
    n: *const polars_expr_t,
    fill_value: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let n = (*n).inner.clone();
    let fill_value = (*fill_value).inner.clone();
    make_expr(expr.shift_and_fill(n, fill_value))
}

gen_impl_expr_binary!(polars_expr_fill_null, Expr::fill_null);
gen_impl_expr_binary!(polars_expr_fill_nan, Expr::fill_nan);

/// `limit` applies only to the `Backward`/`Forward` strategies and is ignored otherwise; a null
/// `limit` means unlimited.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_fill_null_with_strategy(
    expr: *const polars_expr_t,
    strategy: polars_fill_null_strategy_t,
    limit: *const u32,
) -> *const polars_expr_t {
    let limit = if limit.is_null() { None } else { Some(*limit) };
    let expr = (*expr).inner.clone();
    make_expr(expr.fill_null_with_strategy(strategy.to_fill_null_strategy(limit)))
}
// The trailing `false` is `nulls_equal`: a null in `a` is not considered "in" a set containing
// null (matching Polars' default `is_in`). Exposing this flag is a possible future extension.
gen_impl_expr_binary!(polars_expr_is_in, |a, b| Expr::is_in(a, b, false));

gen_impl_expr_binary!(polars_expr_shift, Expr::shift);
gen_impl_expr_binary!(polars_expr_pct_change, Expr::pct_change);

gen_impl_expr_binary!(polars_expr_log, Expr::log);
gen_impl_expr_binary!(polars_expr_rem, core::ops::Rem::rem);
gen_impl_expr_binary!(polars_expr_top_k, Expr::top_k);

#[no_mangle]
pub unsafe extern "C" fn polars_expr_cum_sum(
    expr: *const polars_expr_t,
    reverse: bool,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().cum_sum(reverse))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_cum_prod(
    expr: *const polars_expr_t,
    reverse: bool,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().cum_prod(reverse))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_cum_min(
    expr: *const polars_expr_t,
    reverse: bool,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().cum_min(reverse))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_cum_max(
    expr: *const polars_expr_t,
    reverse: bool,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().cum_max(reverse))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_cum_count(
    expr: *const polars_expr_t,
    reverse: bool,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().cum_count(reverse))
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_null_behavior_t {
    PolarsNullBehaviorDrop,
    PolarsNullBehaviorIgnore,
}

impl polars_null_behavior_t {
    fn to_null_behavior(&self) -> NullBehavior {
        match self {
            polars_null_behavior_t::PolarsNullBehaviorDrop => NullBehavior::Drop,
            polars_null_behavior_t::PolarsNullBehaviorIgnore => NullBehavior::Ignore,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_diff(
    expr: *const polars_expr_t,
    n: *const polars_expr_t,
    null_behavior: polars_null_behavior_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let n = (*n).inner.clone();
    make_expr(expr.diff(n, null_behavior.to_null_behavior()))
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_rank_method_t {
    PolarsRankMethodAverage,
    PolarsRankMethodMin,
    PolarsRankMethodMax,
    PolarsRankMethodDense,
    PolarsRankMethodOrdinal,
}

impl polars_rank_method_t {
    fn to_rank_method(&self) -> RankMethod {
        match self {
            polars_rank_method_t::PolarsRankMethodAverage => RankMethod::Average,
            polars_rank_method_t::PolarsRankMethodMin => RankMethod::Min,
            polars_rank_method_t::PolarsRankMethodMax => RankMethod::Max,
            polars_rank_method_t::PolarsRankMethodDense => RankMethod::Dense,
            polars_rank_method_t::PolarsRankMethodOrdinal => RankMethod::Ordinal,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_rank(
    expr: *const polars_expr_t,
    method: polars_rank_method_t,
    descending: bool,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let options = RankOptions {
        method: method.to_rank_method(),
        descending,
    };
    make_expr(expr.rank(options, None))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_sample_n(
    expr: *const polars_expr_t,
    n: *const polars_expr_t,
    with_replacement: bool,
    shuffle: bool,
    seed: *const u64,
) -> *const polars_expr_t {
    let seed = if seed.is_null() { None } else { Some(*seed) };
    let expr = (*expr).inner.clone();
    let n = (*n).inner.clone();
    make_expr(expr.sample_n(n, with_replacement, shuffle, seed))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_sample_frac(
    expr: *const polars_expr_t,
    frac: *const polars_expr_t,
    with_replacement: bool,
    shuffle: bool,
    seed: *const u64,
) -> *const polars_expr_t {
    let seed = if seed.is_null() { None } else { Some(*seed) };
    let expr = (*expr).inner.clone();
    let frac = (*frac).inner.clone();
    make_expr(expr.sample_frac(frac, with_replacement, shuffle, seed))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_gather(
    expr: *const polars_expr_t,
    idx: *const polars_expr_t,
    null_on_oob: bool,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    let idx = (*idx).inner.clone();
    make_expr(expr.gather(idx, null_on_oob))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_gather_every(
    expr: *const polars_expr_t,
    n: usize,
    offset: usize,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    make_expr(expr.gather_every(n, offset))
}

macro_rules! gen_impl_expr_list {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(a: *const polars_expr_t) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().list());
            make_expr(expr)
        }
    };
}

gen_impl_expr_list!(polars_expr_list_lengths, ListNameSpace::len);
gen_impl_expr_list!(polars_expr_list_max, ListNameSpace::max);
gen_impl_expr_list!(polars_expr_list_min, ListNameSpace::min);
gen_impl_expr_list!(polars_expr_list_arg_max, ListNameSpace::arg_max);
gen_impl_expr_list!(polars_expr_list_arg_min, ListNameSpace::arg_min);
gen_impl_expr_list!(polars_expr_list_sum, ListNameSpace::sum);
gen_impl_expr_list!(polars_expr_list_mean, ListNameSpace::mean);
#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_reverse(a: *const polars_expr_t) -> *const polars_expr_t {
    let expr = (*a).inner.clone().list().eval(element().reverse());
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_unique(a: *const polars_expr_t) -> *const polars_expr_t {
    let expr = (*a).inner.clone().list().eval(element().unique());
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_unique_stable(
    a: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().list().eval(element().unique_stable());
    make_expr(expr)
}

// `n_unique`/`any`/`all` have no native `ListNameSpace` method (unlike `reverse`/`unique` above)
// -- built the same way python-polars itself builds them, as a per-list `agg` of the plain
// (non-list) `Expr` reducer. `agg` (not `eval`, unlike `reverse`/`unique` above) is required
// specifically because these reduce each list to one scalar: `eval` always re-wraps its result
// in a length-1 list per row, while `agg` unwraps it back down to a flat scalar column.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_n_unique(
    a: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().list().agg(element().n_unique());
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_any(
    a: *const polars_expr_t,
    ignore_nulls: bool,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().list().agg(element().any(ignore_nulls));
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_all(
    a: *const polars_expr_t,
    ignore_nulls: bool,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().list().agg(element().all(ignore_nulls));
    make_expr(expr)
}

gen_impl_expr_list!(polars_expr_list_first, ListNameSpace::first);
gen_impl_expr_list!(polars_expr_list_last, ListNameSpace::last);
gen_impl_expr_list!(polars_expr_list_median, ListNameSpace::median);
gen_impl_expr_list!(polars_expr_list_drop_nulls, ListNameSpace::drop_nulls);

/// `Lists.eval`: runs `evaluation` once per row, with `element()` bound to that row's list values
/// -- the same primitive the crate already uses internally for `reverse`/`unique`/`unique_stable`
/// above, exposed directly. This is the multiplier for the "most of the list namespace is
/// missing" finding (`plans/parity/batch-9-lists-structs.md`): `all`/`any` have no dedicated
/// `ListNameSpace` method in this polars version at all and are *only* reachable this way
/// (`eval(element().all(ignore_nulls))`), and `n_unique`/`filter` compose the same way.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_eval(
    a: *const polars_expr_t,
    evaluation: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().list().eval((*evaluation).inner.clone());
    make_expr(expr)
}

/// `Lists.agg`: like `eval`, but the per-row expression is expected to reduce to a single scalar
/// (`EvalVariant::ListAgg` instead of `::List`) -- needed for e.g. `n_unique` per row, which
/// `eval` alone cannot express (it stays list-shaped).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_agg(
    a: *const polars_expr_t,
    evaluation: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().list().agg((*evaluation).inner.clone());
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_sort(
    a: *const polars_expr_t,
    descending: bool,
    nulls_last: bool,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().list().sort(SortOptions {
        descending,
        nulls_last,
        ..Default::default()
    });
    make_expr(expr)
}

macro_rules! gen_impl_expr_binary_list {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            b: *const polars_expr_t,
        ) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().list(), (*b).inner.clone());
            make_expr(expr)
        }
    };
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_get(
    a: *const polars_expr_t,
    index: *const polars_expr_t,
    null_on_oob: bool,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .list()
        .get((*index).inner.clone(), null_on_oob);
    make_expr(expr)
}

gen_impl_expr_binary_list!(polars_expr_list_head, ListNameSpace::head);
gen_impl_expr_binary_list!(polars_expr_list_tail, ListNameSpace::tail);
gen_impl_expr_binary_list!(polars_expr_list_shift, ListNameSpace::shift);
gen_impl_expr_binary_list!(polars_expr_list_count_matches, ListNameSpace::count_matches);
gen_impl_expr_binary_list!(polars_expr_list_union, ListNameSpace::union);
gen_impl_expr_binary_list!(
    polars_expr_list_set_difference,
    ListNameSpace::set_difference
);
gen_impl_expr_binary_list!(
    polars_expr_list_set_intersection,
    ListNameSpace::set_intersection
);
gen_impl_expr_binary_list!(
    polars_expr_list_set_symmetric_difference,
    ListNameSpace::set_symmetric_difference
);

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_std(
    a: *const polars_expr_t,
    ddof: u8,
) -> *const polars_expr_t {
    make_expr((*a).inner.clone().list().std(ddof))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_var(
    a: *const polars_expr_t,
    ddof: u8,
) -> *const polars_expr_t {
    make_expr((*a).inner.clone().list().var(ddof))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_join(
    a: *const polars_expr_t,
    separator: *const polars_expr_t,
    ignore_nulls: bool,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .list()
        .join((*separator).inner.clone(), ignore_nulls);
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_slice(
    a: *const polars_expr_t,
    offset: *const polars_expr_t,
    length: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .list()
        .slice((*offset).inner.clone(), (*length).inner.clone());
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_gather(
    a: *const polars_expr_t,
    index: *const polars_expr_t,
    null_on_oob: bool,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .list()
        .gather((*index).inner.clone(), null_on_oob);
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_gather_every(
    a: *const polars_expr_t,
    n: *const polars_expr_t,
    offset: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .list()
        .gather_every((*n).inner.clone(), (*offset).inner.clone());
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_diff(
    a: *const polars_expr_t,
    n: i64,
    null_behavior: polars_null_behavior_t,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .list()
        .diff(n, null_behavior.to_null_behavior());
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_sample_n(
    a: *const polars_expr_t,
    n: *const polars_expr_t,
    with_replacement: bool,
    shuffle: bool,
    seed: *const u64,
) -> *const polars_expr_t {
    let seed = if seed.is_null() { None } else { Some(*seed) };
    let expr =
        (*a).inner
            .clone()
            .list()
            .sample_n((*n).inner.clone(), with_replacement, shuffle, seed);
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_sample_fraction(
    a: *const polars_expr_t,
    fraction: *const polars_expr_t,
    with_replacement: bool,
    shuffle: bool,
    seed: *const u64,
) -> *const polars_expr_t {
    let seed = if seed.is_null() { None } else { Some(*seed) };
    let expr = (*a).inner.clone().list().sample_fraction(
        (*fraction).inner.clone(),
        with_replacement,
        shuffle,
        seed,
    );
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_to_array(
    a: *const polars_expr_t,
    width: usize,
) -> *const polars_expr_t {
    make_expr((*a).inner.clone().list().to_array(width))
}

/// Converts a `List` column to a `Struct` column, one field per list position, named `names[i]`.
/// `names.len()` fixes the field count (and so the schema) -- a row whose list is shorter gets
/// `null` for the missing trailing fields; longer is a runtime error (upstream's own behavior).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_to_struct(
    a: *const polars_expr_t,
    names: *const *const u8,
    lens: *const usize,
    num_names: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let names: Arc<[PlSmallStr]> = tri!(read_names(names, lens, num_names)).into();
        *out = make_expr((*a).inner.clone().list().to_struct(names));
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_list_contains(
    a: *const polars_expr_t,
    other: *const polars_expr_t,
    nulls_equal: bool,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .list()
        .contains((*other).inner.clone(), nulls_equal);
    make_expr(expr)
}

macro_rules! gen_impl_expr_str {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(a: *const polars_expr_t) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().str());
            make_expr(expr)
        }
    };
}

gen_impl_expr_str!(polars_expr_str_to_uppercase, StringNameSpace::to_uppercase);
gen_impl_expr_str!(polars_expr_str_to_lowercase, StringNameSpace::to_lowercase);
#[cfg(feature = "nightly")]
gen_impl_expr_str!(polars_expr_str_to_titlecase, StringNameSpace::to_titlecase);
gen_impl_expr_str!(polars_expr_str_len_bytes, StringNameSpace::len_bytes);
gen_impl_expr_str!(polars_expr_str_len_chars, StringNameSpace::len_chars);

macro_rules! gen_impl_expr_binary_str {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            b: *const polars_expr_t,
        ) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().str(), (*b).inner.clone());
            make_expr(expr)
        }
    };
}

gen_impl_expr_binary_str!(polars_expr_str_starts_with, StringNameSpace::starts_with);
gen_impl_expr_binary_str!(polars_expr_str_ends_with, StringNameSpace::ends_with);
gen_impl_expr_binary_str!(
    polars_expr_str_contains_literal,
    StringNameSpace::contains_literal
);

gen_impl_expr_binary_str!(polars_expr_str_strip_chars, StringNameSpace::strip_chars);
gen_impl_expr_binary_str!(polars_expr_str_strip_prefix, StringNameSpace::strip_prefix);
gen_impl_expr_binary_str!(polars_expr_str_strip_suffix, StringNameSpace::strip_suffix);
gen_impl_expr_binary_str!(polars_expr_str_split, StringNameSpace::split);
gen_impl_expr_binary_str!(polars_expr_str_extract_all, StringNameSpace::extract_all);
gen_impl_expr_binary_str!(polars_expr_str_zfill, StringNameSpace::zfill);
gen_impl_expr_binary_str!(polars_expr_str_head, StringNameSpace::head);
gen_impl_expr_binary_str!(polars_expr_str_tail, StringNameSpace::tail);
gen_impl_expr_binary_str!(
    polars_expr_str_strip_chars_start,
    StringNameSpace::strip_chars_start
);
gen_impl_expr_binary_str!(
    polars_expr_str_strip_chars_end,
    StringNameSpace::strip_chars_end
);

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_replace_n(
    a: *const polars_expr_t,
    pat: *const polars_expr_t,
    value: *const polars_expr_t,
    literal: bool,
    n: i64,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().str().replace_n(
        (*pat).inner.clone(),
        (*value).inner.clone(),
        literal,
        n,
    );
    make_expr(expr)
}

/// Struct-typed split: exactly `n` fields, the remainder (if any) folded into the last one.
/// Distinct from `polars_expr_str_split` above, which produces a variable-length `List<String>`.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_splitn(
    a: *const polars_expr_t,
    by: *const polars_expr_t,
    n: usize,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().str().splitn((*by).inner.clone(), n);
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_split_exact(
    a: *const polars_expr_t,
    by: *const polars_expr_t,
    n: usize,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().str().split_exact((*by).inner.clone(), n);
    make_expr(expr)
}

/// Aggregating join-with-separator across *all* rows into a single value (upstream `str.join`,
/// the replacement for the deprecated `str.concat`) -- distinct from `Lists.join` above, which
/// joins each row's own list independently. `delimiter` is a plain string (not an `Expr`) because
/// the aggregation itself has no per-row context to evaluate a column expression against.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_join(
    a: *const polars_expr_t,
    delimiter: *const u8,
    delimiter_len: usize,
    ignore_nulls: bool,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let delimiter = tri!(read_str(delimiter, delimiter_len));
        let expr = (*a).inner.clone().str().join(delimiter, ignore_nulls);
        *out = make_expr(expr);
        std::ptr::null()
    })
}

/// Named-capture-group regex extraction into a `Struct` column (one field per named group).
/// `pat` is a plain string, not an `Expr` -- upstream compiles the regex at plan time to
/// determine the output `Struct`'s schema (field names/count), so it cannot vary per row.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_extract_groups(
    a: *const polars_expr_t,
    pat: *const u8,
    pat_len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let pat = tri!(read_str(pat, pat_len));
        let expr = tri!((*a).inner.clone().str().extract_groups(pat));
        *out = make_expr(expr);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_contains(
    a: *const polars_expr_t,
    pat: *const polars_expr_t,
    strict: bool,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .str()
        .contains((*pat).inner.clone(), strict);
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_slice(
    a: *const polars_expr_t,
    offset: *const polars_expr_t,
    length: *const polars_expr_t,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .str()
        .slice((*offset).inner.clone(), (*length).inner.clone());
    make_expr(expr)
}

/// Position (not just presence, unlike `contains`) of the first regex match.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_find(
    a: *const polars_expr_t,
    pat: *const polars_expr_t,
    strict: bool,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().str().find((*pat).inner.clone(), strict);
    make_expr(expr)
}

/// `fill_char` crosses the FFI boundary as a `u32` codepoint (there is no C `char32_t` binding on
/// the Julia side) and is fallible since not every `u32` is a valid Unicode scalar value.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_pad_start(
    a: *const polars_expr_t,
    length: *const polars_expr_t,
    fill_char: u32,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let fill_char = match char::from_u32(fill_char) {
            Some(c) => c,
            None => return make_error(format!("{fill_char} is not a valid Unicode scalar value")),
        };
        let expr = (*a)
            .inner
            .clone()
            .str()
            .pad_start((*length).inner.clone(), fill_char);
        *out = make_expr(expr);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_pad_end(
    a: *const polars_expr_t,
    length: *const polars_expr_t,
    fill_char: u32,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let fill_char = match char::from_u32(fill_char) {
            Some(c) => c,
            None => return make_error(format!("{fill_char} is not a valid Unicode scalar value")),
        };
        let expr = (*a)
            .inner
            .clone()
            .str()
            .pad_end((*length).inner.clone(), fill_char);
        *out = make_expr(expr);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_replace(
    a: *const polars_expr_t,
    pat: *const polars_expr_t,
    value: *const polars_expr_t,
    literal: bool,
) -> *const polars_expr_t {
    let expr =
        (*a).inner
            .clone()
            .str()
            .replace((*pat).inner.clone(), (*value).inner.clone(), literal);
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_replace_all(
    a: *const polars_expr_t,
    pat: *const polars_expr_t,
    value: *const polars_expr_t,
    literal: bool,
) -> *const polars_expr_t {
    let expr =
        (*a).inner
            .clone()
            .str()
            .replace_all((*pat).inner.clone(), (*value).inner.clone(), literal);
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_extract(
    a: *const polars_expr_t,
    pat: *const polars_expr_t,
    group_index: usize,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .str()
        .extract((*pat).inner.clone(), group_index);
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_count_matches(
    a: *const polars_expr_t,
    pat: *const polars_expr_t,
    literal: bool,
) -> *const polars_expr_t {
    let expr = (*a)
        .inner
        .clone()
        .str()
        .count_matches((*pat).inner.clone(), literal);
    make_expr(expr)
}

fn string_literal(s: &str) -> Expr {
    Expr::Literal(LiteralValue::Scalar(Scalar::new(
        DataType::String,
        AnyValue::StringOwned(PlSmallStr::from_str(s)),
    )))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_to_date(
    expr: *const polars_expr_t,
    format: *const u8,
    format_len: usize,
    strict: bool,
    exact: bool,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let format = tri!(read_opt_str(format, format_len));
        let options = StrptimeOptions {
            format,
            strict,
            exact,
            cache: true,
        };
        let result = (*expr).inner.clone().str().to_date(options);
        *out = make_expr(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_str_to_datetime(
    expr: *const polars_expr_t,
    format: *const u8,
    format_len: usize,
    time_unit: polars_time_unit_t,
    strict: bool,
    exact: bool,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let format = tri!(read_opt_str(format, format_len));
        let options = StrptimeOptions {
            format,
            strict,
            exact,
            cache: true,
        };
        let time_unit = tri!(time_unit.to_time_unit());
        let result = (*expr).inner.clone().str().to_datetime(
            Some(time_unit),
            None,
            options,
            string_literal("raise"),
        );
        *out = make_expr(result);
        std::ptr::null()
    })
}

macro_rules! gen_impl_expr_dt {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(a: *const polars_expr_t) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().dt());
            make_expr(expr)
        }
    };
}

gen_impl_expr_dt!(polars_expr_dt_year, DateLikeNameSpace::year);
gen_impl_expr_dt!(polars_expr_dt_month, DateLikeNameSpace::month);
gen_impl_expr_dt!(polars_expr_dt_day, DateLikeNameSpace::day);
gen_impl_expr_dt!(polars_expr_dt_hour, DateLikeNameSpace::hour);
gen_impl_expr_dt!(polars_expr_dt_minute, DateLikeNameSpace::minute);
gen_impl_expr_dt!(polars_expr_dt_second, DateLikeNameSpace::second);
gen_impl_expr_dt!(polars_expr_dt_weekday, DateLikeNameSpace::weekday);
gen_impl_expr_dt!(polars_expr_dt_ordinal_day, DateLikeNameSpace::ordinal_day);
gen_impl_expr_dt!(polars_expr_dt_week, DateLikeNameSpace::week);
gen_impl_expr_dt!(polars_expr_dt_quarter, DateLikeNameSpace::quarter);
// Both ungated in polars-plan (no `#[cfg]`) -- unlike the `total_*` family below, no
// `dtype-duration` feature is needed for these two.
gen_impl_expr_dt!(polars_expr_dt_date, DateLikeNameSpace::date);
gen_impl_expr_dt!(polars_expr_dt_time, DateLikeNameSpace::time);

macro_rules! gen_impl_expr_binary_dt {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            b: *const polars_expr_t,
        ) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().dt(), (*b).inner.clone());
            make_expr(expr)
        }
    };
}

gen_impl_expr_binary_dt!(polars_expr_dt_truncate, DateLikeNameSpace::truncate);
gen_impl_expr_binary_dt!(polars_expr_dt_round, DateLikeNameSpace::round);
gen_impl_expr_binary_dt!(polars_expr_dt_offset_by, DateLikeNameSpace::offset_by);

// Both variants are only ever produced on the Julia side (`@cenum`) and received here as a
// C-ABI parameter value, never constructed by Rust itself -- a false positive for dead_code.
#[allow(dead_code)]
#[repr(C)]
pub enum polars_non_existent_t {
    PolarsNonExistentRaise,
    PolarsNonExistentNull,
}

impl polars_non_existent_t {
    fn to_non_existent(&self) -> NonExistent {
        match self {
            polars_non_existent_t::PolarsNonExistentRaise => NonExistent::Raise,
            polars_non_existent_t::PolarsNonExistentNull => NonExistent::Null,
        }
    }
}

/// `convert_time_zone`: re-labels the same instant into a different (mandatory) time zone,
/// e.g. UTC -> "America/New_York". Fails if `tz` is not a valid IANA time zone name.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_dt_convert_time_zone(
    expr: *const polars_expr_t,
    tz: *const u8,
    tz_len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let tz = tri!(read_str(tz, tz_len));
        let time_zone = match TimeZone::opt_try_new(Some(tz)) {
            Ok(Some(time_zone)) => time_zone,
            Ok(None) => return make_error("invalid time zone"),
            Err(err) => return make_error(err),
        };
        let result = (*expr).inner.clone().dt().convert_time_zone(time_zone);
        *out = make_expr(result);
        std::ptr::null()
    })
}

/// `replace_time_zone`: attaches/strips/re-attaches a time zone label to the *same* local
/// wall-clock values (unlike `convert_time_zone`, which preserves the instant).
/// `tz_len == 0` means "strip the time zone back to naive" (`time_zone = None`).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_dt_replace_time_zone(
    expr: *const polars_expr_t,
    tz: *const u8,
    tz_len: usize,
    ambiguous: *const polars_expr_t,
    non_existent: polars_non_existent_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let tz = tri!(read_opt_str(tz, tz_len));
        let time_zone = tri!(TimeZone::opt_try_new(tz));
        let result = (*expr).inner.clone().dt().replace_time_zone(
            time_zone,
            (*ambiguous).inner.clone(),
            non_existent.to_non_existent(),
        );
        *out = make_expr(result);
        std::ptr::null()
    })
}

/// Fallible since `polars_time_unit_t` mirrors a Julia-side `@cenum` and must reject an
/// out-of-range value rather than let `to_time_unit` panic across the FFI boundary.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_dt_timestamp(
    expr: *const polars_expr_t,
    unit: polars_time_unit_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let unit = tri!(unit.to_time_unit());
        let result = (*expr).inner.clone().dt().timestamp(unit);
        *out = make_expr(result);
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_dt_strftime(
    expr: *const polars_expr_t,
    format: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let format = tri!(read_str(format, len));
        let result = (*expr).inner.clone().dt().strftime(format);
        *out = make_expr(result);
        std::ptr::null()
    })
}

/// `total_*` Duration-decomposition family (`total_days`/`total_hours`/`total_minutes`/
/// `total_seconds`/`total_milliseconds`/`total_microseconds`/`total_nanoseconds`) -- each takes
/// a `fractional` flag (whole-unit truncation vs. exact fractional value) and is otherwise
/// identical in shape, so unlike `gen_impl_expr_dt!` above (no extra args) these get their own
/// small macro rather than 7x hand-written boilerplate. Gated on `dtype-duration` in polars-plan
/// (see c-polars/Cargo.toml and the gap-closure plan's Phase 5 sweep notes) -- confirmed already
/// active via `dtype-slim` (part of the `polars` crate's own default features) before this task's
/// Cargo.toml change, so this is belt-and-suspenders explicitness, not a functional fix (contrast
/// `dtype-time`, which really was inactive on polars-ops until explicitly added).
macro_rules! gen_impl_expr_dt_fractional {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            fractional: bool,
        ) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().dt(), fractional);
            make_expr(expr)
        }
    };
}

gen_impl_expr_dt_fractional!(polars_expr_dt_total_days, DateLikeNameSpace::total_days);
gen_impl_expr_dt_fractional!(polars_expr_dt_total_hours, DateLikeNameSpace::total_hours);
gen_impl_expr_dt_fractional!(
    polars_expr_dt_total_minutes,
    DateLikeNameSpace::total_minutes
);
gen_impl_expr_dt_fractional!(
    polars_expr_dt_total_seconds,
    DateLikeNameSpace::total_seconds
);
gen_impl_expr_dt_fractional!(
    polars_expr_dt_total_milliseconds,
    DateLikeNameSpace::total_milliseconds
);
gen_impl_expr_dt_fractional!(
    polars_expr_dt_total_microseconds,
    DateLikeNameSpace::total_microseconds
);
gen_impl_expr_dt_fractional!(
    polars_expr_dt_total_nanoseconds,
    DateLikeNameSpace::total_nanoseconds
);

#[no_mangle]
pub unsafe extern "C" fn polars_expr_struct_field_by_name(
    a: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let name = tri!(read_str(name, len));
        *out = make_expr((*a).inner.clone().struct_().field_by_name(name));
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_struct_field_by_index(
    a: *const polars_expr_t,
    fieldidx: i64,
) -> *const polars_expr_t {
    let expr = (*a).inner.clone().struct_().field_by_index(fieldidx);
    make_expr(expr)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_struct_rename_fields(
    a: *const polars_expr_t,
    names: *const *const u8,
    lens: *const usize,
    num_names: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        // `read_names` validates UTF-8 and returns the same error every peer function does;
        // `from_utf8_unchecked` in its place is UB on invalid input.
        let names = tri!(read_names(names, lens, num_names));
        *out = make_expr((*a).inner.clone().struct_().rename_fields(names));
        std::ptr::null()
    })
}

gen_impl_expr!(polars_expr_struct_json_encode, |e: Expr| e
    .struct_()
    .json_encode());

/// Applies each of `fields` to the struct's selected field(s) in place (via `pl.field("x")...`
/// inside each expression), leaving other fields untouched -- upstream `struct.with_fields`.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_struct_with_fields(
    a: *const polars_expr_t,
    fields: *const *const polars_expr_t,
    n_fields: usize,
) -> *const polars_expr_t {
    let fields = read_exprs(fields, n_fields);
    make_expr((*a).inner.clone().struct_().with_fields(fields))
}

// ------------------------------------------------------------------------------------------
// Meta (`Expr.meta()` introspection namespace) -- see
// `plans/definitive_guide_gap_closure.md`'s Phase 3 for the full design writeup. `.meta()`
// consumes its receiver by value (`MetaNameSpace(pub(crate) Expr)`), so every function here
// clones `(*expr).inner` first, same as the `.struct_()`/`.dt()` namespace functions above.
// ------------------------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn polars_expr_meta_is_column(expr: *const polars_expr_t) -> bool {
    (*expr).inner.clone().meta().is_column()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_meta_is_literal(
    expr: *const polars_expr_t,
    allow_aliasing: bool,
) -> bool {
    (*expr).inner.clone().meta().is_literal(allow_aliasing)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_meta_has_multiple_outputs(expr: *const polars_expr_t) -> bool {
    (*expr).inner.clone().meta().has_multiple_outputs()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_meta_undo_aliases(
    expr: *const polars_expr_t,
) -> *const polars_expr_t {
    make_expr((*expr).inner.clone().meta().undo_aliases())
}

/// Fails if the expression has no single well-defined output name (e.g. a wildcard or a
/// selector-expanded expression).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_meta_output_name(
    expr: *const polars_expr_t,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    // guard_error-wrapped: unlike the infallible structural checks above (is_column/is_literal/...),
    // output_name() resolves the expression's output field, which is closer to "execution" than pure
    // node construction -- so a hypothetical internal upstream panic becomes a catchable error here
    // rather than aborting the process across the FFI boundary.
    guard_error(|| {
        let name = tri!((*expr).inner.clone().meta().output_name());
        let mut w = UserIOCallback(callback, user);
        // write_all, not write: a single write() may report a short count and silently drop the tail.
        match w.write_all(name.as_bytes()) {
            Ok(()) => std::ptr::null(),
            Err(err) => make_error(err),
        }
    })
}

/// Backs both `tree_format` (`display_as_dot = false`) and `show_graph` (`true`). No schema is
/// threaded through, so unresolved column types show as untyped.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_meta_tree_format(
    expr: *const polars_expr_t,
    display_as_dot: bool,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    // guard_error-wrapped for the same reason as output_name above: into_tree_formatter resolves
    // the expression tree for display, so guard against an internal upstream panic.
    guard_error(|| {
        let formatter = tri!((*expr)
            .inner
            .clone()
            .meta()
            .into_tree_formatter(display_as_dot, None));
        let text = formatter.to_string();
        let mut w = UserIOCallback(callback, user);
        match w.write_all(text.as_bytes()) {
            Ok(()) => std::ptr::null(),
            Err(err) => make_error(err),
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_meta_root_names_len(expr: *const polars_expr_t) -> usize {
    (*expr).inner.clone().meta().root_names().len()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_meta_root_names_get(
    expr: *const polars_expr_t,
    index: usize,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    // guard_error-wrapped for the same reason as output_name above: root_names() walks the resolved
    // expression tree, so guard against an internal upstream panic.
    guard_error(|| {
        let names = (*expr).inner.clone().meta().root_names();
        let Some(name) = names.get(index) else {
            return make_error(format!(
                "root_names index {index} out of bounds (len {})",
                names.len()
            ));
        };
        let mut w = UserIOCallback(callback, user);
        match w.write_all(name.as_bytes()) {
            Ok(()) => std::ptr::null(),
            Err(err) => make_error(err),
        }
    })
}

// ------------------------------------------------------------------------------------------
// Selectors (py-polars' `polars.selectors` / `cs.*`) -- see
// `plans/definitive_guide_gap_closure.md`'s Phase 2 for the full design writeup. A `Selector` is
// just another `Expr` variant (`Expr::Selector(Selector)`), so these functions reuse the same
// `polars_expr_t` handle/destructor/error conventions as every other `Expr`-producing function
// above -- no new opaque pointer type is introduced. The Julia-side `Polars.Selectors.Selector`
// wrapper stays entirely on the Julia side (`struct Selector; expr::Expr; end`), just carrying
// the `Expr` handle these functions hand back.
// ------------------------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn polars_expr_selector_all() -> *const polars_expr_t {
    make_expr(Expr::Selector(Selector::Wildcard))
}

/// The identity element for selector combinators (`empty() | s == s`, `empty() & s == empty()`).
#[no_mangle]
pub unsafe extern "C" fn polars_expr_selector_empty() -> *const polars_expr_t {
    make_expr(Expr::Selector(Selector::Empty))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_selector_by_name(
    names: *const *const u8,
    lens: *const usize,
    n: usize,
    strict: bool,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let names = tri!(read_names(names, lens, n));
        *out = make_expr(Expr::Selector(selector_by_name(names, strict)));
        std::ptr::null()
    })
}

/// Selects columns by 0-based index; negative indices count back from the end.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_selector_by_index(
    indices: *const i64,
    n: usize,
    strict: bool,
) -> *const polars_expr_t {
    let indices = read_i64_array(indices, n);
    make_expr(Expr::Selector(Selector::ByIndex {
        indices: indices.into(),
        strict,
    }))
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_selector_match_kind_t {
    PolarsSelectorMatchKindRegex,
    PolarsSelectorMatchKindStartsWith,
    PolarsSelectorMatchKindEndsWith,
    PolarsSelectorMatchKindContains,
}

/// Escapes every regex metacharacter in `s`, mirroring `regex_syntax::is_meta_character`'s table
/// (`\ . + * ? ( ) | [ ] { } ^ $ # & - ~`). `regex-syntax` is only a transitive dependency here
/// (reached via `polars_utils::regex_cache`, which backs `Selector::Matches`' own regex
/// compilation), not a direct one, so this small inline table avoids adding it just for
/// `regex::escape` -- matching CLAUDE.md's "the C ABI layer does the minimum possible" principle.
fn escape_regex_literal(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if matches!(
            c,
            '\\' | '.'
                | '+'
                | '*'
                | '?'
                | '('
                | ')'
                | '|'
                | '['
                | ']'
                | '{'
                | '}'
                | '^'
                | '$'
                | '#'
                | '&'
                | '-'
                | '~'
        ) {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

/// Backs `matches` (verbatim regex) and the regex-sugar `starts_with`/`ends_with`/`contains`
/// (anchored/escaped literal substrings) -- all four build a `Selector::Matches(pattern)`, differing
/// only in how `pattern` is derived from the caller's raw string. Anchoring and escaping happen
/// here, not on the Julia side: Julia has no built-in regex-metacharacter escaper (`escape_string`
/// escapes string *literals*, not regex syntax), so hand-rolling that table would otherwise have
/// to happen twice.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_selector_matches(
    kind: polars_selector_match_kind_t,
    pattern: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let pattern = tri!(read_str(pattern, len));
        let regex_str = match kind {
            polars_selector_match_kind_t::PolarsSelectorMatchKindRegex => pattern.to_string(),
            polars_selector_match_kind_t::PolarsSelectorMatchKindStartsWith => {
                format!("^{}", escape_regex_literal(pattern))
            }
            polars_selector_match_kind_t::PolarsSelectorMatchKindEndsWith => {
                format!("{}$", escape_regex_literal(pattern))
            }
            polars_selector_match_kind_t::PolarsSelectorMatchKindContains => {
                escape_regex_literal(pattern)
            }
        };
        *out = make_expr(Expr::Selector(Selector::Matches(PlSmallStr::from_string(
            regex_str,
        ))));
        std::ptr::null()
    })
}

/// Zero-argument `DataTypeSelector` leaves. `Datetime`/`Duration`/`List`/`Array` match any
/// unit/timezone rather than a specific one; List/Array do not support inner-selector composition.
#[repr(C)]
#[allow(dead_code)]
pub enum polars_dtype_selector_kind_t {
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
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_selector_dtype_simple(
    kind: polars_dtype_selector_kind_t,
) -> *const polars_expr_t {
    use polars_dtype_selector_kind_t::*;
    let dts = match kind {
        PolarsDtypeSelectorKindNumeric => DataTypeSelector::Numeric,
        PolarsDtypeSelectorKindInteger => DataTypeSelector::Integer,
        PolarsDtypeSelectorKindUnsignedInteger => DataTypeSelector::UnsignedInteger,
        PolarsDtypeSelectorKindSignedInteger => DataTypeSelector::SignedInteger,
        PolarsDtypeSelectorKindFloat => DataTypeSelector::Float,
        PolarsDtypeSelectorKindEnum => DataTypeSelector::Enum,
        PolarsDtypeSelectorKindCategorical => DataTypeSelector::Categorical,
        PolarsDtypeSelectorKindNested => DataTypeSelector::Nested,
        PolarsDtypeSelectorKindStruct => DataTypeSelector::Struct,
        PolarsDtypeSelectorKindDecimal => DataTypeSelector::Decimal,
        PolarsDtypeSelectorKindTemporal => DataTypeSelector::Temporal,
        PolarsDtypeSelectorKindObject => DataTypeSelector::Object,
        PolarsDtypeSelectorKindDatetime => {
            DataTypeSelector::Datetime(TimeUnitSet::all(), TimeZoneSet::Any)
        }
        PolarsDtypeSelectorKindDuration => DataTypeSelector::Duration(TimeUnitSet::all()),
        PolarsDtypeSelectorKindList => DataTypeSelector::List(None),
        PolarsDtypeSelectorKindArray => DataTypeSelector::Array(None, None),
    };
    make_expr(Expr::Selector(Selector::ByDType(dts)))
}

/// `ByDType(AnyOf([...]))` -- backs `string`/`boolean`/`binary`/`date`/`time` (dtypes with no
/// dedicated `DataTypeSelector` variant, so they must route through `AnyOf` rather than
/// `dtype_simple` above) and the explicit `by_dtype([...])`. Fallible per-element: `to_dtype`
/// rejects type codes that need parameters it can't carry (Datetime/Duration/Decimal/List/Struct)
/// -- see `polars_value_type_t::to_dtype`'s own doc. That is intentional here too: those
/// parametrized dtypes are reached via `dtype_simple` instead, so hitting this error path from
/// e.g. `by_dtype([Datetime])` is a real, expected error, not a bug.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_selector_dtype_any_of(
    value_types: *const polars_value_type_t,
    n: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    guard_error(|| {
        let mut dtypes: Vec<DataType> = Vec::with_capacity(n);
        if n > 0 {
            for vt in std::slice::from_raw_parts(value_types, n) {
                dtypes.push(tri!(vt.to_dtype()));
            }
        }
        *out = make_expr(Expr::Selector(Selector::ByDType(DataTypeSelector::AnyOf(
            dtypes.into(),
        ))));
        std::ptr::null()
    })
}

/// Extracts the `Selector` inside an `Expr::Selector(...)`, or a clear error otherwise. Backs the
/// combinators below, which the gap-closure plan deliberately restricts to Selector-Selector
/// operands only: mixing in a bare `Expr` (e.g. `Selectors.numeric() | col("x")`) is rejected
/// rather than silently promoted (a `col("x")` reasonably *could* mean `by_name("x")`, but that
/// promotion is a deliberate follow-up, not an accident -- see the plan). Note this deliberately
/// does *not* use upstream `Expr::try_into_selector`, which treats a bare `Expr::Column` as an
/// implicit single-name selector -- exactly the silent promotion this is meant to reject. The
/// Julia side already raises a `MethodError` before ever reaching here (no `Base.|(::Selector,
/// ::Expr)` method exists), so this is a backstop for anyone calling the C ABI directly.
unsafe fn expect_selector(expr: *const polars_expr_t) -> Result<Selector, String> {
    match &(*expr).inner {
        Expr::Selector(s) => Ok(s.clone()),
        _ => Err(
            "selector combinators require both operands to be Selectors (e.g. from \
             Polars.Selectors), not a plain expression"
                .to_string(),
        ),
    }
}

macro_rules! gen_selector_combinator {
    ($n: ident, $variant: ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            b: *const polars_expr_t,
            out: *mut *const polars_expr_t,
        ) -> *const polars_error_t {
            guard_error(|| {
                let sa = tri!(expect_selector(a));
                let sb = tri!(expect_selector(b));
                *out = make_expr(Expr::Selector(Selector::$variant(
                    Arc::new(sa),
                    Arc::new(sb),
                )));
                std::ptr::null()
            })
        }
    };
}

gen_selector_combinator!(polars_expr_selector_union, Union);
gen_selector_combinator!(polars_expr_selector_difference, Difference);
gen_selector_combinator!(polars_expr_selector_exclusive_or, ExclusiveOr);
gen_selector_combinator!(polars_expr_selector_intersect, Intersect);
