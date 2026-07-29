# Polars.jl

[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://ymiftah.github.io/Polars.jl/dev/)
[![codecov](https://codecov.io/gh/ymiftah/Polars.jl/graph/badge.svg)](https://codecov.io/gh/ymiftah/Polars.jl)
[![Aqua QA](https://juliatesting.github.io/Aqua.jl/dev/assets/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

Polars.jl is a thin wrapper for Julia around the dataframe manipulation library [polars](https://github.com/pola-rs/polars).

> **Fork notice:** this is a fork of [pangoraw/Polars.jl](https://github.com/pangoraw/Polars.jl) by
> Paul Berg, who designed the original C ABI bridge and wrapper architecture this package still
> follows — this fork continues that work rather than inventing a new approach. Much of the code
> and docs in this fork were written with heavy AI assistance and are **still under review**; treat
> it as less vetted than the upstream project until that review is further along.

## Installation

Not yet registered in the General registry — install directly from the repo:

```julia-repl
pkg> add https://github.com/ymiftah/Polars.jl
```

The native `libpolars` library ships as a prebuilt binary artifact, so no Rust toolchain is needed.
Binaries are published for:

| Platform | Notes |
|---|---|
| `x86_64` Linux (glibc) | requires glibc ≥ 2.34 |
| `aarch64` macOS (Apple Silicon) | macOS ≥ 11 |

On any other platform, installation succeeds but loading raises an error telling you to build from
source — see [Polars C-API](#polars-c-api) below. A local `cargo build` always takes precedence over
the downloaded artifact, so contributors get their own build automatically.

> Polars.jl does **not** use the registered `libpolars_jll`. That JLL is built from the original
> upstream repo and exposes far fewer C ABI symbols than this fork needs.

## See Also

Julia already has a very good dataframe story with [DataFrames.jl](https://github.com/JuliaData/DataFrames.jl), which provides a more Julian experience since any types of collections can be used as a column.
On the other hand, Polars works through the Arrow data format and therefore only supports certain physical vectors (materialized in memory) such as `Vector{Int}`.
Polars.jl focuses on wrapping operations on lazy frames since it is one of the main differentiating factor with DataFrames. Consider trying DataFrames.jl
if your problem involves a lot of Julia "interopability" where Polars would not offer the same level of interopability.


## Example

This walkthrough is illustrative -- the referenced parquet files aren't shipped with this
repository; substitute your own data to follow along.

```julia
julia> using Polars

julia> customers = read_parquet("NONE_pandas_pyarrow_customer.parquet") |> lazy;

julia> nations = read_parquet("NONE_pandas_pyarrow_nation.parquet") |> lazy;

julia> customers_nations = innerjoin(customers, nations, col("nation_key"));

julia> gb = group_by(customers_nations, [col("nation_key")]);

julia> gbagg = agg(gb,
           col("name") |> alias("customer_names"),
           col("name_right") |> first |> Strings.lowercase,
           col("acctbal") |> mean,
       );

julia> gbagg_sorted = sort(gbagg, "name_right");

julia> select(gbagg_sorted,
           col("name_right") |> alias("nation_name"),
           col("customer_names"),
           col("acctbal"),
        ) |> collect
25×3 DataFrame
 nation_name  customer_names                    acctbal 
 String       Series{Union{Missing, String}}    Float64 
────────────────────────────────────────────────────────
     algeria  ["Customer#000000029", "Custome…   4442.7
   argentina  ["Customer#000000003", "Custome…   4485.0
      brazil  ["Customer#000000017", "Custome…  4471.02
      canada  ["Customer#000000005", "Custome…  4489.26
       china  ["Customer#000000007", "Custome…  4438.95
       egypt  ["Customer#000000004", "Custome…  4520.49
    ethiopia  ["Customer#000000010", "Custome…  4467.37
      france  ["Customer#000000018", "Custome…  4436.01
      ⋮                      ⋮                     ⋮
                                         17 rows omitted
```

## Polars C-API

To build the polars c-api, run the following commands:

```
cd c-polars
cargo build # --release
```

This is mostly helpful for development to test C-API changes with the Julia version.
[A header file]() is also included if one wants to use the API from C directly.
