module Structs
    using ..Polars: API, polars_expr_t, Expr, polars_error, _name_ptrs

    """
        field_by_name(expr::Polars.Expr, name::String)::Polars.Expr
        field_by_name(name::String)::Base.Fix2{typeof(field_by_name), String}

    Retrieve one of the fields of the struct as a new Series. Also supports wildcard `"*"` and
    regex expansion.
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

    Rename the fields of the struct with the provided new names.
    """
    function rename_fields(expr, new_names)
        owned, ptrs, lens = _name_ptrs(convert(Vector{String}, new_names))
        GC.@preserve owned begin
            out = Ref{Ptr{polars_expr_t}}()
            err = API.polars_expr_struct_rename_fields(expr, ptrs, lens, length(ptrs), out)
            polars_error(err)
        end
        return Expr(out[])
    end
    rename_fields(new_names) = Base.Fix2(rename_fields, new_names)

    """
        with_fields(expr::Polars.Expr, fields::Polars.Expr...)::Polars.Expr

    Adds or overwrites fields of the struct in `expr` with each (aliased) expression in `fields`
    (referencing existing fields via `field_by_name`/`field_by_index` on the struct itself), leaving
    any other fields untouched. If an entry's alias matches an existing field name, that field is
    overwritten in place (count/order unchanged); an alias with no matching field is appended as a
    new field instead.
    """
    function with_fields(expr::Expr, fields::Expr...)
        fields = collect(Expr, fields)
        GC.@preserve fields begin
            ptrs = Ptr{polars_expr_t}[f.ptr for f in fields]
            out = API.polars_expr_struct_with_fields(expr, ptrs, length(ptrs))
        end
        return Expr(out)
    end

    """
        json_encode(expr::Polars.Expr)::Polars.Expr

    Encodes each struct value of `expr` as a JSON string.
    """
    json_encode(expr::Expr) = Expr(API.polars_expr_struct_json_encode(expr))

    export field_by_name, field_by_index, rename_fields, with_fields, json_encode

end # module Structs

export Structs
