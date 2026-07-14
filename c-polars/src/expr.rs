use polars::{lazy::dsl::string::StringNameSpace, lazy::dsl::ListNameSpace, prelude::*};

use crate::{value::polars_value_type_t, *};

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
pub unsafe extern "C" fn polars_expr_literal_utf8(
    s: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let value = match std::str::from_utf8(std::slice::from_raw_parts(s, len)) {
        Ok(value) => value,
        Err(err) => return make_error(err),
    };
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
    let name = match std::str::from_utf8(std::slice::from_raw_parts(name, len)) {
        Ok(value) => value,
        Err(err) => return make_error(err),
    };
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
    return std::ptr::null();
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_alias(
    expr: *const polars_expr_t,
    name: *const u8,
    len: usize,
    out: *mut *const polars_expr_t,
) -> *const polars_error_t {
    let name = match std::str::from_utf8(std::slice::from_raw_parts(name, len)) {
        Ok(value) => value,
        Err(err) => return make_error(err),
    };
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
    let name = match std::str::from_utf8(std::slice::from_raw_parts(name, len)) {
        Ok(value) => value,
        Err(err) => return make_error(err),
    };
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
    let name = match std::str::from_utf8(std::slice::from_raw_parts(name, len)) {
        Ok(value) => value,
        Err(err) => return make_error(err),
    };
    let aliased = (*expr).inner.clone().name().suffix(name);
    *out = make_expr(aliased);
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_keep_name(expr: *const polars_expr_t) -> *const polars_expr_t {
    let aliased = (*expr).inner.clone().name().keep();
    return make_expr(aliased);
}

#[no_mangle]
pub unsafe extern "C" fn polars_expr_cast(
    expr: *const polars_expr_t,
    dtype: polars_value_type_t,
) -> *const polars_expr_t {
    let expr = (*expr).inner.clone();
    make_expr(cast(expr, dtype.to_dtype()))
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
    let partition_by: Vec<Expr> = std::slice::from_raw_parts(partition_by, n_partition_by)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect();
    let expr = (*expr).inner.clone();
    let result = match expr.over(partition_by) {
        Ok(result) => result,
        Err(err) => return make_error(err),
    };
    *out = make_expr(result);
    std::ptr::null()
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

gen_impl_expr!(polars_expr_n_unique, Expr::n_unique);
gen_impl_expr!(polars_expr_unique, Expr::unique);
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
pub unsafe extern "C" fn polars_expr_implode(expr: *const polars_expr_t) -> *const polars_expr_t {
    let expr = &(*expr).inner;
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
gen_impl_expr_binary!(polars_expr_is_in, |a, b| Expr::is_in(a, b, false));

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
            let expr = $t((*a).inner.clone().list(), ((*b).inner.clone()));
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
// gen_impl_expr_str!(polars_expr_str_explode, StringNameSpace::explode);

macro_rules! gen_impl_expr_binary_str {
    ($n: ident, $t: expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            a: *const polars_expr_t,
            b: *const polars_expr_t,
        ) -> *const polars_expr_t {
            let expr = $t((*a).inner.clone().str(), ((*b).inner.clone()));
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

#[no_mangle]
pub unsafe extern "C" fn polars_expr_struct_field_by_name(
    a: *const polars_expr_t,
    name: *const u8,
    len: usize,
) -> *const polars_expr_t {
    let name = std::slice::from_raw_parts(name, len);
    let Ok(name) = std::str::from_utf8(name) else {
        return std::ptr::null();
    };
    let expr = (*a).inner.clone().struct_().field_by_name(name);
    make_expr(expr)
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
) -> *const polars_expr_t {
    let names = std::slice::from_raw_parts(names, num_names);
    let lens = std::slice::from_raw_parts(lens, num_names);

    let names: Vec<String> = names
        .iter()
        .zip(lens)
        .map(|(name, len)| {
            std::str::from_utf8_unchecked(std::slice::from_raw_parts(*name, *len)).to_owned()
        })
        .collect();

    let expr = (*a).inner.clone().struct_().rename_fields(names);
    make_expr(expr)
}
