DROP TABLE IF EXISTS ch_storage_demo;

CREATE TABLE ch_storage_demo
(
    event_date Date,
    user_id UInt32,
    category LowCardinality(String),
    region LowCardinality(String),
    amount Float64,
    clicks UInt32,
    payload String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, user_id);

INSERT INTO ch_storage_demo
SELECT
    toDate('2025-01-01') + (number % 120) AS event_date,
    number % 1000000 AS user_id,
    arrayElement(['A','B','C','D','E'], 1 + (number % 5)) AS category,
    arrayElement(['North','South','East','West'], 1 + (number % 4)) AS region,
    randCanonical() * 1000 AS amount,
    rand() % 100 AS clicks,
    repeat('x', 200) AS payload
FROM numbers(5000000);

SELECT count() FROM ch_storage_demo;

SELECT
    table,
    name,
    part_type,
    rows,
    bytes_on_disk,
    data_compressed_bytes,
    data_uncompressed_bytes
FROM system.parts
WHERE active
  AND table = 'ch_storage_demo'
ORDER BY name;