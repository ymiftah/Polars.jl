### A Pluto.jl notebook ###
# v0.20.17

using Markdown
using InteractiveUtils

# ╔═╡ 402e585a-940e-4b8a-b88b-6056cb8da169
# ╠═╡ show_logs = false
import Pkg; Pkg.activate(temp=true)

# ╔═╡ 3612e7ca-ce1f-4674-b473-8f9f21b5391a
# ╠═╡ show_logs = false
Pkg.develop(url=joinpath(@__DIR__, "..")); Pkg.add("PlutoUI")

# ╔═╡ 527c1a41-fb67-4642-b2d6-20369a3a00c3
using Polars

# ╔═╡ 4d7c1c89-e30b-419d-80c8-0cadd4eef740
using PlutoUI

# ╔═╡ e2e91bde-514d-11ee-05f7-059ef81a44ec
md"""
# Polars.jl
"""

# ╔═╡ 3e5ede95-8dbc-4e30-8e3b-8cb7e3d7bb3a
md"""
Polars.jl is a frontend for the [polars](pola.rs) dataframe library for the [Julia programming language](https://julialang.org).
"""

# ╔═╡ 51bdfbba-b75b-429d-958d-d8ec64c52c62
md"""
## Structures

Polars being a dataframe library, it provides a `DataFrame` struct. A `DataFrame` is a columnar table where each column can have a different data type and a name.
"""

# ╔═╡ cd43bc4f-8659-4584-b9bb-bfa989297e74
md"""
Dataframes can be constructed from objects implementings the [Tables.jl](https://github.com/juliadata/tables.jl) interface.
"""

# ╔═╡ 0841cf66-c999-43af-84a8-5a4abfde68ba
DataFrame((;
	quantity = [1,         2,          missing      ],
	price =    [1.2,       2.3,        4.5          ],
	items =    ["eggs 🥚", "cheese 🧀", "tomatoes 🍅"],
))

# ╔═╡ 82f16419-11de-4055-8796-cc36aece3f8a
md"""

Polars datatypes map to the corresponding Julia type according to this correspondance table:

| Polars dtype | Julia type |
|--------------|------------|
| Null         | Missing    |
| Boolean      | Bool       |
| UInt8        | UInt8      |
| UInt16       | UInt16     |
| UInt32       | UInt32     |
| UInt64       | UInt64     |
| Int8         | Int8       |
| Int16        | Int16      |
| Int32        | Int32      |
| Int64        | Int64      |
| Float32      | Float32    |
| Float64      | Float64    |
| UTF8         | String     |
| List<t>      | Series{T}  |
| Struct       | NamedTuple |
| Datetime<t>  | DateTime   |
| Duration<t>  | Period     |
"""

# ╔═╡ 466c8871-e7be-4731-a347-ce6faabf8edb
md"""
## Lazyness 😴
"""

# ╔═╡ 5b87268c-f807-445f-ba69-16b6774cfed1
let df = DataFrame((; x = [1,2,3]))

	# All operations on lazy_frame are recorded
	# but are only materialized when the lazy frame
	# is collected using `collect`.
	lazy_frame = lazy(df)

	# Manipulate lazy_frame
	lazy_frame = select(lazy_frame, col("x") * 2)
	lazy_frame = filter(lazy_frame, col("x") > 2.5)

	# Collect the resulting lazy frame
	collect(lazy_frame)
end

# ╔═╡ 98292e8b-810a-44e3-834b-b6bfd6a184fb
md"""
## Manipulation
"""

# ╔═╡ a0898cdf-7630-4519-a7e7-3ba114989a5c
Docs.Binding(Polars, :select)

# ╔═╡ 00b9020f-e05b-4e36-bee8-71da1ce7aeeb
let df = DataFrame((; x=[1,2,3]))
	select(df, (col("x") + 2) |> alias("x + 2"), col("*"))
end

# ╔═╡ f9459d17-b568-4b7c-b15a-7df28b1037d8
let df = DataFrame((; x=[1,2,3]))
	with_columns(df, (col("x") + 2) |> alias("x + 2"))
end

# ╔═╡ 79099779-5108-445a-87b7-ef1f9b253550
let df = DataFrame((; x=[1,2,3]))
	filter(df, col("x") > 1)
