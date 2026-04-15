# ClickHouse Columnar Storage Analysis

## Overview

This project presents a detailed analysis of the storage architecture of the ClickHouse database system. The focus is on understanding how ClickHouse achieves high-performance analytical query execution through its columnar storage design.

The system is reverse engineered by analyzing its internal write path and validating behavior using multiple experiments.

---

## Objectives

* Analyze how data is stored internally in ClickHouse
* Understand the complete write path from insertion to disk
* Identify key design decisions and their tradeoffs
* Evaluate system performance using experimental validation

---

## System Understanding

ClickHouse uses a columnar storage model implemented through the MergeTree engine.

### Key Concepts

* **Columnar Storage**
  Data is stored column-by-column, allowing queries to read only required columns.

* **Sorting (ORDER BY)**
  Data is physically sorted to enable efficient filtering and pruning.

* **Sparse Indexing (Granules & Marks)**
  Data is divided into blocks (granules), allowing the system to skip large portions of data.

* **Compression**
  Each column is compressed independently to reduce storage and improve I/O performance.

> ClickHouse improves performance by reducing the amount of data read, not by increasing computational speed.

---

## Write Path (Simplified)

1. Insert query is received
2. Data is converted into blocks
3. Data is sorted based on primary key
4. Data is divided into granules
5. Columns are written separately to disk
6. Metadata (marks, min-max index) is generated
7. Data part is stored on disk

---

## Experimental Evaluation

---

### Experiment 1 — Columnar Storage Efficiency

* Compared narrow vs wide queries
* Result: Wide query reads significantly more bytes
* Insight: Only required columns are accessed

![Experiment 1](graphs/exp1_read_bytes.png)

---

### Experiment 2 — Good vs Bad Filter

* Compared filter aligned with ORDER BY vs non-aligned filter
* Result: ~73K vs ~5M rows scanned (~68x difference)
* Insight: Sorting enables efficient pruning

![Experiment 2](graphs/exp2_read_rows.png)

---

### Experiment 3 — Performance on Large Data

* Compared 1M vs 10M datasets
* Result: Increased read_bytes and query time with larger data
* Insight: Performance scales with data size

![Experiment 3](graphs/exp3_read_bytes.png)

---

### Experiment 4 — Index Granularity

* Compared granularity 8192 vs 1024
* Result: Smaller granularity reads fewer rows but increases metadata
* Insight: Tradeoff between precision and overhead

![Experiment 4](graphs/exp4_1.png)

---

### Experiment 5 — Wide vs Compact Parts

* Compared storage formats
* Result: Wide format used ~6.4% less storage
* Insight: Column-wise storage improves compression efficiency

![Experiment 5](graphs/exp5_storage.png)

---

### Experiment 6 — Compression Efficiency

* Compared compressed vs uncompressed data
* Result: ~15.94x compression achieved
* Insight: Columnar storage significantly reduces storage and I/O

![Experiment 6](graphs/exp6_compression.png)

---

## Execution Proof

Terminal outputs for all experiments are provided in:

```
/screenshots/
```

These demonstrate actual execution and validate system behavior.

---

## Project Structure

```
clickhouse-columnar-storage/
│
├── report/         → Final report  
├── experiments/    → SQL queries  
├── graphs/         → Output graphs  
├── screenshots/    → Terminal outputs  
├── scripts/        → Setup guide  
├── notes/          → Code analysis  
└── README.md
```

---

## Setup Instructions

Refer to:

```
scripts/setup_clickhouse.md
```

---

## Code Analysis

Detailed explanation of internal ClickHouse functions:

```
notes/code_analysis.md
```

---

## Design Decisions & Tradeoffs

| Design           | Benefit            | Tradeoff          |
| ---------------- | ------------------ | ----------------- |
| Columnar Storage | Reduced I/O        | Complex writes    |
| Sorting          | Efficient pruning  | Insert overhead   |
| Granularity      | Query precision    | Metadata overhead |
| Compression      | Storage efficiency | CPU overhead      |

---

## System-Level Insight

The experiments demonstrate that ClickHouse performance is governed by storage design:

* Columnar layout reduces unnecessary data access
* Sorting enables pruning of irrelevant data
* Granularity controls precision vs overhead
* Compression reduces disk I/O

> Performance is driven by minimizing data access rather than increasing computational speed.

---

## Limitations

ClickHouse is not ideal for:

* OLTP workloads
* Frequent updates
* Small transactional queries

---

## Repository

GitHub Repository:
https://github.com/sanilshah01/ClickHouse-Column-Storage

---

## Conclusion

This project demonstrates how storage architecture directly impacts database performance.

The experiments confirm that:

* Columnar storage reduces unnecessary reads
* Sorting and indexing enable efficient pruning
* Compression significantly reduces storage and I/O

ClickHouse achieves high performance by optimizing data access patterns rather than computation.
