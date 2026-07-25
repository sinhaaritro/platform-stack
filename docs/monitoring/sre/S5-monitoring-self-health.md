# S5 — Monitoring Self-Health

| | |
|---|---|
| **Folder** | SRE / Operations |
| **Dashboard ID** | S5 |
| **Refresh** | 30s |
| **Audience** | You wearing the ops hat — "who watches the watchmen?" |

> **Purpose:** Meta-monitoring of the monitoring stack itself: **Mimir** (metrics storage), **Loki** (log storage), **Alloy** (scraping/shipping agent), and **Alertmanager** (notification routing). If any of these are degraded, every other dashboard on the platform becomes untrustworthy — data gaps, missing alerts, and stale panels are the symptoms. S5 exists to catch monitoring infrastructure problems before they cause blind spots in the dashboards that depend on it.

**← Back to [Dashboard Catalog](../README.md#-sre--operations-6-dashboards)**

---

## Data Flow

```
Mimir (port 8080, /metrics)
  │
  ├──→ Already scraped (meta-monitoring)  ← ALREADY CONFIGURED ✅
  │
Loki (port 3100, /metrics)
  │
  ├──→ Already scraped (meta-monitoring)  ← ALREADY CONFIGURED ✅
  │
Alloy (port 12345, /metrics — self-scrape)
  │
  ├──→ Already scraped (built-in)        ← ALREADY CONFIGURED ✅
  │
Alertmanager (within Mimir, /metrics)
  │
  ├──→ Already scraped (meta-monitoring)  ← ALREADY CONFIGURED ✅
```

> [!NOTE]
> **No new scrape blocks needed.** Mimir meta-monitoring and Alloy self-scraping are already configured. S5 is a query-building exercise — assembling the right PromQL queries to surface monitoring health from metrics that are already flowing.

---

## Dashboard Layout

Organized into **5 tabs**, one per monitoring component plus an alerts tab.

---

### Tab 1: Health at a Glance

> **Design:** Stat strip. An operator should know if the monitoring stack itself is healthy within 5 seconds.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Mimir Up** | Stat | `up{job="mimir"}` | 1 🟢, 0 🔴 | Is the metrics backend alive? If Mimir is down, no metrics are being stored — every Prometheus-based panel on every dashboard goes stale. |
| **Loki Up** | Stat | `up{job="loki"}` | 1 🟢, 0 🔴 | Is the log backend alive? If Loki is down, all log panels (error streams, log explorer) stop updating — but the logs themselves are buffered by Alloy for a limited time. |
| **Alloy Targets Healthy** | Stat (fraction) | `sum(alloy_prometheus_scrape_targets_healthy) / sum(alloy_prometheus_scrape_targets_total)` | 100% 🟢, <100% 🟡 | What percentage of scrape targets are reachable? A non-100% value means at least one exporter/service is down or unreachable — the "are we even collecting data" check. |
| **Alloy Scrape Failures (5m)** | Stat (red if >0) | `sum(increase(alloy_prometheus_scrape_failures_total[5m]))` | 0 🟢, ≥1 🔴 | Active scrape failures — more specific than "targets healthy" because it catches intermittent failures (target up but returning errors). |
| **Alertmanager Notifications Failing** | Stat (red if >0) | `sum(increase(alertmanager_notifications_failed_total[1h]))` | 0 🟢, ≥1 🔴 | Are alert notifications reaching their receivers? Even with stub receivers, a failure here indicates a routing or configuration problem that would matter once real receivers are plugged in. |

---

### Tab 2: Mimir (Metrics Storage)

> **Design:** Deep dive into the metrics backend — ingestion rate, active series, query performance, and storage.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Ingestion Rate (samples/sec)** | Time series | `sum(rate(cortex_ingester_ingested_samples_total[5m]))` | How many metric samples are being written per second? A sudden drop means a scrape target stopped sending; a sudden spike may indicate a cardinality explosion (new labels creating many new series). |
| **Active Series** | Time series | `sum(cortex_ingester_active_series)` | Total number of unique time series in Mimir. This is the primary cost/capacity metric — each active series consumes memory and storage. If this grows unexpectedly, investigate with the "Top Series by Label" panel. |
| **Query Latency (p50/p95/p99)** | Time series | `histogram_quantile(0.95, sum(rate(cortex_request_duration_seconds_bucket{route=~".*query.*"}[5m])) by (le))` | How fast is Mimir responding to dashboard queries? Slow queries make dashboards feel sluggish. p99 above 5s usually means a panel is querying too many series or too long a time range. |
| **Query Errors** | Time series | `rate(cortex_request_duration_seconds_count{route=~".*query.*", status_code!~"2.."}[5m])` | Failed queries — means dashboards are showing "no data" or errors. Often caused by hitting Mimir's per-tenant limits (max series, max samples). |
| **TSDB Storage Used** | Time series | SeaweedFS bucket size for `mimir-tsdb` (reused from [S4 Tab 4](../sre/STORAGE.md#tab-4-seaweedfs-object-store)) | How much object storage are metrics consuming? Combined with the active series trend, helps predict storage costs. |

---

### Tab 3: Loki (Log Storage)

> **Design:** Deep dive into the log backend — ingestion rate, error rate, and storage.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Ingestion Rate (bytes/sec)** | Time series | `sum(rate(loki_distributor_bytes_received_total[5m]))` | How much log data is flowing into Loki per second? A sudden drop means Alloy stopped shipping logs; a spike means a log-heavy workload appeared (or a log loop started). |
| **Ingestion Errors** | Time series | `sum(rate(loki_distributor_ingester_append_failures_total[5m]))` | Failed log ingestion — logs are being dropped. Usually indicates Loki chunk storage (SeaweedFS) is full or unreachable. |
| **Log Lines per Namespace** | Time series (stacked) | `sum(rate(loki_ingester_chunks_flushed_total[5m])) by (tenant)` or equivalent per-stream metric | Which namespace is producing the most log volume? Helps with retention tuning and cost attribution — often one noisy namespace dominates. |
| **Query Latency** | Time series | `histogram_quantile(0.95, sum(rate(loki_request_duration_seconds_bucket{route=~".*query.*"}[5m])) by (le))` | How fast is Loki responding to log queries? Slow log queries make [D2 — Log Explorer](../developer/LOG_EXPLORER.md) unusable for real-time investigation. |
| **Chunks Storage Used** | Time series | SeaweedFS bucket size for `loki-chunks` (reused from [S4 Tab 4](../sre/STORAGE.md#tab-4-seaweedfs-object-store)) | How much object storage are logs consuming? Loki chunk growth is often the fastest-growing bucket — this determines your retention policy. |

---

### Tab 4: Alloy (Collection Agent)

> **Design:** Is Alloy successfully scraping metrics and shipping logs?

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Scrape Target Status** | Table | `alloy_prometheus_scrape_targets_healthy` with columns: Job, Target, Healthy (yes/no), Last Scrape Duration | Full list of what Alloy is scraping and whether each target is reachable — the "scrape inventory" view. A target showing unhealthy here explains why a specific dashboard panel shows "no data." |
| **Scrape Duration per Target** | Time series | `alloy_prometheus_scrape_duration_seconds` by `job` | Which targets take longest to scrape? Slow scrapes can cause timeouts and dropped data. Velero and kube-state-metrics are common slow scrapers. |
| **Dropped Samples** | Time series | `sum(rate(alloy_prometheus_remote_write_dropped_samples_total[5m]))` | Samples being dropped before reaching Mimir — usually means Mimir rejected them (rate limit, label validation) or Alloy's WAL is full. |
| **Remote Write Queue** | Time series | `alloy_prometheus_remote_write_pending_samples` | How many samples are buffered waiting to be sent to Mimir? A growing queue means Alloy is collecting faster than Mimir can ingest — risk of data loss if the buffer overflows. |
| **Alloy Pod Resource Usage** | Time series | `container_cpu_usage_seconds_total{container="alloy"}`, `container_memory_working_set_bytes{container="alloy"}` | CPU and memory consumption of the Alloy DaemonSet. Alloy can become resource-hungry with many scrape targets — if it hits its resource limits, scraping fails silently. |

---

### Tab 5: Active Alerts

> **Design:** Same pattern as all other dashboards.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `alertgroup="monitoring"` | Single pane for active monitoring infrastructure issues, color-coded by severity. |

#### Alert Rules (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|------------------|-----|----------|-------------|
| `MimirDown` | `up{job="mimir"} == 0` | 2m | **Critical** | Metrics storage is down — all metric-based dashboards will stop updating. |
| `LokiDown` | `up{job="loki"} == 0` | 2m | **Critical** | Log storage is down — all log panels will stop updating. |
| `MimirIngestionDrop` | `sum(rate(cortex_ingester_ingested_samples_total[10m])) < sum(rate(cortex_ingester_ingested_samples_total[10m] offset 1h)) * 0.5` | 10m | **Warning** | Mimir ingestion rate dropped by more than 50% compared to 1 hour ago — a scrape target may have stopped sending. |
| `MimirHighQueryLatency` | `histogram_quantile(0.95, sum(rate(cortex_request_duration_seconds_bucket{route=~".*query.*"}[5m])) by (le)) > 5` | 10m | **Warning** | Mimir query latency p95 over 5 seconds — dashboards will feel sluggish. |
| `LokiIngestionErrors` | `sum(rate(loki_distributor_ingester_append_failures_total[5m])) > 0` | 5m | **Critical** | Loki is dropping logs — investigate chunk storage (SeaweedFS) health. |
| `AlloyTargetsUnhealthy` | `sum(alloy_prometheus_scrape_targets_healthy) / sum(alloy_prometheus_scrape_targets_total) < 1` | 5m | **Warning** | One or more scrape targets are unreachable — data gaps will appear on affected dashboards. |
| `AlertmanagerNotificationFailing` | `increase(alertmanager_notifications_failed_total[1h]) > 0` | 15m | **Warning** | Alert notifications are failing — alerts will fire but not be delivered to receivers. |

---

**← Back to [Dashboard Catalog](../README.md#-sre--operations-6-dashboards)** | **Previous: [S4 — Storage](STORAGE.md)**
