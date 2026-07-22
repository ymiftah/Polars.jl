use std::ffi::c_void;

use polars::prelude::*;

use crate::types::{polars_expr_t, polars_series_t};

/// The callback provided for display functions, returns -1 on error.
pub(crate) type IOCallback =
    unsafe extern "C" fn(user: *const c_void, data: *const u8, len: usize) -> isize;

/// Reads a `(ptr-array, n)` of borrowed `polars_expr_t` handles into an owned `Vec<Expr>` (each
/// `Expr` is cloned; the handles remain owned by the caller). The shared convention for passing
/// `Vec<Expr>`-shaped arguments across the C ABI.
///
/// `n == 0` short-circuits without touching `exprs`, since `slice::from_raw_parts` requires a
/// non-null aligned pointer even for length 0 and callers may pass null/dangling for an empty list.
pub(crate) unsafe fn read_exprs(exprs: *const *const polars_expr_t, n: usize) -> Vec<Expr> {
    if n == 0 {
        return Vec::new();
    }
    std::slice::from_raw_parts(exprs, n)
        .iter()
        .map(|expr| (**expr).inner.clone())
        .collect()
}

/// Reads a `(ptr-array, n)` of borrowed `polars_series_t` handles into an owned `Vec<Column>`
/// (each `Series` is cloned -- an `Arc`-refcount bump, not a data copy -- then converted via
/// `.into_column()`; the handles remain owned by the caller). Modeled on `read_exprs` above, but
/// yields `Vec<Column>` rather than `Vec<Series>` since `DataFrame::hstack` takes `&[Column]`, not
/// `&[Series]` (confirmed, `polars-core-0.54.4/src/frame/mod.rs:514`).
///
/// `n == 0` short-circuits without touching `series` (see `read_exprs` for why).
pub(crate) unsafe fn read_series(series: *const *mut polars_series_t, n: usize) -> Vec<Column> {
    if n == 0 {
        return Vec::new();
    }
    std::slice::from_raw_parts(series, n)
        .iter()
        .map(|s| (**s).inner.clone().into_column())
        .collect()
}

/// Reads a `(ptrs, lens, n)` triple of UTF-8 byte slices into a `Vec<PlSmallStr>`, the shared
/// convention for passing plain column-name lists (as opposed to `Vec<Expr>`) across the C ABI.
pub(crate) unsafe fn read_names(
    ptrs: *const *const u8,
    lens: *const usize,
    n: usize,
) -> Result<Vec<PlSmallStr>, std::str::Utf8Error> {
    // `slice::from_raw_parts` requires a non-null, aligned pointer even for len 0, and callers may
    // legitimately pass a null/dangling pointer for an empty list -- so short-circuit here.
    if n == 0 {
        return Ok(Vec::new());
    }
    let ptrs = std::slice::from_raw_parts(ptrs, n);
    let lens = std::slice::from_raw_parts(lens, n);
    ptrs.iter()
        .zip(lens.iter())
        .map(|(&p, &len)| {
            std::str::from_utf8(std::slice::from_raw_parts(p, len)).map(PlSmallStr::from_str)
        })
        .collect()
}

/// Reads an `n`-element boolean mask supplied by the caller. Rust considers any byte other than
/// `0`/`1` in a `bool` to be UB, so we read the buffer as `u8` and normalize (`!= 0`) rather than
/// materializing a `&[bool]` directly. `n == 0` short-circuits (see `read_names` for why).
pub(crate) unsafe fn read_bool_mask(ptr: *const bool, n: usize) -> Vec<bool> {
    if n == 0 {
        return Vec::new();
    }
    std::slice::from_raw_parts(ptr.cast::<u8>(), n)
        .iter()
        .map(|&b| b != 0)
        .collect()
}

/// Reads an `n`-element `i64` array supplied by the caller (e.g. `Selector::ByIndex`'s column
/// indices). `n == 0` short-circuits (see `read_names` for why).
pub(crate) unsafe fn read_i64_array(ptr: *const i64, n: usize) -> Vec<i64> {
    if n == 0 {
        return Vec::new();
    }
    std::slice::from_raw_parts(ptr, n).to_vec()
}

/// Reads a required `(ptr, len)` UTF-8 string. `len == 0` yields `""` without dereferencing `ptr`
/// (see `read_names` for why). Unlike `unwrap_or_default()`, invalid UTF-8 surfaces as an error
/// rather than being silently coerced to `""`.
pub(crate) unsafe fn read_str<'a>(
    ptr: *const u8,
    len: usize,
) -> Result<&'a str, std::str::Utf8Error> {
    if len == 0 {
        return Ok("");
    }
    std::str::from_utf8(std::slice::from_raw_parts(ptr, len))
}

/// Reads an optional `(ptr, len)` string: a null pointer (or zero length) means `None`, the
/// shared convention for optional strings across the C ABI (mirroring the nullable-pointer
/// convention already used for optional scalars, e.g. `polars_expr_sample_n`'s `seed`).
pub(crate) unsafe fn read_opt_str(
    ptr: *const u8,
    len: usize,
) -> Result<Option<PlSmallStr>, std::str::Utf8Error> {
    if ptr.is_null() || len == 0 {
        return Ok(None);
    }
    std::str::from_utf8(std::slice::from_raw_parts(ptr, len)).map(|s| Some(PlSmallStr::from_str(s)))
}

/// Builds a `Selector::ByName` from a name list (always `Some`, for methods that take a plain
/// `Selector` rather than an `Option`).
pub(crate) fn selector_by_name(names: Vec<PlSmallStr>, strict: bool) -> Selector {
    Selector::ByName {
        names: names.into(),
        strict,
    }
}

/// Builds a `Selector::ByName` from a name list, or `None` if the list is empty (matching the
/// "no subset specified" convention several LazyFrame methods use for `Option<Selector>`).
pub(crate) fn selector_by_name_opt(names: Vec<PlSmallStr>, strict: bool) -> Option<Selector> {
    if names.is_empty() {
        None
    } else {
        Some(Selector::ByName {
            names: names.into(),
            strict,
        })
    }
}

/// A `std::io::Write` adapter over a caller-supplied C callback (the `user` context pointer plus
/// the function). It holds a raw `*const c_void` and so is `!Send`/`!Sync` -- deliberately: the
/// callback reaches back into the caller's runtime (the Julia GC heap), which must only be touched
/// from the thread that made the call. The write paths that use it (`write_*`, `show`) run the
/// writer synchronously on the calling thread; the *sink* pipeline, which can write from worker
/// threads, writes to a filesystem path instead of a callback, so no `Send` writer is ever needed.
/// Keep it that way: never hand a `UserIOCallback` to an API that may move it across threads.
pub(crate) struct UserIOCallback(pub(crate) IOCallback, pub(crate) *const c_void);

impl std::io::Write for UserIOCallback {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let n = unsafe { self.0(self.1, buf.as_ptr(), buf.len()) };
        if n < 0 {
            Err(std::io::Error::other("user callback error"))
        } else if (n as usize) > buf.len() {
            // A callback claiming to have written more than it was given is a bug on the caller's
            // side; reject it rather than fabricating an out-of-range write count that would
            // violate the `Write` contract and confuse `write_all`.
            Err(std::io::Error::other(
                "user callback reported a write longer than the buffer",
            ))
        } else {
            Ok(n as usize)
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
