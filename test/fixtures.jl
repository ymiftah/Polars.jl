# Shared sample-data builders for the test suite, analogous to py-polars' conftest.py fixtures.
# Keep genuinely one-off/edge-case data inline in the test file that needs it instead of adding
# a fixture here.

"""Small dataframe mixing strings and numerics, for join/sort/group_by tests."""
fruits_cars_df() = DataFrame(
    (;
        fruits = ["banana", "banana", "apple", "apple", "banana"],
        cars = ["beetle", "audi", "beetle", "beetle", "beetle"],
        A = [1, 2, 3, 4, 5],
        B = [5, 4, 3, 2, 1],
    )
)

"""One column per major scalar dtype (with a null in each), for schema/round-trip coverage."""
kitchen_sink_df() = DataFrame(
    (;
        int = [1, 2, 3, missing],
        float = [1.5, 2.5, missing, 4.5],
        bool = [true, false, true, missing],
        str = ["a", "b", missing, "d"],
        date = [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3), missing],
        datetime = [DateTime(2024, 1, 1, 0), DateTime(2024, 1, 1, 1), missing, DateTime(2024, 1, 1, 3)],
    )
)

"""24h hourly DateTime series across two stores, for dynamic/rolling group-by tests."""
hourly_store_df() = DataFrame(
    (;
        time = DateTime(2024, 1, 1) .+ Hour.(0:23),
        store = repeat(["a", "b"], 12),
        value = collect(1:24),
    )
)

"""Writes `df` to a fresh temp parquet file and returns its path."""
function write_temp_parquet(df; name = "data.parquet")
    dir = mktempdir()
    path = joinpath(dir, name)
    write_parquet(path, df)
    return path
end

"""Writes `df` to a fresh temp CSV file and returns its path."""
function write_temp_csv(df; name = "data.csv")
    dir = mktempdir()
    path = joinpath(dir, name)
    write_csv(path, df)
    return path
end
