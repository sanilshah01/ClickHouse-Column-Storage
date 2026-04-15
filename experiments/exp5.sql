# Experiment 5: Wide vs Compact Parts
# Objective: Compare physical storage format in MergeTree.

DROP TABLE IF EXISTS ch_wide;
DROP TABLE IF EXISTS ch_compact;

CREATE TABLE ch_wide
(
    id UInt32,
    c1 UInt32,
    c2 UInt32,
    payload String
)
ENGINE = MergeTree
ORDER BY id
SETTINGS min_rows_for_wide_part = 0, min_bytes_for_wide_part = 0;

CREATE TABLE ch_compact
(
    id UInt32,
    c1 UInt32,
    c2 UInt32,
    payload String
)
ENGINE = MergeTree
ORDER BY id
SETTINGS min_rows_for_wide_part = 1000000000, min_bytes_for_wide_part = 1000000000;

INSERT INTO ch_wide
SELECT
    number,
    number % 1000,
    number % 500,
    repeat('x', 200)
FROM numbers(500000);

INSERT INTO ch_compact
SELECT * FROM ch_wide;

SELECT 'wide' AS table_name, count() FROM ch_wide
UNION ALL
SELECT 'compact' AS table_name, count() FROM ch_compact;

SELECT
    table,
    name,
    part_type,
    rows,
    bytes_on_disk
FROM system.parts
WHERE active
  AND table IN ('ch_wide', 'ch_compact')
ORDER BY table, name;

SELECT
    table,
    sum(bytes_on_disk) AS total_bytes
FROM system.parts
WHERE active
  AND table IN ('ch_wide', 'ch_compact')
GROUP BY table
ORDER BY table;