end

# ╔═╡ 659172c1-59b2-4176-97bc-263a6cc19f0a
Docs.Binding(Polars, :group_by)

# ╔═╡ 6e3cfe39-5050-4c0c-af80-7c5e1064a07e
Docs.Binding(Polars, :agg)

# ╔═╡ 94d7f868-cf5b-4cb8-ba10-55cd97724586
Docs.Binding(Polars, :innerjoin)

# ╔═╡ 6703a1c7-1e6d-4bf7-b014-f71b1404225f
md"""
## Expressions

Expressions are used to express transformation in a symbolic manner.

For example, the following expression will express that the result should be the content of column `price` multiplied with the literal value `1.5`.
"""

# ╔═╡ 2dfbdb6a-8057-4610-af28-a808d664daf9
1.5 * col("price")

# ╔═╡ f0be17b6-80a1-454a-a1db-e2af2da30139
Docs.Binding(Polars, :col)

# ╔═╡ 88841d06-f52e-4d36-9357-ccc3c1360c79
Docs.Binding(Polars, :alias)

# ╔═╡ a67a0544-a1c5-4218-a80d-a0eb5a5ce92c
Docs.Binding(Polars, :prefix)

# ╔═╡ a4cd8ed5-d8e8-4907-ab33-176f906d1e3b
Docs.Binding(Polars, :suffix)

# ╔═╡ 5eebab5d-7a2f-4602-9466-8b1ab0fa54df
md"""
### `Polars.Lists`

The `Polars.Lists` module provide functions to create and transform expressions operating on expressions of type [`List`](https://docs.rs/polars/latest/polars/prelude/enum.DataType.html#variant.List).
"""

# ╔═╡ 351798d4-ede7-4025-bfab-01b9d3984741
md"""
### `Polars.Strings`

The `Polars.Strings` module provide functions to create and transform expressions operating on expressions of type [`Utf8`](https://docs.rs/polars/latest/polars/prelude/enum.DataType.html#variant.Utf8).

"""

# ╔═╡ 01de6a83-f99f-4a0a-ab97-a3bbea522164
md"""
### `Polars.Structs`
The `Polars.Structs` module provide functions to create and transform expressions operating on expressions of type [`Struct`](https://docs.rs/polars/latest/polars/prelude/enum.DataType.html#variant.Struct).
"""

# ╔═╡ 93a5d8c8-e667-4e11-a955-e819ea07e8b9
md"""
## IO
"""

# ╔═╡ d3701d1c-1846-46b6-9e6a-39c3e4b82107
Docs.Binding(Polars, :read_parquet)

# ╔═╡ 4645fb6e-e660-4432-a70e-bda3216ece86
Docs.Binding(Polars, :write_parquet)

# ╔═╡ 8f5d7589-c46e-4d3d-bdae-408d6d830ef9
md"""
## Utils
"""

# ╔═╡ aef197d8-81a6-4553-b322-13169e8f1bfc
Polars.version()

# ╔═╡ 6236416d-97e9-4a55-bd89-95f478b5affb
md"""
For example, these docs were generated for polars **v$(Polars.version() |> string)**.
"""

# ╔═╡ 4ab79cc8-1c0b-4d6a-b7d4-f45ba1875b09
md"""
---
"""

# ╔═╡ 28849b97-81a0-4bba-9254-5194c3488035
function module_selector(base_module, mod)
	isdefined(base_module, nameof(mod)) &&
		getproperty(base_module, nameof(mod)) === mod ?
		string(nameof(mod)) : module_selector(base_module, parentmodule(mod)) * "." * nameof(mod)
end;

# ╔═╡ bd9c684f-3668-4549-8ff8-a11c4f94a5fe
begin
	struct Binding
		mod::Module
		name::Symbol
		sig::Any
	end
	Binding(mod, name) = Binding(mod, name, nothing);
	
	function Base.show(io::IO, ::MIME"text/html", b::Binding)
		name = isdefined(@__MODULE__, b.name) &&
			getproperty(@__MODULE__, b.name) === getproperty(b.mod, b.name) ?
			b.name : string(module_selector(@__MODULE__, b.mod), ".", b.name)

		doc = Docs.meta(b.mod)[Docs.Binding(b.mod, b.name)].docs |>
				values |> first
		doc = first(doc.text) |> Markdown.parse
		
		docstring = repr(MIME"text/html"(), doc) 
		r = """
		<div class="pluto-docs-binding">
		<span>$(name)</span>
		$(docstring)
		</div>
		"""
		write(io, r)
	end
