# Experiment 4: Index Granularity
# Objective: Compare selective query behavior for different index_granularity settings.

DROP TABLE IF EXISTS ch_gran_8192;
DROP TABLE IF EXISTS ch_gran_1024;

CREATE TABLE ch_gran_8192
(
    event_date Date,
    user_id UInt32,
    amount Float64,
    payload String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, user_id)
SETTINGS index_granularity = 8192;

CREATE TABLE ch_gran_1024
(
    event_date Date,
    user_id UInt32,
    amount Float64,
    payload String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, user_id)
SETTINGS index_granularity = 1024;

INSERT INTO ch_gran_8192
SELECT
    toDate('2025-01-01') + (number % 120),
    number % 1000000,
    randCanonical() * 1000,
    repeat('x', 200)
FROM numbers(3000000);

INSERT INTO ch_gran_1024
SELECT * FROM ch_gran_8192;

SELECT 'gran_8192' AS table_name, count() FROM ch_gran_8192
UNION ALL
SELECT 'gran_1024' AS table_name, count() FROM ch_gran_1024;

SELECT sum(amount)
FROM ch_gran_8192
WHERE event_date = '2025-02-10'
  AND user_id BETWEEN 10000 AND 20000;

SELECT sum(amount)
FROM ch_gran_1024
WHERE event_date = '2025-02-10'
  AND user_id BETWEEN 10000 AND 20000;

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
    name,
    marks,
    rows,
    bytes_on_disk
FROM system.parts
WHERE active
  AND table IN ('ch_gran_8192', 'ch_gran_1024')
ORDER BY table, name;