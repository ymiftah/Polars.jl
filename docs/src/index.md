# Polars.jl

Polars.jl is a thin Julia wrapper around [polars](https://pola.rs), the Rust dataframe library —
built as a hand-written C ABI bridge over the upstream `polars` crate, not a reimplementation.
Query logic runs entirely inside polars; Polars.jl just marshals expressions and frames across the
boundary.

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

- **[Getting Started](@ref)** — a guided, narrative walk through a small analytics workflow, from
  your first `DataFrame` to combining several operations into one pipeline. Start here if you're
  new to Polars.jl.
- **[Reference](@ref)** — a topic-organized manual covering every public function. Use this once
  you know roughly what you're looking for.
- **[Limitations](@ref)** — known gaps and sharp edges (a broken namespace function, a few names
  that need explicit `Base.` qualification, etc.) worth skimming before you hit them yourself.

## Eager vs. lazy, in one line

`DataFrame` is eager (every operation runs immediately); a lazy frame — obtained via
`lazy` — only records operations, letting polars optimize and fuse the whole
query before executing it via `collect`. Eager operations are implemented as `collect ∘ op ∘ lazy`
under the hood, so both forms give identical results; the [Laziness](@ref) reference page covers
this in depth.

## Installation

```julia-repl
pkg> add Polars
```
