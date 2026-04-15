# Experiment 2: Good Filter vs Bad Filter
# Objective: Compare a filter aligned with ORDER BY vs a non-aligned filter.

SELECT count()
FROM ch_storage_demo
WHERE event_date = '2025-02-10';

SELECT count()
FROM ch_storage_demo
WHERE region = 'North';

SYSTEM FLUSH LOGS;

SELECT
    event_time,
    query,
    query_duration_ms,
    read_rows,
    read_bytes
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE 'SELECT count()%'
ORDER BY event_time DESC
LIMIT 10;