function polars_value_time_unit(value)
    return @ccall libpolars.polars_value_time_unit(value::Ptr{polars_value_t})::polars_time_unit_t
end

function polars_value_time_zone(value, out)
    return @ccall libpolars.polars_value_time_zone(value::Ptr{polars_value_t}, out::Ptr{Ptr{UInt8}})::Csize_t
end

function polars_value_type(value)
    return @ccall libpolars.polars_value_type(value::Ptr{polars_value_t})::polars_value_type_t
end

function polars_value_destroy(value)
    return @ccall libpolars.polars_value_destroy(value::Ptr{polars_value_t})::Cvoid
end

function polars_value_get_bool(value, out)
    return @ccall libpolars.polars_value_get_bool(value::Ptr{polars_value_t}, out::Ptr{Bool})::Ptr{polars_error_t}
end

function polars_value_get_u8(value, out)
    return @ccall libpolars.polars_value_get_u8(value::Ptr{polars_value_t}, out::Ptr{UInt8})::Ptr{polars_error_t}
end

function polars_value_get_u16(value, out)
    return @ccall libpolars.polars_value_get_u16(value::Ptr{polars_value_t}, out::Ptr{UInt16})::Ptr{polars_error_t}
end

function polars_value_get_u32(value, out)
    return @ccall libpolars.polars_value_get_u32(value::Ptr{polars_value_t}, out::Ptr{UInt32})::Ptr{polars_error_t}
end

function polars_value_get_u64(value, out)
    return @ccall libpolars.polars_value_get_u64(value::Ptr{polars_value_t}, out::Ptr{UInt64})::Ptr{polars_error_t}
end

function polars_value_get_i8(value, out)
    return @ccall libpolars.polars_value_get_i8(value::Ptr{polars_value_t}, out::Ptr{Int8})::Ptr{polars_error_t}
end

function polars_value_get_i16(value, out)
    return @ccall libpolars.polars_value_get_i16(value::Ptr{polars_value_t}, out::Ptr{Int16})::Ptr{polars_error_t}
end

function polars_value_get_i32(value, out)
    return @ccall libpolars.polars_value_get_i32(value::Ptr{polars_value_t}, out::Ptr{Int32})::Ptr{polars_error_t}
end

function polars_value_get_i64(value, out)
    return @ccall libpolars.polars_value_get_i64(value::Ptr{polars_value_t}, out::Ptr{Int64})::Ptr{polars_error_t}
end

function polars_value_get_f32(value, out)
    return @ccall libpolars.polars_value_get_f32(value::Ptr{polars_value_t}, out::Ptr{Cfloat})::Ptr{polars_error_t}
end

function polars_value_get_f64(value, out)
    return @ccall libpolars.polars_value_get_f64(value::Ptr{polars_value_t}, out::Ptr{Cdouble})::Ptr{polars_error_t}
end

"""
    polars_value_list_get(value, out)

Returns the value as a Series when the dtype of the value is a list.
"""
function polars_value_list_get(value, out)
    return @ccall libpolars.polars_value_list_get(value::Ptr{polars_value_t}, out::Ptr{Ptr{polars_series_t}})::Ptr{polars_error_t}
end

function polars_value_string_get(value, user, callback)
    return @ccall libpolars.polars_value_string_get(value::Ptr{polars_value_t}, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

"""
    polars_value_duration_get(value, out)

Get the underlying int64 for this duration value.
"""
function polars_value_duration_get(value, out)
    return @ccall libpolars.polars_value_duration_get(value::Ptr{polars_value_t}, out::Ptr{Int64})::Ptr{polars_error_t}
end

"""
    polars_value_datetime_get(value, out)

Get the underlying int64 for this datetime value.
"""
function polars_value_datetime_get(value, out)
    return @ccall libpolars.polars_value_datetime_get(value::Ptr{polars_value_t}, out::Ptr{Int64})::Ptr{polars_error_t}
end

"""
    polars_value_date_get(value, out)

Get the underlying int32 (days since UNIX epoch) for this date value.
"""
function polars_value_date_get(value, out)
    return @ccall libpolars.polars_value_date_get(value::Ptr{polars_value_t}, out::Ptr{Int32})::Ptr{polars_error_t}
end

function polars_value_binary_get(value, user, callback)
    return @ccall libpolars.polars_value_binary_get(value::Ptr{polars_value_t}, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

"""
    polars_value_struct_get(value, fieldidx, out)

Used to get value of of a Struct value fields.

NOTE: The value producing the new value must outlive the value from the field.

Safety: Values lifetimes must be valid and only support physical dtypes for now.
"""
function polars_value_struct_get(value, fieldidx, out)
    return @ccall libpolars.polars_value_struct_get(value::Ptr{polars_value_t}, fieldidx::Csize_t, out::Ptr{Ptr{polars_value_t}})::Ptr{polars_error_t}
end

"""
    polars_value_list_type(value)

Returns the element type of the provided value which must be a list. The value type is PolarsValueTypeUnknown if the value is not a list so makes sure it is one otherwise, you cannot differentiate between list<unkown> and unkown.
"""
function polars_value_list_type(value)
    return @ccall libpolars.polars_value_list_type(value::Ptr{polars_value_t})::polars_value_type_t
end
