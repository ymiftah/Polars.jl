"""
    Expr

Expressions that can be used in various contexts.

Don't construct an `Expr` directly; create one with functions such as [`col`](@ref) and
[`lit`](@ref).
"""
mutable struct Expr
    ptr::Ptr{polars_expr_t}

    Expr(ptr) = finalizer(polars_expr_destroy, new(ptr))
end

Base.unsafe_convert(::Type{Ptr{polars_expr_t}}, expr::Expr) = expr.ptr

# Treat `Expr` as a scalar under broadcasting, so `col("x") .> 1` works.
Base.Broadcast.broadcastable(expr::Expr) = Ref(expr)

Base.convert(::Type{Expr}, ::Colon) = col("*")
function Base.convert(::Type{Expr}, v::Int32)
    out = polars_expr_literal_i32(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, v::Int64)
    out = polars_expr_literal_i64(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, v::UInt32)
    out = polars_expr_literal_u32(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, v::UInt64)
    out = polars_expr_literal_u64(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, v::Bool)
    out = polars_expr_literal_bool(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, f::Float32)
    out = polars_expr_literal_f32(f)
    return Expr(out)
end
function Base.convert(::Type{Expr}, f::Float64)
    out = polars_expr_literal_f64(f)
    return Expr(out)
end
function Base.convert(::Type{Expr}, ::Missing)
    out = polars_expr_literal_null()
    return Expr(out)
end
function Base.convert(::Type{Expr}, s::String)
    out = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_literal_utf8(s, ncodeunits(s), out)
    polars_error(err)
    return Expr(out[])
end
function Base.convert(::Type{Expr}, v::AbstractVector)
    df = DataFrame((; literal = collect(v)))
    series = df[:literal]
    out = API.polars_expr_lit_series(series)
    return Expr(out)
end

# Date/Time/DateTime literals are an integer literal cast to the temporal dtype, using the same
# epoch encoding as `arrowvector` (src/arrow/array.jl). `Meta.is_literal` is therefore `false` for
# them.
function Base.convert(::Type{Expr}, d::Date)
    # days since 1970-01-01
    days = Int32(Dates.value(d - Date(1970, 01, 01)))
    return cast(convert(Expr, days), Date)
end
function Base.convert(::Type{Expr}, t::Dates.Time)
    # nanoseconds since midnight
    ns = Int64(Dates.value(t))
    return cast(convert(Expr, ns), Dates.Time)
end
function Base.convert(::Type{Expr}, dt::DateTime)
    # nanoseconds since 1970-01-01; Int64 nanoseconds limit the range to ~1678-2262.
    ns = Dates.Nanosecond(dt - DateTime(1970, 01, 01)).value
    return cast_datetime(convert(Expr, ns); time_unit = :ns, time_zone = nothing)
end

# `<=`/`>=`/`!=` are composed from `eq`/`lt`/`gt` with `not`, which propagates nulls.
_le(a::Expr, b::Expr) = not(gt(a, b))
_ge(a::Expr, b::Expr) = not(Base.lt(a, b))
_neq(a::Expr, b::Expr) = not(eq(a, b))

# Operator overloads. The `Missing` methods resolve ambiguity with Base's `missing` fallbacks and
# turn `missing` into a null literal. `Base.lt` must stay qualified (it collides with an
# unexported Base binding).
for (op, dsl) in (
        (:(==), :eq), (:!=, :_neq),
        (:<, :(Base.lt)), (:<=, :_le),
        (:>, :gt), (:>=, :_ge),
        (:+, :add), (:-, :sub), (:*, :mul), (:/, :div), (:^, :pow),
        (:&, :and), (:|, :or),
    )
    @eval begin
        Base.$op(a::Expr, b::Expr) = $dsl(a, b)
        Base.$op(a::Expr, b) = $dsl(a, convert(Expr, b))
        Base.$op(a, b::Expr) = $dsl(convert(Expr, a), b)
        Base.$op(a::Expr, ::Missing) = $dsl(a, convert(Expr, missing))
        Base.$op(::Missing, b::Expr) = $dsl(convert(Expr, missing), b)
    end
end

"""
    -(expr::Polars.Expr)::Polars.Expr

Negate `Expr`.
"""
Base.:-(expr::Expr) = Expr(API.polars_expr_neg(expr))

"""
    floor_div(a::Polars.Expr, b::Polars.Expr)::Polars.Expr
    floor_div(a, b::Polars.Expr)::Polars.Expr
    floor_div(a::Polars.Expr, b)::Polars.Expr

Floor divide `a` by `b`.
"""
floor_div(a::Expr, b::Expr) = Expr(API.polars_expr_floor_div(a, b))
floor_div(a, b::Expr) = floor_div(convert(Expr, a), b)
floor_div(a::Expr, b) = floor_div(a, convert(Expr, b))
export floor_div

"""
    col(name::Union{String,Symbol})::Polars.Expr

Create a Column Expression based on a column name. `"*"` selects all columns.
"""
function col(name::AbstractString)
    expr = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_col(name, ncodeunits(name), expr)
    polars_error(err)
    return Expr(expr[])
end
col(name::Symbol) = col(String(name))

"""
    _as_expr(x)::Expr

Coerces a column reference to an `Expr`: a `String`/`Symbol` becomes `col(x)`; an `Expr` passes
through. Any other type is a `MethodError`.
"""
_as_expr(x::AbstractString) = col(String(x))
_as_expr(x::Symbol) = col(String(x))
_as_expr(x::Expr) = x

"""
`time_unit` (`:ns`/`:us`/`:ms`) to its C enum.
"""
_time_unit_enum(time_unit::Symbol) = _enum_lookup(
    time_unit, "time_unit",
    :ns => API.PolarsTimeUnitNanosecond,
    :us => API.PolarsTimeUnitMicrosecond,
    :ms => API.PolarsTimeUnitMillisecond,
)

"""
`null_behavior` (`:ignore`/`:drop`) to its C enum.
"""
_null_behavior_enum(null_behavior::Symbol) = _enum_lookup(
    null_behavior, "null_behavior",
    :ignore => API.PolarsNullBehaviorIgnore,
    :drop => API.PolarsNullBehaviorDrop,
)

