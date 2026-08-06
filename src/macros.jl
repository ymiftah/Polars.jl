# Macros and AST helpers that generate the Julia side of the C ABI wrappers.
#
# This file is the **paved path for wrapping a `polars_*` C function**. Adding a wrapper by hand is
# possible but should be rare and deliberate: the marshalling rules encoded here (`_marshal_arg`)
# are the ones CLAUDE.md flags as easy to get silently wrong -- `ncodeunits` rather than `length`
# for a `(ptr, len)` pair, `polars_error` after every fallible call, `GC.@preserve` around every
# pointer vector. A generated wrapper cannot get those wrong; a hand-written one can, and has.
#
# The macros, roughly in order of how specific they are:
#
# | macro                      | shape                                                          |
# |:---------------------------|:---------------------------------------------------------------|
# | `@generate_expr_fns`       | 1:1 unary/binary ops, declared in bulk from the Rust names      |
# | `@gen_expr_fn`             | `f(expr, args...) = Expr(API.f(...))`, non-fallible             |
# | `@gen_expr_fn_fallible`    | ditto, around an out-param plus `polars_error`                  |
# | `@gen_name_fn`             | `alias`/`prefix`/`suffix`: one string arg, plus a `Fix2` curry  |
# | `@gen_variadic`            | `f(exprs...)`: vector of `Expr`s under `GC.@preserve`           |
# | `@curry`                   | the `|>`-friendly sibling of any of the above                   |
#
# Not yet covered, and so still hand-written -- the natural places to extend next, in rough order
# of how often they recur:
#
#   - the nullable-scalar shape, `x === nothing ? Ptr{T}(C_NULL) : Ref(T(x))` handed to the ccall
#     under `GC.@preserve` (`sample_n`, `sample_frac`, `Lists.sample_n`, `Lists.sample_fraction`,
#     `fill_null`). Worth doing carefully: the `Ref` *must* stay preserved across the call.
#   - the `Vector{String}` shape via `_name_ptrs` (`cut`/`qcut`/`qcut_uniform`,
#     `Lists.to_struct`, `Structs.rename_fields`).
#   - per-argument casts (`UInt8(ddof)`, `Csize_t(n)`) and `Symbol`-to-enum keywords, which would
#     each need a new `_marshal_arg` rule.
#   - anything whose C parameter order differs from the Julia one (`Strings.replace_n`), or whose
#     name collides with `Base`/`Polars` and so needs qualification (`Base.all`, `Lists.head`).

"""
    _enum_lookup(sym::Symbol, label::AbstractString, mapping::Pair{Symbol}...)

Resolves `sym` against `mapping` (each entry `:key => value`), returning the matched `value`.
Raises a plain `ErrorException` naming `label` and listing the valid keys if `sym` matches none
of them. Every `Symbol`-keyword-to-C-enum conversion in this module (`time_unit`, quantile
`method`, `strategy`, ...) goes through this instead of restating its own `if/elseif/error`
chain.
"""
function _enum_lookup(sym::Symbol, label::AbstractString, mapping::Pair{Symbol}...)
    for (key, value) in mapping
        sym === key && return value
    end
    valid = join((string(':', key) for (key, _) in mapping), ", ")
    error("unknown $label $sym, expected one of ($valid)")
end

"""Processes one argument node from a `@curry` target signature, returning
`(decl_node, name, forward_expr)`:
- `decl_node` is what goes in the *curry's own* signature (same node, except an `::Expr`
  annotation is stripped -- the curry accepts a bare literal there, not just an `Expr`).
- `name` is the bare argument `Symbol`, for building the curry's own signature/forwarding call.
- `forward_expr` is what gets passed to the primal at that position: the bare `name` normally, or
  `convert(Expr, name)` when the original annotation was `::Expr` (mirroring what the primal
  itself requires, since it performs no such conversion internally when it declares the arg
  `::Expr`).
Recurses through `x=default`/`x::T=default` (a `:kw` node) to reach the underlying `x`/`x::T`,
preserving the default in `decl_node`."""
function _curry_arg(node::Symbol)
    return node, node, node
