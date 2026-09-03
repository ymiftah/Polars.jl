# Macros and AST helpers that generate the Julia side of the C ABI wrappers.
#
# This file is the **paved path for wrapping a `polars_*` C function**. Adding a wrapper by hand is
# possible but should be rare and deliberate: the marshalling rules encoded here (`_marshal_arg`)
# are the ones CLAUDE.md flags as easy to get silently wrong -- `ncodeunits` rather than `length`
# for a `(ptr, len)` pair, `polars_error` after every fallible call, `GC.@preserve` around every
# pointer vector. A generated wrapper cannot get those wrong; a hand-written one can, and has.
#
#
# ## Which macro do I use?
#
# Pick the row matching the *polars* method you are wrapping -- what you already know when you
# start -- rather than the Julia signature you want out. Take the first row that fits.
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
# The first two rows are one macro: it is a bulk declarative block, so a no-argument op and a
# one-other-expression op are two entry shapes inside it (see "The block DSL" below). The last row
# is not an alternative to the others -- `@curry` generates the pipe-friendly *sibling* of a primal
# that one of the other macros (or a hand-written definition) has already produced.
#
#
# ## Adding a new polars function
#
# The Julia half of CLAUDE.md's "Workflow: adding a wrapped operation":
#
#   1. Write the Rust `extern "C"` shim in the matching `c-polars/src/*.rs`. For the two simple
#      shapes that is one line invoking a `gen_impl_expr*!` macro there; anything else is a
#      hand-written `pub unsafe extern "C" fn`.
#   2. Regenerate: `c-polars/regen_header.sh`, then `julia --project=gen gen/generate.jl`, then
#      `runic -i src/api/generated.jl`. Until that runs there is no `API.polars_<your_fn>` binding,
#      and every macro below fails at expansion with "no binding `API....`".
#   3. Pick the macro from the table above and add one line to the file matching the operation's
#      *category* (`src/expr/string.jl` for a `.str` method, `list.jl` for `.list`, and so on).
#   4. Build, restart the REPL, and exercise it live before writing tests.
#   5. Add tests under the matching `test/<category>/`.
#
# You never state whether the C function is fallible: that is read off the generated bindings at
# expansion time (see `_api_signature`), so the `polars_error` check can be neither forgotten nor
# attached to a function that doesn't need it.
#
#
# ## The block DSL
#
# Inside `@wrap_simple_ops begin ... end` each entry names one of the `macro_rules!` macros in
# `c-polars/src/expr.rs`. That is deliberate: the Rust declaration can be pasted across and given
# a description.
#
#     // c-polars/src/expr.rs
#     gen_impl_expr!(polars_expr_sum, Expr::sum);
#
#     # src/expr/expr.jl
#     gen_impl_expr!(polars_expr_sum, Expr::sum, "Sums the non-null values of `expr`...")
#
# Three things to know about an entry:
#
#   - **`_binary` is the only part of the name that changes what is generated.** A plain entry
#     generates `f(expr::Expr)`; a `_binary` one generates `f(a::Expr, b::Expr)`.
#   - **The namespace suffix (`_list`/`_str`/`_dt`) is ignored by the Julia macro.** The namespace
#     really comes from the submodule the block sits in, and the docstring's link from the
#     `ListNameSpace::max` argument. The suffix is still parsed, and still worth spelling to match
#     Rust, purely so the entry keeps mirroring its Rust counterpart.
#   - **`curried = true` is Julia-only** -- Rust has no `_curried` macro. It asks for the extra
#     `Base.Fix2` pipe form (`col("s") |> Strings.split(",")`), and applies only to a `_binary`
#     entry:
#
#     gen_impl_expr_binary_str!(polars_expr_str_split, StringNameSpace::split, "..."; curried = true)
#
# The description (third positional) is optional; without it the docstring is a bare link to the
# polars Rust docs. Prefer writing one.
#
#
# ## Not yet covered
#
# Still hand-written -- the natural places to extend next, in rough order of how often they recur:
#
#   - the nullable-scalar/nullable-string shapes are now covered by `_nullable_ref`/`_nullable_str`
#     -- reach for those directly rather than restating the `x === nothing ? Ptr{T}(C_NULL) : ...`
#     ternary by hand.
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