"""
`closed` window (`:left`/`:right`/`:both`/`:none`) to `polars_closed_window_t`. Not the same
enum as `is_between`'s `polars_closed_interval_t`.
"""
_closed_window_enum(closed::Symbol) = _enum_lookup(
    closed, "closed",
    :left => API.PolarsClosedWindowLeft,
    :right => API.PolarsClosedWindowRight,
    :both => API.PolarsClosedWindowBoth,
    :none => API.PolarsClosedWindowNone,
)

"""
    nth(n::Int64)::Polars.Expr

Nth column in a DataFrame.

Note: `n` is 1-based; negative values count from the end.
"""
function nth(n)
    n_zero = n < 0 ? n : n - 1
    expr = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_nth(n_zero, expr)
    polars_error(err)
    return Expr(expr[])
end

"""
    element()::Polars.Expr

The current element, e.g. the values of the group in [`pivot`](@ref)'s `agg` argument
(`sum(element())`, `first(element())`).
"""
function element()
    return Expr(API.polars_expr_element())
end

"""
    len()::Polars.Expr

Return the number of rows in the context.
"""
function len()
    return Expr(API.polars_expr_len())
end

@wrap_rename_method alias polars_expr_alias "Rename Column."
@wrap_rename_method prefix polars_expr_prefix "Add a prefix to the root column name."
@wrap_rename_method suffix polars_expr_suffix "Add a suffix to the root column name."
@wrap_rename_method prefix_fields polars_expr_prefix_fields "Add a prefix to the field names of a Struct-typed expression."
@wrap_rename_method suffix_fields polars_expr_suffix_fields "Add a suffix to the field names of a Struct-typed expression."

"""
    lit(x)::Polars.Expr

Create a Literal Expression from `x`. A literal expression behaves like a column that contains a
single distinct value.

The column is automatically of the "correct" length to make the operations work.
"""
function lit(v)
    return convert(Expr, v)
end

"""
Maps a Julia type to its parameter-free `polars_value_type_t`, or `nothing`. `DateTime` and
`Period` types need a time unit and are handled by the callers.
"""
function _plain_value_type_code(dtype)
    return if dtype == Missing
        PolarsValueTypeNull
    elseif dtype == Bool
        PolarsValueTypeBoolean
    elseif dtype == UInt8
        PolarsValueTypeUInt8
    elseif dtype == UInt16
        PolarsValueTypeUInt16
    elseif dtype == UInt32
        PolarsValueTypeUInt32
    elseif dtype == UInt64
        PolarsValueTypeUInt64
    elseif dtype == Int8
        PolarsValueTypeInt8
    elseif dtype == Int16
        PolarsValueTypeInt16
    elseif dtype == Int32
        PolarsValueTypeInt32
    elseif dtype == Int64
        PolarsValueTypeInt64
    elseif dtype == Float32
        PolarsValueTypeFloat32
    elseif dtype == Float64
        PolarsValueTypeFloat64
    elseif dtype == String
        PolarsValueTypeString
    elseif dtype == Vector{UInt8}
        PolarsValueTypeBinary
    elseif dtype == Date
        PolarsValueTypeDate
    elseif dtype == Dates.Time
        PolarsValueTypeTime
    else
        nothing
    end
end

"""
    cast(expr::Polars.Expr, dtype::Type; time_unit::Symbol=:us,
         time_zone::Union{Nothing,AbstractString}=nothing, strict::Bool=false)::Polars.Expr
    cast(dtype::Type; kwargs...)::Base.Callable

Cast expression to another data type.

With `strict=true`: throws an error if conversion had overflows.

Supported `dtype`s: `Missing`, the numeric types, `Bool`, `String`, `Vector{UInt8}` (Binary),
`Date`, `Dates.Time`, `DateTime`, and `Dates.Nanosecond`/`Microsecond`/`Millisecond` (Duration).
`time_unit` (`:ns`, `:us`, `:ms`) and `time_zone` apply to a `DateTime` target only.

Note: `strict` has no effect for `DateTime` and Duration targets. Use [`cast_categorical`](@ref)
and [`cast_decimal`](@ref) for those dtypes.
"""
function cast(
        expr, dtype;
        time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing,
        strict::Bool = false
    )
    if dtype == DateTime
        return cast_datetime(expr; time_unit, time_zone)
    elseif dtype == Dates.Nanosecond
        return cast_duration(expr; time_unit = :ns)
    elseif dtype == Dates.Microsecond
        return cast_duration(expr; time_unit = :us)
    elseif dtype == Dates.Millisecond
        return cast_duration(expr; time_unit = :ms)
    end

    value_type = _plain_value_type_code(dtype)
    value_type === nothing && error("could not cast to type $dtype")

    out = Ref{Ptr{polars_expr_t}}()
    err = if strict
        API.polars_expr_strict_cast(expr, value_type, out)
    else
        API.polars_expr_cast(expr, value_type, out)
    end
    polars_error(err)
    return Expr(out[])
end
cast(dtype; kwargs...) = expr -> cast(expr, dtype; kwargs...)

"""
    cast_datetime(expr::Polars.Expr; time_unit::Symbol=:us,
                  time_zone::Union{Nothing,AbstractString}=nothing)::Polars.Expr

Cast expression to `Datetime(time_unit, time_zone)`. Equivalent to
`cast(expr, DateTime; time_unit, time_zone)`.
"""
function cast_datetime(
        expr::Expr; time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing
    )
    unit_enum = _time_unit_enum(time_unit)
    tz = time_zone === nothing ? "" : String(time_zone)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_cast_datetime(expr, unit_enum, tz, ncodeunits(tz), out)
    polars_error(err)
    return Expr(out[])
end

"""
    cast_duration(expr::Polars.Expr; time_unit::Symbol=:us)::Polars.Expr

Cast expression to `Duration(time_unit)`. Equivalent to `cast(expr, Dates.Nanosecond)` etc.
"""
function cast_duration(expr::Expr; time_unit::Symbol = :us)
    unit_enum = _time_unit_enum(time_unit)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_cast_duration(expr, unit_enum, out)
    polars_error(err)
    return Expr(out[])
end
@curry cast_duration(; time_unit::Symbol = :us)

"""
    cast_decimal(expr::Polars.Expr, precision::Integer, scale::Integer)::Polars.Expr
    cast_decimal(precision::Integer, scale::Integer)::Base.Callable

Cast expression to `Decimal(precision, scale)`.

Note: Decimal columns cannot be read back into Julia; cast them to another type first.
"""
function cast_decimal(expr::Expr, precision::Integer, scale::Integer)
    out = API.polars_expr_cast_decimal(expr, Csize_t(precision), Csize_t(scale))
    return Expr(out)
