"""
    scan_csv(path::String)::LazyFrame

Lazily scans a CSV file without reading it into memory.
"""
function scan_csv(path)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_scan_csv(path, length(path), out)
    polars_error(err)
    return LazyFrame(out[])
end

"""
    read_csv(path::String)::DataFrame

Reads a dataframe stored in a CSV file.
"""
read_csv(path) = collect(scan_csv(path))

"""
    write_csv(io::IO, df::DataFrame)
    write_csv(path::String, df::DataFrame)

Writes a dataframe to a CSV file provided as an `IO`.
"""
function write_csv(io::IO, df::DataFrame)
    callback = @cfunction(_write_callback, Cssize_t, (Any, Ptr{Cchar}, Cuint))
    ref = Ref(io)
    err = polars_dataframe_write_csv(df, ref, callback)
    polars_error(err)
    return nothing
end
write_csv(p::String, df::DataFrame) = open(io -> write_csv(io, df), p, "w")
"""
    sink_csv(lf::LazyFrame, path::String)
    sink_csv(df::DataFrame, path::String)

Executes the query and writes the result directly to a CSV file via the streaming engine, without
materializing the full result in memory.
"""
sink_csv(df::DataFrame, path::String) = sink_csv(lazy(df), path)
function sink_csv(lf::LazyFrame, path::String)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_sink_csv(lf, path, length(path), out)
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end