"""
    _handle_ptrs(xs::AbstractVector, ::Type{P}) -> (owned::AbstractVector, ptrs::Vector{P})

Builds the `(owned, ptrs)` pair for passing a vector of opaque-handle-wrapping values (`Expr`,
`Series`, `LazyFrame`, ...) across the C ABI -- mirrors [`_name_ptrs`](@ref) for `Vector{String}`.
`owned === xs` always (each element already owns a handle rather than needing conversion, unlike
`_name_ptrs`'s `Vector{Symbol}` case), kept as a separate return purely so both helpers share the
same `owned, ptrs = _thing_ptrs(...)` calling convention and the same "preserve `owned`, not your
original argument" discipline. `ptrs` is what goes into the ccall alongside `length(ptrs)`.

Takes the pointer type `P` (e.g. `Ptr{polars_expr_t}`) as an explicit argument rather than
dispatching on `eltype(xs)`: this file loads before `Expr`/`Series`/`LazyFrame` exist (see
`Polars.jl`'s `include` order), so a method specialized on any of those concrete types could not be
defined here -- this generic, duck-typed-on-`.ptr` form has no such dependency.
"""
_handle_ptrs(xs::AbstractVector, ::Type{P}) where {P} = (xs, P[x.ptr for x in xs])

"""
    _nullable_ref(x, ::Type{T}) where T -> Union{Ptr{T}, Ref{T}}

`x === nothing` yields the null pointer `Ptr{T}(C_NULL)`; otherwise `Ref(T(x))`. The `Ref` this
returns is a fresh local allocation and must be kept alive across the ccall that consumes it via
`GC.@preserve` *at the call site* -- exactly as if you had written the ternary by hand -- since a
`Ref` allocated before a ccall and only reachable through the ccall's own converted argument is a
live GC safepoint (see CLAUDE.md's marshalling section).
"""
_nullable_ref(x, ::Type{T}) where {T} = x === nothing ? Ptr{T}(C_NULL) : Ref(T(x))

"""
    _nullable_str(s::Union{Nothing,AbstractString}) -> (ptr, len::Int)

`s === nothing` yields `(Ptr{UInt8}(C_NULL), 0)`; otherwise `(s, ncodeunits(s))` -- the `(ptr, len)`
pair the C ABI expects for an optional string. Returns the string `s` itself (not a materialized
pointer) as the first element, exactly as every existing hand-written call site already did, so it
continues to rely on `ccall`'s own automatic rooting of a directly-passed `String` argument for the
duration of the call -- no additional `GC.@preserve` is needed for the string half specifically
(only for any *other* `Ref`s built alongside it, per [`_nullable_ref`](@ref) above).
"""
_nullable_str(s::Union{Nothing, AbstractString}) = s === nothing ? (Ptr{UInt8}(C_NULL), 0) : (s, ncodeunits(s))

"""
    _io_read(f) -> Vector{UInt8}

Calls `f(io::Ref{IOBuffer}, callback)` -- expected to invoke one `API.polars_*` ccall taking `io`
and `callback` as its trailing two arguments and returning a `*const polars_error_t`-shaped `err`
-- checks that `err` via [`polars_error`](@ref), and returns the bytes `f` wrote into `io[]`.
Shared by every FFI site that streams bytes back into a *fresh* Julia value (contrast
`write_csv`/`write_parquet`, which stream into a caller-supplied `io`, and so build their own
`_io_callback()`/`Ref(io)` pair directly rather than through this helper).
"""
function _io_read(f)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = f(io, callback)
    polars_error(err)
    return take!(io[])
end

"""
    @wrap_path_writer fname errmsg

**Use this when** an `fname(io::IO, df::DataFrame; kwargs...)` primal already exists and a
`path::String` local-file sibling is all that's missing. Generates:

    fname(p::String, df::DataFrame; kwargs...) = begin
        occursin("://", p) && error(errmsg)
        open(io -> fname(io, df; kwargs...), p, "w")
    end

Not a fit for `write_parquet`, whose `path::String` sibling *routes* a `"://"` path to
`sink_parquet` instead of erroring -- the one asymmetric case, which stays hand-written.
"""
macro wrap_path_writer(fname, errmsg)
    return esc(
        quote
            function $fname(p::String, df::DataFrame; kwargs...)
                occursin("://", p) && error($errmsg)
                return open(io -> $fname(io, df; kwargs...), p, "w")
            end
        end
    )
end

