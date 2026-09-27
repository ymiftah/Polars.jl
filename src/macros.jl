# Macros that generate the Julia side of the C ABI wrappers. They encode the marshalling rules
# (`ncodeunits` for a `(ptr, len)` pair, `polars_error` after every fallible call, `GC.@preserve`
# around pointer vectors), so prefer extending one over hand-writing a wrapper.
#
# | the polars method...                             | example                         | use                            |
# |:-------------------------------------------------|:--------------------------------|:-------------------------------|
# | takes nothing beyond `self`                      | `Expr::sum`, `.str.len_bytes`   | `@wrap_simple_ops` block       |
# | takes exactly one other expression, nothing else | `Expr::is_in`, `.str.split`     | `@wrap_simple_ops` block       |
# | takes further arguments or options               | `.str.contains(pat, strict)`    | `@wrap_expr_method`            |
# | only renames the output column                   | `Expr::alias`/`prefix`/`suffix` | `@wrap_rename_method`          |
# | is a free function over N expressions            | `sum_horizontal`, `as_struct`   | `@wrap_multi_expr_function`    |
# | -- and you also want a pipe form                 | `col("x") \|> round(2)`         | `@curry`, on top of the above  |
#
# Whether a C function is fallible is read off the generated bindings at expansion time (see
# `_api_signature`), never declared at the call site.
#
# `@wrap_simple_ops` entries mirror the `gen_impl_expr*!` macro invocations in
# `c-polars/src/expr.rs`, with an optional description:
#
#     gen_impl_expr!(polars_expr_sum, Expr::sum, "Sum all the values.")
#     gen_impl_expr_binary_str!(polars_expr_str_split, StringNameSpace::split, "..."; curried = true)
#
# Only `_binary` changes what is generated (`f(a::Expr, b::Expr)` instead of `f(expr::Expr)`); the
# `_list`/`_str`/`_dt` suffix is ignored (the namespace comes from the enclosing submodule).
# `curried = true` adds a `Base.Fix2` pipe form and applies only to `_binary` entries.
#
# Still hand-written: nullable-scalar arguments (`Ref` under `GC.@preserve`), `Vector{String}`
# arguments via `_name_ptrs`, per-argument casts and `Symbol`-to-enum keywords, and functions whose
# C parameter order differs from the Julia one or whose name needs qualification.

"""
    _enum_lookup(sym::Symbol, label::AbstractString, mapping::Pair{Symbol}...)

Resolves `sym` against `mapping` (each entry `:key => value`), returning the matched `value`.
Raises an error naming `label` and listing the valid keys if nothing matches.
"""
function _enum_lookup(sym::Symbol, label::AbstractString, mapping::Pair{Symbol}...)
    for (key, value) in mapping
        sym === key && return value
    end
    valid = join((string(':', key) for (key, _) in mapping), ", ")
    error("unknown $label $sym, expected one of ($valid)")
end

"""Processes one argument node from a `@curry` signature, returning
`(decl_node, name, forward_expr)`. An `::Expr` annotation is dropped from `decl_node` and the
argument is forwarded as `convert(Expr, name)`; anything else is forwarded as-is. Defaults
(`:kw` nodes) are preserved."""
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

Generates the pipe form of an existing `f(expr::Expr, args...; kwargs...)`:

    f(args...; kwargs...) = expr -> f(expr, args...; kwargs...)

with a "Curried form of `f`" docstring. Pass `f`'s signature without the leading `expr::Expr`.
Arguments annotated `::Expr` are forwarded as `convert(Expr, x)` and lose the annotation, so the
curry accepts bare literals. For example, `@curry contains(pat::Expr; strict::Bool=true)`
generates `contains(pat; strict=true) = expr -> contains(expr, convert(Expr, pat); strict)`.

Curries with narrower argument types than the primal (`sort_by`, `over`) or varargs are
hand-written.
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

Marshalling rule for one argument of a `@wrap_expr_method`/`@wrap_rename_method` signature.
`decl` is the node to put in the generated signature; `fwds` is the (possibly two-element) list of
C arguments it expands into. The declared *type annotation* selects the rule, so a signature written
the way it should read to a caller already says how to marshal it:

| annotation        | generated signature | forwarded to the ccall     |
|:------------------|:--------------------|:---------------------------|
| `::Expr`          | annotation dropped  | `convert(Expr, x)`         |
| `::AbstractString`| kept                | `String(x), ncodeunits(x)` |
| `::Char`          | kept                | `codepoint(x)`             |
| anything else     | kept                | `x`                        |

`::Expr` drops its annotation so the argument accepts a bare literal. `String(x)` materialises
a `SubString` into a `String` whose pointer can cross the boundary.

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
        error("@wrap_expr_method: can't process argument node $node")
    end
end

