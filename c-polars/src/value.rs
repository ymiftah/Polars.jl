use std::ffi::c_void;
use std::io::Write;

use polars::prelude::*;

use crate::{ffi_util::*, make_error, polars_error_t, series::make_series, types::*};

#[repr(C)]
pub enum polars_value_type_t {
    PolarsValueTypeNull,
    PolarsValueTypeBoolean,
    PolarsValueTypeUInt8,
    PolarsValueTypeUInt16,
    PolarsValueTypeUInt32,
    PolarsValueTypeUInt64,
    PolarsValueTypeInt8,
    PolarsValueTypeInt16,
    PolarsValueTypeInt32,
    PolarsValueTypeInt64,
    PolarsValueTypeFloat32,
    PolarsValueTypeFloat64,
    PolarsValueTypeList,
    PolarsValueTypeString,
    PolarsValueTypeStruct,
    PolarsValueTypeBinary,
    PolarsValueTypeDatetime,
    PolarsValueTypeDate,
    PolarsValueTypeDuration,
    PolarsValueTypeUnknown,
}

impl polars_value_type_t {
    pub(crate) fn from_dtype(d: &DataType) -> Self {
        use polars_value_type_t::*;
        match d {
            DataType::Null => PolarsValueTypeNull,
            DataType::Boolean => PolarsValueTypeBoolean,
            DataType::UInt8 => PolarsValueTypeUInt8,
            DataType::UInt16 => PolarsValueTypeUInt16,
            DataType::UInt32 => PolarsValueTypeUInt32,
            DataType::UInt64 => PolarsValueTypeUInt64,
            DataType::Int8 => PolarsValueTypeInt8,
            DataType::Int16 => PolarsValueTypeInt16,
            DataType::Int32 => PolarsValueTypeInt32,
            DataType::Int64 => PolarsValueTypeInt64,
            DataType::Float32 => PolarsValueTypeFloat32,
            DataType::Float64 => PolarsValueTypeFloat64,
            DataType::List(_) => PolarsValueTypeList,
            DataType::String => PolarsValueTypeString,
            DataType::Struct(_) => PolarsValueTypeStruct,
            DataType::Binary => PolarsValueTypeBinary,
            DataType::Date => PolarsValueTypeDate,
            DataType::Datetime(_, _) => PolarsValueTypeDatetime,
            DataType::Duration(_) => PolarsValueTypeDuration,
            DataType::Unknown(_) => PolarsValueTypeUnknown,
            _ => PolarsValueTypeUnknown,
        }
    }

    pub(crate) fn to_dtype(&self) -> DataType {
        use polars_value_type_t::*;
        match self {
            PolarsValueTypeNull => DataType::Null,
            PolarsValueTypeBoolean => DataType::Boolean,
            PolarsValueTypeUInt8 => DataType::UInt8,
            PolarsValueTypeUInt16 => DataType::UInt16,
            PolarsValueTypeUInt32 => DataType::UInt32,
            PolarsValueTypeUInt64 => DataType::UInt64,
            PolarsValueTypeInt8 => DataType::Int8,
            PolarsValueTypeInt16 => DataType::Int16,
            PolarsValueTypeInt32 => DataType::Int32,
            PolarsValueTypeInt64 => DataType::Int64,
            PolarsValueTypeFloat32 => DataType::Float32,
            PolarsValueTypeFloat64 => DataType::Float64,
            PolarsValueTypeString => DataType::String,
            PolarsValueTypeBinary => DataType::Binary,
            _ => DataType::Unknown(UnknownKind::Any), // Cannot map structs and lists
        }
    }
}

#[repr(C)]
pub enum polars_time_unit_t {
    PolarsTimeUnitNanosecond,
    PolarsTimeUnitMicrosecond,
    PolarsTimeUnitMillisecond,
    PolarsTimeUnitInvalid,
}