"""
    _resolve_descending(rev, n::Integer, prefix::AbstractString) -> Vector{Bool}

Broadcasts a bare `rev::Bool` to `n` copies, or validates an already-`Vector` `rev` has exactly `n`
entries -- one per `\$prefix expression` (`prefix` is e.g. `"sort"`/`"key"`/`"by"`). Raises an
`ArgumentError` naming `prefix` if the lengths disagree -- a real exception, not an `@assert`: this
validates caller-supplied input, which the Julia manual says assertions (removable, "this cannot
happen") must not be used for.
"""
function _resolve_descending(rev, n::Integer, prefix::AbstractString)
    descending = rev isa Bool ? fill(rev, n) : rev
    length(descending) == n || throw(
        ArgumentError(
            "rev must have one entry per $prefix expression (got $n $prefix expressions and " *
                "$(length(descending)) rev)"
        )
    )
    return descending
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

**Use this when** a wrapper already exists and you want its `|>` pipe form as well -- it is the
sibling of the other macros here, never an alternative to them.

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

An optional trailing `fix2 = true` (e.g. `@curry head(n::Expr) fix2 = true`) generates a
`Base.Fix2` instead of a closure -- `f(x) = Base.Fix2(f, x)` (or `convert(Expr, x)` in its place
per the same `::Expr`-annotation rule above) -- for the shape that has exactly one required
positional argument and no keywords, matching the convention every `Base.Fix2`-returning curry in
this package already follows (prints legibly at the REPL, unlike an anonymous closure). Only
applies to that one-positional-arg, no-keywords shape; using it with keywords or more than one
positional argument is an error at macro-expansion time.
"""
macro curry(sig, opts...)
    @assert sig isa Base.Expr && sig.head === :call "@curry expects a call signature, e.g. `@curry f(x; y=1)`"
    fix2 = false
    for opt in opts
        @assert opt isa Base.Expr && opt.head === :(=) && opt.args[1] === :fix2 "@curry: unknown option $opt (the only option is `fix2 = true`)"
        fix2 = opt.args[2] === true
    end
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

    if fix2
        @assert isempty(kwarg_decls) && length(posarg_decls) == 1 "@curry: fix2 = true only applies to a single required positional argument and no keywords"
        curry_def = Base.Expr(:(=), curry_sig, Base.Expr(:call, :(Base.Fix2), fname, posarg_forwards[1]))
        return_type = "Base.Fix2{typeof($fname)}"
    else
        call_args = Any[fname, :expr]
        append!(call_args, posarg_forwards)
        call_expr = Base.Expr(:call, call_args...)
        isempty(kwarg_forwards) || insert!(call_expr.args, 2, Base.Expr(:parameters, kwarg_forwards...))
        curry_def = Base.Expr(:(=), curry_sig, Base.Expr(:->, :expr, Base.Expr(:block, call_expr)))
        return_type = "Base.Callable"
    end

    docstring = """
        $(curry_sig)::$return_type

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
        error("@wrap_expr_method: can't process argument node $node")
    end
end

"""
    _gen_expr_parts(macro_name, sig) -> (gen_sig, fwd_args)

Shared signature processing for [`@wrap_expr_method`](@ref) and [`@wrap_rename_method`](@ref):
splits `sig` into its keyword and positional parts, checks it leads with `expr::Expr`, and runs every
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

"""Builds the `Docs.@doc` call every `@wrap_expr_method`-family macro attaches, documenting `gen_sig`
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
    _api_signature(cname) -> (arity, returns_error)

Reflects on the generated binding `API.cname`: how many arguments it takes, and whether it
reports failure by returning a `polars_error_t`.

Both facts come from `src/api/generated.jl`, which is itself generated from
`c-polars/include/polars.h` -- so whether a wrapper needs the out-param-and-`polars_error` shape
is *read off the C header* rather than restated at the call site, and cannot drift from it. The
generated bindings are plain, single-method, fixed-arity functions (no defaults, no varargs, no
keywords), which is what makes both numbers exact; the return type is the declared `@ccall`
return, so inference gives it precisely regardless of argument types.

The two answers cross-check each other, which is what makes this safe to rely on: a fallible
binding takes exactly one argument more than the call marshals (the out-param). So if the return
type were ever read wrong, the arity assertion in [`_resolve_fallible`](@ref) fails and the build
stops -- the failure mode is a loud error at expansion, never a silently mismatched body.
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

