function _join_coalesce_enum(coalesce::Symbol)
    coalesce == :join_specific && return API.PolarsJoinCoalesceJoinSpecific
    coalesce == :coalesce_columns && return API.PolarsJoinCoalesceCoalesceColumns
    coalesce == :keep_columns && return API.PolarsJoinCoalesceKeepColumns
    return error(
        "unknown coalesce $coalesce, expected one of (:join_specific, :coalesce_columns, :keep_columns)"
    )
end

function _join_validation_enum(validate::Symbol)
    validate == :many_to_many && return API.PolarsJoinValidationManyToMany
    validate == :many_to_one && return API.PolarsJoinValidationManyToOne
    validate == :one_to_many && return API.PolarsJoinValidationOneToMany
    validate == :one_to_one && return API.PolarsJoinValidationOneToOne
    return error(
        "unknown validate $validate, expected one of (:many_to_many, :many_to_one, :one_to_many, :one_to_one)"
    )
end

function _join_maintain_order_enum(maintain_order::Symbol)
    maintain_order == :none && return API.PolarsMaintainOrderJoinNone
    maintain_order == :left && return API.PolarsMaintainOrderJoinLeft
    maintain_order == :right && return API.PolarsMaintainOrderJoinRight
    maintain_order == :left_right && return API.PolarsMaintainOrderJoinLeftRight
    maintain_order == :right_left && return API.PolarsMaintainOrderJoinRightLeft
    return error(
        "unknown maintain_order $maintain_order, expected one of (:none, :left, :right, :left_right, :right_left)"
    )
end

function _join(
        a::LazyFrame, b::LazyFrame, exprs_a::Vector, exprs_b::Vector, how;
        suffix::Union{Nothing, AbstractString} = nothing,
        coalesce::Symbol = :join_specific,
        validate::Symbol = :many_to_many,
        nulls_equal::Bool = false,
        maintain_order::Symbol = :none
    )
    # No `slice` keyword: polars panics on `JoinArgs.slice` ("impl error: slice is not handled").
    # The FFI parameter is always null.
    exprs_a = _expr_vector(exprs_a)
    exprs_b = _expr_vector(exprs_b)
    coalesce_enum = _join_coalesce_enum(coalesce)
    validate_enum = _join_validation_enum(validate)
    maintain_order_enum = _join_maintain_order_enum(maintain_order)
    suffix_arg = suffix === nothing ? Ptr{UInt8}(C_NULL) : suffix
    suffix_len = suffix === nothing ? 0 : ncodeunits(suffix)
    GC.@preserve exprs_a exprs_b begin
        exprs_a_ptr = Ptr{polars_expr_t}[expr.ptr for expr in exprs_a]
        exprs_b_ptr = Ptr{polars_expr_t}[expr.ptr for expr in exprs_b]
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_join(
            a, b,
            exprs_a_ptr, length(exprs_a_ptr),
            exprs_b_ptr, length(exprs_b_ptr),
            how, suffix_arg, suffix_len, coalesce_enum, validate_enum, nulls_equal,
            maintain_order_enum,
            Ptr{Int64}(C_NULL), Ptr{Csize_t}(C_NULL), out,
        )
        polars_error(err)
    end
    return LazyFrame(out[])
end

for (jl_name, how, description) in (
        (:innerjoin, :PolarsJoinTypeInner, "Inner join"),
        (:leftjoin, :PolarsJoinTypeLeft, "Left outer join"),
        (:rightjoin, :PolarsJoinTypeRight, "Right outer join"),
        (:outerjoin, :PolarsJoinTypeFull, "Full outer join"),
        (:semijoin, :PolarsJoinTypeSemi, "Left semi join"),
        (:antijoin, :PolarsJoinTypeAnti, "Left anti join"),
    )
    doc = """
        $jl_name(a, b, on; suffix=nothing, coalesce=:join_specific, validate=:many_to_many, nulls_equal=false)
        $jl_name(a, b, on_a, on_b; kwargs...)

    $description `a` with `b`.

    Matches on the values of the expressions `on_a` and `on_b` (or `on` for both): a column name,
    an expression, or a `Vector` of them. `a` and `b` are both `DataFrame`s or both `LazyFrame`s.

    - `suffix`: appended to right-side column names that collide (`"_right"` if `nothing`).
    - `coalesce`: `:join_specific` (default), `:coalesce_columns` or `:keep_columns`.
    - `validate`: check the join keys are `:many_to_many` (default, no check), `:many_to_one`,
      `:one_to_many` or `:one_to_one`.
    - `nulls_equal`: whether null keys match each other.
    - `maintain_order`: `:none` (default), `:left`, `:right`, `:left_right` or `:right_left`.
    """
    @eval begin
        $jl_name(a, b, expr; kwargs...) = $jl_name(a, b, expr, expr; kwargs...)
        $jl_name(a::DataFrame, b::DataFrame, exprs_a, exprs_b; kwargs...) =
            $jl_name(lazy(a), lazy(b), exprs_a, exprs_b; kwargs...) |> collect
        $jl_name(a::LazyFrame, b::LazyFrame, expr_a, expr_b; kwargs...) =
            $jl_name(a, b, [expr_a], [expr_b]; kwargs...)
        $jl_name(a::LazyFrame, b::LazyFrame, exprs_a::Vector, exprs_b::Vector; kwargs...) =
            _join(a, b, exprs_a, exprs_b, API.$how; kwargs...)
        @doc $doc $jl_name
    end
