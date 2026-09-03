"""
    LazyFrame

A lazy frame: operations are only recorded into a query plan, not executed, until
[`collect`](@ref) runs the whole thing (optionally fused and reordered by polars' query
optimizer). Obtained from a [`DataFrame`](@ref) via [`lazy`](@ref), or directly via
`scan_parquet`/`scan_csv`/`scan_ipc`.
"""
mutable struct LazyFrame
    ptr::Ptr{polars_lazy_frame_t}

    LazyFrame(ptr) =
        finalizer(polars_lazy_frame_destroy, new(ptr))
end

Base.unsafe_convert(::Type{Ptr{polars_lazy_frame_t}}, df::LazyFrame) = df.ptr

# lazy is a no-op on a LazyFrame, same as in py-polars
lazy(df::LazyFrame) = identity(df)

"""
    Base.show(io::IO, lf::LazyFrame)

Prints the column names (resolved via [`collect_schema`](@ref), which doesn't execute the query),
or a bare `"LazyFrame"` if the plan can't be resolved (e.g. it references a column that doesn't
exist).
"""
function Base.show(io::IO, lf::LazyFrame)
    print(io, "LazyFrame(")
    try
        print(io, join(collect_schema(lf).names, ", "))
    catch
        print(io, "?")
    end
    return print(io, ")")
end

"""
    lazy(df::DataFrame)::LazyFrame

Converts `df` into a `LazyFrame`.

See also [`collect`](@ref).
"""
function lazy(df::DataFrame)
    out = polars_dataframe_lazy(df)
    return LazyFrame(out)
end

"""
    collect(lf::LazyFrame; engine=:default)::DataFrame

Execute all the lazy operations and collect them into a [`DataFrame`](@ref). The query is
optimized prior to execution.

Note: `engine` selects `:default` (the in-memory engine) or `:streaming` explicitly; upstream's
own default additionally auto-selects between engines, which this wrapper does not expose.
"""
function Base.collect(df::LazyFrame; engine = :default)
    engine = engine === :default ? API.PolarsEngineInMemory : engine === :streaming ? API.PolarsEngineStreaming : error("unknown engine $engine, expected one of (:default, :streaming)")
    out = Ref{Ptr{polars_dataframe_t}}()
    err = polars_lazy_frame_collect(df, engine, out)
    polars_error(err)
    return DataFrame(out[])
end
"""
    clone(lf::LazyFrame)::LazyFrame

Returns a new `LazyFrame` wrapping a clone of `lf`'s underlying query plan. Mutating in-place
operations (`select`, `filter`, etc.) always clone their input first, so this is only needed
when you want an explicit, independent handle to the same plan -- e.g. to branch it into two
different downstream queries without one affecting the other.
"""
function clone(df::LazyFrame)
    out = polars_lazy_frame_clone(df)
    return LazyFrame(out)
end
"""
    collect_schema(lf::LazyFrame)::Tables.Schema

A handle to the schema — a map from column names to data types — of the current `LazyFrame`
computation, without executing the query.

Note: unlike upstream, whose schema carries no nullability, this wrapper must choose between `T`
and `Union{T,Missing}` per column; since the query hasn't run, actual null counts are unknown and
every column is conservatively reported as nullable. See [`schema`](@ref) for a `DataFrame`'s
schema refined by actual null counts.
"""
function collect_schema(df::LazyFrame)
    out = Ref{CArrowSchema}()
    err = polars_lazy_frame_collect_schema(df, out)
    polars_error(err)
    return load_dataframe_schema(out[])
end

"""
    explain(df::LazyFrame; optimized::Bool=true)::String

Return a `String` describing `df`'s logical plan. If `optimized` is `true` (the default), explains
the optimized plan — after predicate/projection pushdown and the other optimizer passes. If
`optimized` is `false`, explains the naive, un-optimized plan.
"""
function explain(df::LazyFrame; optimized::Bool = true)
    io = Ref(IOBuffer())
    callback = _io_callback()
    err = API.polars_lazy_frame_explain(df, optimized, io, callback)
    polars_error(err)
    return String(take!(io[]))
end

"""
    cache(df::LazyFrame)::LazyFrame

Caches the result into a new `LazyFrame`. This should be used to prevent computations running
multiple times.
"""
function cache(df::LazyFrame)
    out = clone(df)
    API.polars_lazy_frame_cache(out)
    return out
end

export explain, cache
