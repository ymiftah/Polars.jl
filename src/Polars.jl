module Polars

import PrecompileTools, PrettyTables, Tables

const MaybeMissing{T} = Union{T, Missing}
const PhysicalDType = Union{
    Bool, Int8, Int16, Int32, Int64, UInt8,
    UInt16, UInt32, UInt64, Float32, Float64,
}
const ColId = Union{String, Symbol}

nomissing(::Type{MaybeMissing{T}}) where {T} = T
nomissing(::Type{T}) where {T} = T

"Writes `len` bytes at `data` into `user` (an `IO` or a `Ref` to one); returns -1 on failure."
function _write_callback(user, data, len)
    return try
        n = unsafe_write(user isa IO ? user : user[], data, len)
        Int(n)
    catch
        -1
    end
end

"""
    _io_callback()

The `@cfunction` pointer for `_write_callback`, matching the C `IOCallback` signature. Used by
every FFI call that streams bytes into a Julia `IO`.
"""
_io_callback() = @cfunction(_write_callback, Cssize_t, (Any, Ptr{Cchar}, Csize_t))

include("./api/API.jl")

using .API

using Dates
using Statistics

# Wrapper-generating macros; included before any file that expands them.
include("./macros.jl")

# Arrow C Data Interface. See https://github.com/apache/arrow-julia/issues/184 for C Data
# Interface support in Arrow.jl.
include("./arrow/schema.jl")
include("./arrow/array.jl")
include("./series.jl")
include("./arrow/read.jl")
include("./value.jl")

"""
    version()::VersionNumber

Returns the rust Polars version with which the C-API was built.
"""
function version()
    out = Ref{Ptr{UInt8}}()
    len = polars_version(out)
    ver = unsafe_string(out[], len)
    return VersionNumber(ver)
end

"""
    PolarsError <: Exception

Raised when polars reports an error. `message` is polars' error text.
"""
struct PolarsError <: Exception
    message::String
end

Base.showerror(io::IO, err::PolarsError) = print(io, "PolarsError: ", err.message)

function polars_error(err::Ptr{polars_error_t})
    err == C_NULL && return
    str = Ref{Ptr{UInt8}}()
    len = polars_error_message(err, str)
    message = unsafe_string(str[], len)
    polars_error_destroy(err)
    throw(PolarsError(message))
end

# Include order: `DataFrame`/`LazyFrame` and `Expr` appear in method signatures below, and
# `struct.jl`/`selectors.jl` import `_name_ptrs` from `verbs.jl`.
include("./dataframe.jl")
include("./lazyframe.jl")

include("./expr/expr.jl")
include("./expr/ranges.jl")
include("./expr/statistics.jl")
include("./expr/list.jl")
include("./expr/string.jl")
include("./expr/datetime.jl")

include("./group_by.jl")
include("./select.jl")
include("./verbs.jl")

include("./expr/struct.jl")
include("./expr/selectors.jl")
include("./expr/meta.jl")

include("./join.jl")
include("./reshape.jl")
include("./sort.jl")
include("./describe.jl")
include("./io/partition.jl")
include("./io/cast_policy.jl")
include("./io/parquet.jl")
include("./io/csv.jl")
include("./io/ipc.jl")
include("./io/json.jl")

# `Expr` functions and the namespace submodules export their own names next to their definitions.
export Series, DataFrame, PolarsError, PartitionByKey, CastPolicy,
    read_series, names, dtype, native_repr,
    select, with_columns, head, tail, collect_schema,
    read_parquet, write_parquet, scan_parquet,
    read_csv, write_csv, scan_csv, sink_parquet,
    read_ipc, write_ipc, scan_ipc, sink_csv, sink_ipc,
    read_json, write_json, read_ndjson, write_ndjson, scan_ndjson, sink_ndjson,
    lazy, group_by, group_by_dynamic, rolling, agg, concat,
    innerjoin, leftjoin, rightjoin, outerjoin, semijoin, antijoin, crossjoin, join_asof,
    drop, rename, drop_nulls, with_row_index, explode, unpivot, unnest, nth,
    describe, pivot, upsample, hstack, vstack, transpose, get_column

# Precompilation to reduce TTFX.
PrecompileTools.@compile_workload begin
    df = DataFrame((; a = [1, 2, 3], b = ["x", "y", "z"]))
    lf = lazy(df)
    lf = select(lf, col("a"), col("b"))
    lf = filter(lf, col("a") > 1)
    out = collect(lf)
    collect(out["a"])
    collect(out["b"])
end

end # module Polars
