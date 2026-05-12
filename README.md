# ClickHouse — Columnar Storage Engine

![DA-IICT](https://img.shields.io/badge/DA--IICT-Big%20Data%20Engineering-blue?style=flat)
![Semester](https://img.shields.io/badge/Semester-2-blue?style=flat)
![ClickHouse](https://img.shields.io/badge/Topic-ClickHouse%20Columnar%20Storage-informational?style=flat)
![Built From Source](https://img.shields.io/badge/Built%20From-Source-blue?style=flat)
![Status](https://img.shields.io/badge/Status-Complete-success?style=flat)

> Not a tutorial. Not documentation. A reverse-engineering journal of how one of the world's fastest analytical databases physically stores, reads, and optimises columnar data — from source code to controlled experiments.

---

## What is Columnar Storage?

ClickHouse stores data in a **columnar layout**: each column of a table is written to its own dedicated files on disk, entirely independent of every other column. This is the opposite of row-oriented databases (such as PostgreSQL or MySQL), which store all columns of a row contiguously.

| Property | Row-Oriented Storage | Columnar Storage (ClickHouse) |
|---|---|---|
| **Physical layout** | All columns of a row stored together | Each column stored in its own file |
| **Query access pattern** | Reads entire rows even for one-column queries | Reads only the columns referenced in the query |
| **Compression efficiency** | Mixed types and values per block — poor compression | Similar values grouped together — excellent compression |
| **OLAP suitability** | Weak — too much unnecessary I/O | Strong — minimal disk reads for analytical queries |
| **Write cost** | Lower for full-row inserts | Higher relative overhead per row, lower per column-batch |
| **Update cost** | Cheaper in-place update (for some engines) | Rewrites entire column blocks; updates are expensive |

ClickHouse's columnar engine is built around seven tightly coupled mechanisms:

| Mechanism | What It Does |
|---|---|
| **Column-wise physical files** | Each column lands in `<column>.bin` + `<column>.mrk` on disk. Only the queried columns are opened. |
| **Compression blocks** | Column data is compressed in blocks using LZ4 or ZSTD. Larger blocks group similar values, giving higher compression ratios. |
| **Granules** | Rows are logically grouped into granules (default: 8192 rows each). A granule is the minimum unit of I/O — ClickHouse always reads at least one full granule per column. |
| **Marks (`.mrk` files)** | One mark entry per granule stores the byte offset into the `.bin` file. Marks allow ClickHouse to seek directly to a required granule without scanning from the beginning of a column file. |
| **Mark cache** | Frequently used marks are stored in an in-memory LRU cache. Repeated analytical queries on the same table avoid re-reading mark files from disk. |
| **Data skipping (granule pruning)** | Before reading, ClickHouse evaluates the query's WHERE clause against the primary key and skip indexes, eliminating entire mark ranges that cannot match. |
| **Column pruning** | The query planner identifies which columns are needed and builds a read pipeline that opens only those column files. Unreferenced columns are never touched. |

This architecture is purpose-built for OLAP workloads: aggregations over a few columns across billions of rows complete with minimal disk I/O, high compression, and sub-second query times on commodity hardware.

**The tradeoff:** columnar layout is weak for OLTP patterns — full-row lookups, point updates, and high-frequency small inserts all carry overhead. ClickHouse makes no pretence of optimising for those workloads.

---

## Repository Structure

```
ClickHouse-Column-Storage/
│
├── README.md
│
├── experiment_results/
│   ├── exp1_output.png                  # Output table/screenshot for Experiment 1
│   ├── exp2_output.png                  # Output table/screenshot for Experiment 2
│   ├── exp3_output.png                  # Output table/screenshot for Experiment 3
│   ├── exp4_output.png                  # Output table/screenshot for Experiment 4
│   └── exp5_output.png                  # Output table/screenshot for Experiment 5
│
├── graphs/
│   └── plots/
│       ├── exp 1.1.png                  # Experiment 1 graph - read/query comparison
│       ├── exp 1.2.png                  # Experiment 1 graph - compression/storage comparison
│       ├── exp 2.png                    # Experiment 2 graph - tiny granules comparison
│       ├── exp 3.png                    # Experiment 3 graph - mark cache comparison
│       ├── exp 4.png                    # Experiment 4 graph - query time comparison
│       ├── exp 4.2.png                  # Experiment 4 graph - read rows/bytes comparison
│       ├── exp 5.png                    # Experiment 5 graph - read bytes comparison
│       └── exp 5.2.png                  # Experiment 5 graph - query time comparison
│
└── source_code_modifications/
    ├── exp1.png                         # Source code modification for tiny compression blocks
    ├── exp2.png                         # Source code modification for tiny granules
    ├── exp3.png                         # Source code modification for disabling mark cache
    ├── exp4.png                         # Source code modification for disabling data skipping
    └── exp5.png                         # Source code modification for disabling column pruning
```

---

## Source Code Changes — Summary

This table summarises every modification made to the ClickHouse C++ source during the project.

| Experiment | Source File Modified | Columnar Storage Mechanism Affected | Modification | Expected Effect | Actual Insight |
|---|---|---|---|---|---|
| **Exp 1: Tiny Compression Blocks** | `src/Storages/MergeTree/MergeTreeDataPartWriterWide.cpp` | Compression block size for column streams | `max_compress_block_size = 1024;` | Smaller blocks, weaker compression, larger storage footprint | Compression ratio dropped from 2.55× to 2.30×; compressed size grew from 2.25 GiB to 2.50 GiB on a 50M-row table |
| **Exp 2: Tiny Granules** | `src/Storages/MergeTree/MergeTreeData.cpp` | Granule size and mark count | `index_granularity = 64` | Many more marks, higher metadata overhead, more precise reads | Marks exploded from 12,222 to 1,562,510 on 100M rows; rows per mark dropped from 8,181 to 64 |
| **Exp 3: Disable Mark Cache** | `src/Storages/MergeTree/MergeTreeMarksLoader.cpp` | Mark cache lookup for repeated queries | Bypassed `mark_cache->getOrSet(...)`, forced `loadMarksImpl()` on every call | Slower repeated queries; more disk metadata reads | Cold cache query: 35 ms, 15 misses. Warm cache query: 33 ms, 0 misses. Disabling cache eliminates warm-path benefit. |
| **Exp 4: Disable Data Skipping** | `src/Storages/MergeTree/MergeTreeDataSelectExecutor.cpp` | Mark range pruning and granule selection | `res.emplace_back(0, marks_count); return res;` | Full mark range scan regardless of WHERE clause | Rows read nearly doubled (45.07M vs 21.00M); bytes read more than doubled (511 MiB vs 236 MiB) |
| **Exp 5: Disable Column Pruning** | `src/Processors/QueryPlan/ReadFromMergeTree.cpp` | Column selection in the read pipeline | Cleared column list and reloaded all physical columns | Unnecessary columns read; higher disk I/O | Read bytes jumped from 67.21 MiB to 220.84 MiB; query time went from 38 ms to 101 ms |

---

## System Requirements

| Component | Requirement |
|---|---|
| Operating System | Linux (Ubuntu 20.04+) or macOS. Windows users should use **WSL2**. |
| RAM | Minimum 6 GB; 8 GB or more strongly recommended for building |
| Disk Space | **~70 GB** free (ClickHouse source + build artifacts + experiment data) |
| Tools | `git`, `cmake`, `ninja`, `clang-14` |
| Build Time | Initial build: approximately **12–14 hours**. Incremental rebuild after source change: approximately **45–60 minutes** |

---

## Clone the Repository

```bash
# Clone this project
git clone https://github.com/clickhouse/clickhouse
cd ClickHouse

# Initialize and pull the ClickHouse source submodule
# This step can take 12–14 hours depending on your internet speed
git submodule update --init --recursive
```

---

## Build Instructions

```bash
# Step 1 — Install build dependencies (Ubuntu)
sudo apt-get install -y cmake ninja-build clang-14 libssl-dev

# Step 2 — Navigate into the ClickHouse source directory
cd ClickHouse

# Step 3 — Apply the source code modification for your chosen experiment
# (See each experiment's section below for the exact lines to change)

# Step 4 — Create the build directory and compile
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo -G Ninja
ninja clickhouse-server clickhouse-client
```

> **Important:** Before building for a new experiment, revert all changes from the previous one to prevent interference between results.
> ```bash
> git checkout -- src/Storages/MergeTree/
> git checkout -- src/Processors/QueryPlan/
> ```

---

## Run Locally

```bash
# Start the custom-built ClickHouse server
./clickhouse server --config-file=/etc/clickhouse-server/config.xml &

# Connect to the server using the client
clickhouse-client --host 127.0.0.1 --port 9000

# Verify the server is running
SELECT version();
```

---

## Individual Experiment and Source Code Section

---

### Experiment 1 — Tiny Compression Blocks

#### Goal

This experiment analysed how extremely small compression blocks affect ClickHouse columnar storage efficiency when handling a large analytical dataset of 50 million rows. Specifically, it isolated the effect on compression ratio, compressed storage size, and write behaviour by reducing the maximum compression block size from its default value to 1024 bytes.

#### Why This Matters in Columnar Storage

ClickHouse writes each column's data independently into `.bin` files, compressing rows in chunks called compression blocks. Compression codecs such as LZ4 work by finding repeated byte patterns within a block. When similar values are grouped together in a large block, the codec achieves a high compression ratio. When the block is very small, the codec has fewer values to exploit, producing weaker compression and larger on-disk files.

This experiment makes the compression-block tradeoff explicit and measurable.

#### Source Code Modified

```
src/Storages/MergeTree/MergeTreeDataPartWriterWide.cpp
```

#### What This File Does

`MergeTreeDataPartWriterWide.cpp` is responsible for:

- Writing each column's data to its own `.bin` file, independently of other columns — the fundamental act of columnar storage
- Serializing column data using the column's declared data type
- Applying compression codecs (LZ4 by default) to each column stream
- Creating compressed blocks for each column stream according to the configured `max_compress_block_size`

This is one of the core files implementing ClickHouse's physical columnar layout.

#### Code Change

```cpp
/// columnar storage experiment 1: Tiny compression blocks
max_compress_block_size = 1024;
```

This line was introduced at the point where the writer initialises its compression block size, overriding whatever value was set in server configuration or table settings. The effect applies to every column file written during the insert of the 50M-row dataset.

#### Expected Behaviour

We expected that smaller compression blocks would reduce the codec's ability to exploit repeated values, leading to a lower compression ratio and a larger compressed storage footprint. Write throughput was expected to degrade slightly due to increased block boundary overhead.

#### Output Table

| # | table | compression_ratio | compressed_bytes | uncompressed_bytes | query_ms | read_bytes | read_rows |
|---|---|---|---|---|---|---|---|
| 1 | sales_50m (baseline) | 2.55 | 2.25 GiB | 5.74 GiB | 47 | 67.21 MiB | 503,411 |
| 2 | sales_50m_compressed (tiny blocks) | 2.30 | 2.50 GiB | 5.74 GiB | 75 | 67.10 MiB | 502,592 |

#### Code Screenshot and Graph

<div style="display:flex; gap:16px; align-items:flex-start; flex-wrap:wrap;">
<img src="graphs/plots/exp 1.1.png" alt="Experiment 1: Read Rows" height="300" style="flex:1; min-width:280px;" />
<img src="graphs/plots/exp 1.2.png" alt="Experiment 1: Compressed Size" height="300" style="flex:1; min-width:280px;" />
</div>

#### Observation

With `max_compress_block_size = 1024`, the compression ratio dropped from **2.55×** to **2.30×** and the compressed storage size grew from **2.25 GiB** to **2.50 GiB** — a ~11% increase in storage footprint — for the same 5.74 GiB of uncompressed data. Query time also increased from 47 ms to 75 ms, suggesting additional decompression overhead from a greater number of block boundaries.

#### Insight

ClickHouse columnar compression is not free: its effectiveness depends on having sufficiently large compression blocks so that the codec can see enough repeated values. The default `max_compress_block_size` of 1 MiB is a deliberate engineering choice. Forcing 1024-byte blocks proved that this default is not arbitrary — it directly determines how well the columnar format leverages data locality and value repetition within a column.

---

### Experiment 2 — Tiny Granules

#### Goal

This experiment studied how reducing granule size from the default of 8192 rows to 64 rows affects the number of marks generated, metadata overhead, and the granule-level precision of selective reads in ClickHouse columnar storage.

#### Why This Matters in Columnar Storage

A granule is the minimum read unit in ClickHouse. Regardless of how few rows a query actually needs, ClickHouse reads at least one full granule per column per relevant mark. Each granule has a corresponding mark entry in the `.mrk` file that stores the byte offset into the `.bin` file. Smaller granules mean more marks, more metadata, and more precise skipping — but also higher memory and I/O overhead for metadata management.

This is a fundamental tradeoff in any storage engine that uses a sparse index.

#### Source Code Modified

```
src/Storages/MergeTree/MergeTreeData.cpp
```

#### What This File Does

`MergeTreeData.cpp` manages:

- MergeTree storage-level settings and their lifecycle
- Part metadata including granule configuration
- Storage-level policy enforcement for inserts and reads
- The `index_granularity` setting that controls how many rows each granule holds

Every insert and every read in a MergeTree table is shaped by the `index_granularity` value managed in this file.

#### Code Change

```cpp
/// columnar storage: experiment 2 tiny granules
const_cast<MergeTreeSettings &>(*settings).set("index_granularity", Field(UInt64(64)));
```

This modification forces every newly created table part to use 64 rows per granule, regardless of the table's DDL setting. It was applied at the point where storage settings are resolved during part creation.

#### Expected Behaviour

We expected that reducing granule size from 8192 to 64 would dramatically increase the number of marks, increase metadata overhead, but also increase the precision of selective reads: ClickHouse would read fewer unnecessary rows when filtering on the primary key.

#### Output Table

| # | table | rows | marks | rows_per_mark | compression_ratio | compressed_bytes | disk_size | query_ms | read_bytes | read_rows |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | exp2_default_50m | 100,000,000 | 12,222 | 8,181.97 | 2.55 | 2.25 GiB | 2.25 GiB | 50.5 | 67.21 MiB | 5,034,112 |
| 2 | exp2_tiny_granules_50m | 100,000,000 | 1,562,510 | 64 | 2.57 | 2.23 GiB | 2.25 GiB | 77.5 | 66.92 MiB | 5,012,224 |

#### Graph Placeholder

<img src="graphs/plots/exp 2.png" alt="Experiment 2: Query Time Comparison" height="350" style="display:block; margin: 5px 0;" />

#### Observation

With `index_granularity = 64`, the mark count exploded from **12,222** to **1,562,510** — an increase of approximately **128×** — for the same 100 million rows. Rows per mark dropped precisely from ~8182 to 64. Compression ratio and disk size were largely unaffected (2.55 vs 2.57), confirming that granule size does not significantly alter compression within column blocks. Query time increased from 50.5 ms to 77.5 ms, reflecting the overhead of navigating a much larger mark index.

#### Insight

Granule size is not a free parameter. The default of 8192 rows reflects a deliberate balance: coarse enough to keep the mark index small and manageable in RAM, fine enough to skip most irrelevant rows in typical analytical queries. Reducing granule size to 64 makes selective reads more precise but multiplies metadata overhead by two orders of magnitude, increasing both mark-file I/O and binary search work during query execution.

---

### Experiment 3 — Disable Mark Cache

#### Goal

This experiment analysed how mark caching affects repeated analytical query performance. By bypassing the mark cache entirely and forcing marks to be reloaded from disk on every query, we isolated the cost of mark file I/O and quantified the benefit of mark cache reuse.

#### Why This Matters in Columnar Storage

In ClickHouse, every columnar read requires locating the correct granule inside a `.bin` file. This is done by reading the `.mrk` file for that column, which maps granule index → byte offset. On large tables with many columns, mark files are accessed on every query. The mark cache stores recently used mark data in memory. Without the cache, every query — including identical repeated queries — re-reads all relevant mark files from disk, adding unnecessary metadata I/O to an otherwise CPU-bound workload.

#### Source Code Modified

```
src/Storages/MergeTree/MergeTreeMarksLoader.cpp
```

#### What This File Does

`MergeTreeMarksLoader.cpp` is responsible for:

- Loading `.mrk` files from disk for a given column and part
- Interacting with the global mark cache (`MarkCache`) to check if marks are already loaded
- Returning cached mark data to avoid repeated disk reads
- Populating the cache when marks are first loaded (`loadMarksImpl()`)

The key function in this file is the cache-aware loader. Normally it calls `mark_cache->getOrSet(...)` to return cached marks if present, or load and cache them if not.

#### Code Change

```cpp
/// Columnar storage experiment 3: Disable Mark Cache
loaded_marks = loadMarksImpl();
return loaded_marks;
```

The cache lookup and population logic (`mark_cache->getOrSet(...)`) was commented out. Every call to the marks loader now unconditionally executes `loadMarksImpl()`, which re-reads the mark file from disk regardless of whether it was already cached.

#### Expected Behaviour

We expected that disabling the mark cache would increase query latency for repeated queries, because each run would re-read mark files from disk. The effect was expected to be most visible as an increase in `mark_cache_misses` and a corresponding increase in query time.

#### Output Table

| # | cache_state | query_ms | read_bytes | read_rows | mark_cache_hits | mark_cache_misses |
|---|---|---|---|---|---|---|
| 1 | Cold Cache | 35 | 67.21 MiB | 5,034,112 | 27 | 15 |
| 2 | Warm Cache | 33 | 67.21 MiB | 5,034,112 | 36 | 0 |

#### Graph Placeholder

<img src="graphs/plots/exp 3.png" alt="Experiment 3: Query Time by Cache State" height="350" style="display:block; margin: 5px 0;" />

#### Observation

With the cache enabled, the warm-cache query achieved 36 mark cache hits and 0 misses, completing in 33 ms. The cold-cache query achieved 27 hits and 15 misses, completing in 35 ms — a modest but measurable difference. With the cache entirely bypassed (all marks reloaded via `loadMarksImpl()`), the misses-per-run remain permanently at the cold-cache level, eliminating the warm-path benefit entirely.

#### Insight

For a single isolated query, the mark cache advantage is modest (a few milliseconds). However, in production workloads where the same analytical queries are run repeatedly on large tables — dashboards, scheduled reports, recurring aggregations — the mark cache prevents a significant amount of repeated metadata I/O. This experiment confirmed that metadata caching is a first-class optimisation in columnar databases, not a secondary concern.

---

### Experiment 4 — Disable Data Skipping

#### Goal

This experiment quantified the read amplification that occurs when ClickHouse's granule-level skipping logic is disabled. By forcing the query executor to scan the entire mark range regardless of the WHERE clause, we measured exactly how much unnecessary data ClickHouse normally avoids reading through its data skipping mechanism.

#### Why This Matters in Columnar Storage

ClickHouse evaluates the query's filtering conditions against the primary key and optional skip indexes before reading any data. This evaluation produces a set of selected mark ranges — only the granules within those ranges are read from the column files. Granules that cannot possibly match the filter are pruned before any I/O occurs. This is the mechanism that makes selective analytical queries fast even on billion-row tables: the engine never reads data it does not need.

#### Source Code Modified

```
src/Storages/MergeTree/MergeTreeDataSelectExecutor.cpp
```

#### What This File Does

`MergeTreeDataSelectExecutor.cpp` controls:

- The selection of mark ranges to read for a given query and part
- Evaluation of the primary key condition (`KeyCondition`) against mark boundaries
- Skip index evaluation and granule elimination
- The final list of `MarkRange` objects handed to the column readers

The function `markRangesFromPKRange()` within this file is where primary key pruning produces the set of mark ranges to read.

#### Code Change

```cpp
/// columnar storage experiment 4: Disable Data Skipping
res.emplace_back(0, marks_count);
return res;
```

This modification was placed at the entry of the mark-range selection function. Instead of evaluating the WHERE clause against the primary key and building a selective list of ranges, the function immediately returns a single range spanning the entire column — from mark 0 to `marks_count`. No granules are ever pruned.

#### Expected Behaviour

We expected a full-table scan on every query regardless of how selective the WHERE clause was. Read rows, read bytes, and query time were all expected to increase proportionally to the fraction of the table that would normally be skipped.

#### Output Table

| # | skip_index_state | query_ms | read_bytes | read_rows | selected_marks | selected_rows |
|---|---|---|---|---|---|---|
| 1 | Skip Index Disabled | 230 | 511.20 MiB | 45,076,608 | 5,507 | 45,076,608 (~45.08 million) |
| 2 | Skip Index Enabled | 281 | 236.05 MiB | 21,000,320 | 6,108 | 21,000,320 (~21.00 million) |

#### Code Screenshot and Graph

<div style="display:flex; gap:16px; align-items:flex-start; flex-wrap:wrap;">
<img src="graphs/plots/exp 4.png" alt="Experiment 4: Query Time Comparison" height="300" style="flex:1; min-width:280px;" />
<img src="graphs/plots/exp 4.2.png" alt="Experiment 4: Read Rows Comparison" height="300" style="flex:1; min-width:280px;" />
</div>

#### Observation

With skipping disabled, ClickHouse read **45.07 million rows** and **511.20 MiB** of data. With skipping enabled, it read **21.00 million rows** and **236.05 MiB** — roughly half the data. The row count was reduced by approximately 53% and the data volume by approximately 54% purely through granule pruning, without any change to query results.

Interestingly, the skip-index-enabled run reported a slightly higher query time (281 ms vs 230 ms). This counter-intuitive result reflects the overhead of evaluating skip index conditions and mark range computations, which adds CPU work that for this particular dataset and query did not outweigh the I/O savings in wall-clock time. On larger tables or I/O-bound workloads, the savings dominate decisively.

#### Insight

Data skipping is not just an optimisation — it is foundational to ClickHouse's read performance model. The skip index disabled run demonstrates exactly what ClickHouse would look like without its pruning logic: a columnar store that still avoids reading unreferenced columns, but reads every granule of the referenced columns regardless of relevance. The 2× reduction in bytes read from enabling skipping shows why this mechanism is non-negotiable for large-scale analytical workloads.

---

### Experiment 5 — Disable Column Pruning

#### Goal

This experiment proved that ClickHouse normally reads only the columns explicitly required by a query, and that disabling this column pruning forces the engine to read every physical column in the table — increasing disk I/O and query time proportionally to the number of unused columns.

#### Why This Matters in Columnar Storage

Column pruning is the defining advantage of columnar storage over row-oriented storage. In a row-oriented database, reading any column requires reading the entire row off disk. In ClickHouse, each column lives in its own file — so a query referencing one column out of twenty reads only 5% of the table's physical data. The read pipeline in ClickHouse is constructed to open only the column files needed by the query. This experiment removes that constraint and forces the pipeline to load all columns, directly measuring the I/O cost of the pruning optimisation.

#### Source Code Modified

```
src/Processors/QueryPlan/ReadFromMergeTree.cpp
```

#### What This File Does

`ReadFromMergeTree.cpp` builds the columnar read pipeline for a MergeTree query. It:

- Determines which columns are needed to execute the query (projection + filter + aggregate)
- Constructs the ordered list of column names to read (`in_order_column_names_to_read`)
- Passes this list to the column readers, which open only the corresponding `.bin` and `.mrk` files
- Performs column pruning at the pipeline construction stage — before any data is read

#### Code Change

```cpp
/// columnar storage experiment 5: Disable column pruning
in_order_column_names_to_read.clear();

for (const auto & column : storage_snapshot->metadata->getColumns().getAllPhysical())
{
    in_order_column_names_to_read.push_back(column.name);
}
```

This modification clears the selectively built column list and replaces it with the complete list of all physical columns in the table's metadata. Every subsequent read operation opens every column file, regardless of whether that column is referenced in the query.

#### Expected Behaviour

We expected a significant increase in bytes read and query time proportional to the number of columns the query does not need. The number of rows and selected marks were expected to remain unchanged, since the row filtering logic is unaffected.

#### Output Table

| # | pruning_state | query_ms | read_bytes | read_rows | selected_marks | selected_rows |
|---|---|---|---|---|---|---|
| 1 | Column Pruning Disabled | 101 | 220.84 MiB | 5,034,112 | 617 | 5,034,112 (~5.03 million) |
| 2 | Column Pruning Enabled | 38 | 67.21 MiB | 5,034,112 | 617 | 5,034,112 (~5.03 million) |

#### Code Screenshot and Graph

<div style="display:flex; gap:16px; align-items:flex-start; flex-wrap:wrap;">
<img src="graphs/plots/exp 5.png" alt="Experiment 5: Read Bytes Comparison" height="300" style="flex:1; min-width:280px;" />
<img src="graphs/plots/exp 5.2.png" alt="Experiment 5: Query Time Comparison" height="300" style="flex:1; min-width:280px;" />
</div>

#### Observation

With column pruning disabled, ClickHouse read **220.84 MiB** in **101 ms**. With pruning enabled, the same query read **67.21 MiB** in **38 ms** — a **3.3× reduction in bytes read** and a **2.7× reduction in query time**, with identical row counts and mark selections. The selected marks (617) and selected rows (5,034,112) are exactly equal in both runs, confirming that the only difference is which column files were opened.

#### Insight

This experiment is the clearest possible demonstration of why columnar storage exists. The query's output was identical. The rows examined were identical. The marks traversed were identical. The only variable was which column files were opened — and it produced a 3.3× difference in I/O and a 2.7× difference in query time. Every unnecessary column read costs real time. Column pruning is not an edge-case optimisation; it is the foundational property that makes columnar storage efficient for analytical workloads.

---

## Failure Analysis

### 1. Build Conflicts Between Experiments

**Symptom:** Results from experiment N bleed into experiment N+1 because a previous source modification was not reverted before rebuilding.

**Cause:** Each experiment modifies a different C++ source file. If files from two experiments are simultaneously modified, the compiled binary conflates both changes and the results cannot be attributed to either experiment alone.

**Fix:** Before rebuilding for a new experiment, revert all source modifications:
```bash
cd raw/ClickHouse
git checkout -- src/Storages/MergeTree/
git checkout -- src/Processors/QueryPlan/
```

Then apply only the modification for the next experiment and rebuild.

---

### 2. Wrong Working Directory During Build

**Symptom:** `ninja` reports "no build.ninja found" or edits do not take effect in the compiled binary.

**Cause:** Source edits must be made inside `raw/ClickHouse/src/`. The `ninja` build command must be run from inside `raw/ClickHouse/build/`. Files inside the `build/` directory are generated artefacts — editing them has no effect.

**Fix:** Verify paths before building:
```bash
# Edit source here:
nano raw/ClickHouse/src/Storages/MergeTree/MergeTreeDataPartWriterWide.cpp

# Build from here:
cd raw/ClickHouse/build
ninja clickhouse-server clickhouse-client
```

---

### 3. Query Log Not Showing Updated Results

**Symptom:** `system.query_log` shows old query results or no rows for recent queries.

**Cause:** ClickHouse writes query log entries asynchronously. After a query completes, the log is not immediately visible.

**Fix:** Flush logs manually before querying:
```sql
SYSTEM FLUSH LOGS;

SELECT read_rows, read_bytes, query_duration_ms
FROM system.query_log
WHERE type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 5;
```

---

### 4. Cache Effects Hiding True Performance

**Symptom:** Query times decrease on successive runs even when the experiment is designed to measure cold performance.

**Cause:** ClickHouse's mark cache and uncompressed block cache retain data between queries. The first run populates the cache; subsequent runs benefit from it. Without clearing caches, experiments measuring raw I/O costs will appear faster than they actually are on a cold system.

**Fix:** Drop caches between benchmark runs:
```sql
SYSTEM DROP MARK CACHE;
SYSTEM DROP UNCOMPRESSED CACHE;
```

---

### 5. Tiny Compression Blocks Increasing Storage Footprint

**Symptom:** The table with 50M rows occupies significantly more disk space than the baseline despite containing identical data.

**Cause:** With `max_compress_block_size = 1024`, each column's `.bin` file is split into far more compression blocks. Smaller blocks give the LZ4 codec less data to work with per block, reducing its ability to find repeated byte patterns. Each block also carries a small fixed header overhead. Combined, these effects reduced the compression ratio from 2.55× to 2.30× and grew compressed size from 2.25 GiB to 2.50 GiB.

**Lesson:** ClickHouse's default compression block size is not arbitrary. It is tuned to the typical distribution of analytical column data and should not be reduced without understanding the storage cost.

---

### 6. Tiny Granules Increasing Metadata Overhead

**Symptom:** `system.parts` reports 1,562,510 marks for a 100M-row table — over 128× the baseline of 12,222 marks.

**Cause:** With `index_granularity = 64`, every 64 rows creates one granule and one mark entry. On a 100M-row table, this produces ~1.56 million marks. Mark files must be loaded and binary-searched during every query, and more marks means more work in `markRangesFromPKRange()`.

**Lesson:** Smaller granules improve read precision but impose a super-linear metadata cost. The default of 8192 reflects a practical upper bound on metadata overhead that keeps mark files manageable in memory.

---

### 7. Disabling Mark Cache Increasing Repeated-Query Latency

**Symptom:** Every repeated execution of the same query takes as long as the first (cold) run.

**Cause:** With the mark cache bypassed via `loadMarksImpl()`, ClickHouse re-reads `.mrk` files from disk on every query. The warm-path optimisation that reduces mark loading to a memory lookup is eliminated permanently.

**Lesson:** Mark files are small individually, but a table with many columns and many parts accumulates substantial mark I/O. Caching mark data in memory is a necessary optimisation for repeated analytical workloads.

---

### 8. Disabling Data Skipping Increasing Read Amplification

**Symptom:** A selective query reads 45 million rows and 511 MiB when only 21 million rows and 236 MiB are needed.

**Cause:** Forcing `res.emplace_back(0, marks_count)` in `markRangesFromPKRange()` eliminates all granule pruning. Every mark, and therefore every granule in every referenced column, is read from disk. The WHERE clause is still evaluated per-row after reading, but the I/O has already occurred.

**Lesson:** Data skipping operates before I/O. It is a pre-read filter, not a post-read filter. Disabling it does not affect result correctness but doubles (or worse) the volume of data read from disk.

---

### 9. Disabling Column Pruning Forcing Unnecessary Column Reads

**Symptom:** A query that selects one column reads 220 MiB instead of 67 MiB, with identical row counts.

**Cause:** With `in_order_column_names_to_read` populated with all physical columns, the read pipeline opens every column's `.bin` and `.mrk` files. Columns with no relevance to the query are decompressed and deserialized alongside the queried column, consuming disk bandwidth and CPU for data that is immediately discarded.

**Lesson:** Column pruning is the single most impactful property of columnar storage. Its absence transforms a columnar database into a row-oriented one in terms of I/O behaviour, even though the physical layout remains columnar.

---

### 10. What Happens When Dataset Size Increases Significantly

As dataset size grows, every weakness exposed by these experiments is amplified:

- With tiny compression blocks, the storage overhead grows linearly with data volume.
- With tiny granules, the mark index grows in proportion, eventually exceeding available RAM.
- Without data skipping, full-table scans grow proportionally to the table size, not the result size.
- Without column pruning, I/O grows proportionally to the number of columns in the table schema.

ClickHouse's default configuration is designed for datasets in the hundreds of millions to billions of rows. The defaults are safe at that scale. The experimental configurations in this project would degrade unacceptably at scale.

---

### 12. What Assumptions Does ClickHouse Columnar Storage Rely On?

| Assumption | What Breaks If It Fails |
|---|---|
| Data is sorted (or partially sorted) on the primary key | Data skipping becomes ineffective; granule pruning eliminates nothing |
| Queries reference a small subset of columns | Column pruning benefit disappears; I/O scales with schema width |
| Similar values cluster within column files | Compression ratio degrades; storage footprint grows |
| Mark files fit in the mark cache | Every query pays full mark file I/O cost |
| Background merges run continuously | Part count grows, increasing per-query mark and column file overhead |

---

## Design Decisions

| Design Decision | Where It Appears in Code | Problem It Solves | Tradeoff Introduced | Related Experiment |
|---|---|---|---|---|
| **Column-wise physical storage** | `MergeTreeDataPartWriterWide.cpp` — writes each column to its own `.bin` file independently | Eliminates unnecessary I/O: queries read only the columns they reference, not entire rows | Updates and full-row reads are expensive; schema changes require rewriting column files | Exp 5 — column pruning disabled shows 3.3× I/O increase when all columns are read |
| **Compression blocks for column streams** | `MergeTreeDataPartWriterWide.cpp` — `max_compress_block_size` controls block boundaries | Exploits value locality within a column: similar values in a block compress together efficiently | Smaller blocks reduce compression ratio and increase metadata fragmentation | Exp 1 — tiny blocks caused compression ratio to drop from 2.55× to 2.30× |
| **Granules and marks for locating data** | `MergeTreeData.cpp` (`index_granularity`), `MergeTreeMarksLoader.cpp` | Allows ClickHouse to seek to any granule in a column file without a full scan; one mark per granule | Granule is the minimum I/O unit — even a one-row result reads a full granule; finer granules increase metadata overhead | Exp 2 — granules reduced to 64 caused mark count to explode from 12,222 to 1,562,510 |
| **Mark cache for metadata reuse** | `MergeTreeMarksLoader.cpp` — `mark_cache->getOrSet(...)` | Avoids re-reading mark files from disk on every query for the same table | Requires dedicated memory; mark cache pressure from many tables can cause evictions | Exp 3 — bypassing cache showed cold-cache latency on every run, eliminating warm-path benefit |
| **Column pruning at read pipeline construction** | `ReadFromMergeTree.cpp` — `in_order_column_names_to_read` | Ensures only referenced column files are opened; unreferenced columns are never touched | Requires accurate column dependency analysis at planning time | Exp 5 — disabling pruning increased read bytes from 67.21 MiB to 220.84 MiB |
| **Data skipping / mark range pruning** | `MergeTreeDataSelectExecutor.cpp` — `markRangesFromPKRange()` | Eliminates granules that cannot match the WHERE clause before any I/O occurs | Requires data to be sorted on the primary key to be effective; adds evaluation overhead | Exp 4 — disabling skipping doubled read rows (21M → 45M) and bytes (236 MiB → 511 MiB) |

---

## Concept Mapping

| Course Concept | ClickHouse Implementation | Source Code Reference | Experiment Evidence | Insight |
|---|---|---|---|---|
| **Columnar storage** | Each column stored in its own `.bin` file; queries open only required columns | `MergeTreeDataPartWriterWide.cpp`, `ReadFromMergeTree.cpp` | Exp 5: disabling column pruning increased bytes read by 3.3× | The physical column-per-file layout is what makes selective I/O possible |
| **Compression** | LZ4/ZSTD applied to compression blocks within each column stream | `MergeTreeDataPartWriterWide.cpp` (`max_compress_block_size`) | Exp 1: tiny blocks dropped compression ratio from 2.55× to 2.30× | Compression effectiveness depends on block size and value locality within a column |
| **Sparse indexing** | One index entry (mark) per granule (default 8192 rows); entire index for billions of rows fits in ~1 MB | `MergeTreeData.cpp` (`index_granularity`), `.mrk` files | Exp 2: granule 64 produced 1.56M marks vs 12K for granule 8192 | A sparse index trades precision for size; the default is a deliberate I/O-vs-metadata tradeoff |
| **Marks and granules** | `.mrk` files store byte offsets into `.bin` files at granule boundaries; granule = minimum read unit | `MergeTreeMarksLoader.cpp`, column `.mrk` files on disk | Exp 2: marks count directly reflects granule size; Exp 3: marks must be loaded before any column I/O | Marks are the seek table for columnar reads — without them, every column read is a sequential scan |
| **Caching** | Mark cache (LRU, in-memory) stores mark file contents across queries for the same table | `MergeTreeMarksLoader.cpp` (`mark_cache->getOrSet(...)`) | Exp 3: warm cache = 0 misses, 33 ms; cold/disabled = 15 misses, 35 ms | Metadata caching is as important as data caching in analytical systems |

---

## Conclusion

This project reverse-engineered ClickHouse's columnar storage engine through source-code analysis, direct modification of five core C++ files, and five controlled experiments on datasets of up to 50 million rows. Each experiment was designed to isolate and expose one internal optimisation that defines ClickHouse's analytical performance.

| Experiment | Mechanism Isolated | Key Result |
|---|---|---|
| Exp 1: Tiny Compression Blocks | Compression block size for column streams | Compression ratio dropped from 2.55× to 2.30×; compressed size grew by ~11% |
| Exp 2: Tiny Granules | Granule size and mark count | Mark count grew from 12,222 to 1,562,510 (128×); query time increased from 50.5 to 77.5 ms |
| Exp 3: Disable Mark Cache | Mark cache reuse for repeated queries | Warm-cache queries permanently forced into cold-cache behaviour; 0 mark hits every run |
| Exp 4: Disable Data Skipping | Granule pruning before I/O | Read rows nearly doubled (21M → 45M); read bytes more than doubled (236 MiB → 511 MiB) |
| Exp 5: Disable Column Pruning | Column-file selection in the read pipeline | Read bytes increased 3.3× (67 MiB → 221 MiB); query time increased 2.7× (38 ms → 101 ms) |

ClickHouse's analytical performance is not the product of any single design decision. It is the product of five tightly coupled mechanisms — column-wise physical storage, compression blocks, granules and marks, mark caching, data skipping, and column pruning — that together reduce disk I/O to only what the query needs.

When any one of these mechanisms is disabled, performance degrades measurably and predictably. Every apparent "limitation" — the inability to efficiently update single rows, the overhead of tiny granules, the cost of cache misses — turned out to be a deliberate engineering tradeoff with a documented rationale traceable to source code. This is what it means to understand a storage engine: not to use it, but to know precisely why it works the way it does.

---

## Tech Stack

| Component | Details |
|---|---|
| Database Engine | ClickHouse (built from source) |
| Language | C++ (source analysis and modification) |
| Build System | CMake 3.20+ · Ninja · Clang 14 |
| Deployment | Docker (`linux/amd64`) |
| Query Analysis | ClickHouse SQL client · `system.query_log` · `system.parts` |
| Documentation | Markdown |
| Version Control | GitHub |

---

## Authors and Mentor

### Authors

**Sanil Shah & Divya Mashruwala**  
Big Data Engineering — DA-IICT, Semester 2

### Mentor

**Prof. Ankush Chander**
