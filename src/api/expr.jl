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
