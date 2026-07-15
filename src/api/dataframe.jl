function polars_dataframe_size(df, rows, cols)
    return @ccall libpolars.polars_dataframe_size(df::Ptr{polars_dataframe_t}, rows::Ptr{Csize_t}, cols::Ptr{Csize_t})::Cvoid
end

"""
    polars_dataframe_new_from_carrow(cfield, carray)

Creates a DataFrame from a series of [`ArrowArray`](@ref) and [`ArrowSchema`](@ref) compatible the arrow C-ABI.

# Safety The field array should be valid [`ArrowSchema`](@ref) according to the C Data Interface. The array array should be valid [`ArrowArray`](@ref) according to the C Data Interface, this means that the memory ownership is transferred in the created arrow::Array. Therefore, the caller should *not* free the underlying memories for this arrow as this will be done through the release field of the array.

Returns null if something went wrong.
"""
function polars_dataframe_new_from_carrow(cfield, carray)
    return @ccall libpolars.polars_dataframe_new_from_carrow(cfield::Ptr{ArrowSchema}, carray::ArrowArray)::Ptr{polars_dataframe_t}
end

"""
    polars_dataframe_schema(df)

Returns a [`ArrowSchema`](@ref) describing the dataframe's schema according to Arrow C Data interface.
"""
function polars_dataframe_schema(df)
    return @ccall libpolars.polars_dataframe_schema(df::Ptr{polars_dataframe_t})::ArrowSchema
end