"""
    _gen_expr_parts(macro_name, sig) -> (gen_sig, fwd_args)

Signature processing for [`@wrap_expr_method`](@ref) and [`@wrap_rename_method`](@ref): checks
`sig` leads with `expr::Expr` and runs every other argument through [`_marshal_arg`](@ref).
Returns the signature to generate and the C argument list (positionals, then keywords), which must
match the C function's parameter order after `expr`.
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

"""Builds the `Docs.@doc` call documenting `gen_sig` with description `desc`."""
function _gen_expr_doc(gen_sig, desc)
    string_sig = replace(string(gen_sig), "Expr" => "Polars.Expr")
    docstring = """
        $(string_sig)::Polars.Expr

    $desc
    """
    return :(Docs.@doc $docstring $gen_sig)
end

"""
    _api_signature(cname) -> (arity, returns_error)

Reflects on the generated binding `API.cname`: how many arguments it takes, and whether it
returns a `polars_error_t`. Generated bindings are single-method and fixed-arity, so both are
exact. A fallible binding takes one more argument (the out-param) than the call marshals, which
[`_resolve_fallible`](@ref) checks.
"""
function _api_signature(cname::Symbol)
    isdefined(API, cname) || error(
        "no binding `API.$cname` -- check the name against c-polars/include/polars.h, and that " *
            "the header and src/api/generated.jl have both been regenerated"
    )
    f = getfield(API, cname)
    ms = methods(f)
    length(ms) == 1 || error("`API.$cname` has $(length(ms)) methods; a generated binding has exactly one")
    arity = length(first(ms).sig.parameters) - 1
    return arity, only(Base.return_types(f, NTuple{arity, Any})) === Ptr{polars_error_t}
end

"""Returns whether `cname` is fallible, checking its arity against the `nargs` marshalled C
arguments. A mismatch is an error at macro expansion."""
function _resolve_fallible(macro_name, cname, nargs)
    arity, returns_error = _api_signature(cname)
    if returns_error
        arity == nargs + 1 || error(
            "$macro_name: `API.$cname` is fallible and takes $arity arguments, but the signature " *
                "given marshals to $nargs (so $(nargs + 1) with the out-param). If it returns its " *
                "result through an `IOCallback` rather than a trailing out-param -- as " *
                "`polars_expr_meta_output_name` and the write/sink entry points do -- this macro " *
                "cannot express it; write that wrapper by hand."
        )
        return true
    end
    arity == nargs || error(
        "$macro_name: `API.$cname` takes $arity arguments but the signature given marshals to " *
            "$nargs. Check the argument list and its order against c-polars/include/polars.h."
    )
    return false
end

"""Emits the function definition for `gen_sig`, with the fallible or infallible body depending
on `cname`."""
function _gen_expr_body(macro_name, gen_sig, cname, fwd_args)
    api_fn = Base.Expr(:(.), :API, QuoteNode(cname))
    if _resolve_fallible(macro_name, cname, length(fwd_args))
        ccall_expr = Base.Expr(:call, api_fn, fwd_args..., :out)
        # `Expr(:function, ...)`: a whole signature can't be interpolated after `function`.
        body = quote
            out = Ref{Ptr{polars_expr_t}}()
            err = $ccall_expr
            polars_error(err)
            return Expr(out[])
        end
        return Base.Expr(:function, gen_sig, body)
    end
    return Base.Expr(:(=), gen_sig, :(Expr($(Base.Expr(:call, api_fn, fwd_args...)))))
end

"""
    @wrap_expr_method f(expr::Expr, pos...; kw...) cname desc

Wraps a polars method called on an expression with further arguments or options
(`.str.contains(pat, strict)`, `Expr::clip(min, max)`). Every argument after `expr::Expr` is
forwarded as a C argument, marshalled by its type annotation (see [`_marshal_arg`](@ref)).

Whether `cname` is fallible is looked up from the generated bindings (see
[`_api_signature`](@ref)), and the body follows:

    f(expr::Expr, args...) = Expr(API.cname(expr, args...))                    # infallible

    function f(expr::Expr, args...)                                            # fallible
        out = Ref{Ptr{polars_expr_t}}()
        err = API.cname(expr, args..., out)
        polars_error(err)
        return Expr(out[])
    end

Only fits arguments `_marshal_arg` covers, and names that don't need `Base.` qualification.
"""
macro wrap_expr_method(sig, cname, desc)
    gen_sig, fwd_args = _gen_expr_parts("@wrap_expr_method", sig)
    fn_def = _gen_expr_body("@wrap_expr_method", gen_sig, cname, fwd_args)
    return esc(
        quote
            $fn_def
            $(_gen_expr_doc(gen_sig, desc))
        end
    )
end

"""
    @wrap_rename_method f cname desc

