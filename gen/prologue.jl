using libpolars_jll
export libpolars_jll

# Prefer a local dev build over the registered JLL when one exists (this fork's C ABI surface has
# grown well past what's published upstream). `release/` is checked first -- if the caller has
# built one (`cargo build --release`), it's what should actually be exercised; `debug/` remains
# the fallback for the normal dev-loop `cargo build`.
const libpolars_local_release_dir = joinpath(@__DIR__, "../../c-polars/target/release/")
const libpolars_local_debug_dir = joinpath(@__DIR__, "../../c-polars/target/debug/")
@static if isdir(libpolars_local_release_dir) && isfile(
        begin
            libpolars_local_file_path = joinpath(libpolars_local_release_dir, "libpolars" * (Sys.islinux() ? ".so" : ".dylib"))
        end
    )
    const libpolars = libpolars_local_file_path
elseif isdir(libpolars_local_debug_dir) && isfile(
        begin
            libpolars_local_file_path = joinpath(libpolars_local_debug_dir, "libpolars" * (Sys.islinux() ? ".so" : ".dylib"))
        end
    )
    const libpolars = libpolars_local_file_path
end