end
function _curry_arg(node::Base.Expr)
    if node.head === :(::)
        name, T = node.args[1], node.args[2]
        return T === :Expr ? (name, name, Base.Expr(:call, :convert, :Expr, name)) : (node, name, name)
    elseif node.head === :kw
        inner_decl, name, forward = _curry_arg(node.args[1])
        return Base.Expr(:kw, inner_decl, node.args[2]), name, forward
    else
        error("@curry: can't process argument node $node")
    end
end

"""
    @curry f(args...; kwargs...)

Generates the curried (pipe-with-`|>`) sibling of `f`, whose primary method takes the piped
`Polars.Expr` as its first (unnamed here) argument -- i.e. expands to

    f(args...; kwargs...) = expr -> f(expr, args...; kwargs...)

plus a `"Curried form of [`f`](@ref) for use with `\\|>`."` docstring, the exact convention every
hand-written curry in this module already follows. Write the *same* argument list `f`'s own
primary method declares from its second argument onward -- including any `::Expr` annotation --
except with the leading `expr::Expr` dropped: any argument written `::Expr` here is wrapped in
`convert(Expr, ·)` before being forwarded (since the primary method requires an actual `Expr` at
that position and performs no conversion of its own), and the annotation itself is dropped from
the curry's own signature so it keeps accepting bare literals, not just `Expr`s. An argument with
any other type (or none) is forwarded as-is, on the assumption the primary method converts it
itself. For example, `contains(expr::Expr, pat::Expr; strict::Bool=true)` pairs with
`@curry contains(pat::Expr; strict::Bool=true)`, generating
`contains(pat; strict=true) = expr -> contains(expr, convert(Expr, pat); strict)`.

Not a fit for a curry whose accepted argument types are deliberately *narrower* than the primary
method's own (`sort_by`/`over` restrict their curried `by`/`partition_by` to column names, not
arbitrary `Expr`s, since an `Expr` there would be ambiguous with the piped `expr` itself) or that
splats a variable number of arguments -- both stay hand-written.
"""
macro curry(sig)
    @assert sig isa Base.Expr && sig.head === :call "@curry expects a call signature, e.g. `@curry f(x; y=1)`"
    fname = sig.args[1]
    posarg_decls, posarg_forwards = Any[], Any[]
    kwarg_decls, kwarg_forwards = Any[], Any[]
    for a in sig.args[2:end]
        if a isa Base.Expr && a.head === :parameters
            for kw in a.args
                decl, name, forward = _curry_arg(kw)
                push!(kwarg_decls, decl)
                push!(kwarg_forwards, forward === name ? name : Base.Expr(:kw, name, forward))
            end
        else
            decl, _, forward = _curry_arg(a)
            push!(posarg_decls, decl)
            push!(posarg_forwards, forward)
        end
    end

    curry_sig_args = Any[fname]
    isempty(kwarg_decls) || push!(curry_sig_args, Base.Expr(:parameters, kwarg_decls...))
    append!(curry_sig_args, posarg_decls)
    curry_sig = Base.Expr(:call, curry_sig_args...)

    call_args = Any[fname, :expr]
    append!(call_args, posarg_forwards)
    call_expr = Base.Expr(:call, call_args...)
    isempty(kwarg_forwards) || insert!(call_expr.args, 2, Base.Expr(:parameters, kwarg_forwards...))
    curry_def = Base.Expr(:(=), curry_sig, Base.Expr(:->, :expr, Base.Expr(:block, call_expr)))

    docstring = """
        $(curry_sig)::Base.Callable

    Curried form of [`$fname`](@ref) for use with `|>`.
    """
    return esc(
        quote
            Docs.@doc $docstring $curry_sig
            $curry_def
        end
    )
end