end

# ╔═╡ b6eff110-9d21-4583-babc-eeafa5ea4749
Binding(Polars, :DataFrame)

# ╔═╡ 7cf29bf5-b57e-4482-aff0-285a55f29260
Binding(Polars, :Series)

# ╔═╡ 69abd0c5-e6b8-44df-bee1-9502d6a9aa76
Binding(Polars, :lazy)

# ╔═╡ 2497da50-f439-4551-ab8f-41a783a02e66
Binding(Polars, :collect)

# ╔═╡ 6cabf4ea-cf1e-4e91-a2dd-ebf97245cca9
Binding(Polars, :with_columns)

# ╔═╡ 10848dd7-f82d-49bd-aa8e-3524b8dc35d6
Binding(Polars, :filter, Tuple{Polars.LazyFrame, Polars.Expr})

# ╔═╡ ca6a03f8-0b5a-47d8-b22f-16fbbd66c0fe
Binding(Polars, :sort)

# ╔═╡ 24fe0edd-eae2-4051-981f-e1951579c9e3
Binding(Polars, :keep_name)

# ╔═╡ b90c70c6-19e2-46f7-83b7-1145eaf2c7b9
Binding(Polars, :lit)

# ╔═╡ 33a72173-b972-4434-b5e7-55411acba353
Binding(Polars, :cast)

# ╔═╡ 79d753e6-8d92-4030-9a98-a9da9dcaa244
let
	names = [:and, :not, :or, :mean, :median, :is_finite, :is_infinite, :is_nan, 			:is_null, :is_not_null, :drop_nans, :drop_nulls, :implode, :flatten,
			 :nan_min, :nan_max, :arg_min, :arg_max]
	Markdown.MD(map(names) do name
		Markdown.Paragraph([Binding(Polars, name), Markdown.LineBreak()])
	end)
end

# ╔═╡ 4f19cb30-d540-4f3a-986e-295a4f892e31
Markdown.MD(map(filter(!=(:Lists), names(Lists))) do name
	Markdown.Paragraph([Binding(Lists, name), Markdown.LineBreak()])
end)

# ╔═╡ 791fadd8-e5d5-408e-88ef-649791b2f0a5
Markdown.MD(map(filter(!=(:Strings), names(Strings))) do name
	Markdown.Paragraph([Binding(Strings, name), Markdown.LineBreak()])
end)

# ╔═╡ 231c0ac5-7b76-4735-a77c-a7572e707ab7
Binding(Polars.Structs, :field_by_name)

# ╔═╡ 9e591afb-2004-4a8a-8fbb-31618c46f52f
Binding(Polars.Structs, :field_by_index)

# ╔═╡ 2fd11dc3-6bca-4254-ba7b-45cd99ff654f
Binding(Polars.Structs, :rename_fields)

# ╔═╡ b6c70ba2-25a8-468f-a2d5-5191017ea24a
Binding(Polars, :version)

# ╔═╡ a23e1e66-b71f-4ebd-87ad-82d0a08a1f98
TableOfContents(include_definitions=true)

# ╔═╡ 54f08991-5fb4-4deb-a546-a11bdc2f0f49
html"""
<script>
	const elts = document.querySelectorAll("code")
	for (let elt of elts) {
		elt.classList.add("hljs")
		elt.classList.add("language-julia")
	}
	window.hljs.configure({languages: ["julia"]})
	window.hljs.highlightAll()
</script>
"""

