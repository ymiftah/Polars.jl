module Lists
    using ..Polars: @wrap_simple_ops, @wrap_expr_method, @curry,
        API, polars_expr_t, Expr, polars_error, _null_behavior_enum

    @wrap_simple_ops begin
        gen_impl_expr_list!(polars_expr_list_lengths, ListNameSpace::lengths, "Return the number of elements in each list.\n\nNull values are treated like regular elements in this context.")
        gen_impl_expr_list!(polars_expr_list_max, ListNameSpace::max, "Compute the maximum of the items in every sublist.")
        gen_impl_expr_list!(polars_expr_list_min, ListNameSpace::min, "Compute the minimum of the items in every sublist.")
        gen_impl_expr_list!(polars_expr_list_arg_max, ListNameSpace::arg_max, "Return the index of the maximum value of every sublist.\n\nNote: the index is 0-based.")
        gen_impl_expr_list!(polars_expr_list_arg_min, ListNameSpace::arg_min, "Return the index of the minimal value of every sublist.\n\nNote: the index is 0-based.")
        gen_impl_expr_list!(polars_expr_list_sum, ListNameSpace::sum, "Compute the sum the items in every sublist.")
        gen_impl_expr_list!(polars_expr_list_mean, ListNameSpace::mean, "Compute the mean of every sublist and return a `Series` of dtype `Float64`.")
        gen_impl_expr_list!(polars_expr_list_reverse, ListNameSpace::reverse, "Reverse every sublist.")
        gen_impl_expr_list!(polars_expr_list_unique, ListNameSpace::unique, "Get the unique values of every sublist.")
        gen_impl_expr_list!(polars_expr_list_unique_stable, ListNameSpace::unique_stable, "Get the unique values of every sublist, maintaining order.")
        gen_impl_expr_list!(polars_expr_list_first, ListNameSpace::first, "Get first item of every sublist.")
        gen_impl_expr_list!(polars_expr_list_last, ListNameSpace::last, "Get last item of every sublist.")
        gen_impl_expr_list!(polars_expr_list_median, ListNameSpace::median, "Compute the median of every sublist.")
        gen_impl_expr_list!(polars_expr_list_drop_nulls, ListNameSpace::drop_nulls, "Drop null values in every sublist.")
        gen_impl_expr_list!(polars_expr_list_n_unique, ListNameSpace::n_unique, "Count the number of unique values in every sublist.")

        gen_impl_expr_binary_list!(polars_expr_list_union, ListNameSpace::union, "Return the SET UNION between both list arrays.\n\n!!! note \"Has a curried form\"\n    `union(other)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_list!(polars_expr_list_set_difference, ListNameSpace::set_difference, "Return the SET DIFFERENCE between both list arrays.\n\n!!! note \"Has a curried form\"\n    `set_difference(other)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_list!(polars_expr_list_set_intersection, ListNameSpace::set_intersection, "Return the SET INTERSECTION between both list arrays.\n\n!!! note \"Has a curried form\"\n    `set_intersection(other)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_list!(polars_expr_list_set_symmetric_difference, ListNameSpace::set_symmetric_difference, "Return the SET SYMMETRIC DIFFERENCE between both list arrays.\n\n!!! note \"Has a curried form\"\n    `set_symmetric_difference(other)`, for `|>` pipelines."; curried = true)
    end

    # `head` is hand-written so it is not exported (it collides with `Polars.head`).
    """
        head(expr::Polars.Expr, n::Polars.Expr)::Polars.Expr

    Get the head of every sublist.
    """
    function head(a::Expr, b::Expr)
        out = API.polars_expr_list_head(a, b)
        return Expr(out)
    end

    """
        head(n)::Base.Fix2{typeof(head)}

    Curried form of `head` for use with `|>`, e.g. `col("x") |> Lists.head(2)`.
    """
    head(n) = Base.Fix2(head, convert(Expr, n))

    """
        tail(expr::Polars.Expr, n::Polars.Expr)::Polars.Expr

    Get the tail of every sublist.
    """
    function tail(a::Expr, b::Expr)
        out = API.polars_expr_list_tail(a, b)
        return Expr(out)
    end
    tail(n) = Base.Fix2(tail, convert(Expr, n))

    """
        shift(expr::Polars.Expr, periods::Polars.Expr)::Polars.Expr

    Shift every sublist.
    """
    function shift(a::Expr, b::Expr)
        out = API.polars_expr_list_shift(a, b)
        return Expr(out)
    end
    shift(n) = Base.Fix2(shift, convert(Expr, n))

    @wrap_expr_method get(expr::Expr, index::Expr; null_on_oob::Bool = false) polars_expr_list_get "Get items in every sublist by index.\n\n`null_on_oob`: return a null when an index is out of bounds. This behavior is more expensive than defaulting to returning an error.\n\nNote: `index` is 0-based; negative values count from the end."
    @curry get(index; null_on_oob::Bool = false)

    """
        gather(expr::Polars.Expr, index::Polars.Expr; null_on_oob::Bool=false)::Polars.Expr

    Get items in every sublist by multiple indexes.

    - `null_on_oob`: return a null when an index is out of bounds. This behavior is more expensive
      than defaulting to returning an error.

    Note: `index` is 0-based and should be List-typed (e.g. `implode(lit([0, -1]))`).
    """
    function gather(expr::Expr, index::Expr; null_on_oob::Bool = false)
        out = API.polars_expr_list_gather(expr, index, null_on_oob)
        return Expr(out)
    end

    @wrap_expr_method gather_every(expr::Expr, n::Expr; offset::Expr = 0) polars_expr_list_gather_every "Take every `n`th value in every sublist, starting at `offset`.\n\nNote: `offset` is 0-based."

    """
        sample_n(expr::Polars.Expr, n; with_replacement::Bool=false, shuffle::Bool=false,
                  seed::Union{Nothing,Integer}=nothing)::Polars.Expr

    Sample `n` values from every sublist.
    """
    function sample_n(
            expr::Expr, n; with_replacement::Bool = false, shuffle::Bool = false,
            seed::Union{Nothing, Integer} = nothing
        )
        n = convert(Expr, n)
        seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
        out = GC.@preserve seed_ref API.polars_expr_list_sample_n(expr, n, with_replacement, shuffle, seed_ref)
        return Expr(out)
    end

    """
        sample_fraction(expr::Polars.Expr, fraction; with_replacement::Bool=false, shuffle::Bool=false,
                         seed::Union{Nothing,Integer}=nothing)::Polars.Expr

    Sample a fraction of the values from every sublist.
    """
    function sample_fraction(
            expr::Expr, fraction; with_replacement::Bool = false, shuffle::Bool = false,
            seed::Union{Nothing, Integer} = nothing
        )
        fraction = convert(Expr, fraction)
        seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
        out = GC.@preserve seed_ref API.polars_expr_list_sample_fraction(
            expr, fraction, with_replacement, shuffle, seed_ref
        )
        return Expr(out)
    end
    export sample_fraction

    @wrap_expr_method contains(expr::Expr, other::Expr; nulls_equal::Bool = true) polars_expr_list_contains "Check if the list array contain an element."
    @curry contains(other; nulls_equal::Bool = true)

    @wrap_expr_method count_matches(expr::Expr, element::Expr) polars_expr_list_count_matches "Count how often the value produced by `element` occurs."
    count_matches(element) = Base.Fix2(count_matches, convert(Expr, element))
    export count_matches

    @wrap_expr_method sort(expr::Expr; descending::Bool = false, nulls_last::Bool = false) polars_expr_list_sort "Sort every sublist."
    @curry sort(; descending::Bool = false, nulls_last::Bool = false)

    @wrap_expr_method join(expr::Expr, separator::Expr; ignore_nulls::Bool = true) polars_expr_list_join "Join all string items in a sublist and place a separator between them.\n\nThis errors if the inner type of the list is not `String`."
    @curry join(separator; ignore_nulls::Bool = true)

    @wrap_expr_method slice(expr::Expr, offset::Expr, length::Expr) polars_expr_list_slice "Slice every sublist.\n\nNote: `offset` is 0-based; a negative `offset` counts from the end."
    @curry slice(offset, length)
    export slice

    """
        diff(expr::Polars.Expr, n=1; null_behavior::Symbol=:ignore)::Polars.Expr

    Diff every sublist. `null_behavior` is `:ignore` or `:drop`.
    """
    function diff(expr::Expr, n::Integer = 1; null_behavior::Symbol = :ignore)
        behavior = _null_behavior_enum(null_behavior)
        out = API.polars_expr_list_diff(expr, Int64(n), behavior)
        return Expr(out)
    end


    @wrap_expr_method any(expr::Expr; ignore_nulls::Bool = true) polars_expr_list_any "Evaluate whether any boolean value is true for every sublist.\n\nWith `ignore_nulls=false`, Kleene logic is used: a sublist with no `true` value and at least one null gives null."

    @wrap_expr_method all(expr::Expr; ignore_nulls::Bool = true) polars_expr_list_all "Evaluate whether all boolean values are true for every sublist.\n\nWith `ignore_nulls=false`, Kleene logic is used: a sublist with no `false` value and at least one null gives null."


    """
        std(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

    Compute the standard deviation of every sublist.
    """
    std(expr::Expr; ddof::Integer = 1) = Expr(API.polars_expr_list_std(expr, UInt8(ddof)))

    """
        var(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

    Compute the variance of every sublist.
    """
    var(expr::Expr; ddof::Integer = 1) = Expr(API.polars_expr_list_var(expr, UInt8(ddof)))

    # Upstream's `eval`; `eval` is reserved in every Julia module.
    @wrap_expr_method apply(expr::Expr, evaluation::Expr) polars_expr_list_eval "Run an expression against every sublist, with [`element`](@ref) as the sublist values, e.g. `Lists.apply(col(\"x\"), unique(element()))`.\n\nNote: this is `list.eval` upstream."

    @wrap_expr_method agg(expr::Expr, evaluation::Expr) polars_expr_list_agg "Run an aggregation expression against every sublist, with [`element`](@ref) as the sublist values, returning one value per sublist."

    """
        to_array(expr::Polars.Expr, width::Integer)::Polars.Expr

    Convert a List column into an Array column with the same inner data type.

    Note: `Array` columns cannot be read back into Julia; see [Limitations](@ref).
    """
    to_array(expr::Expr, width::Integer) = Expr(API.polars_expr_list_to_array(expr, Csize_t(width)))
    export to_array

    """
        to_struct(expr::Polars.Expr, names::Vector{String})::Polars.Expr

    Convert this `List` to a `Series` of type `Struct`, with one field per name in `names`. Shorter
    lists get nulls in the trailing fields.
    """
    function to_struct(expr::Expr, names::Vector{String})
        GC.@preserve names begin
            ptrs = Ptr{UInt8}[pointer(s) for s in names]
            lens = Csize_t[ncodeunits(s) for s in names]
            out = Ref{Ptr{polars_expr_t}}()
            err = API.polars_expr_list_to_struct(expr, ptrs, lens, length(ptrs), out)
            polars_error(err)
        end
        return Expr(out[])
    end
    export to_struct

    # Names colliding with `Base` or a top-level `Polars` export are not exported.
end # module Lists

export Lists