Wraps a polars method that renames the output from a single string ([`alias`](@ref),
[`prefix`](@ref), [`suffix`](@ref)): [`@wrap_expr_method`](@ref) over
`f(expr::Expr, s::AbstractString)`, plus a `Base.Fix2` curry (which prints legibly in the REPL)
and one docstring covering both signatures.
"""
macro wrap_rename_method(fname, cname, desc)
    @assert fname isa Symbol && cname isa Symbol "@wrap_rename_method expects (fname::Symbol, cname::Symbol, desc::String)"
    gen_sig, fwd_args = _gen_expr_parts("@wrap_rename_method", :($fname(expr::Expr, s::AbstractString)))
    fn_def = _gen_expr_body("@wrap_rename_method", gen_sig, cname, fwd_args)
    # Attached to the two-argument signature, not the bare function name.
    docstring = """
        $(fname)(expr::Polars.Expr, s::AbstractString)::Polars.Expr
        $(fname)(s::AbstractString)::Base.Fix2{typeof($fname), <:AbstractString}

    $desc
    """
    return esc(
        quote
            $fn_def
            $fname(s::AbstractString) = Base.Fix2($fname, s)
            Docs.@doc $docstring $gen_sig
        end
    )
end

"""
    @wrap_multi_expr_function fname cname has_ignore_nulls desc

Wraps a free polars function over any number of expressions (`sum_horizontal(a, b, c)`,
`as_struct(...)`) as `fname(exprs...)`, or `fname(exprs...; ignore_nulls::Bool=true)` when
`has_ignore_nulls` is the literal `true`. `cname` must be fallible.
"""
macro wrap_multi_expr_function(fname, cname, has_ignore_nulls, desc)
    @assert fname isa Symbol && has_ignore_nulls isa Bool "@wrap_multi_expr_function expects (fname::Symbol, cname::Symbol, has_ignore_nulls::Bool, desc::String) -- got ($fname, $cname, $has_ignore_nulls, $desc)"

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

"""
    @wrap_simple_ops begin
        gen_impl_expr!(polars_expr_sum, Expr::sum, "Sums the non-null values of `expr`...")
        gen_impl_expr_binary_str!(polars_expr_str_split, StringNameSpace::split, "..."; curried = true)
    end

Wraps polars methods that take nothing beyond `self`, or exactly one other expression
(`Expr::sum`, `Expr::is_in`). One line per wrapper generates the function, its docstring, its
export (unless the name collides with `Base`), and optionally a `Base.Fix2` curry. See the header
of this file for the entry syntax. The generated bodies are infallible; wrap a fallible C function
with [`@wrap_expr_method`](@ref).
"""
macro wrap_simple_ops(ex)
    @assert ex.head === :block
    out = Base.Expr(:block)
    for call in ex.args
        call isa Base.Expr || continue
        # Options (`curried = true`) sit in a leading `:parameters` node; strip them first.
        entry_args = call.args[2:end]
        opts = Dict{Symbol, Any}()
        if !isempty(entry_args) && entry_args[1] isa Base.Expr && entry_args[1].head === :parameters
            for kw in entry_args[1].args
                @assert kw isa Base.Expr && kw.head === :kw "@wrap_simple_ops: expected `name = value` options, got $kw"
                opts[kw.args[1]] = kw.args[2]
            end
            entry_args = entry_args[2:end]
        end
        @assert length(entry_args) in (2, 3) "@wrap_simple_ops: expected `cname, Namespace::method[, \"description\"]`, got $(length(entry_args)) arguments"
        cname = entry_args[1]
        ns_fname_node = entry_args[2]
        orig_fname = last(ns_fname_node.args)
        desc = length(entry_args) >= 3 ? entry_args[3] : nothing
        # A Base-colliding name is not exported. In `Polars` it extends `Base.fname`; in a
        # namespace submodule it stays a local binding used qualified (`Lists.get`).
        base_collision = isdefined(Base, orig_fname)
        base_qualified = __module__ == Polars && base_collision
        fname = base_qualified ? Base.Expr(:(.), :Base, QuoteNode(orig_fname)) : orig_fname
        sig = Base.Expr(:call, fname)
        # Only `_binary` changes what is generated; the namespace suffix is ignored.
        entry_name = string(call.args[1])
        entry = match(r"^gen_impl_expr(_binary)?(_list|_str|_dt)?!$", entry_name)
        @assert entry !== nothing "@wrap_simple_ops: `$entry_name` is not one of the `gen_impl_expr*!` names from c-polars/src/expr.rs (did you mean to pass `curried = true` instead of a `_curried` suffix?)"
        is_binary = entry.captures[1] !== nothing
        # `curried = true` also emits `orig_fname(b) = Base.Fix2(orig_fname, convert(Expr, b))`.
        # Not supported for a `Base.`-qualified name.
        curried = get(opts, :curried, false) === true
        for k in keys(opts)
            @assert k === :curried "@wrap_simple_ops: unknown option `$k` (the only option is `curried = true`)"
        end
        if curried
            @assert is_binary "@wrap_simple_ops: `curried = true` only applies to a `_binary` entry"
            @assert !base_qualified "curried Fix2 form not supported for a Base-qualified name ($orig_fname); write it by hand"
        end
        if is_binary
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
        # Documented under the unqualified name, as `?fname` in the REPL expects.
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