end
@curry cast_decimal(precision::Integer, scale::Integer)

"""
    cast_categorical(expr::Polars.Expr)::Polars.Expr

Cast expression to `Categorical`, using the global categories. A Categorical column is read back
into Julia as `String`.
"""
function cast_categorical(expr::Expr)
    out = API.polars_expr_cast_categorical(expr)
    return Expr(out)
end

"""
    when(cond::Polars.Expr, then, otherwise)::Polars.Expr

Start a `when-then-otherwise` expression. `then`/`otherwise` may be expressions or literals.
"""
function when(cond::Expr, then, otherwise)
    then = convert(Expr, then)
    otherwise = convert(Expr, otherwise)
    out = API.polars_expr_when_then_otherwise(cond, then, otherwise)
    return Expr(out)
end

"""
    when(pairs::Pair...; otherwise)::Polars.Expr

A chained `when-then-otherwise` expression: the first `cond => value` pair whose condition holds
is taken, otherwise `otherwise`. Values may be expressions or literals.

```julia
when(col("x") == 1 => "one", col("x") == 2 => "two"; otherwise = "other")
```
"""
function when(pairs::Pair...; otherwise)
    conds = Expr[convert(Expr, first(p)) for p in pairs]
    vals = Expr[convert(Expr, last(p)) for p in pairs]
    otherwise = convert(Expr, otherwise)
    GC.@preserve conds vals begin
        cond_ptrs = Ptr{polars_expr_t}[c.ptr for c in conds]
        val_ptrs = Ptr{polars_expr_t}[v.ptr for v in vals]
        out = API.polars_expr_when_then(cond_ptrs, val_ptrs, length(cond_ptrs), otherwise)
    end
    return Expr(out)
end

