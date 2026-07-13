const libpolars_local_dir = joinpath(@__DIR__, "../c-polars/target/debug/")
@static if isdir(libpolars_local_dir) && isfile(
        begin
            libpolars_local_file_path = joinpath(libpolars_local_dir), "libpolars" * (Sys.islinux() ? ".so" : ".dylib")
        end
    )
    const libpolars = libpolars_local_file_path
end