"""
    _marshal_arg(node) -> (decl, fwds)

Marshalling rule for one argument of a `@gen_expr_fn`/`@gen_expr_fn_fallible` signature. `decl` is
the node to put in the generated signature; `fwds` is the (possibly two-element) list of C
arguments it expands into. The declared *type annotation* selects the rule, so a signature written
the way it should read to a caller already says how to marshal it:

| annotation        | generated signature | forwarded to the ccall     |
|:------------------|:--------------------|:---------------------------|
| `::Expr`          | annotation dropped  | `convert(Expr, x)`         |
| `::AbstractString`| kept                | `String(x), ncodeunits(x)` |
| `::Char`          | kept                | `codepoint(x)`             |
| anything else     | kept                | `x`                        |

`::Expr` drops its annotation so the argument keeps accepting a bare literal (`clip(col("x"), 0,
10)`); `::AbstractString` expands to the `(ptr, len)` pair the C ABI takes, which is the single
most error-prone marshalling in this package -- **`ncodeunits` (bytes), never `length`
(characters)**, the latter cutting non-ASCII arguments mid-codepoint. `String(x)` is a no-op on a
`String` and materialises anything else (a `SubString`, say) into one whose pointer is safe to
hand across the boundary.

Recurses through `x = default` (a `:kw` node) to reach the underlying `x`/`x::T`, preserving the
default.
"""
function _marshal_arg(node::Symbol)
    return node, Any[node]
end
function _marshal_arg(node::Base.Expr)
    if node.head === :(::)
        name, T = node.args[1], node.args[2]
        T === :Expr && return name, Any[:(convert(Expr, $name))]
        T === :AbstractString && return node, Any[:(String($name)), :(ncodeunits($name))]
        T === :Char && return node, Any[:(codepoint($name))]
        return node, Any[name]
    elseif node.head === :kw
        inner_decl, fwds = _marshal_arg(node.args[1])
        return Base.Expr(:kw, inner_decl, node.args[2]), fwds
    else
        error("@gen_expr_fn: can't process argument node $node")
    end
end

"""
    _gen_expr_parts(macro_name, sig) -> (gen_sig, fwd_args)

Shared signature processing for [`@gen_expr_fn`](@ref) and [`@gen_expr_fn_fallible`](@ref): splits
`sig` into its keyword and positional parts, checks it leads with `expr::Expr`, and runs every
other argument through [`_marshal_arg`](@ref). Returns the signature to generate and the C
argument list, in declaration order (positionals first, then keywords) -- which is therefore the
order the C function's own parameters must be in after `expr`.
"""
function _gen_expr_parts(macro_name, sig)
    @assert sig isa Base.Expr && sig.head === :call && sig.args[1] isa Symbol "$macro_name expects a call signature, e.g. `clip(expr::Expr, min::Expr, max::Expr)`"
    fname = sig.args[1]
    rest = sig.args[2:end]
    kwparams = if !isempty(rest) && rest[1] isa Base.Expr && rest[1].head === :parameters
        p = rest[1]
        rest = rest[2:end]
        p.args
    else
        ()
    end
    @assert !isempty(rest) && rest[1] == Base.Expr(:(::), :expr, :Expr) "$macro_name's first positional argument must be `expr::Expr` -- got $(isempty(rest) ? "nothing" : rest[1])"

    # `expr` itself is already an `Expr`: kept verbatim in the signature, forwarded unconverted.
    decl_args, fwd_args = Any[rest[1]], Any[:expr]
    for a in rest[2:end]
        decl, fwds = _marshal_arg(a)
        push!(decl_args, decl)
        append!(fwd_args, fwds)
    end
    kwdecls = Any[]
    for kw in kwparams
        decl, fwds = _marshal_arg(kw)
        push!(kwdecls, decl)
        append!(fwd_args, fwds)
    end

    sig_args = Any[fname]
    isempty(kwdecls) || push!(sig_args, Base.Expr(:parameters, kwdecls...))
    append!(sig_args, decl_args)
    return Base.Expr(:call, sig_args...), fwd_args
end

"""Builds the `Docs.@doc` call every `@gen_expr_fn`-family macro attaches, documenting `gen_sig`
under a `sig::Polars.Expr` header derived from the signature itself."""
function _gen_expr_doc(gen_sig, desc)
    string_sig = replace(string(gen_sig), "Expr" => "Polars.Expr")
    docstring = """
        $(string_sig)::Polars.Expr

    $desc
    """
    return :(Docs.@doc $docstring $gen_sig)
end

