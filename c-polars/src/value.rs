use std::ffi::c_void;
use std::io::Write;

use polars::prelude::*;

use crate::{ffi_util::*, guard_error, make_error, polars_error_t, series::make_series, types::*};

#[repr(C)]
#[derive(Debug)]
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
    PolarsValueTypeTime,
    PolarsValueTypeUnknown,
}

impl polars_value_type_t {
    /// Classifies an `AnyValue` *without* going through `AnyValue::dtype()`, which is
    /// unimplemented (panics) for Categorical/Enum -- and a panic across `extern "C"` aborts the
    /// process. This is the single classifier behind both `polars_value_type` and (via
    /// `from_dtype`) `polars_series_type`, so one value cannot classify two different ways
    /// depending on which entry point the caller came through.
    pub(crate) fn from_any_value(av: &AnyValue) -> Self {
        match av {
            // Resolved as strings, matching `get_str()` / `polars_value_string_get` and the
            // Categorical/Enum arm of `from_dtype` below.
            AnyValue::Categorical(_, _)
            | AnyValue::CategoricalOwned(_, _)
            | AnyValue::Enum(_, _)
            | AnyValue::EnumOwned(_, _) => polars_value_type_t::PolarsValueTypeString,
            av => Self::from_dtype(&av.dtype()),
        }
    }

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
            DataType::Time => PolarsValueTypeTime,
            // Categorical/Enum resolve to their string representation -- see `from_any_value`.
            DataType::Categorical(_, _) | DataType::Enum(_, _) => PolarsValueTypeString,
            // Decimal, Array, and anything added upstream: no code in this enum. `Unknown` is the
            // honest answer for the *outbound* direction (there is no error channel -- this is
            // returned by value); the inbound direction rejects it, see `to_dtype`.
            _ => PolarsValueTypeUnknown,
        }
    }

    /// Maps an inbound type code to a `DataType`. Fallible: this backs `polars_expr_cast`, where
    /// mapping an un-encodable arm to `Unknown(UnknownKind::Any)` would silently turn e.g.
    /// `cast(col, Datetime)` into a cast-to-unknown rather than an error.
    pub(crate) fn to_dtype(&self) -> PolarsResult<DataType> {
        use polars_value_type_t::*;
        Ok(match self {
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
            PolarsValueTypeDate => DataType::Date,
            PolarsValueTypeTime => DataType::Time,
            // Datetime/Duration need a time unit (and Datetime a time zone), List/Struct need
            // their inner types, and Unknown carries no type at all -- none of which this enum
            // can encode. Widening the cast ABI to carry them is a logged follow-up.
            other => {
                return Err(PolarsError::InvalidOperation(
                    format!("cannot cast to {other:?}: this type is not encodable as a plain type code (it needs parameters, e.g. a time unit or inner type)").into(),
                ))
            }
        })
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
    /// `PolarsTimeUnitInvalid` is a *return* sentinel (`polars_value_time_unit` yields it for
    /// non-temporal values); it is not a valid *input*, so reject it rather than silently coercing
    /// it to microseconds.
    pub fn to_time_unit(&self) -> PolarsResult<TimeUnit> {
        Ok(match self {
            polars_time_unit_t::PolarsTimeUnitNanosecond => TimeUnit::Nanoseconds,
            polars_time_unit_t::PolarsTimeUnitMicrosecond => TimeUnit::Microseconds,
            polars_time_unit_t::PolarsTimeUnitMillisecond => TimeUnit::Milliseconds,
            polars_time_unit_t::PolarsTimeUnitInvalid => {
                return Err(PolarsError::InvalidOperation(
                    "invalid time unit".to_string().into(),
                ))
            }
        })
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
    pub fn to_closed_window(&self) -> ClosedWindow {
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
    pub fn to_label(&self) -> Label {
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
    pub fn to_start_by(&self) -> StartBy {
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
        // See `polars_value_datetime_get` on why both datetime variants are matched.
        AnyValue::DatetimeOwned(_, tu, _) | AnyValue::Datetime(_, tu, _) => tu,
        _ => return polars_time_unit_t::PolarsTimeUnitInvalid,
    };

    match tu {
        TimeUnit::Nanoseconds => polars_time_unit_t::PolarsTimeUnitNanosecond,
        TimeUnit::Microseconds => polars_time_unit_t::PolarsTimeUnitMicrosecond,
        TimeUnit::Milliseconds => polars_time_unit_t::PolarsTimeUnitMillisecond,
    }
}

/// Borrowed pointer into this datetime value's timezone name, valid as long as `value` is alive.
/// Returns 0 (and leaves `out` unwritten) for a naive datetime or any non-datetime value.
#[no_mangle]
pub unsafe extern "C" fn polars_value_time_zone(
    value: *mut polars_value_t,
    out: *mut *const u8,
) -> usize {
    // `DatetimeOwned` holds `Option<Arc<TimeZone>>` where `Datetime` holds `Option<&TimeZone>`;
    // both deref to `TimeZone`, and the `Arc`'s payload lives exactly as long as the value does, so
    // the borrowed-pointer contract is the same either way.
    match &(*value).inner {
        AnyValue::DatetimeOwned(_, _, Some(tz)) => {
            let s = tz.as_str();
            *out = s.as_ptr();
            s.len()
        }
        AnyValue::Datetime(_, _, Some(tz)) => {
            let s = tz.as_str();
            *out = s.as_ptr();
            s.len()
        }
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn polars_value_type(value: *mut polars_value_t) -> polars_value_type_t {
    polars_value_type_t::from_any_value(&(*value).inner)
}

#[no_mangle]
pub unsafe extern "C" fn polars_value_destroy(value: *mut polars_value_t) {
    Opaque::destroy(value);
}

macro_rules! gen_value_get {
    ($n: ident, $t: ident, $rt: ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $n(
            value: *mut polars_value_t,
            out: *mut $t,
        ) -> *const polars_error_t {
            guard_error(|| {
                match &(*value).inner {
                    AnyValue::$rt(v) => *out = *v,
                    // Reached both for a dtype mismatch and for a null value (see
                    // `gen_series_get!` in series.rs, which shares this shape) -- name the
                    // expectation and what was actually there.
                    other => {
                        return make_error(format!(
                            "expected a {} value, got {other:?}",
                            stringify!($rt)
                        ));
                    }
                }
                std::ptr::null()
            })
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
    guard_error(|| {
        match &(*value).inner {
            AnyValue::List(series) => *out = make_series(series.clone()),
            other => return make_error(format!("expected a list value, got {other:?}")),
        }
        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_value_string_get(
    value: *mut polars_value_t,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    guard_error(|| {
        let mut w = UserIOCallback(callback, user);
        // get_str() also resolves Categorical/Enum values to their string representation.
        let Some(s) = (*value).inner.get_str() else {
            return make_error(format!("expected a string value, got {:?}", (*value).inner));
        };
        // write_all, not write: a single write() may report a short count and silently drop the tail.
        match w.write_all(s.as_bytes()) {
            Ok(()) => std::ptr::null(),
            Err(err) => make_error(err),
        }
    })
}

/// Get the underlying int64 for this duration value.
#[no_mangle]
pub unsafe extern "C" fn polars_value_duration_get(
    value: *mut polars_value_t,
    out: *mut i64,
) -> *const polars_error_t {
    guard_error(|| {
        match &(*value).inner {
            AnyValue::Duration(i, _) => *out = *i,
            other => return make_error(format!("expected a duration value, got {other:?}")),
        }

        std::ptr::null()
    })
}

/// Get the underlying int64 for this datetime value.
#[no_mangle]
pub unsafe extern "C" fn polars_value_datetime_get(
    value: *mut polars_value_t,
    out: *mut i64,
) -> *const polars_error_t {
    guard_error(|| {
        match &(*value).inner {
            // `DatetimeOwned` is what `into_static` produces (see `polars_value_t`); the borrowed
            // `Datetime` arm is kept so the accessor stays correct for a value built another way.
            AnyValue::DatetimeOwned(i, _, _) | AnyValue::Datetime(i, _, _) => *out = *i,
            other => return make_error(format!("expected a datetime value, got {other:?}")),
        }

        std::ptr::null()
    })
}

/// Get the underlying int32 (days since UNIX epoch) for this date value.
#[no_mangle]
pub unsafe extern "C" fn polars_value_date_get(
    value: *mut polars_value_t,
    out: *mut i32,
) -> *const polars_error_t {
    guard_error(|| {
        match &(*value).inner {
            AnyValue::Date(i) => *out = *i,
            other => return make_error(format!("expected a date value, got {other:?}")),
        }

        std::ptr::null()
    })
}

/// Get the underlying int64 for this time value. `DataType::Time` is always nanoseconds since
/// midnight (unlike Datetime/Duration, it carries no `TimeUnit`), so there is no companion
/// `polars_value_time_unit`-style call for it.
#[no_mangle]
pub unsafe extern "C" fn polars_value_time_get(
    value: *mut polars_value_t,
    out: *mut i64,
) -> *const polars_error_t {
    guard_error(|| {
        match &(*value).inner {
            AnyValue::Time(i) => *out = *i,
            other => return make_error(format!("expected a time value, got {other:?}")),
        }

        std::ptr::null()
    })
}

#[no_mangle]
pub unsafe extern "C" fn polars_value_binary_get(
    value: *mut polars_value_t,
    user: *const c_void,
    callback: IOCallback,
) -> *const polars_error_t {
    guard_error(|| {
        let mut w = UserIOCallback(callback, user);
        // `BinaryOwned` is what `into_static` produces; the borrowed `Binary` arm is kept for the
        // same reason the datetime accessor keeps its.
        let s: &[u8] = match &(*value).inner {
            AnyValue::BinaryOwned(v) => v,
            AnyValue::Binary(v) => v,
            other => return make_error(format!("expected a binary value, got {other:?}")),
        };
        // write_all, not write: a single write() may report a short count and silently drop the tail.
        match w.write_all(s) {
            Ok(()) => std::ptr::null(),
            Err(err) => make_error(err),
        }
    })
}

/// Returns the value of struct field `fieldidx`. The result owns its data (see `polars_value_t`),
/// so it may outlive `value` and be destroyed in any order relative to it.
#[no_mangle]
pub unsafe extern "C" fn polars_value_struct_get(
    value: *mut polars_value_t,
    fieldidx: usize,
    out: *mut *mut polars_value_t,
) -> *const polars_error_t {
    guard_error(|| {
        // Always `StructOwned` rather than `Struct`: `make_value` ran `into_static`, which
        // materializes the fields into a `Vec`. That makes this a direct index instead of a walk
        // of the field list per call. It is also the only correct match -- polars-core's
        // `_iter_struct_av` (the borrowed-`Struct` accessor) hits an `unreachable!()` on an owned
        // struct, and that panic has no greppable message.
        let AnyValue::StructOwned(payload) = &(*value).inner else {
            return make_error("invalid type for value");
        };
        let Some(field_value) = payload.0.get(fieldidx) else {
            return make_error(format!(
                "invalid field index {fieldidx} (struct has {} fields)",
                payload.0.len()
            ));
        };

        *out = make_value(field_value.clone());

        std::ptr::null()
    })
}

/// Returns the element type of the provided value which must be a list.
/// The value type is PolarsValueTypeUnknown if the value is not a list
/// so makes sure it is one otherwise, you cannot differentiate between list<unkown>
/// and unkown.
#[no_mangle]
pub unsafe extern "C" fn polars_value_list_type(value: *mut polars_value_t) -> polars_value_type_t {
    // `AnyValue::dtype()` is unimplemented for Categorical/Enum (it panics -- see the same note on
    // `polars_value_type`), and a panic across `extern "C"` aborts the process. A categorical value
    // is not a list, so short-circuit to Unknown here rather than reaching `.dtype()`.
    match &(*value).inner {
        AnyValue::Categorical(_, _)
        | AnyValue::CategoricalOwned(_, _)
        | AnyValue::Enum(_, _)
        | AnyValue::EnumOwned(_, _) => polars_value_type_t::PolarsValueTypeUnknown,
        inner => match inner.dtype() {
            DataType::List(eltype) => polars_value_type_t::from_dtype(&eltype),
            _ => polars_value_type_t::PolarsValueTypeUnknown,
        },
    }
}
