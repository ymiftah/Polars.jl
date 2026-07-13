using Polars, Test, Dates

@testset "Create from C Data interface" begin
    table = (; x = randn(Float32, 100))

    df = DataFrame(table)
    s = only(select(df, col("x") |> sum)[:x])

    @test s ≈ sum(table.x)

    df = nothing
end

@testset "GC C Data interface" begin
    GC.gc(true)

    @test isempty(Polars.LIVE_ARRAYS)
    @test isempty(Polars.LIVE_SCHEMAS)
end

@testset "Lazy vs Eager" begin
    table = (; x=randn(Float32, 100), cond = rand(Bool, 100))
    df = DataFrame(table)

    function selector(df)
        df = with_columns(df, cos(col("x")*1.5) |> alias("tmp"))
        filter(df, col("cond") & (col("x") < 0.))
    end

    df2 = df |> lazy |> selector |> collect
    df = selector(df)

    @test df[:tmp] == df2[:tmp]
end

@testset "scan_parquet" begin
    dir = mktempdir()
    write_parquet(joinpath(mkpath(joinpath(dir, "year=2023")), "part.parquet"),
                  DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40])))
    write_parquet(joinpath(mkpath(joinpath(dir, "year=2024")), "part.parquet"),
                  DataFrame((; category = ["a", "b", "a", "b"], amount = [100, 200, 300, 400])))

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

@testset "head" begin
    df = DataFrame((; x = collect(1:5), y = ["a", "b", "c", "d", "e"]))

    h = head(df, 2)
    @test size(h) == (2, 2)
    @test h[:x] == [1, 2]

    h = head(lazy(df), 3) |> collect
    @test size(h) == (3, 2)
    @test h[:x] == [1, 2, 3]
end

@testset "Date" begin
    dates = [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3)]
    df = DataFrame((; d = dates))

    @test Polars.schema(df).types == (Date,)
    @test df[:d] == dates

    dir = mktempdir()
    path = joinpath(dir, "dates.parquet")
    write_parquet(path, df)

    df2 = read_parquet(path)
    @test df2[:d] == dates
end

@testset "collect_schema" begin
    df = DataFrame((; x = collect(1:5), y = ["a", "b", "c", "d", "e"]))
    lf = lazy(df)

    sch = collect_schema(lf)
    @test sch.names == (:x, :y)
    @test sch.types == (Union{Missing,Int64}, Union{Missing,String})

    sch2 = collect_schema(with_columns(lf, (col("x") * 2) |> alias("z")))
    @test sch2.names == (:x, :y, :z)
    @test sch2.types[3] == Union{Missing,Int64}

    @test_throws Exception collect_schema(filter(lf, col("nonexistent") > 0))
end

@testset "Exprs" begin
    df = DataFrame((; x=[1,2,3,3.1,missing]))

    @test filter(df, col("x") >= 2) |> size == (3,1)
    @test filter(df, col("x") > 2)  |> size == (2,1)
    @test filter(df, col("x") == 2) |> size == (1,1)

    @test filter(df, col("x") |> is_null) |> size == (1,1)
    @test filter(df, col("x") |> is_null |> Polars.not) |> size == (4,1)

    df = DataFrame((; names = ["john", "alice", missing, "bob", "lilly"]))

    lengths = select(df, col("names") |> Strings.len_chars |> sum |> suffix("_lengths"))[:names_lengths] |> only
    @test lengths == length("john") + length("alice") + length("bob") + length("lilly")

    df = DataFrame((; names = ["eggs 🥚", "cheese 🧀", "tomatoes 🍅"],
                      price = [1.2, 3.4, 5.4],
                      availability = [20, 2, 3]))
    df = filter(df, (col("price") * col("availability")) < 10.)
    df = select(df, col("names") |> Strings.uppercase |> alias("tobuy"))

    @test df[:tobuy] == ["CHEESE 🧀"]
end

@testset "group_by_dynamic" begin
    df = DataFrame((; time = DateTime(2024, 1, 1) .+ Hour.(0:23),
                      store = repeat(["a", "b"], 12),
                      value = collect(1:24)))
    lf = lazy(df)

    # basic daily bucketing
    r1 = group_by_dynamic(lf, "time"; every="1d") |>
        x -> agg(x, Polars.sum(col("value"))) |>
        collect
    @test size(r1) == (1, 2)
    @test r1[:time] == [DateTime(2024, 1, 1)]
    @test r1[:value] == [sum(1:24)]

    # extra group-by key
    r2 = group_by_dynamic(lf, "time", ["store"]; every="12h") |>
        x -> agg(x, Polars.sum(col("value"))) |>
        collect
    by_store_window = Dict((r2[:store][i], r2[:time][i]) => r2[:value][i] for i in eachindex(r2[:store]))
    @test by_store_window[("a", DateTime(2024, 1, 1, 0))] == sum(1:2:12)
    @test by_store_window[("a", DateTime(2024, 1, 1, 12))] == sum(13:2:24)
    @test by_store_window[("b", DateTime(2024, 1, 1, 0))] == sum(2:2:12)
    @test by_store_window[("b", DateTime(2024, 1, 1, 12))] == sum(14:2:24)

    # rolling
    r3 = rolling(lf, "time"; period="3h") |>
        x -> agg(x, Polars.sum(col("value"))) |>
        collect
    @test size(r3) == (24, 2)
    @test r3[:value][1] == sum(2:4)
end

@testset "Series" begin
    values = [1,2,3,4,5]
    s = Series(:values, values)
    @test sum(values) == sum(s)
end