@wrap_simple_ops begin
    gen_impl_expr!(polars_expr_keep_name, Expr::keep_name, "Keep the original root name.")
    gen_impl_expr!(polars_expr_to_lowercase, Expr::to_lowercase, "Update the root column name to use lowercase characters.")
    gen_impl_expr!(polars_expr_to_uppercase, Expr::to_uppercase, "Update the root column name to use uppercase characters.")

    gen_impl_expr!(polars_expr_sum, Expr::sum, "Reduce groups to the sum of all the values.")
    gen_impl_expr!(polars_expr_min, Expr::min, "Reduce groups to minimal value.")
    gen_impl_expr!(polars_expr_max, Expr::max, "Reduce groups to maximum value.")
    gen_impl_expr!(polars_expr_arg_min, Expr::arg_min, "Get the index value that has the minimum value.\n\nNote: the index is 0-based.")
    gen_impl_expr!(polars_expr_arg_max, Expr::arg_max, "Get the index value that has the maximum value.\n\nNote: the index is 0-based.")
    gen_impl_expr!(polars_expr_nan_min, Expr::nan_min, "Reduce groups to minimal value, propagating `NaN`.")
    gen_impl_expr!(polars_expr_nan_max, Expr::nan_max, "Reduce groups to maximum value, propagating `NaN`.")

    gen_impl_expr!(polars_expr_floor, Expr::floor, "Floor underlying floating point array to the lowest integers smaller or equal to the float value.")
    gen_impl_expr!(polars_expr_ceil, Expr::ceil, "Ceil underlying floating point array to the highest integers smaller or equal to the float value.")
    gen_impl_expr!(polars_expr_abs, Expr::abs, "Convert all values to their absolute/positive value.")
    gen_impl_expr!(polars_expr_cos, Expr::cos, "Compute the cosine of the given expression.")
    gen_impl_expr!(polars_expr_sin, Expr::sin, "Compute the sine of the given expression.")
    gen_impl_expr!(polars_expr_tan, Expr::tan, "Compute the tangent of the given expression.")
    gen_impl_expr!(polars_expr_cosh, Expr::cosh, "Compute the hyperbolic cosine of the given expression.")
    gen_impl_expr!(polars_expr_sinh, Expr::sinh, "Compute the hyperbolic sine of the given expression.")
    gen_impl_expr!(polars_expr_tanh, Expr::tanh, "Compute the hyperbolic tangent of the given expression.")
    gen_impl_expr!(polars_expr_arccos, Expr::arccos, "Compute the inverse cosine of the given expression.")
    gen_impl_expr!(polars_expr_arcsin, Expr::arcsin, "Compute the inverse sine of the given expression.")
    gen_impl_expr!(polars_expr_arctan, Expr::arctan, "Compute the inverse tangent of the given expression.")
    gen_impl_expr!(polars_expr_arccosh, Expr::arccosh, "Compute the inverse hyperbolic cosine of the given expression.")
    gen_impl_expr!(polars_expr_arcsinh, Expr::arcsinh, "Compute the inverse hyperbolic sine of the given expression.")
    gen_impl_expr!(polars_expr_arctanh, Expr::arctanh, "Compute the inverse hyperbolic tangent of the given expression.")
    gen_impl_expr!(polars_expr_cot, Expr::cot, "Compute the cotangent of the given expression.")
    gen_impl_expr!(polars_expr_degrees, Expr::degrees, "Convert from radians to degrees.")
    gen_impl_expr!(polars_expr_radians, Expr::radians, "Convert from degrees to radians.")

    gen_impl_expr!(polars_expr_sqrt, Expr::sqrt, "Compute the square root of the given expression.")
    gen_impl_expr!(polars_expr_cbrt, Expr::cbrt, "Compute the cube root of the given expression.")
    gen_impl_expr!(polars_expr_sign, Expr::sign, "Compute the sign of the given expression.")
    gen_impl_expr!(polars_expr_exp, Expr::exp, "Calculate the exponential of all elements in the input array.")
    gen_impl_expr!(polars_expr_log1p, Expr::log1p, "Compute the natural logarithm of all elements plus one in the input array.")

    gen_impl_expr!(polars_expr_rle, Expr::rle, "Get the lengths of runs of identical values, as a `Struct{len, value}` column.")
    gen_impl_expr!(polars_expr_rle_id, Expr::rle_id, "Similar to [`rle`](@ref), but maps values to run IDs.")

    gen_impl_expr!(polars_expr_n_unique, Expr::n_unique, "Get the number of unique values in the groups.")
    gen_impl_expr!(polars_expr_is_duplicated, Expr::is_duplicated, "Get a mask of duplicated values.")
    gen_impl_expr!(polars_expr_is_unique, Expr::is_unique, "Get a mask of unique values.")
    gen_impl_expr!(polars_expr_is_first_distinct, Expr::is_first_distinct, "Get a mask of the first unique value.")
    gen_impl_expr!(polars_expr_is_last_distinct, Expr::is_last_distinct, "Get a mask of the last unique value.")
    gen_impl_expr!(polars_expr_count, Expr::count, "Count the values of the Series or get counts of the group by operation. Null values are not counted.")
    gen_impl_expr!(polars_expr_first, Expr::first, "Get the first value in the group.")
    gen_impl_expr!(polars_expr_last, Expr::last, "Get the last value in the group.")

    gen_impl_expr!(polars_expr_not, Expr::not, "Negate `Expr`.")
    gen_impl_expr!(polars_expr_is_finite, Expr::is_finite, "Get mask of finite values if dtype is Float.")
    gen_impl_expr!(polars_expr_is_infinite, Expr::is_infinite, "Get mask of infinite values if dtype is Float.")
    gen_impl_expr!(polars_expr_is_nan, Expr::is_nan, "Get mask of NaN values if dtype is Float.")
    gen_impl_expr!(polars_expr_is_null, Expr::is_null, "Run is_null operation on `Expr`.")
    gen_impl_expr!(polars_expr_is_not_null, Expr::is_not_null, "Run is_not_null operation on `Expr`.")
    gen_impl_expr!(polars_expr_null_count, Expr::null_count, "Get the null count of the column/group.")
    gen_impl_expr!(polars_expr_drop_nans, Expr::drop_nans, "Drop NaN values.")
    gen_impl_expr!(polars_expr_drop_nulls, Expr::drop_nulls, "Drop null values.")

    gen_impl_expr!(polars_expr_implode, Expr::implode, "Implode into a list scalar.")
    gen_impl_expr!(polars_expr_reverse, Expr::reverse, "Reverse column.")

    gen_impl_expr!(polars_expr_arg_unique, Expr::arg_unique, "Get the first index of unique values of this expression.\n\nNote: indices are 0-based.")
    gen_impl_expr!(polars_expr_to_physical, Expr::to_physical, "Cast to the physical representation of the dtype (e.g. `Date` to `Int32`).")
    gen_impl_expr!(polars_expr_lower_bound, Expr::lower_bound, "Get minimal value that could be hold by this dtype.")
    gen_impl_expr!(polars_expr_upper_bound, Expr::upper_bound, "Get maximal value that could be hold by this dtype.")

    gen_impl_expr_binary!(polars_expr_eq, Expr::eq, "Compare `Expr` with other `Expr` on equality. Same as `a .== b`.")
    gen_impl_expr_binary!(polars_expr_lt, Expr::lt, "Check if `Expr` < `Expr`. Same as `a .< b`.\n\nNote: not exported; call it as `Base.lt(a, b)`.")
    gen_impl_expr_binary!(polars_expr_gt, Expr::gt, "Check if `Expr` > `Expr`. Same as `a .> b`.")
    gen_impl_expr_binary!(polars_expr_or, Expr::or, "Bitwise \"or\" operation. Same as `a .| b`.")
    gen_impl_expr_binary!(polars_expr_xor, Expr::xor, "Bitwise \"xor\" operation.")
    gen_impl_expr_binary!(polars_expr_and, Expr::and, "Bitwise \"and\" operation. Same as `a .& b`.")

    gen_impl_expr_binary!(polars_expr_pow, Expr::pow, "Raise expression to the power `b`. Same as `a ^ b`.")
    gen_impl_expr_binary!(polars_expr_add, Expr::add, "Add `b` to `a`. Same as `a + b`.")
    gen_impl_expr_binary!(polars_expr_sub, Expr::sub, "Subtract `b` from `a`. Same as `a - b`.")
    gen_impl_expr_binary!(polars_expr_mul, Expr::mul, "Multiply `a` by `b`. Same as `a * b`.")
    gen_impl_expr_binary!(polars_expr_div, Expr::div, "Divide `a` by `b`. Same as `a / b`.")

    gen_impl_expr_binary!(polars_expr_fill_null, Expr::fill_null, "Replace the null values by a value.\n\n!!! note \"Has a curried form\"\n    `fill_null(value)`, for `|>` pipelines."; curried = true)
    gen_impl_expr_binary!(polars_expr_fill_nan, Expr::fill_nan, "Replace the floating point `NaN` values by a value.\n\n!!! note \"Has a curried form\"\n    `fill_nan(value)`, for `|>` pipelines."; curried = true)
    gen_impl_expr_binary!(polars_expr_is_in, Expr::is_in, "Check if the values of the left expression are in the lists of the right expr.\n\n!!! note \"Has a curried form\"\n    `is_in(values)`, for `|>` pipelines. A `Vector` of values is imploded into a list."; curried = true)

    gen_impl_expr_binary!(polars_expr_shift, Expr::shift, "Shift the values in the array by some period.\n\n!!! note \"Has a curried form\"\n    `shift(n)`, for `|>` pipelines."; curried = true)
    gen_impl_expr_binary!(polars_expr_pct_change, Expr::pct_change, "Computes percentage change between values.\n\n!!! note \"Has a curried form\"\n    `pct_change(n)`, for `|>` pipelines."; curried = true)

    gen_impl_expr_binary!(polars_expr_rem, Expr::rem, "Remainder of `a` divided by `b`. Same as `a % b`.")

    gen_impl_expr_binary!(polars_expr_arctan2, Expr::arctan2, "Compute the inverse tangent of the given expression, with the angle expressed as the argument of a complex number.\n\n`arctan2(y, x)`, in radians.")
    gen_impl_expr_binary!(polars_expr_dot, Expr::dot, "Compute the dot/inner product between two expressions.")
end

