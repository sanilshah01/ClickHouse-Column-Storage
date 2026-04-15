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

<img width="1074" height="766" alt="exp_1_read_bytes" src="https://github.com/user-attachments/assets/e026f9b1-8dc7-421b-be7d-b09dd39110f7" />


---

### Experiment 2 — Good vs Bad Filter

* Compared filter aligned with ORDER BY vs non-aligned filter
* Result: ~73K vs ~5M rows scanned (~68x difference)
* Insight: Sorting enables efficient pruning

<img width="910" height="650" alt="exp2_read_bytes" src="https://github.com/user-attachments/assets/2afbc40d-91a7-49ed-a7b7-6486dbb684e3" />
<img width="910" height="650" alt="exp2_read_rows" src="https://github.com/user-attachments/assets/cbe9cada-4c21-4254-b9a8-41f5f7d372ca" />



---

### Experiment 3 — Performance on Large Data

* Compared 1M vs 10M datasets
* Result: Increased read_bytes and query time with larger data
* Insight: Performance scales with data size

<img width="910" height="650" alt="exp3_query_duration" src="https://github.com/user-attachments/assets/34313ae3-038b-4339-a596-b9001a3351f5" />
<img width="910" height="650" alt="exp3_read_bytes" src="https://github.com/user-attachments/assets/fd913683-e343-4829-818a-b1f312f71cd2" />
<img width="910" height="650" alt="exp3_read_rows" src="https://github.com/user-attachments/assets/67527c85-2e3d-48b3-a415-96ed0ef8ce71" />




---

### Experiment 4 — Index Granularity

* Compared granularity 8192 vs 1024
* Result: Smaller granularity reads fewer rows but increases metadata
* Insight: Tradeoff between precision and overhead

<img width="910" height="650" alt="exp4_1" src="https://github.com/user-attachments/assets/de36931c-1bc4-467d-9362-7eff25126c3c" />
<img width="910" height="650" alt="exp4_2" src="https://github.com/user-attachments/assets/bebb1716-86f9-45ac-a716-c64a3692e5e4" />
<img width="910" height="650" alt="exp4_3" src="https://github.com/user-attachments/assets/35f559fe-354c-43ba-a3d4-3611b01ba0d0" />




---

### Experiment 5 — Wide vs Compact Parts

* Compared storage formats
* Result: Wide format used ~6.4% less storage
* Insight: Column-wise storage improves compression efficiency

<img width="910" height="650" alt="exp5_storage" src="https://github.com/user-attachments/assets/10c30187-52f8-4830-95d9-2f7b8aa0b669" />


---

### Experiment 6 — Compression Efficiency

* Compared compressed vs uncompressed data
* Result: ~15.94x compression achieved
* Insight: Columnar storage significantly reduces storage and I/O

<img width="910" height="650" alt="exp6_compression" src="https://github.com/user-attachments/assets/cfa55e06-ae6e-45e5-b057-2dc4b1b2079a" />


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
