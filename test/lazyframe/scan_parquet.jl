@testset "scan_parquet" begin
    dir = mktempdir()
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2023")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    )
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2024")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [100, 200, 300, 400]))
    )

    lf = scan_parquet(dir)
    @test lf isa Polars.LazyFrame

    all_rows = collect(lf)
    @test size(all_rows) == (8, 3)
    @test Set(all_rows[:year]) == Set([2023, 2024])

    result = lf |>
        x -> filter(x, col("year") == 2024) |>
        x -> group_by(x, "category") |>
        x -> agg(x, Polars.sum(col("amount"))) |>
        collect

    by_category = Dict(zip(result[:category], result[:amount]))
    @test by_category["a"] == 400
    @test by_category["b"] == 600
end

@testset "scan_parquet options" begin
    dir = mktempdir()
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2023")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    )
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2024")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [100, 200, 300, 400]))
    )

    @testset "n_rows truncates" begin
        @test size(read_parquet(dir; n_rows = 3)) == (3, 3)
    end

    @testset "row_index_name / row_index_offset" begin
        df = read_parquet(dir; row_index_name = "idx", row_index_offset = 5)
        @test Tables.columnnames(df)[1] == :idx
        @test Vector(df[:idx]) == 5:12
    end

    @testset "parallel strategies all succeed" begin
        for p in (:auto, :none, :columns, :row_groups)
            @test size(collect(scan_parquet(dir; parallel = p))) == (8, 3)
        end
        @test_throws Exception scan_parquet(dir; parallel = :bogus)
    end

    @testset "hive_partitioning=false disables partition-column detection" begin
        df = read_parquet(dir; hive_partitioning = false)
        @test Set(Tables.columnnames(df)) == Set([:category, :amount])
    end

    @testset "include_file_paths adds a source-path column" begin
        df = read_parquet(dir; include_file_paths = "src_path")
        @test length(unique(Vector(df[:src_path]))) == 2
    end

    @testset "rechunk / cache / glob / low_memory / use_statistics accepted, results unaffected" begin
        for kwargs in ((rechunk = true,), (cache = false,), (glob = false,), (low_memory = true,), (use_statistics = false,))
            @test size(collect(scan_parquet(dir; kwargs...))) == (8, 3)
        end
    end

    @testset "allow_missing_columns" begin
        multi = mkpath(joinpath(mktempdir(), "multi"))
        write_parquet(joinpath(multi, "f1.parquet"), DataFrame((; x = [1, 2], y = [3, 4])))
        write_parquet(joinpath(multi, "f2.parquet"), DataFrame((; x = [5, 6])))
        @test_throws Exception collect(scan_parquet(joinpath(multi, "*.parquet")))
        df = read_parquet(joinpath(multi, "*.parquet"); allow_missing_columns = true)
        @test size(df) == (4, 2)
        # missing column in f2 is filled with nulls
        @test isequal(sort(df, col("x"))[:y], [3, 4, missing, missing])
    end

    @testset "allow_missing_columns asymmetry: extra columns still fail (documented in CLAUDE.md)" begin
        # allow_missing_columns only covers files *missing* a column present in the reference
        # schema (whichever file is scanned first) -- it does not cover files with an *extra*
        # column beyond the reference schema, which is a separate policy this wrapper doesn't
        # expose. Regression guard for that documented asymmetry.
        multi = mkpath(joinpath(mktempdir(), "extra"))
        write_parquet(joinpath(multi, "f1.parquet"), DataFrame((; x = [1, 2])))  # reference: 1 col
        write_parquet(joinpath(multi, "f2.parquet"), DataFrame((; x = [3, 4], y = [5, 6])))  # extra col
        @test_throws Exception collect(scan_parquet(joinpath(multi, "*.parquet"); allow_missing_columns = true))
    end
end