"""
    @gen_expr_fn f(expr::Expr, pos...; kw...) cname desc

Generates the non-fallible primal shape that most single-`Expr` wrappers share --

    f(expr::Expr, pos...; kw...) = Expr(API.cname(expr, pos..., kw...))

Every argument after the leading `expr::Expr` is forwarded to the ccall as a positional C
argument, marshalled according to its declared type annotation -- see [`_marshal_arg`](@ref) for
the table, and [`@gen_expr_fn_fallible`](@ref) for the same thing around an out-param.

Only fits arguments whose marshalling that table covers: `rolling_std`'s `ddof` (`UInt8(ddof)`),
`splitn`'s `n` (`Csize_t(n)`), every `Symbol`-to-enum keyword, and `Strings.replace_n` (whose C
parameter order differs from the Julia one) all stay hand-written. Not used for a Base-colliding
name (`Base.all`/`Base.any`/`Base.replace`), which would need the `Base.`-qualification dance
`@generate_expr_fns` carries for that case.
"""
macro gen_expr_fn(sig, cname, desc)
    gen_sig, fwd_args = _gen_expr_parts("@gen_expr_fn", sig)
    ccall_expr = Base.Expr(:call, Base.Expr(:(.), :API, QuoteNode(cname)), fwd_args...)
    return esc(
        quote
            $(Base.Expr(:(=), gen_sig, :(Expr($ccall_expr))))
            $(_gen_expr_doc(gen_sig, desc))
        end
    )
end

"""
    @gen_expr_fn_fallible f(expr::Expr, pos...; kw...) cname desc

[`@gen_expr_fn`](@ref) for a *fallible* ccall -- one returning `*const polars_error_t` with the
result arriving through a trailing out-param:

    function f(expr::Expr, pos...; kw...)
        out = Ref{Ptr{polars_expr_t}}()
        err = API.cname(expr, pos..., kw..., out)
        polars_error(err)
        return Expr(out[])
    end

Argument marshalling is identical (see [`_marshal_arg`](@ref)); only the body differs. Per
CLAUDE.md every fallible entry point *must* check `polars_error`, since a panic unwinding across
`extern "C"` is undefined behaviour -- generating the check is one fewer place to forget it.
"""
macro gen_expr_fn_fallible(sig, cname, desc)
    gen_sig, fwd_args = _gen_expr_parts("@gen_expr_fn_fallible", sig)
    ccall_expr = Base.Expr(:call, Base.Expr(:(.), :API, QuoteNode(cname)), fwd_args..., :out)
    return esc(
        quote
            function $gen_sig
                out = Ref{Ptr{polars_expr_t}}()
                err = $ccall_expr
                polars_error(err)
                return Expr(out[])
            end
            $(_gen_expr_doc(gen_sig, desc))
        end
    )
end

"""
    @gen_name_fn f cname desc

The output-name-rewriting shape shared by [`alias`](@ref)/[`prefix`](@ref)/[`suffix`](@ref):
exactly [`@gen_expr_fn_fallible`](@ref) over the fixed signature `f(expr::Expr, s::AbstractString)`
(so the `(ptr, ncodeunits)` marshalling comes from the same [`_marshal_arg`](@ref) rule as
everywhere else), plus two things that shape needs and the general macro does not emit:

- a `Base.Fix2` curry rather than [`@curry`](@ref)'s closure, so `alias("x")` still prints as
  something legible in the REPL;
- one docstring covering *both* signatures, matching what the hand-written originals carried.
"""
macro gen_name_fn(fname, cname, desc)
    @assert fname isa Symbol && cname isa Symbol "@gen_name_fn expects (fname::Symbol, cname::Symbol, desc::String)"
    gen_sig, fwd_args = _gen_expr_parts("@gen_name_fn", :($fname(expr::Expr, s::AbstractString)))
    ccall_expr = Base.Expr(:call, Base.Expr(:(.), :API, QuoteNode(cname)), fwd_args..., :out)
    # Attached to the two-argument *signature*, not the bare function name -- matching both the
    # hand-written original and `@generate_expr_fns`. `docs/src/reference/expressions.md` lists
    # these in a `@docs` block by bare name, which pulls in every docstring attached to any method;
    # documenting the generic function instead would change what Documenter renders.
    docstring = """
        $(fname)(expr::Polars.Expr, s::AbstractString)::Polars.Expr
        $(fname)(s::AbstractString)::Base.Fix2{typeof($fname), <:AbstractString}

    $desc
    """
    return esc(
        quote
            function $gen_sig
                out = Ref{Ptr{polars_expr_t}}()
                err = $ccall_expr
                polars_error(err)
                return Expr(out[])
            end
            $fname(s::AbstractString) = Base.Fix2($fname, s)
            Docs.@doc $docstring $gen_sig
        end
    )
