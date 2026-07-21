use std::sync::Arc;

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
    ffi_util::{
        read_bool_mask, read_exprs, read_i64_array, read_names, read_opt_str, read_str,
        selector_by_name,
    },
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

/// Targeted cast to `Datetime(unit, tz)` -- `polars_value_type_t::to_dtype` deliberately rejects
/// this (it needs parameters a plain type code can't carry). `tz_len == 0` casts to a naive
/// (timezone-less) Datetime, matching `read_opt_str`'s null-means-None convention.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_cast_datetime(
    expr: *const polars_expr_t,
    unit: polars_time_unit_t,
    tz: *const u8,
    tz_len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let unit = tri!(unit.to_time_unit());
    let tz = tri!(read_opt_str(tz, tz_len));
    let time_zone = tri!(TimeZone::opt_try_new(tz));
    let dtype = DataType::Datetime(unit, time_zone);
    *out = make_expr(cast((*expr).inner.clone(), dtype));
    std::ptr::null()
}

/// Targeted cast to `Duration(unit)` -- see `polars_expr_cast_datetime`'s doc for why this needs
/// its own entry point rather than going through the plain type-code `cast`.
#[no_mangle]
pub unsafe extern "C" fn polars_expr_cast_duration(
    expr: *const polars_expr_t,
    unit: polars_time_unit_t,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let unit = tri!(unit.to_time_unit());
    let dtype = DataType::Duration(unit);
    *out = make_expr(cast((*expr).inner.clone(), dtype));
    std::ptr::null()
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

/// Targeted cast to `Categorical`, using the global category registry (`Categories::global()`,
/// the same one every other Categorical column in a session shares -- matching py-polars'
/// default). Reading a Categorical column back already materializes it as `String` (see
/// `polars_value_type_t::from_dtype`), so no new read path is needed for the round trip.
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

/// Chained `when(c1).then(v1).when(c2).then(v2)....otherwise(otherwise)`, flattened into two
/// parallel expr-slices (`conds`/`vals`) + a final `otherwise` -- no new builder-type FFI handle
/// is needed since `When`/`Then`/`ChainedWhen`/`ChainedThen` all fold to a single right-nested
/// `Expr::Ternary` chain, buildable directly with the existing `when`/`Then::otherwise` free
/// functions already used by `polars_expr_when_then_otherwise` above. `n == 0` degenerates to
/// `otherwise` unchanged.
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

/// `order_by` is a single optional expr (null = none); `over_with_options` itself supports a
/// `Vec` of order-by columns (folding >1 into a struct key), but a single column covers the
/// common case and avoids pulling in that extra marshalling for now. `partition_by` and
/// `order_by` can't both be empty/null (upstream requires at least one).
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
    let partition_by = read_exprs(partition_by, n_partition_by);
    // Always `Some(..)`, even when empty -- matches the plain `Expr::over`'s own behavior
    // (`self.over_with_options(Some(partition_by), None, ..)`, upstream `dsl/mod.rs`), which
    // this function used to delegate to before gaining order_by/mapping support. An empty
    // partition list is a real, meaningful window spec (the whole frame as one group); making
    // it `None` here would incorrectly trip `over_with_options`'s "at least one of partition_by/
    // order_by" check for the zero-partition-columns case that used to succeed.
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
    let result = tri!(expr.over_with_options(partition_by, order_by, mapping.to_window_mapping()));
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

/// `limit` (Backward/Forward only, ignored otherwise -- see
/// `polars_fill_null_strategy_t::to_fill_null_strategy`) is the optional-scalar null-means-None
/// convention used elsewhere (e.g. `sample_n`'s `seed`).
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

/// `Selector::Empty` -- the identity element for the combinators below (`empty() | s == s`,
/// `empty() & s == empty()`). Not reachable from the public `Selectors` surface on the Julia side
/// in this first cut (see the gap-closure plan's Phase 2 scope note); kept here as a primitive
/// since it is the natural base case underlying `Selector`'s own algebra.
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
    let names = tri!(read_names(names, lens, n));
    *out = make_expr(Expr::Selector(selector_by_name(names, strict)));
    std::ptr::null()
}

/// `Selector::ByIndex` -- 0-based upstream (negative indices already count back from the end via
/// `negative_to_usize` inside `into_columns`, so no extra Rust-side handling is needed here). The
/// Julia-facing `Selectors.by_index` is 1-based (matching this package's own `nth`) and converts
/// down to this 0-based primitive before calling in -- see that function's docstring.
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
}

/// Zero-Julia-arg `DataTypeSelector` leaves. Includes four variants that are parametrized in Rust
/// but exposed "any unit/any tz"-only from Julia (`Datetime`/`Duration`/`List`/`Array`) -- see the
/// gap-closure plan's Phase 2 first-cut scope exclusions: no specific time-unit/zone matching, no
/// recursive List/Array inner-selector composition in this cut.
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
            let sa = tri!(expect_selector(a));
            let sb = tri!(expect_selector(b));
            *out = make_expr(Expr::Selector(Selector::$variant(
                Arc::new(sa),
                Arc::new(sb),
            )));
            std::ptr::null()
        }
    };
}

gen_selector_combinator!(polars_expr_selector_union, Union);
gen_selector_combinator!(polars_expr_selector_difference, Difference);
gen_selector_combinator!(polars_expr_selector_exclusive_or, ExclusiveOr);
gen_selector_combinator!(polars_expr_selector_intersect, Intersect);
