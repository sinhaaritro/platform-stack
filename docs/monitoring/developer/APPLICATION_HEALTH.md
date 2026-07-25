# D1 — Application Health

| | |
|---|---|
| **Folder** | Developer |
| **Dashboard ID** | D1 |
| **Refresh** | 30s |
| **Audience** | You wearing the developer hat — application behavior, per-app status, error investigation |

> **Purpose:** Per-application health view for every deployed user-facing service: Immich, Obsidian (LiveSync via CouchDB), Copyparty, and Podinfo (canary). Instead of the infrastructure-centric view of the SRE dashboards, D1 answers "is this *app* working for users?" by combining pod status, Traefik-reported latency/errors, storage usage, and restart history into one place per application.

**← Back to [Dashboard Catalog](../README.md#-developer-3-dashboards)**

---

## Data Flow

```
Traefik (ingress metrics per router/service)
  │
  ├──→ Already scraped (from S3)  ← reuses Traefik data
  │
kube-state-metrics (pod status, restarts)
  │
  ├──→ Already scraped (from S2)  ← reuses KSM data
  │
Longhorn (PVC sizes per volume)
  │
  ├──→ Already scraped (from S4)  ← reuses Longhorn data
  │
  └──→ Loki (application pod logs, already scraped by Alloy)
```

> [!NOTE]
> **No new scrape blocks needed.** D1 is a pure query-building exercise — it reuses metrics already flowing from [S2](../sre/CLUSTER_AND_NODE_HEALTH.md) (kube-state-metrics), [S3](../sre/NETWORKING.md) (Traefik), and [S4](../sre/STORAGE.md) (Longhorn). The only dependency is that those scrape blocks exist, which they do by this phase.

---

## Dashboard Layout

Organized into **4 tabs**. The Grafana variable `$app` (dropdown: `immich`, `obsidian`, `copyparty`, `podinfo`) filters every panel. Each app is identified by its namespace or a label selector — the variable maps to `namespace=~"$app"` for most queries and `service=~".*$app.*"` for Traefik queries.

---

### Tab 1: Health at a Glance

> **Design:** One row per app showing status, error rate, and response time side-by-side. A developer should see "which app is broken" within 5 seconds.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **App Status Grid** | Stat grid (one per app) | `min(kube_pod_status_phase{namespace=~"$app", phase="Running"})` mapped to up/down | Running 🟢, Not Running 🔴 | Are all pods for this app in Running state? A single non-running pod is worth investigating even if the service has replicas. |
| **Error Rate (5xx per app)** | Multi-stat | `sum(rate(traefik_service_requests_total{service=~".*$app.*", code=~"5.."}[5m])) / sum(rate(traefik_service_requests_total{service=~".*$app.*"}[5m])) * 100` | <1% 🟢, 1-5% 🟡, >5% 🔴 | Per-app error rate as seen by users through Traefik — this is the "is it broken for users" metric, not "is the pod running." |
| **Response Time (p95 per app)** | Multi-stat | `histogram_quantile(0.95, sum(rate(traefik_service_request_duration_seconds_bucket{service=~".*$app.*"}[5m])) by (le))` | <500ms 🟢, 500ms-2s 🟡, >2s 🔴 | User-perceived latency per app. Immich (photo serving) will naturally have higher latency than Podinfo (health check). Thresholds should be tuned per app after baselining. |
| **Restarts (24h per app)** | Multi-stat | `sum(increase(kube_pod_container_status_restarts_total{namespace=~"$app"}[24h]))` | 0 🟢, 1-3 🟡, >3 🔴 | A restarting app might still show "Running" at any given moment but is unstable. This catches the instability that point-in-time status misses. |

---

### Tab 2: Per-App Detail

> **Design:** Drill-down into one app at a time (filtered by `$app` variable). Time series for trend analysis.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Pod Status by Container** | Table | `kube_pod_container_status_ready{namespace=~"$app"}` with columns: Pod, Container, Ready, Restarts, Last Terminated Reason | Full breakdown of every container in the app's pods — surfaces init container failures, sidecar crashes, and partial readiness that the high-level status grid hides. |
| **Request Rate** | Time series | `sum(rate(traefik_service_requests_total{service=~".*$app.*"}[5m]))` | Traffic pattern for this specific app. Flat lines during expected-active hours indicate the app is unreachable even if pods show Running. |
| **Error Rate Trend (4xx/5xx)** | Time series (stacked) | `sum(rate(traefik_service_requests_total{service=~".*$app.*", code=~"4.."}[5m]))` and same for `5..` | Same split as [S3 Tab 2](../sre/NETWORKING.md#tab-2-traefik-ingress-traffic-red-method) but filtered to one app — useful to distinguish "users sending bad requests" (4xx) from "app is broken" (5xx). |
| **Latency Trend (p50/p95/p99)** | Time series | `histogram_quantile(0.50/0.95/0.99, ...)` filtered to `$app` | Latency over time per app. Correlate with deployment events — a latency spike right after a deploy indicates a performance regression. |
| **Restart Timeline** | Time series | `increase(kube_pod_container_status_restarts_total{namespace=~"$app"}[5m])` | When did restarts happen? Overlay with Alertmanager annotations to correlate restarts with alert events. |

---

### Tab 3: Storage & Resources

> **Design:** Per-app resource consumption — PVC usage, CPU, and memory.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **PVC Usage per App** | Bar gauge | `longhorn_volume_actual_size_bytes` joined with PVC/namespace labels, filtered to `$app` | How much storage is each app consuming? Immich will dominate. Combined with volume capacity, this shows how close each app is to filling its PV. |
| **PVC Usage vs Capacity** | Gauge | `longhorn_volume_actual_size_bytes / longhorn_volume_capacity_bytes` filtered to `$app` | <70% 🟢, 70-90% 🟡, >90% 🔴 | Percentage view — more actionable than raw bytes. |
| **CPU Usage per App** | Time series | `sum(rate(container_cpu_usage_seconds_total{namespace=~"$app"}[5m])) by (pod)` | Per-pod CPU consumption. Spot one pod consistently using more CPU than its replicas — could indicate uneven load distribution or a hot-partition problem. |
| **Memory Usage per App** | Time series | `sum(container_memory_working_set_bytes{namespace=~"$app"}) by (pod)` | Per-pod memory consumption. A steadily climbing line that never drops is a memory leak — this is how you catch it before OOM kills start. |
| **App Error Log Stream** | Logs panel | Loki: `{namespace=~"$app"} \|= "error" or \|= "ERROR" or \|= "level=error"` | Filtered error stream for the selected app — the starting point for root-cause investigation when the panels above show something is wrong. |

---

### Tab 4: Active Alerts

> **Design:** Same pattern as all other dashboards.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `namespace=~"immich\|obsidian\|copyparty\|podinfo"` | Single pane for active application issues, color-coded by severity. |

#### Alert Rules (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|------------------|-----|----------|-------------|
| `AppDown` | `kube_deployment_status_replicas_available{namespace=~"immich\|obsidian\|copyparty\|podinfo"} == 0` | 2m | **Critical** | An application has zero available replicas — it is completely down for users. |
| `AppHighErrorRate` | `sum(rate(traefik_service_requests_total{service=~".*app.*", code=~"5.."}[5m])) / sum(rate(traefik_service_requests_total{service=~".*app.*"}[5m])) > 0.05` | 5m | **Warning** | More than 5% of requests to this app are server errors. |
| `AppHighLatency` | `histogram_quantile(0.95, sum(rate(traefik_service_request_duration_seconds_bucket{service=~".*app.*"}[5m])) by (le)) > 5` | 10m | **Warning** | p95 latency exceeds 5 seconds — the app is slow enough to frustrate users. |
| `AppPVCNearFull` | `longhorn_volume_actual_size_bytes / longhorn_volume_capacity_bytes > 0.90` | 10m | **Critical** | App's PVC is over 90% full — risk of write failures or data loss. |
| `AppCrashLooping` | `increase(kube_pod_container_status_restarts_total{namespace=~"immich\|obsidian\|copyparty\|podinfo"}[15m]) > 3` | 5m | **Warning** | An app pod is restarting repeatedly — likely a bad deploy or misconfiguration. |

---

**← Back to [Dashboard Catalog](../README.md#-developer-3-dashboards)** | **Next: [D2 — Log Explorer](LOG_EXPLORER.md)**
