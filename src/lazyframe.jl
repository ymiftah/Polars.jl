mutable struct LazyFrame
    ptr::Ptr{polars_lazy_frame_t}

    LazyFrame(ptr) =
        finalizer(polars_lazy_frame_destroy, new(ptr))
end

Base.unsafe_convert(::Type{Ptr{polars_lazy_frame_t}}, df::LazyFrame) = df.ptr

"""
    Base.show(io::IO, lf::LazyFrame)

Prints the column names (resolved via [`collect_schema`](@ref), which -- unlike
[`collect`](@ref) -- doesn't execute the query) rather than the default `mutable struct` dump,
which would otherwise leak the raw `Ptr` value with no useful information alongside it. Falls
back to a bare `"LazyFrame"` if the plan can't be resolved (e.g. it references a column that
doesn't exist) -- a `show` method raising its own error on top of the frame's real problem would
only obscure it.
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

Returns a lazy frame over the provided dataframe.

See also [`collect`](@ref).
"""
function lazy(df)
    out = polars_dataframe_lazy(df)
    return LazyFrame(out)
end

"""
    collect(lf::LazyFrame; engine=:default)::DataFrame

Materializes the lazy frame as a DataFrame.
`engine` can be either `:default` (in-memory engine) or `:streaming`.
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
operations (`select`, `filter`, etc.) always clone their input first (see CLAUDE.md's ownership
conventions), so this is only needed when you want an explicit, independent handle to the same
plan -- e.g. to branch it into two different downstream queries without one affecting the other.
"""
function clone(df::LazyFrame)
    out = polars_lazy_frame_clone(df)
    return LazyFrame(out)
end
"""
    collect_schema(lf::LazyFrame)::Tables.Schema

Resolves and returns the schema of the provided lazy frame, without collecting it.

Since this does not execute the query, actual null counts are unknown and every column is
reported as nullable (`Union{T,Missing}`); see [`schema`](@ref) for a `DataFrame`'s schema
refined by actual null counts.
"""
function collect_schema(df::LazyFrame)
    out = Ref{CArrowSchema}()
    err = polars_lazy_frame_collect_schema(df, out)
    polars_error(err)
    return load_dataframe_schema(out[])
end
