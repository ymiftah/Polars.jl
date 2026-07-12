pub fn main() {
    // Header regeneration is opt-in (CBINDGEN_GENERATE=1) and requires a nightly
    // toolchain (it shells out to `cargo rustc -- -Zunpretty=expanded`, e.g.
    // `CBINDGEN_GENERATE=1 cargo +nightly build`). Default builds use the stable
    // toolchain (see rust-toolchain) specifically to avoid polars-ops's own
    // build.rs, which auto-detects a nightly rustc and unconditionally enables
    // its nightly-only unicode_internals code path -- broken on toolchains where
    // that unstable libcore API has moved. include/polars.h is committed and
    // hand-maintained.
    if std::env::var_os("CBINDGEN_GENERATE").is_none() {
        return;
    }

    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();

    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_pragma_once(true)
        .with_parse_expand(&["c-polars"])
        .with_parse_expand_all_features(false)
        .with_include("arrow.h")
        .with_language(cbindgen::Language::C)
        .generate()
        .expect("could not build headers")
        .write_to_file("include/polars.h");
}