"""
    entropy(expr::Polars.Expr; base::Real=ℯ, normalize::Bool=true)::Polars.Expr
    entropy(; base::Real=ℯ, normalize::Bool=true)

Compute the entropy as `-sum(pk * log(pk))` where `pk` are discrete probabilities.

!!! note "Has a curried form"
    The keyword-only method above, for `|>` pipelines.
"""
function entropy(expr::Expr; base::Real = ℯ, normalize::Bool = true)
    return Expr(API.polars_expr_entropy(expr, Float64(base), normalize))
end
@curry entropy(; base::Real = ℯ, normalize::Bool = true)

"""
    extend_constant(expr::Polars.Expr, value, n)::Polars.Expr

Extend the column with `n` copies of `value`. `value` may be `missing`.
"""
function extend_constant(expr::Expr, value, n)
    return Expr(
        API.polars_expr_extend_constant(expr, convert(Expr, value), convert(Expr, n)),
    )
end

"""
    shuffle(expr::Polars.Expr; seed::Union{Nothing,Integer}=nothing)::Polars.Expr

Shuffle the values. `seed = nothing` uses a random seed.
"""
function shuffle(expr::Expr; seed::Union{Nothing, Integer} = nothing)
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
    out = GC.@preserve seed_ref API.polars_expr_shuffle(expr, seed_ref)
    return Expr(out)
end

"""
    reshape(expr::Polars.Expr, dims::Integer...)::Polars.Expr

Reshape the column into an `Array` column of the given dimensions. Only the first dimension may
be `-1` (inferred).

Note: `Array` columns cannot be read back into Julia, and `collect_schema` fails on a frame that
contains one. Cast the result to another type before reading it.
"""
function Base.reshape(expr::Expr, dims::Integer...)
    dims_vec = Int64[Int64(d) for d in dims]
    out = GC.@preserve dims_vec API.polars_expr_reshape(expr, pointer(dims_vec), length(dims_vec))
    return Expr(out)
end

export entropy, extend_constant, shuffle

"""
    unique(expr::Polars.Expr; maintain_order::Bool=false)::Polars.Expr

Get unique values of this expression. With `maintain_order=true`, the order of first appearance
is kept (this requires more work).
"""
Base.unique(expr::Expr; maintain_order::Bool = false) =
    Expr(maintain_order ? API.polars_expr_unique_stable(expr) : API.polars_expr_unique(expr))

@wrap_expr_method flatten(expr::Expr; empty_as_null::Bool = true, keep_nulls::Bool = true) polars_expr_flatten "Explode the List column. `empty_as_null`: an empty list produces a null row. `keep_nulls`: a null list produces a null row."
export flatten

"""
    all(expr::Polars.Expr; ignore_nulls::Bool=true)::Polars.Expr

Returns whether all values in the column are `true`.

If `ignore_nulls` is `false`, [Kleene logic](https://en.wikipedia.org/wiki/Three-valued_logic) is
used to deal with nulls: if the column contains any null values and no `false` values, the output
is null.
"""
Base.all(expr::Expr; ignore_nulls::Bool = true) = Expr(API.polars_expr_all(expr, ignore_nulls))

"""
    any(expr::Polars.Expr; ignore_nulls::Bool=true)::Polars.Expr

Returns whether any of the values in the column are `true`.

If `ignore_nulls` is `false`, [Kleene logic](https://en.wikipedia.org/wiki/Three-valued_logic) is
used to deal with nulls: if the column contains any null values and no `true` values, the output
is null.
"""
Base.any(expr::Expr; ignore_nulls::Bool = true) = Expr(API.polars_expr_any(expr, ignore_nulls))

"""
    log(base::Polars.Expr, x::Polars.Expr)::Polars.Expr

Compute the logarithm to a given base.

Note: the base is the first argument, as in `Base.log(b, x)`.
"""
function Base.log(base::Expr, x::Expr)
    out = API.polars_expr_log(x, base)
    return Expr(out)
end

"""
    log10(expr::Polars.Expr)::Polars.Expr

Compute the logarithm to base 10.
"""
Base.log10(expr::Expr) = log(convert(Expr, 10), expr)

"""
    has_nulls(expr::Polars.Expr)::Polars.Expr

Whether the column/group contains any null value.
"""
has_nulls(expr::Expr) = null_count(expr) > 0
export has_nulls

# `is_in(values::AbstractVector)` implodes the values into one list literal; `convert` alone would
# build a per-row Series literal.
is_in(other::AbstractVector) = Base.Fix2(is_in, implode(convert(Expr, other)))

# `log`/`rem`/`replace`/`diff`/`round` have no curried form: one accepting bare literals would be
# type piracy on Base.

"""
    fill_null(expr::Polars.Expr; strategy::Symbol, limit::Union{Nothing,Integer}=nothing)::Polars.Expr
    fill_null(; strategy::Symbol, limit::Union{Nothing,Integer}=nothing)

Replace the null values using a fill strategy: `:forward`, `:backward`, `:mean`, `:min`, `:max`,
`:zero` or `:one`. `limit` is the maximum number of consecutive nulls to fill, for `:forward` and
`:backward` only.

!!! note "Has a curried form"
    The keyword-only method above, for `|>` pipelines.
"""
function fill_null(expr::Expr; strategy::Symbol, limit::Union{Nothing, Integer} = nothing)
    strategy_enum = _enum_lookup(
        strategy, "fill_null strategy",
        :backward => API.PolarsFillNullStrategyBackward,
        :forward => API.PolarsFillNullStrategyForward,
        :mean => API.PolarsFillNullStrategyMean,
        :min => API.PolarsFillNullStrategyMin,
        :max => API.PolarsFillNullStrategyMax,
        :zero => API.PolarsFillNullStrategyZero,
        :one => API.PolarsFillNullStrategyOne,
    )
    limit_ref = limit === nothing ? Ptr{UInt32}(C_NULL) : Ref(UInt32(limit))
    out = GC.@preserve limit_ref API.polars_expr_fill_null_with_strategy(expr, strategy_enum, limit_ref)
    return Expr(out)
end
@curry fill_null(; strategy::Symbol, limit::Union{Nothing, Integer} = nothing)

"""
    forward_fill(expr::Polars.Expr; limit::Union{Nothing,Integer}=nothing)::Polars.Expr
    forward_fill(; limit::Union{Nothing,Integer}=nothing)

Fill null values with the last non-null value. Same as `fill_null(expr; strategy=:forward, limit)`.

!!! note "Has a curried form"
    The keyword-only method above, for `|>` pipelines.
"""
forward_fill(expr::Expr; limit::Union{Nothing, Integer} = nothing) = fill_null(expr; strategy = :forward, limit)
@curry forward_fill(; limit::Union{Nothing, Integer} = nothing)

