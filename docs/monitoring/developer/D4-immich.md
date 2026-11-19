# D4 — Immich

| | |
|---|---|
| **Folder** | Developer |
| **Dashboard ID** | D4 |
| **Refresh** | 30s |
| **Audience** | You wearing the developer hat — Immich pipeline health, queues, jobs, and logs |

> **Purpose:** Immich is the only workload with a native Prometheus endpoint. D4 turns that data into a single view of the photo pipeline: how many users, which queues are backed up, whether jobs are failing, how slow the asset and machine-learning repositories are, and what the app is logging. D1 remains the generic per-app view; D4 is the deep dive.

**← Back to [Dashboard Catalog](../README.md#-developer-4-dashboards)**

---

## Data Flow

```
immich-server :8081/metrics   (API worker)
immich-server :8082/metrics   (microservices worker)
  │
  └──→ Alloy (prometheus.scrape "immich", job="immich")
         └──→ Mimir

immich-server / immich-machine-learning stdout
  │
  └──→ Alloy (loki.source.kubernetes)
         └──→ Loki
```

> [!IMPORTANT]
> Immich does **not** export HTTP or PostgreSQL instrumentation metrics. `http.server.request.duration` and `db.client.*` are not present. RED metrics for Immich continue to come from Traefik (D1/S3). Immich's own database work is visible only as `immich_*_repository_*_duration` histograms.

> [!NOTE]
> Queue and job metrics are created lazily — a series only exists after that queue/job has run since the last restart. Panels therefore select by name regex (`{__name__=~"immich_queues_.+_active"}`) instead of hard-coding metric names.

---

## Scrape Configuration

Alloy scrapes the `immich-server` Service on the two metrics ports only:

```alloy
discovery.relabel "immich" {
  targets = discovery.kubernetes.services.targets
  rule { source_labels = ["__meta_kubernetes_namespace"];          regex = "personal"; action = "keep" }
  rule { source_labels = ["__meta_kubernetes_service_name"];       regex = "immich-server"; action = "keep" }
  rule { source_labels = ["__meta_kubernetes_service_port_name"];  regex = "metrics-api|metrics-ms"; action = "keep" }
}
```

Port `2283` is the web application and must be excluded. The chart-generated `ServiceMonitor` is not consumed by Alloy (there is no Prometheus Operator); it can be removed once the static job is trusted.

`IMMICH_HOST=0.0.0.0` is required — see `kubernetes/apps/services/immich/components/metrics/`. With the default `::`, the exporter builds the invalid base URL `http://:::8081/` and answers every scrape with 400.

---

## Dashboard Layout

Organized into **4 tabs**.

### Tab 1: Overview

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Users** | Stat | `immich_users_total` | — | Instant confirmation that the instance is populated. |
| **Active Jobs** | Stat | `sum({__name__=~"immich_queues_.+_active"}) or vector(0)` | <50 🟢, 50-100 🟡, >100 🔴 | Total in-flight work across all queues. |
| **Job Failures (15m)** | Stat | `sum(increase({__name__=~"immich_jobs_.+_failed"}[15m])) or vector(0)` | 0 🟢, ≥1 🔴 | Any failed job deserves a look; these are usually unreadable files or ML errors. |
| **Metrics Target** | Stat | `max(up{job="immich"})` | 0 🔴, 1 🟢 | Catches the exact failure that hid for 33 days: an endpoint that returns 400 and is never scraped. |

### Tab 2: Queues & Jobs

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Queue Backlog** | Time series | `sum by (queue) (label_replace({__name__=~"immich_queues_.+_active"}, "queue", "$1", "__name__", "immich_queues_(.+)_active"))` | A flat high line means a worker is stuck or under-provisioned. |
| **Jobs Started** | Time series | `sum by (queue) (label_replace(rate({__name__=~"immich_queues_.+_started"}[5m]), "queue", "$1", "__name__", "immich_queues_(.+)_started"))` | Throughput per queue, and a leading indicator that the backlog is draining. |
| **Job Results** | Time series | `sum by (job, result) (label_replace(label_replace(rate({__name__=~"immich_jobs_.+_(success\|failed\|skipped)"}[5m]), "job", "$1", "__name__", "immich_jobs_(.+)_(success\|failed\|skipped)"), "result", "$2", "__name__", "immich_jobs_(.+)_(success\|failed\|skipped)"))` | Separates "slow" from "broken": a success rate that stops climbing while failures do is a real incident. |

### Tab 3: Performance

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Asset Repository Latency (p95)** | Time series | `histogram_quantile(0.95, sum by (le) (rate({__name__=~"immich_asset_repository_.+_duration_bucket"}[5m])))` | Catches DB slow-downs before users complain about slow browsing. |
| **Machine Learning Latency (p95)** | Time series | `histogram_quantile(0.95, sum by (le) (rate({__name__=~"immich_machine_learning_repository_.+_duration_bucket"}[5m])))` | ML is a separate pod; rising latency here usually means model reloads or CPU contention. |
| **Process Memory** | Time series | `process_memory_usage{job="immich"}` | A steady climb that never drops is a leak. |
| **Process CPU (cores)** | Time series | `rate(process_cpu_time_total{job="immich"}[5m])` | Correlate with job throughput; high CPU with no jobs means something is stuck. |

### Tab 4: Logs

| Panel | Type | Query (Loki) | Rationale |
|-------|------|--------------|-----------|
| **Server Error Logs** | Logs | `{namespace="personal",pod=~"immich-server.*"} \|= "(?i)(error\|fatal\|unable to run job)"` | Root-cause entry point when a panel above turns red. |
| **Machine Learning Error Logs** | Logs | `{namespace="personal",pod=~"immich-machine-learning.*"} \|= "(?i)(error\|exception\|traceback)"` | ML failures don't show up in the server pod. |

> Logs currently arrive with ANSI colour codes, so Loki labels `detected_level` as `unknown`. Until Alloy strips ANSI (or Immich switches to `IMMICH_LOG_FORMAT=json`), use text filters rather than a `level` label.

---

## Alert Rules (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|------------------|-----|----------|-------------|
| `ImmichMetricsDown` | `up{job="immich"} == 0` | 5m | **Critical** | Immich metrics are no longer being scraped — dashboards and pipeline alerts are blind. |
| `ImmichJobFailures` | `sum(rate({__name__=~"immich_jobs_.+_failed"}[15m])) > 0` | 10m | **Warning** | Immich jobs are failing. |
| `ImmichQueueBacklog` | `max({__name__=~"immich_queues_.+_active"}) > 100` | 15m | **Warning** | A queue is backing up; check ML/server resources. |
| `ImmichDatabaseBackupMissed` | `increase(immich_queues_backup_database_started[26h]) == 0` | 1h | **Warning** | The daily Immich DB dump did not run. |
| `ImmichUserCountDrop` | `delta(immich_users_total[1h]) < 0` | 5m | **Warning** | User count decreased — possible data or auth issue. |

---

## Known Gaps

- **Media storage is not in Longhorn.** Immich media lives on NAS NFS, so `longhorn_volume_*` won't show it. Add NAS filesystem metrics (node_exporter on `atlas`) or query `GET /api/server/storage` with an API key.
- **No per-app HTTP metrics.** Use Traefik (D1/S3) for request rate, error rate, and latency.
- **No traces.** Immich v3.4.2 does not configure a span exporter.

---

## Related Dashboards & Links

| Target | Type | Description |
|--------|------|-------------|
| [D1 — Application Health](D1-application-health.md) | Internal (dashboard) | Generic pod/Traefik/Longhorn view for Immich. |
| [D2 — Log Explorer](D2-log-explorer.md) | Internal (dashboard) | Cross-namespace log search. |
| [S4 — Storage](../sre/S4-storage.md) | Internal (dashboard) | Longhorn volumes; NAS media needs the gap above closed. |
| [B1 — PostgreSQL](../dba/B1-postgresql.md) | Internal (dashboard) | Immich DB health once pg_exporter is deployed. |

**← Back to [Dashboard Catalog](../README.md#-developer-4-dashboards)**
