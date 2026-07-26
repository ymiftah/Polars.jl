# Exceptions

Every fallible operation in Polars.jl — a bad column name, a type mismatch, an unparseable
duration string, and so on — raises a single exception type rather than a hierarchy of specific
error types.

```@docs
PolarsError
```

```julia
using Polars
try
    select(DataFrame((; x = [1])), col("does_not_exist"))
catch e
    e isa PolarsError  # true
end
```

The error message is whatever polars itself produced on the Rust side, stringified and boxed across
the FFI boundary — see the "Error handling" section of the project notes for the out-parameter
convention every fallible `ccall` follows internally.
