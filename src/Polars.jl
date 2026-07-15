module Polars

import PrettyTables, Tables

const MaybeMissing{T} = Union{T, Union{T, Missing}}
const PhysicalDType = Union{
    Bool, Int8, Int16, Int32, Int64, UInt8,
    UInt16, UInt32, UInt64, Float32, Float64,
}

nomissing(::Type{MaybeMissing{T}}) where {T} = T
nomissing(::Type{T}) where {T} = T

"Internal function to write back to an IO from rustland"
function _write_callback(user, data, len)
    return try
        n = unsafe_write(user isa IO ? user : user[], data, len)
        Int(n)
    catch
        -1
    end
end

include("./api/API.jl")

using .API

using Dates

include("./arrow/schema.jl")
include("./arrow/array.jl")
include("./series.jl")
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

function polars_error(err::Ptr{polars_error_t})
    err == C_NULL && return
    str = Ref{Ptr{UInt8}}()
    len = polars_error_message(err, str)
    message = unsafe_string(str[], len)
    polars_error_destroy(err)
    error(message)
end

# `dataframe.jl`/`lazyframe.jl` must precede every other file below: they define `DataFrame`
# and `LazyFrame`, which appear as eager type annotations (`df::DataFrame`, `lf::LazyFrame`) in
# nearly every verb's method signature -- unlike a plain call inside a function body, a type
# annotation in a signature is resolved the moment that method is defined, not lazily.
include("./dataframe.jl")
include("./lazyframe.jl")

# `expr/*.jl` must precede `reshape.jl`: `pivot`'s `agg::Expr` keyword argument is itself an
# eager type annotation needing `Expr` already defined.
include("./expr/expr.jl")
include("./expr/list.jl")
include("./expr/string.jl")
include("./expr/datetime.jl")
include("./expr/struct.jl")

include("./group_by.jl")
include("./select.jl")
include("./verbs.jl")
include("./join.jl")
include("./reshape.jl")
include("./sort.jl")
include("./describe.jl")
include("./io/parquet.jl")
include("./io/csv.jl")
include("./io/ipc.jl")

export Series, DataFrame,
    select, with_columns, head, collect_schema,
    read_parquet, write_parquet, scan_parquet,
    read_csv, write_csv, scan_csv, sink_parquet,
    read_ipc, write_ipc, scan_ipc, sink_csv, sink_ipc,
    lazy, group_by, group_by_dynamic, rolling, agg, concat,
    innerjoin, leftjoin, rightjoin, outerjoin, semijoin, antijoin, crossjoin, join_asof,
    drop, with_row_index, explode, unpivot

end # module Polars
