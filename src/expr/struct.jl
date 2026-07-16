module Structs
using ..Polars: Expr, API

"""
    field_by_name(expr::Polars.Expr, name::String)::Polars.Expr
    field_by_name(name::String)::Base.Fix2{typeof(field_by_name), String}

Returns a new series corresponding to values of the selected field.
"""
function field_by_name(expr, name)
    field = API.polars_expr_struct_field_by_name(expr, name, length(name))
    return Expr(field)
end
field_by_name(name) = Base.Fix2(field_by_name, name)

"""
    field_by_index(expr::Polars.Expr, index::Integer)::Polars.Expr
    field_by_index(index::Integer)::Base.Fix2{typeof(field_by_index), Integer}

Returns a new series corresponding to values of the selected field.
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
    new_struct = API.polars_expr_struct_rename_fields(expr, new_names, length.(new_names), length(new_names))
    @assert new_struct != C_NULL "failed to rename fields"
    return Expr(new_struct)
end
rename_fields(new_names) = Base.Fix2(rename_fields, new_names)

export field_by_name, field_by_index, rename_fields

end # module Structs