end

"""
    @gen_variadic fname cname has_ignore_nulls desc

Generates the variadic shape that takes any number of column references and folds them into one
expression -- `fname(exprs...)`, or `fname(exprs...; ignore_nulls::Bool=true)` when
`has_ignore_nulls` is the literal `true`. The body `_expr_vector`s the arguments, marshals their
pointers under `GC.@preserve`, calls the fallible `cname` ccall, and returns `Expr(out[])`.

Covers the six `_horizontal` row-wise reductions and [`as_struct`](@ref), which is the same shape
despite not being a reduction. `Base.coalesce` is deliberately left hand-written: it needs both
`Base.`-qualification and a `(first::Expr, rest::Expr...)` signature (to reject the zero-argument
call this macro's plain `exprs...` would accept), and teaching the macro two features for one call
site buys nothing.
"""
macro gen_variadic(fname, cname, has_ignore_nulls, desc)
    @assert fname isa Symbol && has_ignore_nulls isa Bool "@gen_variadic expects (fname::Symbol, cname::Symbol, has_ignore_nulls::Bool, desc::String) -- got ($fname, $cname, $has_ignore_nulls, $desc)"

    ccall_args = Any[Base.Expr(:(.), :API, QuoteNode(cname)), :ptrs, :(length(ptrs))]
    has_ignore_nulls && push!(ccall_args, :ignore_nulls)
    push!(ccall_args, :out)
    ccall_expr = Base.Expr(:call, ccall_args...)

    fn_def = if has_ignore_nulls
        quote
            function $fname(exprs...; ignore_nulls::Bool = true)
                exprs = _expr_vector(exprs)
                GC.@preserve exprs begin
                    ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
                    out = Ref{Ptr{polars_expr_t}}()
                    err = $ccall_expr
                    polars_error(err)
                end
                return Expr(out[])
            end
        end
    else
        quote
            function $fname(exprs...)
                exprs = _expr_vector(exprs)
                GC.@preserve exprs begin
                    ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
                    out = Ref{Ptr{polars_expr_t}}()
                    err = $ccall_expr
                    polars_error(err)
                end
                return Expr(out[])
            end
        end
    end

    doc_sig = has_ignore_nulls ? "$(fname)(exprs...; ignore_nulls::Bool=true)" : "$(fname)(exprs...)"
    doc_target = has_ignore_nulls ? :($fname(exprs...; ignore_nulls::Bool = true)) : :($fname(exprs...))
    docstring = """
        $(doc_sig)::Polars.Expr

    $desc
    """
    return esc(
        quote
            $fn_def
            Docs.@doc $docstring $doc_target
        end
    )
end