"""
    backward_fill(expr::Polars.Expr; limit::Union{Nothing,Integer}=nothing)::Polars.Expr
    backward_fill(; limit::Union{Nothing,Integer}=nothing)

Fill null values with the next non-null value. Same as `fill_null(expr; strategy=:backward, limit)`.

!!! note "Has a curried form"
    The keyword-only method above, for `|>` pipelines.
"""
backward_fill(expr::Expr; limit::Union{Nothing, Integer} = nothing) = fill_null(expr; strategy = :backward, limit)
@curry backward_fill(; limit::Union{Nothing, Integer} = nothing)

export forward_fill, backward_fill

@wrap_expr_method shift_and_fill(expr::Expr, n::Expr, fill_value::Expr) polars_expr_shift_and_fill "Shift the values in the array by some period and fill the resulting empty values."
export shift_and_fill

"""
    round(expr::Polars.Expr, decimals::Integer=0; mode::Symbol=:half_to_even)::Polars.Expr

Round underlying floating point array to given decimal numbers. `mode` is one of
`:half_to_even` (default), `:half_away_from_zero`, `:to_zero`.
"""
function Base.round(expr::Expr, decimals::Integer = 0; mode::Symbol = :half_to_even)
    mode_enum = _enum_lookup(
        mode, "round mode",
        :half_to_even => API.PolarsRoundModeHalfToEven,
        :half_away_from_zero => API.PolarsRoundModeHalfAwayFromZero,
        :to_zero => API.PolarsRoundModeToZero,
    )
    out = API.polars_expr_round(expr, UInt32(decimals), mode_enum)
    return Expr(out)
end

@wrap_expr_method clip(expr::Expr, min::Expr, max::Expr) polars_expr_clip "Clip underlying values to a set boundary."
@curry clip(min, max)
export clip

@wrap_expr_method clip_min(expr::Expr, min::Expr) polars_expr_clip_min "Clip underlying values to a lower boundary."
@curry clip_min(min)

@wrap_expr_method clip_max(expr::Expr, max::Expr) polars_expr_clip_max "Clip underlying values to an upper boundary."
@curry clip_max(max)

export clip_min, clip_max

"""
    is_between(expr::Polars.Expr, lower_bound, upper_bound; closed::Symbol=:both)::Polars.Expr

Check if the values are between `lower_bound` and `upper_bound`. `closed` (`:both`, `:left`,
`:right`, `:none`) sets which bounds are inclusive.
"""
function is_between(expr::Expr, lower_bound, upper_bound; closed::Symbol = :both)
    lower_bound = convert(Expr, lower_bound)
    upper_bound = convert(Expr, upper_bound)
    closed_enum = _enum_lookup(
        closed, "closed",
        :both => API.PolarsClosedIntervalBoth,
        :left => API.PolarsClosedIntervalLeft,
        :right => API.PolarsClosedIntervalRight,
        :none => API.PolarsClosedIntervalNone,
    )
    out = API.polars_expr_is_between(expr, lower_bound, upper_bound, closed_enum)
    return Expr(out)
end

@curry is_between(lower_bound, upper_bound; closed::Symbol = :both)

export is_between

"""
    replace(expr::Polars.Expr, old, new)::Polars.Expr

Replace the given values with other values.
"""
function Base.replace(expr::Expr, old, new)
    old = convert(Expr, old)
    new = convert(Expr, new)
    out = API.polars_expr_replace(expr, old, new)
    return Expr(out)
end

"""
    replace_strict(expr::Polars.Expr, old, new; default=nothing)::Polars.Expr

Replace the given values with other values. Values not in `old` are replaced by `default`, or
null if `default` is `nothing`.
"""
function replace_strict(expr::Expr, old, new; default = nothing)
    old = convert(Expr, old)
    new = convert(Expr, new)
    default_expr = default === nothing ? nothing : convert(Expr, default)
    default_ptr = default_expr === nothing ? C_NULL : default_expr.ptr
    out = GC.@preserve default_expr API.polars_expr_replace_strict(expr, old, new, default_ptr)
    return Expr(out)
end

@curry replace_strict(old, new; default = nothing)

export replace_strict

"""
    prod(expr::Polars.Expr)::Polars.Expr

Get the product aggregation of an expression.
"""
Base.prod(expr::Expr) = Expr(API.polars_expr_product(expr))


"""
    over(expr::Polars.Expr, partition_by...; mapping_strategy::Symbol=:group_to_rows,
         order_by=nothing, descending::Bool=false, nulls_last::Bool=false)::Polars.Expr

Apply window function over a subgroup. This is similar to a group_by + aggregation + self join.

- `mapping_strategy`: `:group_to_rows` (default), `:explode` or `:join`.
- `order_by`: sort each group by this column or expression before evaluating `expr`;
  `descending`/`nulls_last` control that ordering.
"""
function over(
        expr::Expr, partition_by...;
        mapping_strategy::Symbol = :group_to_rows,
        order_by = nothing,
        descending::Bool = false,
        nulls_last::Bool = false
    )
    partition_by = _expr_vector(partition_by)
    mapping_enum = _enum_lookup(
        mapping_strategy, "over mapping_strategy",
        :group_to_rows => API.PolarsWindowMappingGroupsToRows,
        :explode => API.PolarsWindowMappingExplode,
        :join => API.PolarsWindowMappingJoin,
    )
    order_by_expr = order_by === nothing ? nothing : _as_expr(order_by)
    GC.@preserve partition_by order_by_expr begin
        partition_ptrs = Ptr{polars_expr_t}[p.ptr for p in partition_by]
        order_by_ptr = order_by_expr === nothing ? Ptr{polars_expr_t}(C_NULL) : order_by_expr.ptr
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_over(
            expr, partition_ptrs, length(partition_ptrs), order_by_ptr,
            descending, nulls_last, mapping_enum, out
        )
        polars_error(err)
    end
    return Expr(out[])
end

"""
    over(partition_by::Union{String,Symbol}...; kwargs...)::Base.Callable

Curried form of [`over`](@ref) for use with `|>`, e.g. `sum(col("x")) |> over("g")`.

Note: accepts column names only; call `over(expr, partition_by...)` for expressions.
"""
over(partition_by::Vararg{ColId}; kwargs...) =
    expr -> over(expr, partition_by...; kwargs...)

