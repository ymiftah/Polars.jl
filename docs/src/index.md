# Polars.jl

Polars.jl is a thin Julia wrapper around [polars](https://pola.rs), the Rust dataframe library.
Query logic runs entirely inside polars, exposed through an idiomatic Julia API.

!!! note "Fork notice"
    This is a fork of [pangoraw/Polars.jl](https://github.com/pangoraw/Polars.jl) by Paul Berg, who
    designed the original C ABI bridge and wrapper architecture this package still follows — this
    fork continues that work rather than inventing a new approach. Much of the code and docs in
    this fork were written with heavy AI assistance and are **still under review**; treat it as
    less vetted than the upstream project until that review is further along.

!!! warning "Experimental — read before using"
    - This package is **very experimental and not battle-tested**. Expect rough edges (see
      [Limitations](@ref)) and breaking changes.
    - If your data fits comfortably in memory, use a native Julia dataframe library like
      [DataFrames.jl](https://github.com/JuliaData/DataFrames.jl) instead. Polars.jl exists to make
      polars' **larger-than-RAM** capabilities (lazy scans, streaming execution, out-of-core
      `sink_*` writes) available from Julia — that's its main reason to exist, not a general-purpose
      DataFrames.jl replacement.
    - This is an independent, community wrapper — **it is not affiliated with or endorsed by the
      polars team**.

```julia
julia> using Polars

julia> df = DataFrame((; store = ["a", "a", "b"], revenue = [10.0, 25.0, 5.0]))
3×2 DataFrame
 store   revenue
 String  Float64
─────────────────
      a     10.0
      a     25.0
      b      5.0

julia> @chain df begin
           lazy
           group_by("store")
           agg(sum(col("revenue")) |> alias("total"))
           sort(col("total"); rev = true)
           collect
       end
2×2 DataFrame
 store   total
 String  Float64
─────────────────
      a     35.0
      b      5.0
```

## Where to start

- [Getting Started](@ref): a tutorial that builds up a small analytics workflow.
- [Reference](@ref): every public function, by type.
- [Limitations](@ref): known gaps, and names that must be called qualified.

## Eager and lazy

Operations on a `DataFrame` run immediately. A `LazyFrame`, obtained with `lazy`, records
operations into a query plan that polars optimizes and runs on `collect`. Both give the same
result; see [LazyFrame](@ref).

## Installation

Not yet registered in the General registry — install directly from the repo:

```julia-repl
pkg> add https://github.com/ymiftah/Polars.jl
```