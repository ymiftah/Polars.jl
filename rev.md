# exprs.rs


Yes — a few things, though most are the usual FFI-shim tradeoffs rather than outright bugs. Caveat: the fetch only gave me roughly the first ~1000 lines, so some of this may be handled further down.

**Actual hazards**

- **Null checks are ad hoc.** `polars_expr_destroy` asserts `!expr.is_null()`, but every other function does `(*expr).inner.clone()` with no check. Meanwhile `replace_strict`, `sample_n`, and `sample_frac` treat null as "None". So null means "optional argument" in three places and "undefined behavior" everywhere else, with nothing documenting which is which.
- **`slice::from_raw_parts(ptr, 0)` is UB if ptr is null.** It requires a non-null, aligned pointer even for zero length. `coalesce` and `as_struct` guard `n == 0` with a nice error message — but the guard runs *after* nothing, fine — while `all_horizontal`, `any_horizontal`, `min/max/sum/mean_horizontal`, `over`, and `sort_by` don't guard at all and hand a possibly-null pointer straight to `read_exprs`.
- **No panic guard.** Nothing is wrapped in `catch_unwind`. Any panic inside the Polars DSL (or that `assert!`) unwinds out of an `extern "C"` fn and aborts the whole Julia process.
- **`descending: *const bool`** in `sort_by`. Rust `bool` is UB for any byte other than 0/1, and this reads a caller-supplied buffer directly into `Vec<bool>`. Same class of issue for the `#[repr(C)]` enums passed by value — an out-of-range integer from Julia makes the `match` UB.

**Design smells**

- **Two error conventions, chosen seemingly at random.** Some functions return `*const polars_error_t` + out-param; others return the pointer directly. `polars_expr_nth` pays for the out-param ceremony despite having no failure path at all.
- **Copy-paste where the macros already exist.** The six `*_horizontal` functions are the same 15-line `match { Ok => …, Err => … }` block six times, in a file that otherwise macro-generates everything.
- **Magic booleans.** `implode(true)`, `explode(ExplodeOptions { empty_as_null: true, keep_nulls: true })`, and `Expr::is_in(a, b, false)` hardcode behavior with no name, comment, or way for the caller to change it — while `list_contains` *does* expose its `nulls_equal`. Also `polars_expr_flatten` calling `explode` is a naming trap.
- **`#[allow(dead_code)]` on the enums.** It's there because variants are only ever constructed from C, but a blanket allow means genuinely dead variants will never be flagged.
- **Minor litter:** a commented-out `str_explode` binding; `#[cfg(feature = "nightly")]` on `str_to_titlecase` means the symbol silently vanishes and the Julia `ccall` fails at runtime; `*const` returned for pointers the caller actually owns and must free (`*mut` would be honest); redundant parens in `((*b).inner.clone())`.

The `.clone()`-everything pattern looks wasteful but I'd defend it — `Expr` is largely `Arc`-backed, and the C side keeps ownership of its handles, so consuming `self` isn't an option.



# dataframe.rs

Got what looks like the whole file this time (992 lines, ending at `polars_lazy_group_by_agg`). **This one is worse than `expr.rs` — C+ to a weak B-.** `expr.rs` was repetitive but coherent; this file has an actual design problem.

**The headline: two ownership models for the same type**

`select`, `with_columns`, `sort`, `filter`, `head`, `tail` **mutate the frame in place** and return nothing. `drop`, `rename`, `unique`, `drop_nulls`, `explode`, `unpivot`, `pivot`, `with_row_index` **clone and hand back a new handle** via out-param. These are all the same category of operation — lazy plan builders — and the caller has to memorize which is which. Worse, `polars_lazy_frame_clone` exists, so two handles can point at plans that alias in ways the in-place ops don't respect.

And the in-place ones do it via `Box::from_raw` → mutate → `std::mem::forget`. It works, but it's a re-borrow laundered through ownership when `mem::replace` on `&mut (*df).inner` would say the same thing without the raw-pointer round trip. (The obvious "panic drops the Box and double-frees" objection is actually masked — unwinding out of `extern "C"` aborts the process first. Which is its own problem.)

**Real bugs**

- **`polars_dataframe_new` is `#[no_mangle] pub fn` — no `extern "C"`.** It's Rust ABI. Nullary returning a pointer will work by accident on most targets, but it's unsound by contract and trivially fixed.
- **`iter::repeat(nulls_last).take(descending.len()).collect()` in `sort` is rayon's `repeat`**, not std's — check the imports (`rayon::iter::{self, ParallelIterator}`; that `ParallelIterator` import exists for this line and nothing else I can see). So it spins up a *parallel collect* to build a `Vec<bool>` of length n. `expr.rs` does the same thing correctly with `std::iter::repeat_n`. Almost certainly an accidental shadow.
- **`unwrap_or_default()` on `str::from_utf8`** in `group_by_dynamic` and `rolling` silently converts invalid UTF-8 into `""`, which then hits `Duration::try_parse` and surfaces as a nonsense parse error. Every other string in the file properly returns `make_error(err)`.
- **`value.unwrap_single()`** in `collect` — panic path, i.e. abort.
- **Silent narrowing:** `offset as IdxSize` (i64 → u32; a negative offset wraps to a huge one) and `n as IdxSize` in `head`/`tail`.