function polars_dataframe_new_from_series(series, nseries, out)
    return @ccall libpolars.polars_dataframe_new_from_series(series::Ptr{Ptr{polars_series_t}}, nseries::Csize_t, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

function polars_dataframe_destroy(df)
    return @ccall libpolars.polars_dataframe_destroy(df::Ptr{polars_dataframe_t})::Cvoid
end

function polars_dataframe_write_parquet(
        df, user, callback, compression, compression_level, statistics, row_group_size,
        data_page_size
    )
    return @ccall libpolars.polars_dataframe_write_parquet(
        df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback,
        compression::polars_parquet_compression_t, compression_level::Ptr{Int32}, statistics::Bool,
        row_group_size::Ptr{Csize_t}, data_page_size::Ptr{Csize_t}
    )::Ptr{polars_error_t}
end

function polars_dataframe_write_csv(
        df, user, callback, include_header, include_bom, separator, quote_char, null_value,
        null_value_len, line_terminator, line_terminator_len, quote_style, date_format,
        date_format_len, time_format, time_format_len, datetime_format, datetime_format_len,
        float_precision, decimal_comma
    )
    return @ccall libpolars.polars_dataframe_write_csv(
        df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback, include_header::Bool,
        include_bom::Bool, separator::UInt8, quote_char::UInt8, null_value::Ptr{UInt8},
        null_value_len::Csize_t, line_terminator::Ptr{UInt8}, line_terminator_len::Csize_t,
        quote_style::polars_quote_style_t, date_format::Ptr{UInt8}, date_format_len::Csize_t,
        time_format::Ptr{UInt8}, time_format_len::Csize_t, datetime_format::Ptr{UInt8},
        datetime_format_len::Csize_t, float_precision::Ptr{Csize_t}, decimal_comma::Bool
    )::Ptr{polars_error_t}
end

function polars_dataframe_write_ipc(df, user, callback, compression, compression_level, record_batch_size)
    return @ccall libpolars.polars_dataframe_write_ipc(
        df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback,
        compression::polars_ipc_compression_t, compression_level::Ptr{Int32},
        record_batch_size::Ptr{Csize_t}
    )::Ptr{polars_error_t}
end

function polars_dataframe_show(df, user, callback)
    return @ccall libpolars.polars_dataframe_show(df::Ptr{polars_dataframe_t}, user::Ptr{Cvoid}, callback::IOCallback)::Ptr{polars_error_t}
end

function polars_dataframe_get(df, name, len, out)
    return @ccall libpolars.polars_dataframe_get(df::Ptr{polars_dataframe_t}, name::Ptr{UInt8}, len::Csize_t, out::Ptr{Ptr{polars_series_t}})::Ptr{polars_error_t}
end

function polars_dataframe_lazy(df)
    return @ccall libpolars.polars_dataframe_lazy(df::Ptr{polars_dataframe_t})::Ptr{polars_lazy_frame_t}
end

function polars_dataframe_upsample(
        df, by_names, by_lens, n_by, time_column, time_column_len, every, every_len, stable, out
    )
    return @ccall libpolars.polars_dataframe_upsample(
        df::Ptr{polars_dataframe_t}, by_names::Ptr{Ptr{UInt8}}, by_lens::Ptr{Csize_t}, n_by::Csize_t,
        time_column::Ptr{UInt8}, time_column_len::Csize_t, every::Ptr{UInt8}, every_len::Csize_t,
        stable::Bool, out::Ptr{Ptr{polars_dataframe_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_destroy(df)
    return @ccall libpolars.polars_lazy_frame_destroy(df::Ptr{polars_lazy_frame_t})::Cvoid
end

function polars_lazy_frame_clone(df)
    return @ccall libpolars.polars_lazy_frame_clone(df::Ptr{polars_lazy_frame_t})::Ptr{polars_lazy_frame_t}
end

function polars_lazy_frame_scan_parquet(
        path, pathlen, n_rows, row_index_name, row_index_name_len, row_index_offset, parallel,
        low_memory, rechunk, cache, glob, use_statistics, allow_missing_columns,
        include_file_paths, include_file_paths_len, hive_partitioning, out
    )
    return @ccall libpolars.polars_lazy_frame_scan_parquet(
        path::Ptr{UInt8}, pathlen::Csize_t, n_rows::Ptr{Csize_t}, row_index_name::Ptr{UInt8},
        row_index_name_len::Csize_t, row_index_offset::UInt32,
        parallel::polars_parquet_parallel_strategy_t, low_memory::Bool, rechunk::Bool, cache::Bool,
        glob::Bool, use_statistics::Bool, allow_missing_columns::Bool,
        include_file_paths::Ptr{UInt8}, include_file_paths_len::Csize_t,
        hive_partitioning::Ptr{Bool}, out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_scan_csv(
        path, pathlen, n_rows, row_index_name, row_index_name_len, row_index_offset, has_header,
        separator, quote_char, comment_prefix, comment_prefix_len, skip_rows,
        skip_rows_after_header, null_value, null_value_len, missing_is_null,
        truncate_ragged_lines, try_parse_dates, infer_schema_length, ignore_errors, low_memory,
        rechunk, cache, glob, include_file_paths, include_file_paths_len, allow_missing_columns,
        out
    )
    return @ccall libpolars.polars_lazy_frame_scan_csv(
        path::Ptr{UInt8}, pathlen::Csize_t, n_rows::Ptr{Csize_t}, row_index_name::Ptr{UInt8},
        row_index_name_len::Csize_t, row_index_offset::UInt32, has_header::Bool,
        separator::UInt8, quote_char::Ptr{UInt8}, comment_prefix::Ptr{UInt8},
        comment_prefix_len::Csize_t, skip_rows::Csize_t, skip_rows_after_header::Csize_t,
        null_value::Ptr{UInt8}, null_value_len::Csize_t, missing_is_null::Bool,
        truncate_ragged_lines::Bool, try_parse_dates::Bool, infer_schema_length::Ptr{Csize_t},
        ignore_errors::Bool, low_memory::Bool, rechunk::Bool, cache::Bool, glob::Bool,
        include_file_paths::Ptr{UInt8}, include_file_paths_len::Csize_t,
        allow_missing_columns::Bool, out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_scan_ipc(
        path, pathlen, n_rows, row_index_name, row_index_name_len, row_index_offset, rechunk,
        cache, glob, include_file_paths, include_file_paths_len, hive_partitioning,
        allow_missing_columns, out
    )
    return @ccall libpolars.polars_lazy_frame_scan_ipc(
        path::Ptr{UInt8}, pathlen::Csize_t, n_rows::Ptr{Csize_t}, row_index_name::Ptr{UInt8},
        row_index_name_len::Csize_t, row_index_offset::UInt32, rechunk::Bool, cache::Bool,
        glob::Bool, include_file_paths::Ptr{UInt8}, include_file_paths_len::Csize_t,
        hive_partitioning::Ptr{Bool}, allow_missing_columns::Bool,
        out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_sink_parquet(
        lf, path, pathlen, compression, compression_level, statistics, row_group_size,
        data_page_size, mkdir, maintain_order, out
    )
    return @ccall libpolars.polars_lazy_frame_sink_parquet(
        lf::Ptr{polars_lazy_frame_t}, path::Ptr{UInt8}, pathlen::Csize_t,
        compression::polars_parquet_compression_t, compression_level::Ptr{Int32}, statistics::Bool,
        row_group_size::Ptr{Csize_t}, data_page_size::Ptr{Csize_t}, mkdir::Bool,
        maintain_order::Bool, out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_sink_csv(
        lf, path, pathlen, include_header, include_bom, separator, quote_char, null_value,
        null_value_len, line_terminator, line_terminator_len, quote_style, date_format,
        date_format_len, time_format, time_format_len, datetime_format, datetime_format_len,
        float_precision, decimal_comma, compression, compression_level, mkdir, maintain_order, out
    )
    return @ccall libpolars.polars_lazy_frame_sink_csv(
        lf::Ptr{polars_lazy_frame_t}, path::Ptr{UInt8}, pathlen::Csize_t, include_header::Bool,
        include_bom::Bool, separator::UInt8, quote_char::UInt8, null_value::Ptr{UInt8},
        null_value_len::Csize_t, line_terminator::Ptr{UInt8}, line_terminator_len::Csize_t,
        quote_style::polars_quote_style_t, date_format::Ptr{UInt8}, date_format_len::Csize_t,
        time_format::Ptr{UInt8}, time_format_len::Csize_t, datetime_format::Ptr{UInt8},
        datetime_format_len::Csize_t, float_precision::Ptr{Csize_t}, decimal_comma::Bool,
        compression::polars_csv_compression_t, compression_level::Ptr{UInt32}, mkdir::Bool,
        maintain_order::Bool, out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_sink_ipc(lf, path, pathlen, compression, compression_level, record_batch_size, mkdir, maintain_order, out)
    return @ccall libpolars.polars_lazy_frame_sink_ipc(
        lf::Ptr{polars_lazy_frame_t}, path::Ptr{UInt8}, pathlen::Csize_t,
        compression::polars_ipc_compression_t, compression_level::Ptr{Int32},
        record_batch_size::Ptr{Csize_t}, mkdir::Bool, maintain_order::Bool,
        out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_frame_sort(df, exprs, nexprs, descending, nulls_last, maintain_order)
    return @ccall libpolars.polars_lazy_frame_sort(df::Ptr{polars_lazy_frame_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t, descending::Ptr{Bool}, nulls_last::Bool, maintain_order::Bool)::Cvoid
end

function polars_lazy_frame_concat(lfs, n, out)
    return @ccall libpolars.polars_lazy_frame_concat(lfs::Ptr{Ptr{polars_lazy_frame_t}}, n::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_with_columns(df, exprs, nexprs)
    return @ccall libpolars.polars_lazy_frame_with_columns(df::Ptr{polars_lazy_frame_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t)::Cvoid
end

function polars_lazy_frame_select(df, exprs, nexprs)
    return @ccall libpolars.polars_lazy_frame_select(df::Ptr{polars_lazy_frame_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t)::Cvoid
end

function polars_lazy_frame_filter(df, expr)
    return @ccall libpolars.polars_lazy_frame_filter(df::Ptr{polars_lazy_frame_t}, expr::Ptr{polars_expr_t})::Cvoid
end

function polars_lazy_frame_head(df, n)
    return @ccall libpolars.polars_lazy_frame_head(df::Ptr{polars_lazy_frame_t}, n::Csize_t)::Cvoid
end

function polars_lazy_frame_tail(df, n)
    return @ccall libpolars.polars_lazy_frame_tail(df::Ptr{polars_lazy_frame_t}, n::Csize_t)::Cvoid
end

function polars_lazy_frame_collect(df, engine, out)
    return @ccall libpolars.polars_lazy_frame_collect(df::Ptr{polars_lazy_frame_t}, engine::PolarsEngine, out::Ptr{Ptr{polars_dataframe_t}})::Ptr{polars_error_t}
end

"""
    polars_lazy_frame_collect_schema(df, out)

Resolves the lazy frame's schema (without collecting it) and returns it through `out` as an
[`ArrowSchema`](@ref) according to the Arrow C Data interface, matching the shape of
`polars_dataframe_schema`.
"""
function polars_lazy_frame_collect_schema(df, out)
    return @ccall libpolars.polars_lazy_frame_collect_schema(df::Ptr{polars_lazy_frame_t}, out::Ptr{ArrowSchema})::Ptr{polars_error_t}
end

function polars_lazy_frame_group_by(df, exprs, nexprs)
    return @ccall libpolars.polars_lazy_frame_group_by(df::Ptr{polars_lazy_frame_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t)::Ptr{polars_lazy_group_by_t}
end

function polars_lazy_frame_group_by_dynamic(df, index_expr, group_by_exprs, n_group_by, every, every_len, period, period_len, offset, offset_len, label, include_boundaries, closed_window, start_by, out)
    return @ccall libpolars.polars_lazy_frame_group_by_dynamic(df::Ptr{polars_lazy_frame_t}, index_expr::Ptr{polars_expr_t}, group_by_exprs::Ptr{Ptr{polars_expr_t}}, n_group_by::Csize_t, every::Ptr{UInt8}, every_len::Csize_t, period::Ptr{UInt8}, period_len::Csize_t, offset::Ptr{UInt8}, offset_len::Csize_t, label::polars_label_t, include_boundaries::Bool, closed_window::polars_closed_window_t, start_by::polars_start_by_t, out::Ptr{Ptr{polars_lazy_group_by_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_rolling(df, index_expr, group_by_exprs, n_group_by, period, period_len, offset, offset_len, closed_window, out)
    return @ccall libpolars.polars_lazy_frame_rolling(df::Ptr{polars_lazy_frame_t}, index_expr::Ptr{polars_expr_t}, group_by_exprs::Ptr{Ptr{polars_expr_t}}, n_group_by::Csize_t, period::Ptr{UInt8}, period_len::Csize_t, offset::Ptr{UInt8}, offset_len::Csize_t, closed_window::polars_closed_window_t, out::Ptr{Ptr{polars_lazy_group_by_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_join(a, b, exprs_a, exprs_a_len, exprs_b, exprs_b_len, how)
    return @ccall libpolars.polars_lazy_frame_join(a::Ptr{polars_lazy_frame_t}, b::Ptr{polars_lazy_frame_t}, exprs_a::Ptr{Ptr{polars_expr_t}}, exprs_a_len::Csize_t, exprs_b::Ptr{Ptr{polars_expr_t}}, exprs_b_len::Csize_t, how::polars_join_type_t)::Ptr{polars_lazy_frame_t}
end

function polars_lazy_frame_join_asof(a, b, on_a, on_b, by_a, by_a_lens, by_a_len, by_b, by_b_lens, by_b_len, strategy, out)
    return @ccall libpolars.polars_lazy_frame_join_asof(a::Ptr{polars_lazy_frame_t}, b::Ptr{polars_lazy_frame_t}, on_a::Ptr{polars_expr_t}, on_b::Ptr{polars_expr_t}, by_a::Ptr{Ptr{UInt8}}, by_a_lens::Ptr{Csize_t}, by_a_len::Csize_t, by_b::Ptr{Ptr{UInt8}}, by_b_lens::Ptr{Csize_t}, by_b_len::Csize_t, strategy::polars_asof_strategy_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_unique(lf, names, lens, n, keep, out)
    return @ccall libpolars.polars_lazy_frame_unique(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, keep::polars_unique_keep_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_drop(lf, names, lens, n, out)
    return @ccall libpolars.polars_lazy_frame_drop(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_rename(lf, existing, existing_lens, new_, new_lens, n, strict, out)
    return @ccall libpolars.polars_lazy_frame_rename(lf::Ptr{polars_lazy_frame_t}, existing::Ptr{Ptr{UInt8}}, existing_lens::Ptr{Csize_t}, new_::Ptr{Ptr{UInt8}}, new_lens::Ptr{Csize_t}, n::Csize_t, strict::Bool, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_drop_nulls(lf, names, lens, n, out)
    return @ccall libpolars.polars_lazy_frame_drop_nulls(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_with_row_index(lf, name, name_len, offset, has_offset, out)
    return @ccall libpolars.polars_lazy_frame_with_row_index(lf::Ptr{polars_lazy_frame_t}, name::Ptr{UInt8}, name_len::Csize_t, offset::Int64, has_offset::Bool, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_explode(lf, names, lens, n, out)
    return @ccall libpolars.polars_lazy_frame_explode(lf::Ptr{polars_lazy_frame_t}, names::Ptr{Ptr{UInt8}}, lens::Ptr{Csize_t}, n::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_unpivot(lf, index_names, index_lens, n_index, on_names, on_lens, n_on, variable_name, variable_name_len, value_name, value_name_len, out)
    return @ccall libpolars.polars_lazy_frame_unpivot(lf::Ptr{polars_lazy_frame_t}, index_names::Ptr{Ptr{UInt8}}, index_lens::Ptr{Csize_t}, n_index::Csize_t, on_names::Ptr{Ptr{UInt8}}, on_lens::Ptr{Csize_t}, n_on::Csize_t, variable_name::Ptr{UInt8}, variable_name_len::Csize_t, value_name::Ptr{UInt8}, value_name_len::Csize_t, out::Ptr{Ptr{polars_lazy_frame_t}})::Ptr{polars_error_t}
end

function polars_lazy_frame_pivot(
        lf, on_names, on_lens, n_on, on_columns, index_names, index_lens, n_index, values_names,
        values_lens, n_values, agg, maintain_order, separator, separator_len, column_naming, out
    )
    return @ccall libpolars.polars_lazy_frame_pivot(
        lf::Ptr{polars_lazy_frame_t}, on_names::Ptr{Ptr{UInt8}}, on_lens::Ptr{Csize_t}, n_on::Csize_t,
        on_columns::Ptr{polars_dataframe_t}, index_names::Ptr{Ptr{UInt8}}, index_lens::Ptr{Csize_t},
        n_index::Csize_t, values_names::Ptr{Ptr{UInt8}}, values_lens::Ptr{Csize_t}, n_values::Csize_t,
        agg::Ptr{polars_expr_t}, maintain_order::Bool, separator::Ptr{UInt8}, separator_len::Csize_t,
        column_naming::polars_pivot_column_naming_t, out::Ptr{Ptr{polars_lazy_frame_t}}
    )::Ptr{polars_error_t}
end

function polars_lazy_group_by_destroy(gb)
    return @ccall libpolars.polars_lazy_group_by_destroy(gb::Ptr{polars_lazy_group_by_t})::Cvoid
end

function polars_lazy_group_by_agg(gb, exprs, nexprs)
    return @ccall libpolars.polars_lazy_group_by_agg(gb::Ptr{polars_lazy_group_by_t}, exprs::Ptr{Ptr{polars_expr_t}}, nexprs::Csize_t)::Ptr{polars_lazy_frame_t}
end
