# Experiment 1: Columnar Storage Efficiency
# Objective: Compare a narrow query vs a wide query on the same dataset.

SELECT sum(amount)
FROM ch_storage_demo
WHERE event_date >= '2025-03-01';

SELECT
    sum(amount),
    sum(clicks),
    any(category),
    any(region),
    any(payload)
FROM ch_storage_demo
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
  AND query LIKE 'SELECT%'
ORDER BY event_time DESC
LIMIT 10;