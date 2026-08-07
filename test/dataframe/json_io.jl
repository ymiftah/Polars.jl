@testset "write_json / read_json round-trip" begin
    df = DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    dir = mktempdir()
    path = joinpath(dir, "data.json")

    write_json(path, df)
    @test startswith(strip(read(path, String)), "[")

    df2 = read_json(path)
    @test df2 isa Polars.DataFrame
    @test size(df2) == size(df)
    @test df2[:category] == df[:category]
    @test df2[:amount] == df[:amount]

    # IO method agrees with the path method
    io = IOBuffer()
    write_json(io, df)
    io_path = joinpath(dir, "from_io.json")
    write(io_path, take!(io))
    @test read_json(io_path)[:amount] == df[:amount]
end

@testset "write_json rejects cloud URIs (no cloud sink for plain JSON)" begin
    df = DataFrame((; x = [1, 2, 3]))
    dir = mktempdir()

    err = nothing
    cd(dir) do
        try
            write_json("s3://some-bucket/out.json", df)
        catch e
            err = e
        end
    end
    @test err !== nothing
    @test isempty(readdir(dir))
    @test !isdir(joinpath(dir, "s3:"))
end

@testset "write_ndjson / read_ndjson round-trip" begin
    df = DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    dir = mktempdir()
    path = joinpath(dir, "data.jsonl")

    write_ndjson(path, df)
    lines = filter(!isempty, split(read(path, String), '\n'))
    @test length(lines) == 4
    @test all(startswith(l, "{") for l in lines)

    df2 = read_ndjson(path)
    @test size(df2) == size(df)
    @test df2[:category] == df[:category]
    @test df2[:amount] == df[:amount]
end

@testset "read_ndjson: infer_schema_length / ignore_errors" begin
    dir = mktempdir()

    path = joinpath(dir, "infer.jsonl")
    write(path, "{\"a\":1}\n{\"a\":2}\n{\"a\":\"not_a_number\"}\n")
    df_full = read_ndjson(path; infer_schema_length = nothing)
    @test collect(df_full[:a]) == ["1", "2", "not_a_number"]

    ok_path = joinpath(dir, "ok.jsonl")
    write(ok_path, "{\"a\":1}\n{\"a\":2}\n")
    df = read_ndjson(ok_path; ignore_errors = true)
    @test collect(df[:a]) == [1, 2]
end

@testset "write_ndjson rejects cloud URIs instead of silently writing a local file" begin
    df = DataFrame((; x = [1, 2, 3]))
    dir = mktempdir()

    err = nothing
    cd(dir) do
        try
            write_ndjson("s3://some-bucket/out.jsonl", df)
        catch e
            err = e
        end
    end
    @test err !== nothing
    @test occursin("sink_ndjson", sprint(showerror, err))
    @test isempty(readdir(dir))
    @test !isdir(joinpath(dir, "s3:"))

    # a plain local path takes the same entry point and still writes normally
    local_path = joinpath(dir, "out.jsonl")
    write_ndjson(local_path, df)
    @test read_ndjson(local_path)[:x] == df[:x]
end

@testset "read_json has no lazy scan_json counterpart" begin
    @test !isdefined(Polars, :scan_json)
end