@testset "cloud IO (Phase 1: aws/gcp/azure Cargo features enabled)" begin
    @testset "s3:// scheme is recognized -- 'aws' feature must be enabled no longer fires" begin
        # Regression guard for c-polars/Cargo.toml's `polars` dependency feature list: before the
        # "aws"/"gcp"/"azure" features were added, any s3:// path failed with the clean
        # `PolarsError: feature 'aws' must be enabled in order to use 'Aws' cloud urls` message
        # (cloud/async/http were already transitively on, so this was never a process abort -- see
        # CLAUDE.md/plans/cloud_io.md). This attempts a real connection and can be run with or
        # without network access -- the assertion is only about the error message, not a
        # successful round-trip, so it stays hermetic either way.
        err_message = try
            collect(scan_parquet("s3://some-bucket/some.parquet"))
            nothing
        catch e
            sprint(showerror, e)
        end
        @test err_message !== nothing
        @test !occursin("feature 'aws' must be enabled", err_message)
    end

    if get(ENV, "POLARS_JL_NETWORK_TESTS", "") == "1"
        @testset "http(s) scan (network)" begin
            df = collect(scan_csv("https://raw.githubusercontent.com/pola-rs/polars/main/examples/datasets/foods1.csv"))
            @test size(df) == (27, 4)
        end
    end
end

@testset "cloud IO (Phase 2: storage_options)" begin
    # Task 2 (already merged) threads a `cloud_options: *const polars_cloud_options_t` handle
    # through all six scan/sink C functions; `_with_cloud_options` (src/io/parquet.jl) builds one
    # from a `storage_options::Dict` for the duration of a single ccall and always destroys it
    # afterward. These tests are hermetic (no real endpoint) -- the FFI-safety property under test
    # is "does a garbage/non-ASCII storage_options value crash the process or corrupt the string",
    # not "does the request succeed".
    @testset "unknown option key does not crash the process" begin
        # NOTE: contrary to the cloud_io.md plan's finding #7 ("upstream polars already rejects
        # unknown option keys with a clean error"), the actual upstream behavior in
        # polars-io-0.54.4's `parse_untyped_config` (cloud/options.rs) is to *silently filter out*
        # any key that doesn't parse as a known `AmazonS3ConfigKey` -- its own source comment reads
        # "Silently ignores custom upstream storage_options" -- rather than erroring. So this key
        # is dropped, not rejected: the scan proceeds with no explicit credentials and fails
        # downstream with a connection/credentials error instead of an "unknown key" error. What
        # this test still proves: passing a bogus key through the FFI boundary is safe (a clean
        # `Exception`, not a process abort) and reaches real `CloudOptions` construction rather
        # than being blocked by a missing Cargo feature (see the Phase 1 testset above).
        err_message = try
            collect(
                scan_parquet(
                    "s3://some-bucket/some.parquet";
                    storage_options = Dict("not_a_real_option_key" => "x")
                )
            )
            nothing
        catch e
            sprint(showerror, e)
        end
        @test err_message !== nothing
        @test !occursin("feature 'aws' must be enabled", err_message)
        @test !occursin("activate", err_message)
    end

    @testset "non-ASCII storage_options value survives the FFI round trip (ncodeunits regression guard)" begin
        # Regression guard for the `length` vs `ncodeunits` bug class documented in CLAUDE.md (24
        # sites truncated multi-byte UTF-8 mid-codepoint by passing a *character* count instead of
        # a *byte* count across the FFI boundary). `_with_cloud_options` builds its key/value
        # pointer arrays via `_name_ptrs` (src/verbs.jl), which is already correct (uses
        # `ncodeunits`) -- this proves it end-to-end: if the byte length were wrong, the value
        # would be truncated mid-codepoint and Rust's UTF-8 validation in
        # `polars_cloud_options_new` would reject it with an "incomplete utf-8 byte sequence"
        # error *before* any network attempt. There's no real endpoint at café.example.com, so
        # this is expected to fail either way -- the point is *how* it fails.
        err_message = try
            collect(
                scan_parquet(
                    "s3://some-bucket/some.parquet";
                    storage_options = Dict("aws_endpoint_url" => "https://café.example.com")
                )
            )
            nothing
        catch e
            sprint(showerror, e)
        end
        @test err_message !== nothing
        @test !occursin("utf-8", lowercase(err_message))
        @test !occursin("utf8", lowercase(err_message))
    end
end

