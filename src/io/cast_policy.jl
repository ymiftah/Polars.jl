"""
    CastPolicy(; integer_upcast=false, integer_to_float_cast=false,
               float_upcast=false, float_downcast=false,
               datetime_nanoseconds_downcast=false,
               datetime_microseconds_downcast=false,
               datetime_convert_timezone=false,
               null_upcast=true,
               categorical_to_string=false,
               missing_struct_fields_raise=true,
               extra_struct_fields_raise=true)

Controls how [`scan_parquet`](@ref)/[`read_parquet`](@ref) handle type mismatches between the file's
schema and any Hive-partition-inferred or previously-scanned schema. The defaults reproduce polars'
own strict `ERROR_ON_MISMATCH` behavior — every flag below opts into a specific, narrower relaxation
of that.

- `integer_upcast`: allow casting to a lossless integer supertype (e.g. `Int32` -> `Int64`).
- `integer_to_float_cast`: allow casting integer columns to floats.
- `float_upcast`: allow upcasting from a smaller float to a larger one (e.g. `Float32` -> `Float64`).
- `float_downcast`: allow downcasting from a larger float to a smaller one.
- `datetime_nanoseconds_downcast`: allow `datetime[ns]` to be cast to a lower precision — needed to
  read datasets written by Spark, which always writes nanosecond precision.
- `datetime_microseconds_downcast`: allow `datetime[us]` to be cast to `datetime[ms]`.
- `datetime_convert_timezone`: allow casting that changes a datetime column's time zone.
- `null_upcast`: allow an all-`Null` column to be cast to any target type (default `true`, matching
  upstream's default).
- `categorical_to_string`: allow a `Categorical` column to be cast to `String`.
- `missing_struct_fields_raise`: error when a struct field present in the target schema is missing
  from a file (default `true`); `false` fills the missing field with nulls instead.
- `extra_struct_fields_raise`: error when a file's struct has a field absent from the target schema
  (default `true`); `false` silently drops the extra field instead.

# Examples
```julia
# Allow integer/float upcasting only
policy = CastPolicy(integer_upcast=true, float_upcast=true)

# Read datasets written by Spark (nanosecond-precision datetimes)
policy = CastPolicy(datetime_nanoseconds_downcast=true)
```
"""
struct CastPolicy
    integer_upcast::Bool
    integer_to_float_cast::Bool
    float_upcast::Bool
    float_downcast::Bool
    datetime_nanoseconds_downcast::Bool
    datetime_microseconds_downcast::Bool
    datetime_convert_timezone::Bool
    null_upcast::Bool
    categorical_to_string::Bool
    missing_struct_fields_raise::Bool
    extra_struct_fields_raise::Bool

    function CastPolicy(;
            integer_upcast::Bool = false,
            integer_to_float_cast::Bool = false,
            float_upcast::Bool = false,
            float_downcast::Bool = false,
            datetime_nanoseconds_downcast::Bool = false,
            datetime_microseconds_downcast::Bool = false,
            datetime_convert_timezone::Bool = false,
            null_upcast::Bool = true,
            categorical_to_string::Bool = false,
            missing_struct_fields_raise::Bool = true,
            extra_struct_fields_raise::Bool = true
        )
        return new(
            integer_upcast, integer_to_float_cast, float_upcast, float_downcast,
            datetime_nanoseconds_downcast, datetime_microseconds_downcast,
            datetime_convert_timezone, null_upcast, categorical_to_string,
            missing_struct_fields_raise, extra_struct_fields_raise
        )
    end
end

_dict_to_cast_policy(d::AbstractDict) = CastPolicy(; (Symbol(k) => v for (k, v) in d)...)

_to_api_struct(p::CastPolicy) = API.polars_cast_columns_policy_t(
    p.integer_upcast, p.integer_to_float_cast, p.float_upcast, p.float_downcast,
    p.datetime_nanoseconds_downcast, p.datetime_microseconds_downcast,
    p.datetime_convert_timezone, p.null_upcast, p.categorical_to_string,
    p.missing_struct_fields_raise, p.extra_struct_fields_raise
)