"""Decides which body [`@wrap_expr_method`](@ref) should emit for `cname`, given that the signature it
was handed marshals to `nargs` C arguments. Every mismatch is an error naming what was expected,
so a wrong argument list or a misspelled symbol fails at expansion rather than at the ccall."""
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

"""Emits the function definition for `gen_sig`, choosing the fallible or infallible body from
what the header says about `cname`. Shared by [`@wrap_expr_method`](@ref) and
[`@wrap_rename_method`](@ref) so there is one definition of each body rather than one per macro."""
function _gen_expr_body(macro_name, gen_sig, cname, fwd_args)
    api_fn = Base.Expr(:(.), :API, QuoteNode(cname))
    if _resolve_fallible(macro_name, cname, length(fwd_args))
        ccall_expr = Base.Expr(:call, api_fn, fwd_args..., :out)
        # Built with `Expr(:function, ...)` rather than `quote function $gen_sig ... end end`:
        # a whole signature cannot be interpolated into the syntactic position after `function`,
        # since the parser has to read a call shape there before any interpolation happens
        # ("invalid signature in function definition"). `@wrap_simple_ops` builds its
        # definitions the same way for the same reason.
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

**Use this when** the polars method is called on an expression and takes further arguments or
options -- `.str.contains(pat, strict)`, `Expr::clip(min, max)`. If it takes nothing beyond one
other expression, the `@wrap_simple_ops` block is the shorter route; if all it does is rename the
output column, use [`@wrap_rename_method`](@ref).

Generates the primal shape that most single-`Expr` wrappers share. Every argument after the
leading `expr::Expr` is forwarded to the ccall as a positional C argument, marshalled according to
its declared type annotation -- see [`_marshal_arg`](@ref) for that table.

**Whether `cname` is fallible is not something you declare here.** It is looked up from the
generated bindings at expansion time (see [`_api_signature`](@ref)), and the body follows:

    f(expr::Expr, args...) = Expr(API.cname(expr, args...))                    # infallible

    function f(expr::Expr, args...)                                            # fallible
        out = Ref{Ptr{polars_expr_t}}()
        err = API.cname(expr, args..., out)
        polars_error(err)
        return Expr(out[])
    end

That split is a fact about the C function, so restating it at the call site could only ever
disagree with the header. Per CLAUDE.md a fallible entry point *must* check `polars_error` --
a panic unwinding across `extern "C"` is undefined behaviour -- and generating the check from the
header means it cannot be forgotten or attached to the wrong function.

Only fits arguments whose marshalling `_marshal_arg` covers: `rolling_std`'s `ddof`
(`UInt8(ddof)`), `splitn`'s `n` (`Csize_t(n)`), every `Symbol`-to-enum keyword, and
`Strings.replace_n` (whose C parameter order differs from the Julia one) all stay hand-written.
Not used for a Base-colliding name (`Base.all`/`Base.any`/`Base.replace`), which would need the
`Base.`-qualification dance `@wrap_simple_ops` carries for that case.
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

**Use this when** the polars method does nothing but rename the output column from a single
string -- there are exactly three, and a fourth would go here too.

The output-name-rewriting shape shared by [`alias`](@ref)/[`prefix`](@ref)/[`suffix`](@ref):
exactly [`@wrap_expr_method`](@ref) over the fixed signature `f(expr::Expr, s::AbstractString)`
(so the `(ptr, ncodeunits)` marshalling comes from the same [`_marshal_arg`](@ref) rule as
everywhere else), plus two things that shape needs and the general macro does not emit:

- a `Base.Fix2` curry rather than [`@curry`](@ref)'s closure, so `alias("x")` still prints as
  something legible in the REPL;
