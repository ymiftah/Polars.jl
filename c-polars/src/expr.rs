use polars::{lazy::dsl::string::StringNameSpace, lazy::dsl::ListNameSpace, prelude::*};
use polars_core::series::ops::NullBehavior;
use polars_ops::series::round::RoundMode;
use polars_ops::series::InterpolationMethod;
use polars_plan::dsl::dt::DateLikeNameSpace;
use polars_plan::dsl::functions::{
    all_horizontal, any_horizontal, as_struct, coalesce, max_horizontal, mean_horizontal,
    min_horizontal, sum_horizontal,
};
use polars_plan::dsl::DataTypeExpr;
use polars_plan::prelude::Literal;

use crate::{
    ffi_util::{read_bool_mask, read_exprs, read_names, read_opt_str, read_str},
    make_error, polars_error_t,
    types::*,
    value::{polars_time_unit_t, polars_value_type_t},
};

fn make_expr(expr: Expr) -> *const polars_expr_t {
    Box::into_raw(Box::new(polars_expr_t { inner: expr }))
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_destroy(expr: *const polars_expr_t) {
    assert!(!expr.is_null());
    let _ = Box::from_raw(expr.cast_mut());
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
    let value = tri!(read_str(s, len));
    *out = make_expr(Expr::Literal(LiteralValue::Scalar(Scalar::new(
        DataType::String,
        AnyValue::StringOwned(PlSmallStr::from_str(value)),
    ))));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_col(
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let name = tri!(read_str(name, len));
    let expr = col(name);
    *out = make_expr(expr);
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_nth(
    n: i64,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    *out = make_expr(Expr::Selector(nth(n)));
    std::ptr::null()
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
    if n == 0 {
        return make_error("coalesce requires at least one expression");
    }
    let exprs = read_exprs(exprs, n);
    *out = make_expr(coalesce(&exprs));
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_as_struct(
    exprs: *const *const polars_expr_t,
    n: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    if n == 0 {
        return make_error("as_struct requires at least one field");
    }
    let exprs = read_exprs(exprs, n);
    *out = make_expr(as_struct(exprs));
    std::ptr::null()
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
            let exprs = read_exprs(exprs, n);
            match $f(&exprs) {
                Ok(result) => {
                    *out = make_expr(result);
                    std::ptr::null()
                }
                Err(err) => make_error(err),
            }
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
            let exprs = read_exprs(exprs, n);
            match $f(&exprs, ignore_nulls) {
                Ok(result) => {
                    *out = make_expr(result);
                    std::ptr::null()
                }
                Err(err) => make_error(err),
            }
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
    let name = tri!(read_str(name, len));
    let aliased = (*expr).inner.clone().alias(name);
    *out = make_expr(aliased);
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_prefix(
    expr: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let name = tri!(read_str(name, len));
    let aliased = (*expr).inner.clone().name().prefix(name);
    *out = make_expr(aliased);
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_suffix(
    expr: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let name = tri!(read_str(name, len));
    let aliased = (*expr).inner.clone().name().suffix(name);
    *out = make_expr(aliased);
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_keep_name(expr: *const polars_expr_t) -> *const polars_expr_t {
    let aliased = (*expr).inner.clone().name().keep();
    make_expr(aliased)
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_cast(
    expr: *const polars_expr_t,
    dtype: polars_value_type_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    // Fallible since `to_dtype` rejects type codes it cannot encode, rather than silently
    // producing a cast to `Unknown` (see `polars_value_type_t::to_dtype`).
    let dtype = tri!(dtype.to_dtype());
    *out = make_expr(cast((*expr).inner.clone(), dtype));
    std::ptr::null()
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

#[no_mangle]
pub unsafe extern "C" fn polars_expr_over(
    expr: *const polars_expr_t,
    partition_by: *const *const polars_expr_t,
    n_partition_by: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let partition_by = read_exprs(partition_by, n_partition_by);
    let expr = (*expr).inner.clone();
    let result = tri!(expr.over(partition_by));
    *out = make_expr(result);
    std::ptr::null()
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

gen_impl_expr!(polars_expr_sqrt, Expr::sqrt);
gen_impl_expr!(polars_expr_sign, Expr::sign);
gen_impl_expr!(polars_expr_exp, Expr::exp);

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
gen_impl_expr!(polars_expr_count, Expr::count);
gen_impl_expr!(polars_expr_first, Expr::first);
gen_impl_expr!(polars_expr_last, Expr::last);

gen_impl_expr!(polars_expr_not, Expr::not);
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
    let name = tri!(read_str(name, name_len));
    let result = (*expr)
        .inner
        .clone()
        .value_counts(sort, parallel, name, normalize);
    *out = make_expr(result);
    std::ptr::null()
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
pub unsafe extern "C" fn polars_expr_flatten(expr: *const polars_expr_t) -> *const polars_expr_t {
    let expr = &(*expr).inner;
    make_expr(expr.clone().explode(ExplodeOptions {
        empty_as_null: true,
        keep_nulls: true,
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

gen_impl_expr_binary!(polars_expr_fill_null, Expr::fill_null);
gen_impl_expr_binary!(polars_expr_fill_nan, Expr::fill_nan);
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
gen_impl_expr_list!(polars_expr_list_first, ListNameSpace::first);
gen_impl_expr_list!(polars_expr_list_last, ListNameSpace::last);

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
/// e.g. UTC -> "America/New_York". Fails (via the out-param error convention) if `tz` is not a
/// valid IANA time zone name.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_dt_convert_time_zone(
    expr: *const polars_expr_t,
    tz: *const u8,
    tz_len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let tz = tri!(read_str(tz, tz_len));
    let time_zone = match TimeZone::opt_try_new(Some(tz)) {
        Ok(Some(time_zone)) => time_zone,
        Ok(None) => return make_error("invalid time zone"),
        Err(err) => return make_error(err),
    };
    let result = (*expr).inner.clone().dt().convert_time_zone(time_zone);
    *out = make_expr(result);
    std::ptr::null()
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
    let tz = tri!(read_opt_str(tz, tz_len));
    let time_zone = tri!(TimeZone::opt_try_new(tz));
    let result = (*expr).inner.clone().dt().replace_time_zone(
        time_zone,
        (*ambiguous).inner.clone(),
        non_existent.to_non_existent(),
    );
    *out = make_expr(result);
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_dt_strftime(
    expr: *const polars_expr_t,
    format: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let format = tri!(read_str(format, len));
    let result = (*expr).inner.clone().dt().strftime(format);
    *out = make_expr(result);
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_struct_field_by_name(
    a: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let name = tri!(read_str(name, len));
    *out = make_expr((*a).inner.clone().struct_().field_by_name(name));
    std::ptr::null()
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
    // `read_names` validates UTF-8; this previously used `from_utf8_unchecked`, which is UB on
    // invalid input rather than the error every peer function returns.
    let names = tri!(read_names(names, lens, num_names));
    *out = make_expr((*a).inner.clone().struct_().rename_fields(names));
    std::ptr::null()
}
