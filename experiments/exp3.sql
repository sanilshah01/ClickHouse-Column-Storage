# Experiment 3: Performance on Large Data Size
# Objective: Compare query performance on 1M rows vs 10M rows.

DROP TABLE IF EXISTS ch_storage_small;
DROP TABLE IF EXISTS ch_storage_large;

CREATE TABLE ch_storage_small AS ch_storage_demo;
CREATE TABLE ch_storage_large AS ch_storage_demo;

INSERT INTO ch_storage_small
SELECT
    toDate('2025-01-01') + (number % 120),
    number % 1000000,
    arrayElement(['A','B','C','D','E'], 1 + (number % 5)),
    arrayElement(['North','South','East','West'], 1 + (number % 4)),
    randCanonical() * 1000,
    rand() % 100,
    repeat('x', 200)
FROM numbers(1000000);

INSERT INTO ch_storage_large
SELECT
    toDate('2025-01-01') + (number % 120),
    number % 1000000,
    arrayElement(['A','B','C','D','E'], 1 + (number % 5)),
    arrayElement(['North','South','East','West'], 1 + (number % 4)),
    randCanonical() * 1000,
    rand() % 100,
    repeat('x', 200)
FROM numbers(10000000);

SELECT 'small' AS table_name, count() FROM ch_storage_small
UNION ALL
SELECT 'large' AS table_name, count() FROM ch_storage_large;

SELECT sum(amount)
FROM ch_storage_small
WHERE event_date >= '2025-03-01';

SELECT sum(amount)
FROM ch_storage_large
WHERE event_date >= '2025-03-01';

SYSTEM FLUSH LOGS;

SELECT
    event_time,
    query,
    query_duration_ms,
    read_rows,
    read_bytes
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE 'SELECT sum(amount)%'
ORDER BY event_time DESC
LIMIT 10;

SELECT
    table,
    sum(rows) AS total_rows,
    sum(bytes_on_disk) AS total_bytes
FROM system.parts
WHERE active
  AND table IN ('ch_storage_small', 'ch_storage_large')
GROUP BY table
ORDER BY table;