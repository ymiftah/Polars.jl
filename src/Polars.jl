module Polars

import PrecompileTools, PrettyTables, Tables

const MaybeMissing{T} = Union{T, Missing}
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

"""
    _io_callback()

Builds the `@cfunction` pointer for [`_write_callback`](@ref), shared by every FFI site that
streams bytes back into a Julia `IO` (parquet/CSV/IPC writers, `Value` string/binary getters).
Defined once here, rather than re-typed at each call site, so the argument types can't drift
from the C `IOCallback` typedef again -- the length argument was `Cuint` (32-bit) at all 5 sites
until this fix, silently narrowing the C side's `uintptr_t` (64-bit on any real platform).
"""
_io_callback() = @cfunction(_write_callback, Cssize_t, (Any, Ptr{Cchar}, Csize_t))

include("./api/API.jl")

using .API

using Dates
using Statistics

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

Raised when the underlying Rust polars library reports a failure -- an unexecutable query, a
malformed argument to a fallible operation (e.g. an invalid duration string), and the like.
`message` is polars' own (Rust-side) error text, unmodified.
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

include("./group_by.jl")
include("./select.jl")
include("./verbs.jl")

# `expr/struct.jl` must follow `verbs.jl`: `Structs.rename_fields` does `using ..Polars:
# _name_ptrs`, and `using`-ing a name before its defining `include` has run produces an
# "Imported binding was undeclared at import time" warning (harmless at runtime -- Julia resolves
# it once `Polars` finishes loading -- but avoidable by just respecting the real dependency order).
include("./expr/struct.jl")

# `expr/selectors.jl` must likewise follow `verbs.jl` (its `module Selectors` also does `using
# ..Polars: _name_ptrs`, for `by_name` -- same reasoning as `struct.jl` just above). Its top-level
# section (before its own `module Selectors`) separately requires `expr/expr.jl` to already be
# loaded: it adds a new `_as_expr` method for the `Selector` type it defines, extending the
# function `expr/expr.jl` first declares -- see that file's own header comment for why the method
# lives in a different file from `_as_expr`'s others. Both orderings hold simultaneously since
# `expr/expr.jl` loads well before `verbs.jl` already.
include("./expr/selectors.jl")

# `expr/meta.jl` (`module Meta`) has no `_name_ptrs`-style ordering dependency of its own (unlike
# `struct.jl`/`selectors.jl` just above), but lives in this same family -- grouped here rather
# than immediately after `expr/expr.jl` purely for stylistic proximity to its siblings.
include("./expr/meta.jl")

include("./join.jl")
include("./reshape.jl")
include("./sort.jl")
include("./describe.jl")
include("./io/parquet.jl")
include("./io/csv.jl")
include("./io/ipc.jl")

# `Expr` methods (both the `@generate_expr_fns`-generated ones and the hand-written ones needing
# extra args the macro's plain shape can't express, e.g. `mean`/`median`/`std`/`var`/`quantile`)
# export themselves inline in src/expr/expr.jl, next to their definitions, rather than here --
# see that file for the full list. The `Lists`/`Strings`/`Dt`/`Structs` namespace submodules
# likewise export their own members from their own files, for qualified use (`Lists.get`, etc.).
export Series, DataFrame, PolarsError,
    read_series, names,
    select, with_columns, head, tail, collect_schema,
    read_parquet, write_parquet, scan_parquet,
    read_csv, write_csv, scan_csv, sink_parquet,
    read_ipc, write_ipc, scan_ipc, sink_csv, sink_ipc,
    lazy, group_by, group_by_dynamic, rolling, agg, concat,
    innerjoin, leftjoin, rightjoin, outerjoin, semijoin, antijoin, crossjoin, join_asof,
    drop, rename, drop_nulls, with_row_index, explode, unpivot, unnest, nth,
    describe, pivot, upsample, hstack, vstack, transpose

# Cuts TTFX: without this, the first `DataFrame`/`select`/`filter`/`collect` call in a fresh
# session pays full compilation for the whole eager-via-lazy pipeline plus both bulk-read paths
# (numeric and string/view) exercised below.
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
