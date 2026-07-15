"""
    scan_ipc(path::String)::LazyFrame

Lazily scans an Arrow IPC (Feather) file without reading it into memory.
"""
function scan_ipc(path)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_scan_ipc(path, length(path), out)
    polars_error(err)
    return LazyFrame(out[])
end

"""
    read_ipc(path::String)::DataFrame

Reads a dataframe stored in an Arrow IPC (Feather) file.
"""
read_ipc(path) = collect(scan_ipc(path))
"""
    sink_ipc(lf::LazyFrame, path::String)
    sink_ipc(df::DataFrame, path::String)

Executes the query and writes the result directly to an Arrow IPC (Feather) file via the streaming
engine, without materializing the full result in memory.
"""
sink_ipc(df::DataFrame, path::String) = sink_ipc(lazy(df), path)
function sink_ipc(lf::LazyFrame, path::String)
    out = Ref{Ptr{polars_lazy_frame_t}}()
    err = polars_lazy_frame_sink_ipc(lf, path, length(path), out)
    polars_error(err)
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end