end

"""
    crossjoin(a::LazyFrame, b::LazyFrame; suffix=nothing, maintain_order=:none)::LazyFrame
    crossjoin(a::DataFrame, b::DataFrame; suffix=nothing, maintain_order=:none)::DataFrame

Creates the Cartesian product from both frames. `suffix` and `maintain_order` are as in
[`innerjoin`](@ref).
"""
crossjoin(a::DataFrame, b::DataFrame; kwargs...) = crossjoin(lazy(a), lazy(b); kwargs...) |> collect
crossjoin(
    a::LazyFrame, b::LazyFrame; suffix::Union{Nothing, AbstractString} = nothing,
    maintain_order::Symbol = :none
) = _join(a, b, Expr[], Expr[], API.PolarsJoinTypeCross; suffix, maintain_order)

"""
    join_asof(a, b, on; by=String[], by_left=String[], by_right=String[], strategy::Symbol=:backward,
              tolerance=nothing, allow_eq::Bool=true, check_sortedness::Bool=true,
              suffix=nothing, nulls_equal::Bool=false)

Asof join: match each row of `a` to the nearest key in `b`, on sorted `on` columns.

- `strategy`: `:backward` (default), `:forward` or `:nearest`.
- `by`, or `by_left` and `by_right`: match only within these groups.
- `tolerance`: a duration string such as `"5m"`; matches further away give nulls.
- `allow_eq`: whether equal keys match.
- `check_sortedness`: check that `on` is sorted.
- `suffix`, `nulls_equal`, `maintain_order`: as in [`innerjoin`](@ref).

Note: only a duration-string `tolerance` is supported.
"""
function join_asof(
        a, b, on;
        by::Vector{<:ColId} = String[],
        by_left::Vector{<:ColId} = String[], by_right::Vector{<:ColId} = String[],
        strategy::Symbol = :backward,
        tolerance::Union{Nothing, AbstractString} = nothing,
        allow_eq::Bool = true,
        check_sortedness::Bool = true,
        suffix::Union{Nothing, AbstractString} = nothing,
        nulls_equal::Bool = false,
        maintain_order::Symbol = :none
    )
    return join_asof(
        a, b, on, on; by, by_left, by_right, strategy, tolerance, allow_eq, check_sortedness,
        suffix, nulls_equal, maintain_order
    )
end
function join_asof(
        a::DataFrame, b::DataFrame, on_a, on_b;
        by::Vector{<:ColId} = String[],
        by_left::Vector{<:ColId} = String[], by_right::Vector{<:ColId} = String[],
        strategy::Symbol = :backward,
        tolerance::Union{Nothing, AbstractString} = nothing,
        allow_eq::Bool = true,
        check_sortedness::Bool = true,
        suffix::Union{Nothing, AbstractString} = nothing,
        nulls_equal::Bool = false,
        maintain_order::Symbol = :none
    )
    return join_asof(
        lazy(a), lazy(b), on_a, on_b; by, by_left, by_right, strategy, tolerance, allow_eq,
        check_sortedness, suffix, nulls_equal, maintain_order
    ) |> collect
end
function join_asof(
        a::LazyFrame, b::LazyFrame, on_a, on_b;
        by::Vector{<:ColId} = String[],
        by_left::Vector{<:ColId} = String[], by_right::Vector{<:ColId} = String[],
        strategy::Symbol = :backward,
        tolerance::Union{Nothing, AbstractString} = nothing,
        allow_eq::Bool = true,
        check_sortedness::Bool = true,
        suffix::Union{Nothing, AbstractString} = nothing,
        nulls_equal::Bool = false,
        maintain_order::Symbol = :none
    )
    if !isempty(by)
        (isempty(by_left) && isempty(by_right)) || throw(
            ArgumentError(
                "give either `by` (the same grouping columns on both sides) or " *
                    "`by_left`/`by_right` (different names per side), not both"
            )
        )
        by_left = by
        by_right = by
    end
    on_a = _as_expr(on_a)
    on_b = _as_expr(on_b)
    strategy_enum = if strategy == :backward
        API.PolarsAsofStrategyBackward
    elseif strategy == :forward
        API.PolarsAsofStrategyForward
    elseif strategy == :nearest
        API.PolarsAsofStrategyNearest
    else
        error("unknown asof strategy $strategy, expected one of (:backward, :forward, :nearest)")
    end
    by_left_names, by_left_ptrs, by_left_lens = _name_ptrs(by_left)
    by_right_names, by_right_ptrs, by_right_lens = _name_ptrs(by_right)
    tolerance_arg = tolerance === nothing ? Ptr{UInt8}(C_NULL) : tolerance
    tolerance_len = tolerance === nothing ? 0 : ncodeunits(tolerance)
    suffix_arg = suffix === nothing ? Ptr{UInt8}(C_NULL) : suffix
    suffix_len = suffix === nothing ? 0 : ncodeunits(suffix)
    maintain_order_enum = _join_maintain_order_enum(maintain_order)
    GC.@preserve by_left_names by_right_names begin
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_join_asof(
            a, b, on_a, on_b,
            by_left_ptrs, by_left_lens, length(by_left_ptrs),
            by_right_ptrs, by_right_lens, length(by_right_ptrs),
            strategy_enum, tolerance_arg, tolerance_len, allow_eq, check_sortedness,
            suffix_arg, suffix_len, nulls_equal, maintain_order_enum, out,
        )
        polars_error(err)
    end
    return LazyFrame(out[])
end
