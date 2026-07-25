# B2 — Cache & Document Stores

| | |
|---|---|
| **Folder** | DBA |
| **Dashboard ID** | B2 |
| **Refresh** | 15s |
| **Audience** | You wearing the DBA hat — cache efficiency, memory pressure, document store health |

> **Purpose:** Unified view of the three non-relational data stores: **Valkey** (primary cache, replacing Redis), **Redis** (legacy, ot-container-kit — kept temporarily for hidden dependencies), and **CouchDB** (document store for Obsidian sync). Valkey is tracked as the primary cache layer with full deep-dive panels; Redis is tracked with minimal up/down + connection metrics and a visible "legacy / sunset" marker; CouchDB gets its own section for document sync health.

**← Back to [Dashboard Catalog](../README.md#-dba-2-dashboards)**

---

## Data Flow

```
Valkey (port 6379, built-in /metrics or via redis-exporter)
  │
  ├──→ Alloy prometheus.scrape "valkey"         ← NEEDS TO BE ADDED
  │
Redis (ot-container-kit, port 6379, via redis-exporter)
  │
  ├──→ Alloy prometheus.scrape "redis-legacy"   ← NEEDS TO BE ADDED
  │
CouchDB (port 5984, /_node/_local/_stats)
  │
  ├──→ couchdb-exporter (port 9984/metrics)     ← NEEDS TO BE DEPLOYED
  │      │
  │      └──→ Alloy prometheus.scrape "couchdb"  ← NEEDS TO BE ADDED
  │           │
  │           └──→ Mimir (prometheus.remote_write)
  │
  └──→ Loki (pod logs for all three, already scraped by Alloy)
```

> [!WARNING]
> **Blocker:** None of the three data stores are currently being scraped by Alloy:
> 1. **Valkey** — Uses the Redis wire protocol, so `redis_exporter` works out of the box. Deploy as sidecar or standalone, then add scrape block.
> 2. **Redis (legacy)** — Same exporter, separate target with a `legacy` label so panels can distinguish the two.
> 3. **CouchDB** — Needs `couchdb-prometheus-exporter` deployed (lightweight Go binary), then add scrape block.

> [!NOTE]
> **Valkey vs Redis distinction:** Both use the same `redis_*` metric names from the exporter. The dashboards differentiate them via the `instance` or `job` label (e.g., `job="valkey"` vs `job="redis-legacy"`). The Redis section is intentionally minimal — it exists only to confirm the legacy instance is still running and to track when it can be safely removed.

---

## Dashboard Layout

Organized into **4 tabs**. Unlike the SRE dashboards which follow the "glance → drill-down" pattern uniformly, B2 groups by data store since the three technologies have fundamentally different metrics and failure modes.

---

### Tab 1: Health at a Glance

> **Design:** Stat strip covering all three data stores — one horizontal row, so a DBA sees the health of the entire caching/document layer in 5 seconds.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Valkey Up** | Stat | `redis_up{job="valkey"}` | 1 🟢, 0 🔴 | Is the primary cache alive? If Valkey is down, every service that depends on it (session storage, rate limiting, job queues) is degraded. |
| **Valkey Hit Rate** | Stat (%) | `redis_keyspace_hits_total{job="valkey"} / (redis_keyspace_hits_total{job="valkey"} + redis_keyspace_misses_total{job="valkey"}) * 100` | >90% 🟢, 70-90% 🟡, <70% 🔴 | Cache effectiveness — below 70% means most lookups miss the cache and hit the backing database, negating the point of having a cache layer. |
| **Valkey Memory Usage** | Gauge | `redis_memory_used_bytes{job="valkey"} / redis_memory_max_bytes{job="valkey"} * 100` | <70% 🟢, 70-90% 🟡, >90% 🔴 | Memory pressure — once Valkey hits `maxmemory`, evictions start and cache hit rate drops. At 100%, writes may fail depending on the eviction policy. |
| **Redis (Legacy) Up** | Stat (with ⚠️ sunset label) | `redis_up{job="redis-legacy"}` | 1 🟢, 0 🟡 (yellow, not red — expected to be removed) | Basic liveness check. Yellow thresholds because this instance is scheduled for removal — we want to know it's up, but don't page if it's down. |
| **CouchDB Up** | Stat | `couchdb_up` or `up{job="couchdb"}` | 1 🟢, 0 🔴 | Is the Obsidian sync backend alive? CouchDB being down means Obsidian clients can't sync — not immediately catastrophic but noticeable to end users. |

---

### Tab 2: Valkey Deep Dive

> **Design:** Full operational visibility into the primary cache layer. This is the tab you live in when investigating cache-related performance issues.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Connected Clients** | Time series | `redis_connected_clients{job="valkey"}` | Baseline client count. A sudden spike could indicate a connection leak; a sudden drop could indicate a client-side failure. |
| **Memory Usage & Fragmentation** | Time series (dual axis) | `redis_memory_used_bytes{job="valkey"}` and `redis_mem_fragmentation_ratio{job="valkey"}` | Memory used tracks total consumption; fragmentation ratio >1.5 means significant wasted memory (OS allocated much more than Valkey is using), which can indicate a memory allocator issue or excessive key churn. |
| **Hit Rate Trend** | Time series | `rate(redis_keyspace_hits_total{job="valkey"}[5m]) / (rate(redis_keyspace_hits_total{job="valkey"}[5m]) + rate(redis_keyspace_misses_total{job="valkey"}[5m]))` | Cache hit rate over time — drops correlate with cold starts (after a restart), key expiry waves, or a working-set change that invalidates the cache. |
| **Evictions & Expired Keys** | Time series | `rate(redis_evicted_keys_total{job="valkey"}[5m])`, `rate(redis_expired_keys_total{job="valkey"}[5m])` | Evictions mean Valkey is out of room and is throwing away data to make space — this is the direct cause of hit rate drops. Expired keys are normal TTL behavior and shouldn't cause concern unless the rate suddenly changes. |
| **Commands per Second (by type)** | Time series (stacked) | `rate(redis_commands_total{job="valkey"}[5m])` grouped by `cmd` | Which operations dominate? `GET` vs `SET` ratio shows read/write split. Unexpected commands (e.g., high `KEYS` or `SCAN` rate) can indicate an application doing expensive operations that block the single-threaded event loop. |
| **Command Latency (p50/p99)** | Time series | `redis_commands_duration_seconds_total{job="valkey"}` / `redis_commands_processed_total{job="valkey"}` (or histogram quantiles if available) | Latency per command type — Valkey is single-threaded, so one slow command blocks everything. This surfaces the specific command causing latency spikes. |
| **Keyspace Size** | Stat + time series | `redis_db_keys{job="valkey"}` | Total key count per database. Growth over time tracks whether the cache is accumulating stale entries (missing TTLs) or staying within expected bounds. |

---

### Tab 3: CouchDB

> **Design:** Document store health for Obsidian sync. CouchDB is a single-node deployment (not clustered) in this setup, so the panels focus on request health and storage rather than cluster coordination.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **HTTP Request Rate** | Time series | `rate(couchdb_httpd_requests_total[5m])` | Baseline request volume — Obsidian sync generates periodic bursts when a client opens or saves. A sustained high rate could indicate a sync loop. |
| **Request Rate by Method** | Time series (stacked) | `rate(couchdb_httpd_request_methods_total[5m])` grouped by `method` (GET, PUT, POST, DELETE) | Read vs write split. Obsidian sync should be mostly PUTs (writes) during active editing and GETs during initial sync. A high DELETE rate is unusual and worth investigating. |
| **Request Latency** | Time series | `rate(couchdb_httpd_request_time_seconds_total[5m]) / rate(couchdb_httpd_requests_total[5m])` | Average request time — CouchDB should respond in single-digit milliseconds for document operations. Latency climbing above 100ms indicates disk I/O pressure or an oversized database. |
| **Document Count** | Stat + time series | `couchdb_database_doc_count` | Total documents across all databases. For Obsidian, each note is typically one document — growth should track your note-taking activity. |
| **Database Disk Size** | Stat + time series | `couchdb_database_data_size_bytes`, `couchdb_database_disk_size_bytes` | Disk size vs data size — a large gap indicates compaction hasn't run or has fallen behind (CouchDB append-only B-tree design means the on-disk size grows without compaction). |
| **HTTP Status Codes** | Time series (stacked) | `rate(couchdb_httpd_status_codes_total[5m])` grouped by `code` | 2xx is healthy; 4xx may indicate auth issues or missing databases; 5xx is a server problem. A spike in 409 (Conflict) is expected during concurrent Obsidian edits but should resolve quickly. |
| **CouchDB Error Log Stream** | Logs panel | Loki: `{namespace=~"databases\|couchdb", container=~"couchdb.*"} \|= "error"` | Root-cause stream for replication failures, disk errors, and auth issues that metrics alone don't explain. |

---

### Tab 4: Active Alerts

> **Design:** Same pattern as all other dashboards — a single table of currently firing cache/document store alerts.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `alertgroup="cache"` or `alertgroup="couchdb"` | Single pane for active data store issues, color-coded by severity. |

#### Alert Rules (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|------------------|-----|----------|-------------|
| `ValkeyDown` | `redis_up{job="valkey"} == 0` | 2m | **Critical** | Primary cache is down — all dependent services are degraded. |
| `ValkeyMemoryHigh` | `redis_memory_used_bytes{job="valkey"} / redis_memory_max_bytes{job="valkey"} > 0.90` | 5m | **Warning** | Memory usage above 90% — evictions will start soon, degrading cache effectiveness. |
| `ValkeyMemoryExhausted` | `redis_memory_used_bytes{job="valkey"} / redis_memory_max_bytes{job="valkey"} > 0.98` | 2m | **Critical** | Memory nearly exhausted — writes may fail depending on eviction policy. |
| `ValkeyHitRateLow` | `redis_keyspace_hits_total{job="valkey"} / (redis_keyspace_hits_total{job="valkey"} + redis_keyspace_misses_total{job="valkey"}) < 0.70` | 15m | **Warning** | Cache hit rate below 70% — the cache is not effective, most requests hit the backing database. |
| `ValkeyHighEvictions` | `rate(redis_evicted_keys_total{job="valkey"}[5m]) > 100` | 10m | **Warning** | High eviction rate — memory pressure is causing data loss from cache. Consider increasing `maxmemory` or reviewing TTL policies. |
| `CouchDBDown` | `up{job="couchdb"} == 0` | 2m | **Critical** | CouchDB is down — Obsidian sync is unavailable. |
| `CouchDBHighErrorRate` | `rate(couchdb_httpd_status_codes_total{code=~"5.."}[5m]) > 0` | 5m | **Warning** | CouchDB returning server errors — investigate disk space, permissions, or database corruption. |
| `CouchDBDiskGrowing` | `deriv(couchdb_database_disk_size_bytes[1d]) > 50 * 1024 * 1024` | 1h | **Warning** | CouchDB disk usage growing >50MB/day — compaction may not be running, or write volume is unusually high. |

---

## Related Dashboards & Links

| Target | Type | Description |
|--------|------|-------------|
| [B1 — PostgreSQL](../../dba/B1-postgresql.md) | Internal (dashboard) | Both databases share the same Longhorn storage layer. |
| [S4 — Storage](../../sre/S4-storage.md) | Internal (dashboard) | SeaweedFS buckets for Valkey and CouchDB tracked here. |

**← Back to [Dashboard Catalog](../README.md#-dba-2-dashboards)** | **Previous: [B1 — PostgreSQL](B1-postgresql.md)**
