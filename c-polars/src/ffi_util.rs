use std::ffi::c_void;

use polars::prelude::*;

/// The callback provided for display functions, returns -1 on error.
pub(crate) type IOCallback =
    unsafe extern "C" fn(user: *const c_void, data: *const u8, len: usize) -> isize;

/// Reads a `(ptrs, lens, n)` triple of UTF-8 byte slices into a `Vec<PlSmallStr>`, the shared
/// convention for passing plain column-name lists (as opposed to `Vec<Expr>`) across the C ABI.
pub(crate) unsafe fn read_names(
    ptrs: *const *const u8,
    lens: *const usize,
    n: usize,
) -> Result<Vec<PlSmallStr>, std::str::Utf8Error> {
    let ptrs = std::slice::from_raw_parts(ptrs, n);
    let lens = std::slice::from_raw_parts(lens, n);
    ptrs.iter()
        .zip(lens.iter())
        .map(|(&p, &len)| {
            std::str::from_utf8(std::slice::from_raw_parts(p, len)).map(PlSmallStr::from_str)
        })
        .collect()
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

pub(crate) struct UserIOCallback(pub(crate) IOCallback, pub(crate) *const c_void);

impl std::io::Write for UserIOCallback {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let n = unsafe { self.0(self.1, buf.as_ptr(), buf.len()) };
        if n < 0 {
            Err(std::io::Error::other("user callback error"))
        } else {
            Ok(n as usize)
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