# ╔═╡ Cell order:
# ╟─e2e91bde-514d-11ee-05f7-059ef81a44ec
# ╟─3e5ede95-8dbc-4e30-8e3b-8cb7e3d7bb3a
# ╠═527c1a41-fb67-4642-b2d6-20369a3a00c3
# ╟─51bdfbba-b75b-429d-958d-d8ec64c52c62
# ╟─b6eff110-9d21-4583-babc-eeafa5ea4749
# ╟─cd43bc4f-8659-4584-b9bb-bfa989297e74
# ╠═0841cf66-c999-43af-84a8-5a4abfde68ba
# ╟─7cf29bf5-b57e-4482-aff0-285a55f29260
# ╟─82f16419-11de-4055-8796-cc36aece3f8a
# ╟─466c8871-e7be-4731-a347-ce6faabf8edb
# ╠═5b87268c-f807-445f-ba69-16b6774cfed1
# ╟─69abd0c5-e6b8-44df-bee1-9502d6a9aa76
# ╟─2497da50-f439-4551-ab8f-41a783a02e66
# ╟─98292e8b-810a-44e3-834b-b6bfd6a184fb
# ╟─a0898cdf-7630-4519-a7e7-3ba114989a5c
# ╠═00b9020f-e05b-4e36-bee8-71da1ce7aeeb
# ╟─6cabf4ea-cf1e-4e91-a2dd-ebf97245cca9
# ╠═f9459d17-b568-4b7c-b15a-7df28b1037d8
# ╟─10848dd7-f82d-49bd-aa8e-3524b8dc35d6
# ╠═79099779-5108-445a-87b7-ef1f9b253550
# ╟─659172c1-59b2-4176-97bc-263a6cc19f0a
# ╟─6e3cfe39-5050-4c0c-af80-7c5e1064a07e
# ╟─94d7f868-cf5b-4cb8-ba10-55cd97724586
# ╟─ca6a03f8-0b5a-47d8-b22f-16fbbd66c0fe
# ╟─6703a1c7-1e6d-4bf7-b014-f71b1404225f
# ╠═2dfbdb6a-8057-4610-af28-a808d664daf9
# ╟─f0be17b6-80a1-454a-a1db-e2af2da30139
# ╟─88841d06-f52e-4d36-9357-ccc3c1360c79
# ╟─a67a0544-a1c5-4218-a80d-a0eb5a5ce92c
# ╟─a4cd8ed5-d8e8-4907-ab33-176f906d1e3b
# ╟─24fe0edd-eae2-4051-981f-e1951579c9e3
# ╟─b90c70c6-19e2-46f7-83b7-1145eaf2c7b9
# ╟─33a72173-b972-4434-b5e7-55411acba353
# ╟─79d753e6-8d92-4030-9a98-a9da9dcaa244
# ╟─5eebab5d-7a2f-4602-9466-8b1ab0fa54df
# ╟─4f19cb30-d540-4f3a-986e-295a4f892e31
# ╟─351798d4-ede7-4025-bfab-01b9d3984741
# ╟─791fadd8-e5d5-408e-88ef-649791b2f0a5
# ╟─01de6a83-f99f-4a0a-ab97-a3bbea522164
# ╟─231c0ac5-7b76-4735-a77c-a7572e707ab7
# ╟─9e591afb-2004-4a8a-8fbb-31618c46f52f
# ╟─2fd11dc3-6bca-4254-ba7b-45cd99ff654f
# ╟─93a5d8c8-e667-4e11-a955-e819ea07e8b9
# ╟─d3701d1c-1846-46b6-9e6a-39c3e4b82107
# ╟─4645fb6e-e660-4432-a70e-bda3216ece86
# ╟─8f5d7589-c46e-4d3d-bdae-408d6d830ef9
# ╟─b6c70ba2-25a8-468f-a2d5-5191017ea24a
# ╠═aef197d8-81a6-4553-b322-13169e8f1bfc
# ╟─6236416d-97e9-4a55-bd89-95f478b5affb
# ╟─4ab79cc8-1c0b-4d6a-b7d4-f45ba1875b09
# ╠═402e585a-940e-4b8a-b88b-6056cb8da169
# ╠═3612e7ca-ce1f-4674-b473-8f9f21b5391a
# ╠═4d7c1c89-e30b-419d-80c8-0cadd4eef740
# ╟─28849b97-81a0-4bba-9254-5194c3488035
# ╟─bd9c684f-3668-4549-8ff8-a11c4f94a5fe
# ╠═a23e1e66-b71f-4ebd-87ad-82d0a08a1f98
# ╟─54f08991-5fb4-4deb-a546-a11bdc2f0f49