impl polars_time_unit_t {
    pub fn to_time_unit(&self) -> TimeUnit {
        match self {
            polars_time_unit_t::PolarsTimeUnitNanosecond => TimeUnit::Nanoseconds,
            polars_time_unit_t::PolarsTimeUnitMicrosecond => TimeUnit::Microseconds,
            polars_time_unit_t::PolarsTimeUnitMillisecond => TimeUnit::Milliseconds,
            polars_time_unit_t::PolarsTimeUnitInvalid => TimeUnit::Microseconds,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_closed_window_t {
    PolarsClosedWindowLeft,
    PolarsClosedWindowRight,
    PolarsClosedWindowBoth,
    PolarsClosedWindowNone,
}

impl polars_closed_window_t {
    pub fn to_closed_window(self) -> ClosedWindow {
        match self {
            polars_closed_window_t::PolarsClosedWindowLeft => ClosedWindow::Left,
            polars_closed_window_t::PolarsClosedWindowRight => ClosedWindow::Right,
            polars_closed_window_t::PolarsClosedWindowBoth => ClosedWindow::Both,
            polars_closed_window_t::PolarsClosedWindowNone => ClosedWindow::None,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_label_t {
    PolarsLabelLeft,
    PolarsLabelRight,
    PolarsLabelDataPoint,
}

impl polars_label_t {
    pub fn to_label(self) -> Label {
        match self {
            polars_label_t::PolarsLabelLeft => Label::Left,
            polars_label_t::PolarsLabelRight => Label::Right,
            polars_label_t::PolarsLabelDataPoint => Label::DataPoint,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
pub enum polars_start_by_t {
    PolarsStartByWindowBound,
    PolarsStartByDataPoint,
    PolarsStartByMonday,
    PolarsStartByTuesday,
    PolarsStartByWednesday,
    PolarsStartByThursday,
    PolarsStartByFriday,
    PolarsStartBySaturday,
    PolarsStartBySunday,
}

impl polars_start_by_t {
    pub fn to_start_by(self) -> StartBy {
        match self {
            polars_start_by_t::PolarsStartByWindowBound => StartBy::WindowBound,
            polars_start_by_t::PolarsStartByDataPoint => StartBy::DataPoint,
            polars_start_by_t::PolarsStartByMonday => StartBy::Monday,
            polars_start_by_t::PolarsStartByTuesday => StartBy::Tuesday,
            polars_start_by_t::PolarsStartByWednesday => StartBy::Wednesday,
            polars_start_by_t::PolarsStartByThursday => StartBy::Thursday,
            polars_start_by_t::PolarsStartByFriday => StartBy::Friday,
            polars_start_by_t::PolarsStartBySaturday => StartBy::Saturday,
            polars_start_by_t::PolarsStartBySunday => StartBy::Sunday,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_value_time_unit(value: *mut polars_value_t) -> polars_time_unit_t {
    let tu = match (*value).inner {
        AnyValue::Duration(_, tu) => tu,
        AnyValue::Datetime(_, tu, _) => tu,
        _ => return polars_time_unit_t::PolarsTimeUnitInvalid,
    };

    match tu {
        TimeUnit::Nanoseconds => polars_time_unit_t::PolarsTimeUnitNanosecond,
        TimeUnit::Microseconds => polars_time_unit_t::PolarsTimeUnitMicrosecond,
        TimeUnit::Milliseconds => polars_time_unit_t::PolarsTimeUnitMillisecond,
    }
}

/// Borrowed pointer into this datetime value's timezone name, valid as long as `value` is alive
/// (same convention as `polars_series_name`). Returns 0 (and leaves `out` unwritten) for a naive
/// datetime or any non-datetime value.
#[no_mangle]
pub unsafe extern "C" fn polars_value_time_zone(
    value: *mut polars_value_t,
    out: *mut *const u8,
) -> usize {
    match &(*value).inner {
        AnyValue::Datetime(_, _, Some(tz)) => {
            let s = tz.as_str();
            *out = s.as_ptr();
            s.len()
        }
        _ => 0,
    }
}

#[no_mangle]
pub extern "C" fn polars_value_type(value: *mut polars_value_t) -> polars_value_type_t {
    // AnyValue::dtype() is unimplemented for Categorical/Enum (see polars-core), so these must
    // be special-cased ahead of it; we treat them as strings, matching polars_value_string_get.
    match unsafe { &(*value).inner } {
        AnyValue::Categorical(_, _)
        | AnyValue::CategoricalOwned(_, _)
        | AnyValue::Enum(_, _)
        | AnyValue::EnumOwned(_, _) => polars_value_type_t::PolarsValueTypeString,
        inner => polars_value_type_t::from_dtype(&inner.dtype()),
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_value_destroy(value: *mut polars_value_t) {
    assert!(!value.is_null());
    let _ = Box::from_raw(value);
}

macro_rules! gen_value_get {
    ($n: ident, $t: ident, $rt: ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            value: *mut polars_value_t,
            out: *mut $t,
        ) -> *const polars_error_t {
            match (*value).inner {
                AnyValue::$rt(value) => *out = value,
                _ => return make_error(concat!("value is not of type ", stringify!($rt))),
            }
            std::ptr::null()
        }
    };
}

gen_value_get!(polars_value_get_bool, bool, Boolean);
gen_value_get!(polars_value_get_u8, u8, UInt8);
gen_value_get!(polars_value_get_u16, u16, UInt16);
gen_value_get!(polars_value_get_u32, u32, UInt32);
gen_value_get!(polars_value_get_u64, u64, UInt64);
gen_value_get!(polars_value_get_i8, i8, Int8);
gen_value_get!(polars_value_get_i16, i16, Int16);
gen_value_get!(polars_value_get_i32, i32, Int32);
gen_value_get!(polars_value_get_i64, i64, Int64);
gen_value_get!(polars_value_get_f32, f32, Float32);
gen_value_get!(polars_value_get_f64, f64, Float64);

/// Returns the value as a Series when the dtype of the value is a list.
#[no_mangle]
pub unsafe extern "C" fn polars_value_list_get(
    value: *mut polars_value_t,
    out: *mut *mut polars_series_t,
) -> *const polars_error_t {
    match &(*value).inner {
        AnyValue::List(series) => *out = make_series(series.clone()),
        _ => return make_error("value is not of type list"),
    }
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_value_string_get(
    value: *mut polars_value_t,
    user: *mut c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    let mut w = UserIOCallback(callback, user);
    // get_str() also resolves Categorical/Enum values to their string representation.
    let Err(err) = (match (*value).inner.get_str() {
        Some(s) => w.write(s.as_bytes()),
        None => return make_error("value is not of type string"),
    }) else {
        return std::ptr::null();
    };
    make_error(err)
}

/// Get the underlying int64 for this duration value.
#[no_mangle]
pub unsafe extern "C" fn polars_value_duration_get(
    value: *mut polars_value_t,
    out: *mut i64,
) -> *const polars_error_t {
    match (*value).inner {
        AnyValue::Duration(i, _) => *out = i,
        _ => return make_error("value is not of type duration"),
    }

    std::ptr::null()
}

/// Get the underlying int64 for this datetime value.
#[no_mangle]
pub unsafe extern "C" fn polars_value_datetime_get(
    value: *mut polars_value_t,
    out: *mut i64,
) -> *const polars_error_t {
    match (*value).inner {
        AnyValue::Datetime(i, _, _) => *out = i,
        _ => return make_error("value is not of type datetime"),
    }

    std::ptr::null()
}

/// Get the underlying int32 (days since UNIX epoch) for this date value.
#[no_mangle]
pub unsafe extern "C" fn polars_value_date_get(
    value: *mut polars_value_t,
    out: *mut i32,
) -> *const polars_error_t {
    match (*value).inner {
        AnyValue::Date(i) => *out = i,
        _ => return make_error("value is not of type date"),
    }

    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn polars_value_binary_get(
    value: *mut polars_value_t,
    user: *mut c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    let mut w = UserIOCallback(callback, user);
    let Err(err) = (match (*value).inner {
        AnyValue::Binary(s) => w.write(s),
        _ => return make_error("value is not of type binary"),
    }) else {
        return std::ptr::null();
    };
    make_error(err)
}

/// Used to get value of of a Struct value fields.
///
/// NOTE: The value producing the new value must outlive the value from the field.
///
/// Safety: Values lifetimes must be valid.
#[no_mangle]
pub unsafe extern "C" fn polars_value_struct_get<'a: 'b, 'b>(
    value: *mut polars_value_t<'a>,
    fieldidx: usize,
    out: *mut *mut polars_value_t<'b>,
) -> *const polars_error_t {
    let inner: &'a AnyValue<'a> = &(*value).inner;
    if !matches!(inner, AnyValue::Struct(_, _, _)) {
        return make_error("invalid type for value");
    }

    let Some(field_value) = inner._iter_struct_av().nth(fieldidx) else {
        return make_error(format!("invalid field index {fieldidx}"));
    };

    *out = Box::into_raw(Box::new(polars_value_t { inner: field_value }));

    std::ptr::null()
}

/// Returns the element type of the provided value which must be a list.
/// The value type is PolarsValueTypeUnknown if the value is not a list
/// so makes sure it is one otherwise, you cannot differentiate between list<unkown>
/// and unkown.
#[no_mangle]
pub unsafe extern "C" fn polars_value_list_type(value: *mut polars_value_t) -> polars_value_type_t {
    match (*value).inner.dtype() {
        DataType::List(eltype) => polars_value_type_t::from_dtype(&eltype),
        _ => polars_value_type_t::PolarsValueTypeUnknown,
    }
}