**Design smells**

- **Three error conventions now.** Out-param + `*const polars_error_t`; bare-null-means-error with no diagnostic (`new_from_carrow` has four such returns); and infallible-direct-return. `dataframe_schema` returns `ArrowSchema` by value while `collect_schema` uses an out-param — and its doc comment claims to match the former's shape.
- **`write_csv` takes 19 parameters** with five copy-pasted `read_opt_str` blocks. That's an options struct.
- **`new_from_series` silently renames every column to `column_0`, `column_1`…**, discarding the names the Series already carry.
- **Helper inconsistency:** `make_dataframe`/`make_series` exist, but `Box::into_raw(Box::new(polars_lazy_frame_t { … }))` is open-coded ~12 times. `selector_by_name_opt(names, true)` in two places, the equivalent `Selector::ByName { strict: true }` inline in four others.
- **Hidden defaults:** `period_len == 0` silently means "use `every`"; `AsOfOptions` hardcodes `tolerance: None`, `allow_eq: true`, `check_sortedness: true` with no way to change them.
- **`polars_lazy_frame_filter` ships an unanswered question as a comment** — *"can we assume that the function takes ownership of it?"* That's a TODO wearing a NOTE's clothes, in a public API.

Credit where due: `new_from_carrow` has a real `# Safety` section explaining the Arrow C-ABI ownership transfer. It's the best-documented thing I've seen in this crate — which makes its absence everywhere else look like an oversight rather than a policy.


# values.rs

Full file this time (372 lines). Interesting one: **it's the best-commented file of the three and the most dangerous.** Several comments here explain genuinely non-obvious polars internals rather than restating the code. But the core design is a dangling-pointer machine, and there's one bug I'd block on.

**The bug**

`polars_value_type` carries this comment:

> `AnyValue::dtype()` is unimplemented for Categorical/Enum (see polars-core), so these must be special-cased ahead of it

…and then `polars_value_list_type`, the last function in the file, calls `(*value).inner.dtype()` with no such guard. Hand it a categorical value and it panics instead of returning `PolarsValueTypeUnknown` as its own doc comment promises — and a panic out of `extern "C"` is an abort. The author knew about this exact hazard, wrote it down, fixed it in one place, and missed the other.

**Lifetime theater**

```rust
pub unsafe extern "C" fn polars_value_struct_get<'a: 'b, 'b>(
    value: *mut polars_value_t<'a>,
    …
```

Lifetime parameters on a `#[no_mangle] extern "C"` fn enforce nothing — C supplies no lifetimes, so the compiler picks whatever satisfies the bound. The `'a: 'b` reads like it's guaranteeing the parent outlives the field, but the doc comment right above it quietly admits the truth ("The value producing the new value must outlive the value from the field"). If it's a caller invariant, say so and drop the parameters; keeping them implies a check that doesn't exist.

That generalizes: `polars_value_t<'a>` wraps `AnyValue<'a>`, which *borrows* from its parent Series. Every value handle Julia holds is a live reference into memory it can independently free. `polars_value_time_zone` handing back a raw `*const u8` into the timezone string makes it explicit. This might be entirely fine if the Julia side roots the parent — but nothing here says so.

**Silent data loss**

- `to_dtype()` maps Date, Datetime, Duration, List, Struct, and Unknown *all* to `DataType::Unknown(UnknownKind::Any)`. This is what `polars_expr_cast` calls — so `cast(col, Date)` from Julia silently becomes a cast-to-unknown rather than an error. The comment says "Cannot map structs and lists" and under-sells its own damage by three types.
- `PolarsTimeUnitInvalid => TimeUnit::Microseconds`. A sentinel meaning "this isn't a time value" is silently accepted as valid input.
- The enum has no `Time`, `Decimal`, `Array`, `Categorical`, or `Enum`; they all collapse to `Unknown` via `from_dtype`'s catch-all. Meanwhile `polars_value_type` special-cases categoricals to `String`. So the same categorical is "String" or "Unknown" depending on which door you came through.

**Convoluted logic**

```rust
let Err(err) = (match (*value).inner.get_str() {
    Some(s) => w.write(s.as_bytes()),
    None => return make_error("value is not of type string"),
}) else {
    return std::ptr::null();
};
make_error(err)
```

A `let`-else destructuring the *error* variant, so the success path lives in the `else` block and the function's happy return is buried mid-statement. It's in both `string_get` and `binary_get`. A plain `match` is three lines and reads forward.

**Smaller**

- **`polars_value_type` is `pub extern "C" fn` — no `unsafe`**, unlike every other function here, while dereferencing a raw pointer through an internal `unsafe {}` block. That's an unsound safe function; a Rust caller can trigger UB without writing `unsafe`.
- `_iter_struct_av()` is an underscore-prefixed polars internal — semver-exempt, will break silently. It's also `.nth(fieldidx)`, so walking all fields is quadratic.
- `to_closed_window(self)`/`to_label(self)` take `self`; `to_time_unit(&self)`/`to_dtype(&self)` take `&self`. Pick one.

**Rating: B-.** Fix `list_type` and I'd move on; the comments here are good enough that I'd want whoever wrote them writing the safety docs for the rest of the crate.