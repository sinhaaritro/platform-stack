# D4 — Immich

| | |
|---|---|
| **Folder** | Developer |
| **Dashboard ID** | D4 |
| **Refresh** | 30s |
| **Default range** | 24h (logs are sparse on an idle instance) |
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

> [!WARNING]
> **Multi-metric regex queries break PromQL.** A selector like `{__name__=~"immich_asset_repository_.+_duration_bucket"}` matches several metrics whose labels are identical apart from `__name__`. Any function that drops `__name__` (`rate`, `increase`) then fails with `vector cannot contain metrics with the same labelset`. D4 therefore names one metric per query. Do not "simplify" these panels back into regex aggregations.

> [!NOTE]
> Queue and job metrics are created lazily — a series only exists after that queue/job has run since the last restart. Panels use `{__name__=~...}` only where no function drops `__name__` (gauges, `sum by (job)` with `label_replace`).

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
| **Job Failures** | Stat | `sum({__name__=~"immich_jobs_.+_failed_total"}) or vector(0)` | 0 🟢, ≥1 🔴 | Cumulative failures since the worker started. |
| **Metrics Target** | Stat | `max(up{job="immich"})` | 0 🔴, 1 🟢 | Catches the exact failure that hid for 33 days: an endpoint that returns 400 and is never scraped. |

### Tab 2: Queues & Jobs

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Queue Backlog** | Time series | `sum by (queue) (label_replace({__name__=~"immich_queues_.+_active"}, "queue", "$1", "__name__", "immich_queues_(.+)_active"))` | A flat high line means a worker is stuck or under-provisioned. |
| **Job Successes** | Table (instant) | `sum by (job) (label_replace({__name__=~"immich_jobs_.+_success_total"}, "job", "$1", "__name__", "immich_jobs_(.+)_success_total"))` | Cumulative completions per job type — shows which pipelines are actually running. |
| **Job Failures** | Table (instant) | `sum by (job) (label_replace({__name__=~"immich_jobs_.+_failed_total"}, "job", "$1", "__name__", "immich_jobs_(.+)_failed_total"))` | Cumulative failures per job type. Empty is good. |

> There is no `immich_queues_*_started_total` series in practice, so the previous "Jobs Started" panel was removed.

### Tab 3: Performance

Every query names one metric and falls back to `0` when the histogram has no recent samples:

```promql
(histogram_quantile(0.95, sum by (le) (rate(<metric>[1h]))) > 0) or vector(0)
```

| Panel | Queries (per metric) | Unit | Rationale |
|-------|----------------------|------|-----------|
| **Asset Repository Latency (p95)** | `immich_asset_repository_get_file_samples_*`, `..._get_time_bucket_*`, `..._get_time_buckets_*` | ms | Catches DB slow-downs before users complain about slow browsing. 0 = method idle. |
| **Machine Learning Latency (p95)** | `immich_machine_learning_repository_{check,setup,tick,set_healthy,teardown}_*` | ms | ML is a separate pod; rising latency here usually means model reloads or CPU contention. |
| **Process Memory** | `process_memory_usage{job="immich"}` | bytes | A steady climb that never drops is a leak. |
| **Process CPU** | `rate(process_cpu_time_total{job="immich"}[5m])` | cores | Correlate with job throughput; high CPU with no jobs means something is stuck. |

### Tab 4: Logs

Each panel has its **own** level dropdown and text filter. The controls are dashboard variables, but they are scoped per panel — changing one does not affect the other.

| Panel | Level control | Search control | Query (Loki) |
|-------|---------------|----------------|--------------|
| **Server Logs** | `$server_log_level` | `$server_log_search` | `{namespace="$namespace",pod=~"immich-server.*"} \| decolorize \|~ "$server_log_level" \|~ "(?i)$server_log_search"` |
| **Machine Learning Logs** | `$ml_log_level` | `$ml_log_search` | `{namespace="$namespace",pod=~"immich-machine-learning.*"} \| decolorize \|~ "$ml_log_level" \|~ "(?i)$ml_log_search"` |

Both default to `All` / empty, so the panels show everything. Each block has its own pair of controls, so filtering the server logs does not touch the ML panel. `| decolorize` strips ANSI at query time, which keeps the level filter readable on older entries.

The namespace comes from the dashboard-level `$namespace` query variable (`label_values(kube_pod_info, namespace)`), so the template is not tied to `personal`. The default selection is `personal`; change it at runtime on a cluster that names the namespace differently.

> Immich only logs on activity (jobs, websocket connects, errors). On an idle instance a 6h window can legitimately be empty, which is why the dashboard defaults to 24h.

---

## Log normalisation (Alloy)

Alloy now runs every pod log line through a `loki.process` pipeline before writing to Loki:

```alloy
loki.process "pod_logs" {
  forward_to = [loki.write.default.receiver]

  // 1. strip ANSI colour escapes
  stage.replace {
    expression = "\\x1b\\[[0-9;]*[A-Za-z]"
    replace    = ""
  }

  // 2. extract a level token (NestJS LOG/ERROR, uvicorn INFO, ...)
  stage.regex {
    expression = "(?i)\\b(?P<level>trace|verbose|debug|info|log|warn|warning|error|fatal)\\b"
  }

  // 3. expose it as the `level` stream label
  stage.labels {
    values = { level = "level" }
  }
}
```

Consequences:

- Alloy strips ANSI and attaches a real `level` label, so Loki can classify most lines instead of returning `unknown`. The D4 log panels still filter with a level regex plus `| decolorize`, which also works for entries stored before this change.
- Stack-trace continuation lines (`at async …`, `Error: …`) still have no level of their own; they are matched by the text filter and remain part of the same stream.
- This is **not** the same as `IMMICH_LOG_FORMAT=json`. The app still emits console text; only Alloy normalises it.
- Old entries written before this change have no `level` label. The panels keep working on them because they filter the decolorized line text, not the label.

---

## Alert Rules (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|------------------|-----|----------|-------------|
| `ImmichMetricsDown` | `up{job="immich"} == 0` | 5m | **Critical** | Immich metrics are no longer being scraped — dashboards and pipeline alerts are blind. |
| `ImmichJobFailures` | `sum(rate({__name__=~"immich_jobs_.+_failed_total"}[15m])) > 0` | 10m | **Warning** | Immich jobs are failing. |
| `ImmichQueueBacklog` | `max({__name__=~"immich_queues_.+_active"}) > 100` | 15m | **Warning** | A queue is backing up; check ML/server resources. |
| `ImmichDatabaseBackupMissed` | `increase(immich_queues_backup_database_active[26h]) == 0` | 1h | **Warning** | The daily Immich DB dump did not run. |
| `ImmichUserCountDrop` | `delta(immich_users_total[1h]) < 0` | 5m | **Warning** | User count decreased — possible data or auth issue. |

> The `ImmichJobFailures` rule needs a single metric per job type because of the duplicate-labelset rule above. Generate one rule per job, or use `sum by (__name__)` with a gauge — not `rate` over a multi-name selector.

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
