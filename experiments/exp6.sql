# Experiment 6: Compression Efficiency
# Objective: Measure compressed vs uncompressed size in columnar storage.

SELECT
    table,
    sum(data_uncompressed_bytes) AS uncompressed_bytes,
    sum(data_compressed_bytes) AS compressed_bytes,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS compression_ratio
FROM system.parts
WHERE active
  AND table = 'ch_storage_demo'
GROUP BY table;

SELECT
    name,
    rows,
    data_uncompressed_bytes,
    data_compressed_bytes,
    round(data_uncompressed_bytes / data_compressed_bytes, 2) AS compression_ratio
FROM system.parts
WHERE active
  AND table = 'ch_storage_demo'
ORDER BY name;

SELECT
    column,
    sum(rows) AS total_rows,
    sum(data_compressed_bytes) AS compressed_bytes,
    sum(data_uncompressed_bytes) AS uncompressed_bytes,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS compression_ratio
FROM system.parts_columns
WHERE active
  AND table = 'ch_storage_demo'
GROUP BY column
ORDER BY compression_ratio DESC;