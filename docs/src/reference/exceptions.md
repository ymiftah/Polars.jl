# Exceptions

Errors reported by polars are raised as a `PolarsError`.

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
