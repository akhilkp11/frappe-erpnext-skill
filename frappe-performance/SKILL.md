---
name: frappe-performance
description: Find and fix slow Frappe/ERPNext code - slow pages, APIs, reports, list views, scheduler jobs, high MariaDB load, N+1 queries, missing indexes, large get_doc loops, caching and invalidation, Recorder/EXPLAIN profiling. Use for any latency, timeout, "report takes minutes", or database load investigation, including audits of custom apps.
---

# Performance audit and optimization

Measure first. Claims such as "this is 10x faster" need numbers from before and after; without profiling data, label findings as hypotheses.

## 1. Locate the time
- **Recorder** (Desk > Recorder): start it, repeat the slow action, inspect query count, duration per query, and the Python call stack of the worst offenders.
- **Slow query log / process list** on MariaDB for production-only issues (read-only: `SHOW PROCESSLIST`, `SHOW FULL PROCESSLIST`).
- **EXPLAIN / EXPLAIN ANALYZE** (where the MariaDB version supports it) on the suspect SQL from the Recorder.
- Python-level: `cProfile`/`py-spy` for CPU-bound code; timing wrappers for external calls.
- Separate: database time, Python time, external HTTP time, queue/scheduler delay, and browser rendering (large JSON, huge grids).
- In tests, `self.assertQueryCount(n)` (IntegrationTestCase) pins query counts so regressions fail CI.

## 2. Typical findings and fixes
**N+1 queries**
```python
# slow: one query per invoice
for inv in invoices:
    inv.territory = frappe.get_doc("Customer", inv.customer).territory

# fast: one query, map by key
customers = list({i.customer for i in invoices})
territory = {c.name: c.territory for c in
             frappe.get_all("Customer", filters={"name": ["in", customers]}, fields=["name", "territory"])}
for inv in invoices:
    inv.territory = territory.get(inv.customer)
```
Chunk very large `IN` lists (for example 1,000 at a time).

**Over-fetching**: `get_doc` for one field, `fields=["*"]`, loading child tables you do not use. Use `db.get_value`, explicit `fields`, and `pluck`.

**Computation in the database**: sum/group in SQL (`frappe.qb` with `Sum`, `groupby`) instead of fetching rows and adding in Python.

**Missing/ineffective indexes**: check the query plan first. Index columns used in WHERE/JOIN/ORDER BY of hot queries; remember write cost and existing indexes (`SHOW INDEX FROM \`tabSales Invoice\``). `LIKE '%text%'` cannot use an index. Add via DocType `search_index` or `frappe.db.add_index` in a patch; never edit the schema by hand on production.

**Child-table joins**: filter the parent first, join children on `parent`, and avoid joining several child tables in one query (row explosion).

**Per-request recomputation**: use `frappe.get_cached_doc` for read-only masters/settings, `frappe.utils.caching` helpers (`request_cache`, `site_cache`, `redis_cache`) where available, or Redis via the cache API. The cache object access differs between versions (`frappe.cache()` vs `frappe.cache`): check the installed source. Every cache needs an invalidation story (when does the value change? is the key scoped by user/company/site?).

**Heavy work in the request**: queue it (`frappe-background-jobs`) or use Prepared Reports; return job status to the UI.

**Unbounded responses and exports**: limit rows, require filters, stream/export in a job.

**Hook cost**: a `doc_events` wildcard (`"*"`) or a validate hook that queries per row slows every save. Count queries per save in Recorder.

**Server shape**: too few gunicorn/worker processes, MariaDB `innodb_buffer_pool_size` far below data size, swap usage, or Redis at maxmemory show up as general slowness. These are infrastructure fixes (see `frappe-devops`), not code changes.

## 3. Safety while optimizing
Preserve results first: compare old and new output on the same data (row counts and totals), keep permission behavior (`get_list` vs `get_all`), keep company/filter semantics, and keep ledger correctness. Optimize the biggest measured cost, not the code that "looks" slow.

## 4. Deliverable
Severity-ranked findings, each with file/function, evidence (query counts, timings, plan), impact, the fix, and how to validate (before/after numbers). If you could not run the code or profile, say so and mark each item as a hypothesis.