- one docstring covering *both* signatures, matching what the hand-written originals carried.
"""
macro wrap_rename_method(fname, cname, desc)
    @assert fname isa Symbol && cname isa Symbol "@wrap_rename_method expects (fname::Symbol, cname::Symbol, desc::String)"
    gen_sig, fwd_args = _gen_expr_parts("@wrap_rename_method", :($fname(expr::Expr, s::AbstractString)))
    fn_def = _gen_expr_body("@wrap_rename_method", gen_sig, cname, fwd_args)
    # Attached to the two-argument *signature*, not the bare function name -- matching both the
    # hand-written original and `@wrap_simple_ops`. `docs/src/reference/expressions.md` lists
    # these in a `@docs` block by bare name, which pulls in every docstring attached to any method;
    # documenting the generic function instead would change what Documenter renders.
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

**Use this when** the polars function is a *free* function over any number of expressions rather
than a method on one -- `sum_horizontal(a, b, c)`, `as_struct(...)`. Anything called on a single
leading expression belongs to [`@wrap_expr_method`](@ref) or the `@wrap_simple_ops` block instead.

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

**Use this when** the polars method takes nothing beyond `self`, or exactly one other expression
and nothing else -- `Expr::sum`, `.str.len_bytes`, `Expr::is_in`, `.str.split`. The moment it takes
a third thing (an option, a count, a fill character), it belongs to [`@wrap_expr_method`](@ref).

A bulk declarative block: one line per wrapper, generating the function, its docstring, its export
(unless the name collides with `Base`), and optionally its `Base.Fix2` curry. Each entry name
mirrors a `macro_rules!` macro in `c-polars/src/expr.rs`, so the Rust declaration can be pasted
across and given a description. See "The block DSL" at the top of this file for what each part of
an entry does -- in short: `_binary` selects `f(a::Expr, b::Expr)` over `f(expr::Expr)`, the
`_list`/`_str`/`_dt` suffix is documentary, and `curried = true` is a Julia-only request for the
pipe form.

The bodies here are the infallible shape (`Expr(API.cname(expr))`), because the Rust
`gen_impl_expr*!` macros return the handle directly -- they marshal nothing that can be rejected.
A fallible C function belongs to [`@wrap_expr_method`](@ref) instead, which derives the
`polars_error` check from the header rather than taking your word for it.
"""
macro wrap_simple_ops(ex)
    @assert ex.head === :block
    out = Base.Expr(:block)
    for call in ex.args
        call isa Base.Expr || continue
        # Split the entry into `curried = true`-style options and the positional arguments. The
        # options come first in the AST (Julia puts `f(a, b; k = v)`'s `:parameters` node at
        # `args[2]`), so everything positional is read *after* stripping them -- indexing
        # `call.args` directly would shift by one the moment an entry takes an option.
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
        # Optional third positional: a hand-written description, e.g.
        # `gen_impl_expr!(polars_expr_sum, Expr::sum, "Sums the non-null values...")`, threaded
        # into the docstring below instead of the bare Rust-doc-link fallback.
        desc = length(entry_args) >= 3 ? entry_args[3] : nothing
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
        # The entry name is one of the `macro_rules!` names in `c-polars/src/expr.rs`, so a Rust
        # declaration can be pasted here and given a description. Matched against the shape of
        # that family rather than a substring search: `occursin("binary", ...)` would misfire on
        # any future polars method whose own name contains "binary", and a typo would silently
        # generate the unary form. Only `_binary` changes what is generated -- the namespace part
        # is documentary (the real namespace comes from the `ListNameSpace::max` argument), and is
        # matched here purely so the entry keeps mirroring Rust.
        entry_name = string(call.args[1])
        entry = match(r"^gen_impl_expr(_binary)?(_list|_str|_dt)?!$", entry_name)
        @assert entry !== nothing "@wrap_simple_ops: `$entry_name` is not one of the `gen_impl_expr*!` names from c-polars/src/expr.rs (did you mean to pass `curried = true` instead of a `_curried` suffix?)"
        is_binary = entry.captures[1] !== nothing
        # `curried = true` additionally emits `orig_fname(b) = Base.Fix2(orig_fname,
        # convert(Expr, b))` -- the `Base.Fix2` curry a binary op needs for `|>` pipelines
        # (`col("x") |> is_in([1, 2])`). It is an option rather than part of the entry name
        # because Rust has no `_curried` macro: currying is purely a Julia-side concern, and
        # spelling it as a suffix made four Julia-only inventions look like part of the mirror.
        # Guarded against `base_qualified`, not the weaker `base_collision`: a namespace submodule
        # (`split` in `Strings`, `round` in `Dt`) can collide with a Base name and still curry
        # unqualified fine, since its primal is already its own wholly local binding there (see
        # the base-collision note above) that the unqualified `orig_fname` in the curry correctly
        # picks up; only the top-level `Polars`-module + collision case (`base_qualified`) would
        # need `Base.orig_fname` qualification this curry doesn't attempt, so it's excluded.
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
