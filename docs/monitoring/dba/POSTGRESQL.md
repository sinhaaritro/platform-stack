# B1 — PostgreSQL

| | |
|---|---|
| **Folder** | DBA |
| **Dashboard ID** | B1 |
| **Refresh** | 15s |
| **Audience** | You wearing the DBA hat — database performance, query health, replication monitoring |

> **Purpose:** Deep visibility into both PostgreSQL instances — PG14 (Authentik) and PG18 (Immich). Covers connection management, transaction throughput, cache efficiency, storage growth, lock contention, replication health, and slow query investigation. These are the two most critical stateful services on the platform — if either database is degraded, the application it backs is degraded.

**← Back to [Dashboard Catalog](../README.md#-dba-2-dashboards)**

---

## Data Flow

```
PostgreSQL PG14 (Authentik) — port 5432
  │
  └──→ pg_exporter (sidecar or standalone, port 9187/metrics)  ← NEEDS TO BE DEPLOYED
        │
PostgreSQL PG18 (Immich) — port 5432
  │
  └──→ pg_exporter (sidecar or standalone, port 9187/metrics)  ← NEEDS TO BE DEPLOYED
        │
        ├──→ Alloy prometheus.scrape "postgres"                ← NEEDS TO BE ADDED
        │      │
        │      └──→ Mimir (prometheus.remote_write)
        │
        └──→ Loki (PostgreSQL pod logs, already scraped by Alloy)
```

> [!WARNING]
> **Blocker:** Neither PostgreSQL instance currently has a metrics exporter. You need to:
> 1. Deploy `postgres_exporter` (or `pg_exporter`) for both PG14 and PG18 — either as a sidecar container in each PG pod, or as a standalone deployment per instance.
> 2. Add a `postgres` scrape block to Alloy `custom-config` targeting both exporter endpoints.
>
> Without this, every panel on this dashboard will show "no data." The exporter uses the `DATA_SOURCE_NAME` env var to connect to PostgreSQL — you'll need read-only credentials for each instance.

> [!NOTE]
> **Slow query logging:** The "Slow Query Log Stream" panel (Tab 4) depends on PostgreSQL being configured with `log_min_duration_statement` set to a threshold (e.g., `500ms`). If this isn't already set in your PG configs, it's a one-line change in `postgresql.conf` or the Helm values, but it does produce additional log volume — worth setting before this dashboard goes live so the panel isn't empty.

---

## Dashboard Layout

Organized into **5 tabs**. The Grafana variable `$instance` (dropdown: `pg14-authentik`, `pg18-immich`) filters every panel so you can view one database at a time or both side-by-side.

---

### Tab 1: Health at a Glance

> **Design:** Stat strip. A DBA should know if either database is in trouble within 5 seconds — before application-layer symptoms appear.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Database Up** | Multi-stat (per instance) | `pg_up{instance=~"$instance"}` | 1 🟢, 0 🔴 | Is the exporter able to reach the database? Down here means either the database or the exporter has failed — either way, all other panels are meaningless. |
| **Active Connections** | Stat (per instance) | `pg_stat_activity_count{state="active", instance=~"$instance"}` | <80% of `max_connections` 🟢, 80-95% 🟡, >95% 🔴 | Connection exhaustion is one of the most common PostgreSQL failure modes — once `max_connections` is hit, new connections are refused and the app starts throwing errors. |
| **Cache Hit Ratio** | Stat (%) | `pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read) * 100` per instance | >99% 🟢, 95-99% 🟡, <95% 🔴 | A healthy PostgreSQL should serve >99% of reads from shared_buffers/OS cache. Dropping below 95% means either the working set no longer fits in memory or shared_buffers is undersized. |
| **Transactions per Second** | Stat | `rate(pg_stat_database_xact_commit{instance=~"$instance"}[5m]) + rate(pg_stat_database_xact_rollback{instance=~"$instance"}[5m])` | informational | Baseline throughput indicator. A sudden drop often correlates with lock contention or connection exhaustion; a spike may indicate a runaway batch job. |
| **Deadlocks (1h)** | Stat (red if >0) | `sum(increase(pg_stat_database_deadlocks{instance=~"$instance"}[1h]))` | 0 🟢, ≥1 🔴 | Deadlocks indicate a schema or query pattern problem. Even one deadlock is worth investigating — they cause transaction rollbacks and wasted work. |

---

### Tab 2: Connection Management

> **Design:** Drill-down into who is connected and how connections are being used.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Connections by State** | Stacked bar (per instance) | `pg_stat_activity_count` grouped by `state` (active, idle, idle in transaction, waiting) | "idle in transaction" connections are the silent performance killer — they hold locks and prevent autovacuum from running. A high count here demands investigation before it manifests as slow queries. |
| **Connections by Database** | Bar gauge | `pg_stat_activity_count` grouped by `datname` | Which database is consuming the most connections? In a multi-database setup (Authentik + Immich), this immediately shows if one app is hogging the connection pool. |
| **Connection Usage vs Max** | Gauge (per instance) | `sum(pg_stat_activity_count{instance=~"$instance"}) / pg_settings_max_connections{instance=~"$instance"} * 100` | <70% 🟢, 70-90% 🟡, >90% 🔴 | Percentage of `max_connections` in use — the raw connection count from Tab 1 is contextless without knowing the configured limit. |
| **Connection Trend** | Time series | `sum(pg_stat_activity_count{instance=~"$instance"})` over time | Spot gradual connection leaks — a slowly climbing baseline that never returns to its idle level usually means the application is opening connections without closing them properly. |

---

### Tab 3: Performance & Throughput

> **Design:** Transaction health, cache behavior, and write amplification.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **TPS (Commits vs Rollbacks)** | Time series (dual axis) | `rate(pg_stat_database_xact_commit[5m])` vs `rate(pg_stat_database_xact_rollback[5m])` per instance | A rising rollback rate relative to commits usually indicates deadlocks, serialization failures, or application retry storms — the ratio matters more than absolute numbers. |
| **Cache Hit Ratio Trend** | Time series | `pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read)` over time | Catches gradual cache degradation — e.g., after a bulk import that evicts the working set, the ratio drops and may take hours to recover. |
| **Rows Returned vs Fetched** | Time series | `rate(pg_stat_database_tup_returned[5m])` vs `rate(pg_stat_database_tup_fetched[5m])` | A large gap between "returned" (scanned) and "fetched" (actually used) indicates sequential scans or missing indexes — the classic PostgreSQL tuning signal. |
| **Temporary Files & Bytes** | Time series | `rate(pg_stat_database_temp_files[5m])`, `rate(pg_stat_database_temp_bytes[5m])` | Temporary files are created when `work_mem` is too small for a sort or hash operation — they spill to disk, which is orders of magnitude slower. A steady stream here means `work_mem` needs tuning. |
| **Checkpoint & WAL Activity** | Time series | `rate(pg_stat_bgwriter_checkpoints_timed[5m])`, `rate(pg_stat_bgwriter_checkpoints_req[5m])`, `rate(pg_stat_bgwriter_buffers_checkpoint[5m])` | Requested checkpoints (vs timed) indicate write pressure exceeding the configured `checkpoint_completion_target` — a signal to tune WAL settings or reduce write amplification. |

---

### Tab 4: Database Size & Slow Queries

> **Design:** Storage growth tracking and query-level investigation.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Database Size** | Bar gauge (per database) | `pg_database_size_bytes` | Raw size per database — Immich will likely dominate due to media metadata. Tracks growth over time to project storage needs. |
| **Database Size Trend (30d)** | Time series | `pg_database_size_bytes` over time | "Immich database grew 2GB this month" — combined with Longhorn PVC capacity from [S4](../sre/STORAGE.md), tells you when the PV backing this database needs resizing. |
| **Table Size Top 10** | Table, sorted descending | `pg_stat_user_tables_size_bytes` or equivalent, top 10 by size | Which tables are consuming the most space? Often reveals unexpected bloat (dead tuples from missing autovacuum) or a single table growing faster than expected. |
| **Slow Query Log Stream** | Logs panel | Loki: `{namespace=~"databases\|authentik\|immich", container=~"postgres.*"} \|~ "duration: [0-9]+\\.[0-9]+ ms"` | Real-time slow query stream — requires `log_min_duration_statement` to be set in PostgreSQL config. This is where you find the actual SQL causing latency, not just the symptom. |
| **Autovacuum Activity** | Time series | `pg_stat_user_tables_autovacuum_count`, `pg_stat_user_tables_autoanalyze_count` | Autovacuum keeping up? If it's running constantly or not at all, both are problems — constant means heavy write churn, absent means table bloat is accumulating. |

---

### Tab 5: Active Alerts

> **Design:** Same pattern as all other dashboards — a single table of currently firing database alerts, backed by Mimir Ruler → Alertmanager.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `alertgroup="postgresql"` | Single pane for active database issues, color-coded by severity. |

#### Alert Rules (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|------------------|-----|----------|-------------|
| `PostgreSQLDown` | `pg_up == 0` | 2m | **Critical** | PostgreSQL exporter cannot reach the database — either the database or the exporter has failed. |
| `PostgreSQLConnectionsHigh` | `sum(pg_stat_activity_count) / pg_settings_max_connections > 0.85` | 5m | **Warning** | Connection usage above 85% of `max_connections` — risk of connection exhaustion. |
| `PostgreSQLConnectionsExhausted` | `sum(pg_stat_activity_count) / pg_settings_max_connections > 0.95` | 2m | **Critical** | Connection usage above 95% — new connections will be refused imminently. |
| `PostgreSQLCacheHitLow` | `pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read) < 0.95` | 15m | **Warning** | Cache hit ratio below 95% — the working set may no longer fit in memory. Investigate `shared_buffers` sizing. |
| `PostgreSQLDeadlocks` | `increase(pg_stat_database_deadlocks[15m]) > 0` | 0m | **Warning** | A deadlock has occurred — investigate the application's transaction patterns. |
| `PostgreSQLReplicationLag` | `pg_replication_lag_seconds > 30` | 5m | **Warning** | Replication lag exceeds 30 seconds — the replica is falling behind, which impacts failover RPO. |
| `PostgreSQLDiskSpaceLow` | `pg_database_size_bytes / on(instance) group_left() longhorn_volume_capacity_bytes > 0.85` | 10m | **Critical** | Database is using more than 85% of its PVC capacity — risk of out-of-disk crash. |

---

**← Back to [Dashboard Catalog](../README.md#-dba-2-dashboards)** | **Next: [B2 — Cache & Document Stores](CACHE_AND_DOCUMENT_STORES.md)**
