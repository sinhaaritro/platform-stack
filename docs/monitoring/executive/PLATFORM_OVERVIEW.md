# E1 — Platform Overview

| | |
|---|---|
| **Folder** | Executive |
| **Dashboard ID** | E1 |
| **Refresh** | 1 min |
| **Audience** | You (platform owner) and any stakeholder who wants a 10-second health check — no query builders, no knobs, pure status |

> **Purpose:** Single pane of glass for the entire platform. A rollup dashboard that re-aggregates data from S1, S2, and future dashboards into fewer, bigger, simpler panels. It adds no new metrics of its own.

**← Back to [Dashboard Catalog](../README.md#-executive-2-dashboards)**

---

## Design Philosophy

E1 is **not tabbed**. An executive dashboard that requires clicking through tabs has failed its purpose. Everything lives on one screen, arranged top-to-bottom by importance: overall status first, trends and detail last.

E1 is a **rollup dashboard** — it queries the same Mimir data as S1/S2 but re-aggregates it into fewer, bigger, simpler panels.

---

## Dependencies

E1 is a rollup of data from other dashboards. Most panels reuse queries from [S1](../sre/BACKUP_AND_DISASTER_RECOVERY.md) and [S2](../sre/CLUSTER_AND_NODE_HEALTH.md). Two panels depend on data sources that are not yet being scraped:

- **Certificate expiry countdown** → depends on cert-manager metrics ([S3 — Networking](../sre/NETWORKING.md)).
- **Ingress request sparkline** → depends on Traefik metrics ([S3 — Networking](../sre/NETWORKING.md)).

These two panels should ship as **"Pending"** placeholders (e.g., a text panel or a "no data" note) so the layout is final now and only backfills data later, avoiding a second layout change.

---

## Dashboard Layout

Single-screen, no tabs. Panels arranged in rows by importance.

| Panel | Type | Query (PromQL) | Thresholds | Rationale | Status |
|-------|------|----------------|------------|-----------|--------|
| **Service Status Map** | Status grid / node graph | `up` across all scraped jobs (`velero`, `node-exporter`, `kube-state-metrics`, `mimir`, `loki`, `alloy`) | green = up, red = down | One glance shows exactly which component of the platform is down, not just "something's wrong." | ✅ Ready |
| **Node Count** | Stat | `count(kube_node_info)` | informational | Ground truth for fleet size — noticeable at a glance if a node silently left the cluster. | ✅ Ready |
| **Total Pods** | Stat | `count(kube_pod_info)` | informational | Coarse but useful growth/health indicator across the whole platform. | ✅ Ready |
| **Cluster CPU Gauge** | Gauge | Same query as [S2 Tab 1](../sre/CLUSTER_AND_NODE_HEALTH.md#tab-1-fleet-health-at-a-glance) Cluster CPU Utilization | <70% 🟢, 70-85% 🟡, >85% 🔴 | Reused directly from S2 — E1 doesn't recompute, it re-displays. | ✅ Ready |
| **Cluster Memory Gauge** | Gauge | Same query as [S2 Tab 1](../sre/CLUSTER_AND_NODE_HEALTH.md#tab-1-fleet-health-at-a-glance) Cluster Memory Utilization | <70% 🟢, 70-85% 🟡, >85% 🔴 | Same reuse principle. | ✅ Ready |
| **Cluster Disk Gauge** | Gauge | `1 - (sum(node_filesystem_avail_bytes{fstype!~"tmpfs\|overlay"}) / sum(node_filesystem_size_bytes{fstype!~"tmpfs\|overlay"}))` | <70% 🟢, 70-85% 🟡, >85% 🔴 | Aggregate disk pressure across the fleet, one number. | ✅ Ready |
| **Active Alerts Count** | Stat (red if >0) | Alertmanager `ALERTS{alertstate="firing"}` count | 0 🟢, 1-3 🟡, >3 🔴 | Rolls up firing alerts from every dashboard (S1, S2, and future S3-S6) into a single number. | ✅ Ready |
| **Certificate Expiry Countdown** | Stat (days) | `min(x509_cert_not_after) - time()` (cert-manager metric) | **Placeholder — Pending** | Reserved slot; wired up once cert-manager scrape lands (see [S3](../sre/NETWORKING.md)). | ⏳ Pending |
| **Backup SLA %** | Stat | Same query as [S1 Tab 1](../sre/BACKUP_AND_DISASTER_RECOVERY.md#tab-1-health-at-a-glance) Backup SLA % | ≥99% 🟢, 95-99% 🟡, <95% 🔴 | Reused directly from S1 — this is why S1 shipped first, it's a direct input here. | ✅ Ready |
| **Ingress Request Sparkline** | Sparkline | `sum(rate(traefik_service_requests_total[5m]))` | **Placeholder — Pending** | Reserved slot; wired up once Traefik scrape lands (see [S3](../sre/NETWORKING.md)). | ⏳ Pending |

---

**← Back to [Dashboard Catalog](../README.md#-executive-2-dashboards)** | **Previous: [S2 — Cluster & Node Health](../sre/CLUSTER_AND_NODE_HEALTH.md)**