macro generate_expr_fns(ex)
    @assert ex.head === :block
    out = Base.Expr(:block)
    for call in ex.args
        call isa Base.Expr || continue
        cname = call.args[2]
        # Fixed position, not `last(call.args)`: an optional 4th arg (the description below)
        # would otherwise become `last(call.args)` itself once present, silently corrupting
        # `orig_fname`/`namespace` extraction below (this broke once already -- see
        # plans/docstring_and_examples_coverage.md's "Rebaseline" section).
        ns_fname_node = call.args[3]
        orig_fname = last(ns_fname_node.args)
        # Optional 4th call arg: a hand-written description, e.g.
        # `gen_impl_expr!(polars_expr_sum, Expr::sum, "Sums the non-null values...")`, threaded
        # into the docstring below instead of the bare Rust-doc-link fallback.
        desc = length(call.args) >= 4 ? call.args[4] : nothing
        # A name colliding with an existing Base binding is never exported here -- for the
        # top-level `Polars` module that's because the function below is instead defined as a new
        # `Base.fname` method (which already works unqualified via Base's own export, see
        # CLAUDE.md's sharp-edges note); for a namespace submodule (`Lists`/`Strings`/`Dt`), the
        # function stays a wholly unrelated local binding (never Base-qualified -- extending e.g.
        # `Base.get`/`Base.max` with unrelated list/string semantics would be actively wrong), just
        # not exported, since it's designed for qualified use (`Lists.get`) and `using
        # Polars.Lists` would otherwise clash with Base's own same-named export.
        base_collision = isdefined(Base, orig_fname)
        base_qualified = __module__ == Polars && base_collision
        fname = base_qualified ? Base.Expr(:(.), :Base, QuoteNode(orig_fname)) : orig_fname
        sig = Base.Expr(:call, fname)
        gen_name = string(first(call.args))
        @assert occursin("gen", gen_name)
        # "curried" is opt-in on top of "binary" (e.g. `gen_impl_expr_binary_curried!`): besides
        # the plain `(a::Expr, b::Expr)` method, also emits `orig_fname(b) = Base.Fix2(orig_fname,
        # convert(Expr, b))` -- the `Base.Fix2`-style curry every binary op with a natural
        # "value to curry in" needs for `|>` pipelines (`col("x") |> is_in([1, 2])`), previously
        # hand-written next to each macro-generated primal. Guarded against `base_qualified`, not
        # the weaker `base_collision`: a namespace submodule (`split` in `Strings`, `round` in
        # `Dt`) can collide with a Base name and still curry unqualified fine, since its primal
        # is already its own wholly local binding there (see the base-collision note above) that
        # the unqualified `orig_fname` in the curry correctly picks up; only the top-level
        # `Polars`-module + collision case (`base_qualified`) would need `Base.orig_fname`
        # qualification this curry doesn't attempt, so it's excluded instead.
        curried = occursin("curried", gen_name)
        if curried
            @assert occursin("binary", gen_name) "the curried variant is only defined for binary generators"
            @assert !base_qualified "curried Fix2 form not supported for a Base-qualified name ($orig_fname); write it by hand"
        end
        if occursin("binary", gen_name)
            push!(sig.args, Base.Expr(:(::), :a, :Expr), Base.Expr(:(::), :b, :Expr))
            body = quote
                out = API.$(cname)(a, b)
                Expr(out)
            end
        else
            push!(sig.args, Base.Expr(:(::), :expr, :Expr))
            body = quote
                out = API.$(cname)(expr)
                Expr(out)
            end
        end
        push!(out.args, Base.Expr(:function, sig, body))
        # Attach a docstring regardless of Base collision -- documented under the plain,
        # unqualified name (`orig_fname`), not `Base.fname`: that's how `fname` resolves inside
        # this module anyway (every module sees Base unqualified), and it's what `?fname` in the
        # REPL expects.
        namespace = string(first(ns_fname_node.args))
        namespace_type = namespace == "Expr" ? "enum" : "struct"
        rust_doc_url = "https://docs.rs/polars/latest/polars/prelude/$(namespace_type).$(namespace).html#method.$orig_fname"
        string_sig = replace(string(sig), "Expr" => "Polars.Expr")
        docstring = if desc === nothing
            """
                $(string_sig)::Polars.Expr

            Refer to [the polars documentation]($rust_doc_url).
            """
        else
            """
                $(string_sig)::Polars.Expr

            $desc

            See also [the polars documentation]($rust_doc_url).
            """
        end
        push!(
            out.args, quote
                Docs.@doc $docstring $sig
            end
        )
        base_collision || push!(out.args, :(export $orig_fname))
        if curried
            curry_sig = Base.Expr(:call, orig_fname, :b)
            curry_body = :(Base.Fix2($orig_fname, convert(Expr, b)))
            push!(out.args, Base.Expr(:(=), curry_sig, curry_body))
            curry_docstring = """
                $(orig_fname)(b)::Base.Callable

            Curried form of [`$orig_fname`](@ref) for use with `|>`.
            """
            push!(
                out.args, quote
                    Docs.@doc $curry_docstring $curry_sig
                end
            )
        end
    end
    return esc(out)
end
