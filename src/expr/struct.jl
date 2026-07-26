module Structs
using ..Polars: API, polars_expr_t, Expr, polars_error, _name_ptrs

"""
    field_by_name(expr::Polars.Expr, name::String)::Polars.Expr
    field_by_name(name::String)::Base.Fix2{typeof(field_by_name), String}

Returns a new expression corresponding to values of the selected field.
"""
function field_by_name(expr, name)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_struct_field_by_name(expr, name, ncodeunits(name), out)
    polars_error(err)
    return Expr(out[])
end
field_by_name(name) = Base.Fix2(field_by_name, name)

"""
    field_by_index(expr::Polars.Expr, index::Integer)::Polars.Expr
    field_by_index(index::Integer)::Base.Fix2{typeof(field_by_index), Integer}

Returns a new expression corresponding to values of the selected field.
"""
function field_by_index(expr, fieldidx)
    field = API.polars_expr_struct_field_by_index(expr, fieldidx)
    return Expr(field)
end
field_by_index(fieldidx) = Base.Fix2(field_by_index, fieldidx)

"""
    rename_fields(expr::Polars.Expr, new_names::Vector{String})::Polars.Expr
    rename_fields(new_names::Vector{String})::Base.Fix2{typeof(rename_fields), Vector{String}}

Renames the fields of the struct series with the provided new names.
"""
function rename_fields(expr, new_names)
    new_names = convert(Vector{String}, new_names)
    GC.@preserve new_names begin
        ptrs, lens = _name_ptrs(new_names)
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_struct_rename_fields(expr, ptrs, lens, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end
rename_fields(new_names) = Base.Fix2(rename_fields, new_names)

export field_by_name, field_by_index, rename_fields

end # module Structs
