# Unified Enterprise Monitoring Platform

> **One platform. Multiple viewpoints.**

This is a single, unified Grafana deployment organized into **persona-based folders**. This is a entrprise grade solution to monioring, catering to all different stakeholders that may be involved in the running and management of the platform. Each folder will contain dashboards tailored to that specific persona.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│               KUBERNETES DATA SOURCES                   │
│                                                         │
│  Alloy (DaemonSet)                                      │
│  ├── Scrapes: node-exporter, velero, traefik,           │
│  │   longhorn, seaweedfs, pg-exporter, valkey,          │
│  │   couchdb, cert-manager, authentik, kyverno          │
│  ├── Writes metrics → Mimir                             │
│  └── Ships logs    → Loki                               │
│                                                         │
├─────────────────────────────────────────────────────────┤
│              EXTERNAL DATA SOURCES (Future)             │
│                                                         │
│  Proxmox   → pve-exporter → Alloy → Mimir               │
│  AWS       → cloudwatch-exporter / S3 API → Mimir       │
│  Cloudflare→ cloudflare-exporter / API → Mimir          │
│  AdGuard   → adguard-exporter (LXC) → Mimir             │
│  Netbird   → netbird API / metrics → Mimir              │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                  STORAGE LAYER                          │
│                                                         │
│  Mimir (metrics)  ←→  SeaweedFS S3 (mimir-tsdb)         │
│  Loki  (logs)     ←→  SeaweedFS S3 (loki-chunks)        │
│  Alertmanager     ←→  SeaweedFS S3 (mimir-alertmanager) │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                 VISUALIZATION LAYER                     │
│                                                         │
│  Grafana                                                │
│  ├── 📁 Portal           (user-facing app links + IoT)  │
│  ├── 📁 Executive        (high-level health)            │
│  ├── 📁 SRE / Operations (infra + backup + external)    │
│  ├── 📁 Developer        (apps + services + logs)       │
│  └── 📁 DBA              (databases + cache)            │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                  ALERTING LAYER                         │
│                                                         │
│  Mimir Ruler (recording + alerting rules)               │
│  → Alertmanager (routing, dedup, silencing)             │
│  → Notification channels (stub config — no creds yet)   │
│     ├── Email (SMTP)                                    │
│     ├── Webhook (Slack/Discord)                         │
│     └── Push (ntfy/Gotify/Pushover)                     │
└─────────────────────────────────────────────────────────┘
```

---

## Grafana Folder & Dashboard Catalog

Each Grafana folder maps to a **persona**. Each dashboard is a ConfigMap with the `grafana_dashboard: "1"` label (matching your existing sidecar pattern). Access control is handled via **Authentik → Grafana RBAC** — different Authentik groups see different folders.

### 📁 Portal (3 dashboards)

> **Audience:** End users, trusted users, admins. Think **Homarr / Homepage** — but inside Grafana so it's part of the same platform.
> **Access control:** Authentik groups determine which portal variant a user sees as their Grafana home dashboard.
> **Refresh:** 5 min. Static links + live status indicators.

| # | Dashboard | Audience | Content |
|---|-----------|----------|--------|
| P1 | **Home — Public** | Generic end users (family, friends) | App links only: Immich, Obsidian, Copyparty. Clean card layout with app icons, descriptions, and direct URLs. Status indicators (🟢/🔴) showing if each app is reachable. No admin links, no metrics. |
| P2 | **Home — Trusted** | Close/known users (household, power users) | Everything in P1 **plus**: Weather widget (via JSON API datasource or iframe), smart home status panel (lights on/off, fan speed — via Home Assistant API or MQTT metrics), room-by-room IoT status, quick actions links. |
| P3 | **Home — Admin** | You (platform admin) | Everything in P2 **plus**: Links to all Grafana dashboards (Executive, SRE, Developer, DBA), cluster health summary strip (node count, CPU, alerts), recent alert feed, backup SLA %, quick-links to Traefik dashboard, Longhorn UI, Grafana Explore. This is your personal command center. |

> [!NOTE]
> **Implementation options for Portal dashboards:**
> - **Option A (Grafana-native):** Use Grafana's Text panels (HTML mode), Stat panels for status, and Link panels. Grafana supports setting a different "home dashboard" per organization or user role. Works today.
> - **Option B (Homepage app + embed):** Deploy [Homepage](https://gethomepage.dev/) or [Homarr](https://homarr.dev/) as a separate K8s service, and embed it in Grafana via iframe or link from Portal P1. Better UX for non-technical users, but adds another service to maintain.
> - **Option C (Hybrid):** P1 and P2 are Homepage/Homarr (better for end users), P3 is a Grafana dashboard (better for admin who already lives in Grafana).
>
> We'll decide this when we reach the Portal phase. For now, the plan accounts for all three.

---

### 📁 Executive (2 dashboards)

> **Audience:** You (platform owner), stakeholders who want a 10-second health check.
> **Refresh:** 1 min. No knobs to turn, no query builders. Pure status.

| # | Dashboard | Purpose | Key Panels |
|---|-----------|---------|------------|
| E1 | **Platform Overview** | Single pane of glass for the entire platform | Service status map (all components), node count, total pods, cluster CPU/memory/disk gauges, active alerts count, certificate expiry countdown, backup SLA %, ingress request sparkline |
| E2 | **Capacity & Trends** | Growth tracking and budget forecasting | Storage growth (Longhorn + SeaweedFS) over 30/90d, database size trends, backup storage consumption, pod count trend, resource utilization trends with linear projection |

---

### 📁 SRE / Operations (6 dashboards)

> **Audience:** You wearing the ops hat. On-call. Troubleshooting. Infrastructure.
> **Refresh:** 30s. Interactive. Drill-down capable.

| # | Dashboard | Purpose | Key Panels |
|---|-----------|---------|------------|
| S1 | [**🔥 Backup & Disaster Recovery**](BACKUP_AND_DISASTER_RECOVERY.md) | Full Velero visibility. | Backup SLA %, failed backups (7d), schedule status & history, BSL/S3 storage health, restore test status, Velero error log stream *(see [BACKUP_AND_DISASTER_RECOVERY.md](BACKUP_AND_DISASTER_RECOVERY.md))* |
| S2 | **Cluster & Node Health** | Kubernetes node + pod health (USE method) | Per-node CPU/memory/disk/network, pod distribution, pod restarts, system load, OOM kills, kubelet health |
| S3 | **Networking & Ingress** | Traefik, cert-manager, MetalLB, external-dns | Request rate/error rate/latency (RED), TLS cert expiry, certificate ready status, MetalLB pool usage, DNS sync status, Cloudflare tunnel health |
| S4 | **Storage** | Longhorn volumes + SeaweedFS object store | Volume health/capacity/IOPS/throughput, node disk space, replica count, SeaweedFS master/volume/filer status, bucket sizes, S3 request rate |
| S5 | **Monitoring Self-Health** | "Who watches the watchmen?" | Mimir ingestion rate/active series/query latency, Loki ingestion/errors, Alloy scrape target count/failures, Alertmanager notification rate/failures |
| S6 | [**External Infrastructure**](EXTERNAL_INFRASTRUCTURE.md) | Proxmox, AWS, Cloudflare, AdGuard, Netbird | Proxmox node/VM metrics, AWS S3 storage & cost, Cloudflare tunnels & threats, AdGuard DNS stats, Netbird peer status *(see [EXTERNAL_INFRASTRUCTURE.md](EXTERNAL_INFRASTRUCTURE.md))* |

---

### 📁 Developer (3 dashboards)

> **Audience:** You wearing the developer hat. Application behavior. Logs. Debugging.
> **Refresh:** 30s. Log search. Error investigation.

| # | Dashboard | Purpose | Key Panels |
|---|-----------|---------|------------|
| D1 | **Application Health** | Per-app status for Immich, Obsidian, Copyparty, Podinfo | Pod status per app, API response time (via Traefik), error rate (5xx + app logs), storage usage per app PVC, restart history |
| D2 | **Log Explorer** | Centralized log search across all namespaces | Loki log panels with namespace/pod/container filters, error rate by namespace, log volume heatmap, pre-built queries for common patterns |
| D3 | **Security & Auth** | Authentik, Kyverno, sealed-secrets, external-secrets | Login rate/failed logins, active sessions, Kyverno policy violations, sealed-secrets controller health, external-secrets sync status |

---

### 📁 DBA (2 dashboards)

> **Audience:** You wearing the DBA hat. Database performance. Query health. Cache efficiency.
> **Refresh:** 15s. Deep metrics.
> **Note:** Valkey is replacing Redis (ot-container-kit). Redis remains temporarily for hidden dependencies but will be removed once the full system is functional. The dashboard tracks Valkey as the primary cache layer.

| # | Dashboard | Purpose | Key Panels |
|---|-----------|---------|------------|
| B1 | **PostgreSQL** | PG14 + PG18 health (Authentik, Immich DBs) | Connections (active/idle), TPS, cache hit ratio, database sizes, deadlocks, replication lag, slow query log panel |
| B2 | **Cache & Document Stores** | Valkey (primary) + Redis (legacy, until removed) + CouchDB | Valkey: connected clients, memory usage, hit rate, evictions, commands/sec, latency. CouchDB: HTTP request rate, doc count, request latency. Redis: basic up/down + connection count (sunset indicator) |

---

## Complete Build Order

We build Module 1 first, then expand. Each module is a self-contained Grafana dashboard JSON delivered as a Kustomize ConfigMap.

| Phase | Module | Dashboard ID | Priority | Dependencies |
|-------|--------|-------------|----------|-------------|
| **Phase 1** | 🔥 **Backup & DR** | S1 | **NOW** | Add Velero scrape to Alloy, add alert rules to Mimir Ruler, stub Alertmanager receivers |
| **Phase 2** | Cluster & Node Health | S2 | High | Node Exporter data already flowing ✅ |
| | Platform Overview | E1 | High | Depends on S1 + S2 data being available |
| **Phase 3** | Storage | S4 | High | Add Longhorn metrics to Alloy, fix empty SeaweedFS dashboard |
| | Networking & Ingress | S3 | High | Add Traefik + cert-manager metrics to Alloy |
| **Phase 4** | PostgreSQL | B1 | Medium | Deploy pg_exporter for PG14 + PG18 |
| | Cache & Document Stores | B2 | Medium | Add Valkey + CouchDB metrics to Alloy |
| **Phase 5** | Application Health | D1 | Medium | Depends on Traefik metrics (Phase 3) + Loki |
| | Security & Auth | D3 | Medium | Add Authentik + Kyverno metrics to Alloy |
| **Phase 6** | Log Explorer | D2 | Low | Loki already flowing ✅, this is a query-building exercise |
| | Monitoring Self-Health | S5 | Low | Mimir meta-monitoring already configured ✅ |
| | Capacity & Trends | E2 | Low | Depends on all other phases for comprehensive data |
| **Phase 7** | External Infrastructure | S6 | Low | Deploy pve-exporter, cloudflare-exporter, adguard-exporter. Configure Netbird + AWS API scraping. |
| **Phase 8** | Home — Admin | P3 | Low | Depends on all dashboards existing to link to |
| | Home — Trusted | P2 | Low | Decide on IoT data source (Home Assistant API / MQTT) |
| | Home — Public | P1 | Low | Decide on implementation approach (Grafana-native vs Homepage app) |

---

## Grafana Folder Structure (Kustomize)

Each dashboard is a ConfigMap in the `monitoring` namespace. The Grafana sidecar picks them up via the `grafana_dashboard: "1"` label. Folder assignment is done via an annotation.

```
kubernetes/apps/infrastructure/grafana/components/dashboards/
├── kustomization.yaml                # Lists all dashboard ConfigMaps
├── dashboard-node-exporter.yaml      # (existing)
├── dashboard-loki.yaml               # (existing)
├── dashboard-seaweedfs.yaml          # (existing — currently empty {})
├── dashboard-backup-dr.yaml          # Phase 1 (S1)
├── dashboard-cluster-health.yaml     # Phase 2 (S2)
├── dashboard-platform-overview.yaml  # Phase 2 (E1)
├── dashboard-storage.yaml            # Phase 3 (S4)
├── dashboard-networking.yaml         # Phase 3 (S3)
├── dashboard-postgresql.yaml         # Phase 4 (B1)
├── dashboard-cache-docstores.yaml    # Phase 4 (B2)
├── dashboard-app-health.yaml         # Phase 5 (D1)
├── dashboard-security-auth.yaml      # Phase 5 (D3)
├── dashboard-log-explorer.yaml       # Phase 6 (D2)
├── dashboard-monitoring-health.yaml  # Phase 6 (S5)
├── dashboard-capacity-trends.yaml    # Phase 6 (E2)
├── dashboard-external-infra.yaml     # Phase 7 (S6)
├── dashboard-portal-admin.yaml       # Phase 8 (P3)
├── dashboard-portal-trusted.yaml     # Phase 8 (P2)
└── dashboard-portal-public.yaml      # Phase 8 (P1)
```

Each ConfigMap uses the folder annotation to organize within Grafana:

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

configMapGenerator:
  - name: grafana-dashboard-backup-dr
    namespace: monitoring
    files:
      - backup-dr.json # ← File containing the JSON
    options:
      disableNameSuffixHash: true
      labels:
        grafana_dashboard: "1"
      annotations:
        grafana_folder: "SRE / Operations" # ← Grafana folder assignment
```

---

## Resolved Decisions

| Decision | Resolution |
|----------|------------|
| **Notification channels** | Multiple: Email + Webhook + Push. Alertmanager will be configured with **stub receivers** (no real creds). Data goes to void for now — the routing and rule structure will be in place so we just plug in creds later. |
| **Valkey vs Redis** | Valkey is the primary cache going forward. Redis (ot-container-kit) stays temporarily for hidden dependencies. DBA dashboard will track both, with Redis marked as "legacy / sunset". Redis component will be removed once the full system is functional. |
| **Portal dashboards** | 3 role-based homepages (Public, Trusted, Admin) added as Phase 8. Implementation approach (Grafana-native vs Homepage/Homarr vs hybrid) to be decided when we reach that phase. |
| **Dashboard approach** | Fully custom dashboards built from scratch. No community dashboard IDs. All dashboard JSON generated programmatically and delivered as ConfigMaps. |
| **External infrastructure** | Proxmox, AWS, Cloudflare, AdGuard (LXC), Netbird (LXC) are part of the platform. Dashboard S6 added as Phase 7. Exporters/API integrations to be set up when we reach that phase. |
