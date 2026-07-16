using Clang.Generators

cd(@__DIR__)

include_dir = normpath(joinpath(@__DIR__, "../c-polars/include"))
headers = [joinpath(include_dir, "polars.h")]

options = load_options(joinpath(@__DIR__, "generator.toml"))

args = get_default_args()
push!(args, "-I$include_dir")

ctx = create_context(headers, args, options)

build!(ctx)