export over

"""
    sort_by(expr::Polars.Expr, by...; rev=false, nulls_last::Bool=false, maintain_order::Bool=false)::Polars.Expr

Sort this column by the ordering of another column evaluated from given expr. Can also be used
in a group_by context to sort the groups. `rev` is a `Bool` or one `Bool` per `by`.
"""
function sort_by(expr::Expr, by...; rev = false, nulls_last::Bool = false, maintain_order::Bool = false)
    by = _expr_vector(by)
    n_by = length(by)
    descending = rev isa Bool ? fill(rev, n_by) : rev
    length(descending) == n_by || throw(
        ArgumentError(
            "rev must have one entry per by expression (got $n_by by expressions and " *
                "$(length(descending)) rev)"
        )
    )
    GC.@preserve by begin
        by_ptrs = Ptr{polars_expr_t}[e.ptr for e in by]
        out = API.polars_expr_sort_by(expr, by_ptrs, n_by, descending, nulls_last, maintain_order)
    end
    return Expr(out)
end

"""
    sort_by(by::Union{String,Symbol}...; rev=false, nulls_last::Bool=false, maintain_order::Bool=false)::Base.Callable

Curried form of [`sort_by`](@ref) for use with `|>`, e.g. `col("x") |> sort_by("y"; rev=true)`.

Note: accepts column names only; call `sort_by(expr, by...)` for expressions.
"""
function sort_by(by::Vararg{ColId}; rev = false, nulls_last::Bool = false, maintain_order::Bool = false)
    return expr -> sort_by(expr, by...; rev, nulls_last, maintain_order)
end

export sort_by

"""
    arg_sort(expr::Polars.Expr; descending::Bool=false, nulls_last::Bool=false)::Polars.Expr

Get the index values that would sort this expression.

Note: the indices are 0-based.
"""
function arg_sort(expr::Expr; descending::Bool = false, nulls_last::Bool = false)
    out = API.polars_expr_arg_sort(expr, descending, nulls_last)
    return Expr(out)
end

@curry arg_sort(; descending::Bool = false, nulls_last::Bool = false)

export arg_sort

@wrap_expr_method gather(expr::Expr, idx::Expr; null_on_oob::Bool = false) polars_expr_gather "Take values by index.\n\n`null_on_oob`: return a null when an index is out of bounds, instead of an error.\n\nNote: `idx` is 0-based (negative indices count from the end), matching the output of [`arg_sort`](@ref), `arg_min` and `arg_max`."

export gather

@wrap_expr_method gather_every(expr::Expr, n::Integer; offset::Integer = 0) polars_expr_gather_every "Take every `n`th value, starting at `offset`.\n\nNote: `offset` is 0-based."

export gather_every

"""
    filter(expr::Polars.Expr, predicate)::Polars.Expr

Filter a single column.

Should be used in aggregation context. To filter a frame, use `filter` on the frame.
"""
function Base.filter(expr::Expr, predicate)
    predicate = _as_expr(predicate)
    return Expr(API.polars_expr_filter(expr, predicate))
end
# Resolves ambiguity with `Base.filter(f, ::String)`.
Base.filter(expr::Expr, predicate::Union{SubString{String}, String}) =
    Expr(API.polars_expr_filter(expr, _as_expr(predicate)))

"""
    sort(expr::Polars.Expr; rev::Bool=false, nulls_last::Bool=false, multithreaded::Bool=true, maintain_order::Bool=false)::Polars.Expr

Sort with given options.
"""
function Base.sort(
        expr::Expr;
        rev::Bool = false, nulls_last::Bool = false, multithreaded::Bool = true,
        maintain_order::Bool = false
    )
    out = API.polars_expr_sort(expr, rev, nulls_last, multithreaded, maintain_order)
    return Expr(out)
end

"""
    head(expr::Polars.Expr, n::Union{Nothing,Integer}=nothing)::Polars.Expr

Get the first `n` elements of the Expr result (10 if `n` is `nothing`).
"""
function head(expr::Expr, n::Union{Nothing, Integer} = nothing)
    n_ref = n === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(n))
    out = GC.@preserve n_ref API.polars_expr_head(expr, n_ref)
    return Expr(out)
end

"""
    tail(expr::Polars.Expr, n::Union{Nothing,Integer}=nothing)::Polars.Expr

Get the last `n` elements of the Expr result (10 if `n` is `nothing`).
"""
function Base.tail(expr::Expr, n::Union{Nothing, Integer} = nothing)
    n_ref = n === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(n))
    out = GC.@preserve n_ref API.polars_expr_tail(expr, n_ref)
    return Expr(out)
end

"""
    limit(expr::Polars.Expr, n::Union{Nothing,Integer}=nothing)::Polars.Expr

Alias for [`head`](@ref).
"""
limit(expr::Expr, n::Union{Nothing, Integer} = nothing) = head(expr, n)

export limit

"""
    slice(expr::Polars.Expr, offset, length)::Polars.Expr

Slice the Series.

Note: `offset` is 0-based; a negative `offset` counts from the end.
"""
function slice(expr::Expr, offset, length)
    offset = convert(Expr, offset)
    length = convert(Expr, length)
    out = API.polars_expr_slice(expr, offset, length)
    return Expr(out)
end

export slice

"""
    get(expr::Polars.Expr, index; null_on_oob::Bool=false)::Polars.Expr

Take the values by a single index. `null_on_oob`: return a null when the index is out of bounds,
instead of an error.

Note: `index` is 0-based; negative values count from the end.
"""
function Base.get(expr::Expr, index; null_on_oob::Bool = false)
    index = convert(Expr, index)
    out = API.polars_expr_get(expr, index, null_on_oob)
    return Expr(out)
end

"""
    top_k_by(expr::Polars.Expr, k, by...; rev=false)::Polars.Expr

Returns the `k` largest rows by given column. For single column, use [`top_k`](@ref).

`rev` is a `Bool` or one `Bool` per `by`.
"""
function top_k_by(expr::Expr, k, by...; rev = false)
    k = convert(Expr, k)
    by = _expr_vector(by)
    n_by = length(by)
    descending = rev isa Bool ? fill(rev, n_by) : rev
    length(descending) == n_by || throw(
        ArgumentError(
            "rev must have one entry per by expression (got $n_by by expressions and " *
                "$(length(descending)) rev)"
        )
    )
    GC.@preserve by begin
        by_ptrs = Ptr{polars_expr_t}[e.ptr for e in by]
        out = API.polars_expr_top_k_by(expr, k, by_ptrs, n_by, descending)
    end
    return Expr(out)