if get(ENV, "POLARS_JL_MINIO_TESTS", "") == "1"
    @testset "storage_options MinIO round-trip (real, live; requires Docker)" begin
        # Spins up a throwaway local MinIO container and exercises a real S3-compatible
        # sink_*/scan_* round-trip through `storage_options`, gated behind
        # `POLARS_JL_MINIO_TESTS=1` since it needs Docker and a free port (CI has no Docker,
        # offline runs have no meaningful way to reach even localhost containers from a sandboxed
        # test runner) -- same gating pattern as `POLARS_JL_NETWORK_TESTS` above.
        #
        # This test drives the whole container lifecycle itself (start MinIO, wait for it to
        # become healthy, create a bucket via the `minio/mc` image, tear the container down in a
        # `finally` regardless of outcome). To reproduce/debug manually, the equivalent shell
        # commands are:
        #
        #   docker run -d --name polars-jl-minio-manual -p 0:9000 \
        #     -e MINIO_ROOT_USER=minioadmin -e MINIO_ROOT_PASSWORD=minioadmin \
        #     minio/minio server /data --console-address :9001
        #   HOST_PORT=$(docker port polars-jl-minio-manual 9000/tcp | head -1 | cut -d: -f2)
        #   # poll http://localhost:$HOST_PORT/minio/health/live until it returns 200
        #   docker run --rm --network container:polars-jl-minio-manual --entrypoint sh minio/mc -c \
        #     "mc alias set local http://localhost:9000 minioadmin minioadmin && mc mb local/polars-jl-test-bucket"
        #   # ... then aws_endpoint_url = "http://localhost:$HOST_PORT" in storage_options ...
        #   docker rm -f polars-jl-minio-manual
        #
        # (`--network container:<name>` shares the MinIO container's network namespace with the
        # short-lived `mc` container, so `mc` can reach it at `localhost:9000` without needing a
        # separate user-defined docker network.)
        @test Sys.which("docker") !== nothing

        container = "polars-jl-minio-test-$(getpid())"
        bucket = "polars-jl-test-bucket"
        try
            run(
                `docker run -d --name $container -p 0:9000 -e MINIO_ROOT_USER=minioadmin
                -e MINIO_ROOT_PASSWORD=minioadmin minio/minio server /data --console-address :9001`
            )

            port_info = readchomp(`docker port $container 9000/tcp`)
            host_port = parse(Int, split(split(port_info, '\n')[1], ':')[end])

            ready = false
            for _ in 1:60
                try
                    code = readchomp(
                        `curl -s -o /dev/null -w '%{http_code}' http://localhost:$host_port/minio/health/live`
                    )
                    if code == "200"
                        ready = true
                        break
                    end
                catch
                end
                sleep(0.5)
            end
            @test ready

            run(
                `docker run --rm --network container:$container --entrypoint sh minio/mc -c
                "mc alias set local http://localhost:9000 minioadmin minioadmin && mc mb local/$bucket"`
            )

            storage_options = Dict(
                "aws_endpoint_url" => "http://localhost:$host_port",
                "aws_access_key_id" => "minioadmin",
                "aws_secret_access_key" => "minioadmin",
                "aws_region" => "us-east-1",
                "aws_allow_http" => "true"
            )

            df = DataFrame((; a = [1, 2, 3], b = ["x", "y", "z"], v = [1.5, 2.5, 3.5]))

            @testset "sink_parquet / scan_parquet" begin
                path = "s3://$bucket/roundtrip.parquet"
                sink_parquet(df, path; storage_options)
                df2 = collect(scan_parquet(path; storage_options))
                @test df2 == df
            end

            @testset "sink_csv / scan_csv" begin
                path = "s3://$bucket/roundtrip.csv"
                sink_csv(df, path; storage_options)
                df2 = collect(scan_csv(path; storage_options))
                @test df2 == df
            end

            @testset "sink_ipc / scan_ipc" begin
                path = "s3://$bucket/roundtrip.ipc"
                sink_ipc(df, path; storage_options)
                df2 = collect(scan_ipc(path; storage_options))
                @test df2 == df
            end
        finally
            try
                run(`docker rm -f $container`)
            catch e
                @warn "failed to remove MinIO test container $container -- manual cleanup needed" exception = e
            end
        end
    end
end
