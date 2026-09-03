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
    # No `slice` keyword: `JoinArgs.slice` panics unconditionally in this polars version
    # ("impl error: slice is not handled", verified live against both the in-memory and
    # `:streaming` engines) -- caught by `guard_error`'s `catch_unwind` rather than aborting the
    # process, but there is no working codepath behind it to expose. The FFI parameter stays
    # (always null here) so a future polars upgrade that fixes this needs only a Julia-side change.
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
        (:innerjoin, :PolarsJoinTypeInner, "keeping only rows with a matching key in both frames"),
        (
            :leftjoin, :PolarsJoinTypeLeft,
            "keeping every row of `a`, with `missing` in `b`'s columns where there's no match",
        ),
        (
            :rightjoin, :PolarsJoinTypeRight,
            "keeping every row of `b`, with `missing` in `a`'s columns where there's no match",
        ),
        (
            :outerjoin, :PolarsJoinTypeFull,
            "keeping every row of both `a` and `b`, with `missing` filled in on whichever side has no match",
        ),
        (
            :semijoin, :PolarsJoinTypeSemi,
            "keeping only `a`'s rows that have a matching key in `b` (no columns from `b` are added)",
        ),
        (
            :antijoin, :PolarsJoinTypeAnti,
            "keeping only `a`'s rows that have *no* matching key in `b` (no columns from `b` are added)",
        ),
    )
    doc = """
        $jl_name(a, b, on; suffix=nothing, coalesce=:join_specific, validate=:many_to_many, nulls_equal=false)
        $jl_name(a, b, on_a, on_b; kwargs...)

    Joins `a` (left) and `b` (right), $description. `on` (or `on_a`/`on_b`, when the join key is
    named differently in each frame) is a column name/expression, or a `Vector` of them for a
    multi-column join. `a`/`b` can each be a `DataFrame` or a `LazyFrame` (mixing the two is not
    supported -- both must be the same kind).

    - `suffix`: appended to a right-side column name that collides with a left-side one (upstream
      default: `"_right"`, applied when `suffix` is left `nothing`).
    - `coalesce`: how to handle same-named join-key columns in the output -- `:join_specific`
      (default; coalesces for inner/left/right, keeps both for outer/cross/semi/anti),
      `:coalesce_columns` (always coalesce into one column), or `:keep_columns` (always keep both).
    - `validate`: raises a `PolarsError` if the key-uniqueness assumption doesn't hold --
      `:many_to_many` (default, no check), `:many_to_one`/`:one_to_many`/`:one_to_one`.
    - `nulls_equal`: whether a `null` key on one side matches a `null` key on the other (default
      `false`, matching upstream).
    - `maintain_order`: which side's row order to preserve in the output -- `:none` (default, no
      guarantee), `:left`, `:right`, `:left_right` (left order first, right as the tiebreak), or
      `:right_left`.
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

Returns the Cartesian product of the rows of `a` and `b` (`nrow(a) * nrow(b)` rows, no join
keys involved). `suffix` is appended to a right-side column name that collides with a left-side
one (upstream default: `"_right"`, applied when `suffix` is left `nothing`). `maintain_order`
selects which side's row order to preserve -- `:none` (default), `:left`, `:right`,
`:left_right`, or `:right_left` -- see [`innerjoin`](@ref).
"""
crossjoin(a::DataFrame, b::DataFrame; kwargs...) = crossjoin(lazy(a), lazy(b); kwargs...) |> collect
crossjoin(
    a::LazyFrame, b::LazyFrame; suffix::Union{Nothing, AbstractString} = nothing,
    maintain_order::Symbol = :none
) = _join(a, b, Expr[], Expr[], API.PolarsJoinTypeCross; suffix, maintain_order)

"""
    join_asof(a, b, on; by_left=String[], by_right=String[], strategy::Symbol=:backward,
              tolerance=nothing, allow_eq::Bool=true, check_sortedness::Bool=true,
              suffix=nothing, nulls_equal::Bool=false)

Joins `a` (left) and `b` (right) on the nearest key in `on` (columns/expressions, typically
sorted numeric or temporal), matching each left row to the nearest right row according to
`strategy`: `:backward` (default, the last right row `<=` the left key), `:forward` (the first
right row `>=` the left key), or `:nearest`. `by_left`/`by_right` are optional equality
group-by column names applied before the asof match.

- `tolerance`: a duration string (e.g. `"1d"`, `"5m"`) capping how far the matched right key may
  be from the left key; unmatched rows beyond the tolerance get `missing`. Only the string form is
  supported (a numeric tolerance for non-temporal `on` columns is not exposed).
- `allow_eq`: whether an exactly-equal key counts as a match (default `true`).
- `check_sortedness`: validate that `on` is sorted within each `by` group before joining (default
  `true`); upstream requires `on` to be sorted regardless, this only controls whether a violation
  is caught with a clear error or produces silently wrong results.
- `suffix`/`nulls_equal`/`maintain_order`: same as the other join verbs, see [`innerjoin`](@ref).
"""
function join_asof(
        a, b, on;
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
        a, b, on, on; by_left, by_right, strategy, tolerance, allow_eq, check_sortedness, suffix,
        nulls_equal, maintain_order
    )
end
function join_asof(
        a::DataFrame, b::DataFrame, on_a, on_b;
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
        lazy(a), lazy(b), on_a, on_b; by_left, by_right, strategy, tolerance, allow_eq,
        check_sortedness, suffix, nulls_equal, maintain_order
    ) |> collect
end
function join_asof(
        a::LazyFrame, b::LazyFrame, on_a, on_b;
        by_left::Vector{<:ColId} = String[], by_right::Vector{<:ColId} = String[],
        strategy::Symbol = :backward,
        tolerance::Union{Nothing, AbstractString} = nothing,
        allow_eq::Bool = true,
        check_sortedness::Bool = true,
        suffix::Union{Nothing, AbstractString} = nothing,
        nulls_equal::Bool = false,
        maintain_order::Symbol = :none
    )
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
