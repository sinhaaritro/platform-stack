# P3 — Home — Admin

| | |
|---|---|
| **Folder** | Portal |
| **Dashboard ID** | P3 |
| **Refresh** | 1 min |
| **Audience** | You (platform admin) — personal command center |

> **Purpose:** Everything in [P2 — Home — Trusted](P2-home-trusted.md) plus a platform operations summary and quick-links to every tool you use. P3 is *your* landing page — the first thing you see when opening Grafana. It combines household context (weather, smart home) with a compressed infrastructure overview and navigation links to all dashboards and admin UIs. Think of it as a personalized "mission control" rather than a monitoring dashboard.

**← Back to [Dashboard Catalog](../README.md#-portal-3-dashboards)**

---

## Implementation Decision

> [!IMPORTANT]
> **Recommendation: Option A (Grafana-native) for P3.** Unlike P1/P2 where a Homepage/Homarr app might provide a better UX for non-technical users, P3 is specifically for the admin who already lives in Grafana. A native dashboard avoids context-switching and has direct access to all Grafana datasources for live status panels.

---

## Design Philosophy

P3 is a **high-density dashboard** — the opposite of P1/P2's minimalism. An admin wants maximum information per pixel:

- **Information density** — more panels, smaller text, denser layout. Every empty pixel is wasted.
- **One-click navigation** — links to every dashboard, every admin UI, every tool. No hunting through sidebars.
- **Live status, not deep metrics** — P3 shows *summaries*, not detail. For drill-down, click through to the specialist dashboard.
- **Latest alerts visible** — the most recent fired alerts should be visible without clicking anything.

---

## Dashboard Layout

Single-screen. Four sections stacked vertically, ordered by urgency:

1. **Platform Health Strip** (top — "is anything broken right now?")
2. **Recent Alerts Feed** (if something fired, what was it?)
3. **Dashboard & Tool Links** (navigation hub)
4. **Household Status** (inherited from P2, pushed to bottom since it's not ops-critical)

---

### Section 1: Platform Health Strip

> **Design:** A compressed horizontal strip of key metrics — one stat per domain. Each stat links to its specialist dashboard for drill-down.

| Panel | Type | Query (PromQL) | Thresholds | Links To |
|-------|------|----------------|------------|----------|
| **Nodes** | Stat | `count(kube_node_info)` | Expected count 🟢, <expected 🔴 | [S2 — Cluster & Node Health](../sre/CLUSTER_AND_NODE_HEALTH.md) |
| **Pods** | Stat | `count(kube_pod_info)` | informational | [S2](../sre/CLUSTER_AND_NODE_HEALTH.md) |
| **CPU** | Gauge | `sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) / sum(rate(node_cpu_seconds_total[5m])) * 100` | <70% 🟢, 70-85% 🟡, >85% 🔴 | [S2](../sre/CLUSTER_AND_NODE_HEALTH.md#tab-1-fleet-health-at-a-glance) |
| **Memory** | Gauge | `1 - (sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))` | <70% 🟢, 70-85% 🟡, >85% 🔴 | [S2](../sre/CLUSTER_AND_NODE_HEALTH.md#tab-1-fleet-health-at-a-glance) |
| **Disk** | Gauge | `1 - (sum(node_filesystem_avail_bytes{fstype!~"tmpfs\|overlay"}) / sum(node_filesystem_size_bytes{fstype!~"tmpfs\|overlay"}))` | <70% 🟢, 70-85% 🟡, >85% 🔴 | [S4 — Storage](../sre/STORAGE.md) |
| **Backup SLA** | Stat (%) | Same as [E1](../executive/PLATFORM_OVERVIEW.md) Backup SLA % | ≥99% 🟢, 95-99% 🟡, <95% 🔴 | [S1 — Backup & DR](../sre/BACKUP_AND_DISASTER_RECOVERY.md) |
| **Active Alerts** | Stat (red if >0) | `count(ALERTS{alertstate="firing"})` | 0 🟢, 1-3 🟡, >3 🔴 | [E1 — Platform Overview](../executive/PLATFORM_OVERVIEW.md) |
| **Ingress Errors** | Stat (%) | `sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) / sum(rate(traefik_service_requests_total[5m])) * 100` | <1% 🟢, 1-5% 🟡, >5% 🔴 | [S3 — Networking](../sre/NETWORKING.md) |

---

### Section 2: Recent Alerts Feed

> **Design:** A compact table of the 10 most recent alerts (firing + recently resolved). This is the "what happened while I was away" panel.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Recent Alerts** | Table | Alertmanager API — columns: Alert Name, Severity, Status (firing/resolved), Namespace, Started At, Duration | The first thing you check after opening Grafana. Shows both currently firing alerts and recently resolved ones (last 24h), so you can see what fired overnight even if it auto-resolved. |
| **Alert Trend (7d)** | Sparkline | `count(ALERTS{alertstate="firing"})` over 7 days | At-a-glance trend — are alerts increasing or decreasing over the past week? A climbing trend means the platform is getting noisier and alert rules may need tuning. |

---

### Section 3: Dashboard & Tool Links

> **Design:** A structured link grid organized by persona. Each link opens the target dashboard or admin UI in a new tab.

#### Dashboard Navigation

| Group | Links |
|-------|-------|
| **Executive** | [E1 — Platform Overview](../executive/E1-platform-overview.md), [E2 — Capacity & Trends](../executive/E2-capacity-and-trends.md) |
| **SRE / Operations** | [S1 — Backup & DR](../sre/S1-backup-and-disaster-recovery.md), [S2 — Cluster Health](../sre/S2-cluster-and-node-health.md), [S3 — Networking](../sre/S3-networking.md), [S4 — Storage](../sre/S4-storage.md), [S5 — Monitoring Health](../sre/S5-monitoring-self-health.md), [S6 — External Infra](../sre/S6-external-infrastructure.md) |
| **Developer** | [D1 — App Health](../developer/D1-application-health.md), [D2 — Log Explorer](../developer/D2-log-explorer.md), [D3 — Security](../developer/D3-security-auth.md) |
| **DBA** | [B1 — PostgreSQL](../dba/B1-postgresql.md), [B2 — Cache & Docs](../dba/B2-cache-and-document-stores.md) |

#### Admin Tool Quick-Links

| Tool | URL | Purpose |
|------|-----|---------|
| **Grafana Explore** | `/explore` | Ad-hoc PromQL/LogQL queries |
| **Traefik Dashboard** | `https://traefik.<domain>/dashboard/` | Ingress route inspection |
| **Longhorn UI** | `https://longhorn.<domain>/` | Volume management |
| **Proxmox UI** | `https://<proxmox>:8006/` | Hypervisor management |
| **ArgoCD** | `https://argocd.<domain>/` | GitOps deployment status |
| **Authentik Admin** | `https://auth.<domain>/if/admin/` | Identity provider management |
| **AdGuard Home** | `http://<adguard-lxc>:3000/` | DNS filter management |

### Implementation Details (Grafana-Native)

| Element | Grafana Feature | Notes |
|---------|----------------|-------|
| **Health strip** | Stat panels with panel links | Each stat panel has a "Panel link" configured to the target dashboard URL. Click → navigate. |
| **Alert feed** | Alertmanager datasource → Table panel | Built-in Alertmanager datasource supports direct querying of alert history. |
| **Link grid** | Text panel (HTML mode) | HTML `<a>` tags in a Text panel create a clickable link grid. Style with inline CSS for a card-like appearance. |
| **Tool links** | Same Text panel or Grafana "Link" panel type | Grafana Link panels are purpose-built for external URL links with icons. |

---

### Section 4: Household Status

Inherited from [P2 — Home — Trusted](P2-home-trusted.md#section-2-household-status). Same weather widget, room status grid, and smart home panels, pushed to the bottom of the page since ops context is more urgent for the admin persona.

---

**← Back to [Dashboard Catalog](../README.md#-portal-3-dashboards)** | **Previous: [P2 — Home — Trusted](P2-home-trusted.md)**
