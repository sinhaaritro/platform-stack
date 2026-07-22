## E1 — Platform Overview

**Folder:** Executive
**Refresh:** 1 min
**Audience:** You (platform owner) and any stakeholder who wants a 10-second health check — no query builders, no knobs, pure status.

### Design Philosophy

E1 is **not tabbed**. An executive dashboard that requires clicking through tabs has failed its purpose. Everything lives on one screen, arranged top-to-bottom by importance: overall status first, trends and detail last. E1 is a **rollup dashboard** — it queries the same Mimir data as S1/S2 but re-aggregates it into fewer, bigger, simpler panels. It adds no new metrics of its own.

### Dependency Note

Per the build order, E1 depends on S1 (live) and S2 (this phase) for its core panels. Two panels reference data that won't exist until later phases:

- **Certificate expiry countdown** → depends on cert-manager metrics, added in Phase 3 (S3).
- **Ingress request sparkline** → depends on Traefik metrics, added in Phase 3 (S3).

Recommend shipping E1 in this phase with those two panels present but visibly marked as **"Pending Phase 3"** (e.g., a text panel or a "no data" placeholder with a note), rather than omitting them — so the dashboard's layout is final now and only backfills data later, avoiding a second layout change.

### Dashboard Layout: E1 — Platform Overview

| Panel | Type | Query (PromQL) | Thresholds | Rationale | Data Source Phase |
|-------|------|----------------|------------|-----------|---------|
| **Service Status Map** | Status grid / node graph | `up` across all scraped jobs (`velero`, `node-exporter`, `kube-state-metrics`, `mimir`, `loki`, `alloy`) | green = up, red = down | One glance shows exactly which component of the platform is down, not just "something's wrong." | Phase 1 + 2 |
| **Node Count** | Stat | `count(kube_node_info)` | informational | Ground truth for fleet size — noticeable at a glance if a node silently left the cluster. | Phase 2 (S2) |
| **Total Pods** | Stat | `count(kube_pod_info)` | informational | Coarse but useful growth/health indicator across the whole platform. | Phase 2 (S2) |
| **Cluster CPU Gauge** | Gauge | Same query as S2 Tab 1 Cluster CPU Utilization | <70% 🟢, 70-85% 🟡, >85% 🔴 | Reused directly from S2 — E1 doesn't recompute, it re-displays. | Phase 2 (S2) |
| **Cluster Memory Gauge** | Gauge | Same query as S2 Tab 1 Cluster Memory Utilization | <70% 🟢, 70-85% 🟡, >85% 🔴 | Same reuse principle. | Phase 2 (S2) |
| **Cluster Disk Gauge** | Gauge | `1 - (sum(node_filesystem_avail_bytes{fstype!~"tmpfs\|overlay"}) / sum(node_filesystem_size_bytes{fstype!~"tmpfs\|overlay"}))` | <70% 🟢, 70-85% 🟡, >85% 🔴 | Aggregate disk pressure across the fleet, one number. | Phase 2 (S2) |
| **Active Alerts Count** | Stat (red if >0) | Alertmanager `ALERTS{alertstate="firing"}` count | 0 🟢, 1-3 🟡, >3 🔴 | Rolls up firing alerts from every dashboard (S1, S2, and future S3-S6) into a single number. | Phase 1 + 2 |
| **Certificate Expiry Countdown** | Stat (days) | `min(x509_cert_not_after) - time()` (cert-manager metric) | **Placeholder — "Pending Phase 3"** | Reserved slot; wired up once cert-manager scrape lands in S3. | Phase 3 (not yet) |
| **Backup SLA %** | Stat | Same query as S1 Tab 1 Backup SLA % | ≥99% 🟢, 95-99% 🟡, <95% 🔴 | Reused directly from S1 — this is why S1 shipped first, it's a direct input here. | Phase 1 (S1) ✅ |
| **Ingress Request Sparkline** | Sparkline | `sum(rate(traefik_service_requests_total[5m]))` | **Placeholder — "Pending Phase 3"** | Reserved slot; wired up once Traefik scrape lands in S3. | Phase 3 (not yet) |

---

## Phase 2 Task Checklist

1. Add `kube-state-metrics` scrape block to Alloy `custom-config` (deploy kube-state-metrics if not already present in-cluster).
2. Add `cadvisor` scrape block to Alloy `custom-config`, pointed at each kubelet's `/metrics/cadvisor`.
3. Build **S2 — Cluster & Node Health** dashboard JSON (5 tabs as above), deliver as `dashboard-cluster-health.yaml` ConfigMap, folder annotation `grafana_folder: "SRE / Operations"`.
4. Build **E1 — Platform Overview** dashboard JSON (single-screen, no tabs), deliver as `dashboard-platform-overview.yaml` ConfigMap, folder annotation `grafana_folder: "Executive"`, with two panels marked "Pending Phase 3".
5. Add the 7 cluster/node alert rules to Mimir Ruler (table above), routed through the existing stub Alertmanager receivers from Phase 1.
6. Verify Firing Alerts Table on S2 Tab 6 and Active Alerts Count on E1 both correctly surface the new alert rules once triggered (test with a synthetic node cordon or pod crash).
7. Update `kustomization.yaml` in `kubernetes/apps/infrastructure/grafana/components/dashboards/` to include the two new ConfigMaps.