end

export top_k_by

"""
    bottom_k_by(expr::Polars.Expr, k, by...; rev=false)::Polars.Expr

Returns the `k` smallest rows by given column. For single column, use `bottom_k`.

`rev` is a `Bool` or one `Bool` per `by`.
"""
function bottom_k_by(expr::Expr, k, by...; rev = false)
    k = convert(Expr, k)
    by = _expr_vector(by)
    n_by = length(by)
    descending = rev isa Bool ? fill(rev, n_by) : rev
    length(descending) == n_by || throw(
        ArgumentError(
            "rev must have one entry per by expression (got $n_by by expressions and " *
                "$(length(descending)) rev)"
        )
    )
    GC.@preserve by begin
        by_ptrs = Ptr{polars_expr_t}[e.ptr for e in by]
        out = API.polars_expr_bottom_k_by(expr, k, by_ptrs, n_by, descending)
    end
    return Expr(out)
end

export bottom_k_by

@wrap_expr_method item(expr::Expr; allow_empty::Bool = false) polars_expr_item "Get the single value in the group. If there are multiple values, an error is returned. With `allow_empty=true`, an empty group gives null."


"""
One argument's contribution to an expression list. A `Vector` argument is flattened one level,
so `sort(df, [:a, :b])` is `sort(df, :a, :b)`.
"""
_expr_flatten(x) = (_as_expr(x),)
_expr_flatten(xs::AbstractVector) = (_as_expr(x) for x in xs)

"""
Coerces column references (names, `Expr`s, `Selector`s, or `Vector`s of those) into a
`Vector{Expr}`.
"""
_expr_vector(args) = Expr[e for arg in args for e in _expr_flatten(arg)]

"""
    coalesce(exprs::Expr...)::Polars.Expr

Folds the expressions from left to right keeping the first non-null values.
"""
function Base.coalesce(first::Expr, rest::Expr...)
    exprs = _expr_vector((first, rest...))
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_coalesce(ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

@wrap_multi_expr_function as_struct polars_expr_as_struct false "Take several expressions and collect them into a Struct column."

export as_struct

@wrap_multi_expr_function concat_list polars_expr_concat_list false "Concat lists entries."

export concat_list

"""
    concat_str(exprs...; separator::AbstractString="", ignore_nulls::Bool=false)::Polars.Expr

Horizontally concat string columns in linear time.

With `ignore_nulls=false`, a null in any input gives a null result.
"""
function concat_str(exprs...; separator::AbstractString = "", ignore_nulls::Bool = false)
    exprs = _expr_vector(exprs)
    separator = String(separator)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_concat_str(
            ptrs, length(ptrs), separator, ncodeunits(separator), ignore_nulls, out
        )
        polars_error(err)
    end
    return Expr(out[])
end

export concat_str

"""
    format(fmt::AbstractString, args...)::Polars.Expr

Format the expressions into `fmt`, with a `{}` placeholder per argument. `args` are expressions
or column names.
"""
function format(fmt::AbstractString, args...)
    exprs = _expr_vector(args)
    fmt = String(fmt)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_format(fmt, ncodeunits(fmt), ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

export format

@wrap_multi_expr_function concat_arr polars_expr_concat_arr false "Horizontally concatenate columns into a single array-type column.\n\nNote: `Array` columns cannot be read back into Julia, and `collect_schema` fails on a frame that contains one."

export concat_arr

@wrap_multi_expr_function all_horizontal polars_expr_all_horizontal false "Create a new column with the bitwise-and of the elements in each row.\n\nThe name of the resulting column will be \"all\"; use [`alias`](@ref) to choose a different name."
@wrap_multi_expr_function any_horizontal polars_expr_any_horizontal false "Create a new column with the bitwise-or of the elements in each row.\n\nThe name of the resulting column will be \"any\"; use [`alias`](@ref) to choose a different name."
@wrap_multi_expr_function min_horizontal polars_expr_min_horizontal false "Create a new column with the minimum value per row.\n\nThe name of the resulting column will be \"min\"; use [`alias`](@ref) to choose a different name."
@wrap_multi_expr_function max_horizontal polars_expr_max_horizontal false "Create a new column with the maximum value per row.\n\nThe name of the resulting column will be \"max\"; use [`alias`](@ref) to choose a different name."
@wrap_multi_expr_function sum_horizontal polars_expr_sum_horizontal true "Sum all values horizontally across columns."
@wrap_multi_expr_function mean_horizontal polars_expr_mean_horizontal true "Compute the mean of all values horizontally across columns."

export all_horizontal, any_horizontal, min_horizontal, max_horizontal, sum_horizontal, mean_horizontal

"""
    interpolate(expr::Polars.Expr; method::Symbol=:linear)::Polars.Expr

Interpolate intermediate values. `method` is `:linear` or `:nearest`. Nulls at the beginning and
end of the series remain null.
"""
function interpolate(expr::Expr; method::Symbol = :linear)
    method_enum = _enum_lookup(
        method, "interpolation method",
        :linear => API.PolarsInterpolationMethodLinear,
        :nearest => API.PolarsInterpolationMethodNearest,
    )
    out = API.polars_expr_interpolate(expr, method_enum)
    return Expr(out)
end

@curry interpolate(; method::Symbol = :linear)

export interpolate

"""
    diff(expr::Polars.Expr, n=1; null_behavior::Symbol=:ignore)::Polars.Expr

Calculate the n-th discrete difference between values. `null_behavior` is `:ignore` or `:drop`.
"""
function Base.diff(expr::Expr, n = 1; null_behavior::Symbol = :ignore)
    n = convert(Expr, n)
    behavior = _null_behavior_enum(null_behavior)
    out = API.polars_expr_diff(expr, n, behavior)
    return Expr(out)
end

export col, alias, prefix, suffix, prefix_fields, suffix_fields, lit, cast, when, element, len,
    cast_datetime, cast_duration, cast_decimal, cast_categorical
