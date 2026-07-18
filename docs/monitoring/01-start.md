# Unified Enterprise Monitoring Platform

> **One platform. Multiple viewpoints. Build Backup & DR first.**

This is a single, unified Grafana deployment organized into **persona-based folders**. Each folder contains dashboards tailored to a specific stakeholder. Backup & Disaster Recovery is **Module 1** — the first thing we build and ship.

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
| S1 | **🔥 Backup & Disaster Recovery** | **MODULE 1 — BUILD FIRST.** Full Velero visibility. | *Detailed below.* |
| S2 | **Cluster & Node Health** | Kubernetes node + pod health (USE method) | Per-node CPU/memory/disk/network, pod distribution, pod restarts, system load, OOM kills, kubelet health |
| S3 | **Networking & Ingress** | Traefik, cert-manager, MetalLB, external-dns | Request rate/error rate/latency (RED), TLS cert expiry, certificate ready status, MetalLB pool usage, DNS sync status, Cloudflare tunnel health |
| S4 | **Storage** | Longhorn volumes + SeaweedFS object store | Volume health/capacity/IOPS/throughput, node disk space, replica count, SeaweedFS master/volume/filer status, bucket sizes, S3 request rate |
| S5 | **Monitoring Self-Health** | "Who watches the watchmen?" | Mimir ingestion rate/active series/query latency, Loki ingestion/errors, Alloy scrape target count/failures, Alertmanager notification rate/failures |
| S6 | **External Infrastructure** | Proxmox, AWS, Cloudflare, AdGuard, Netbird | *Detailed below.* |

#### S6 — External Infrastructure (Panel Breakdown)

> **Purpose:** Visibility into everything *outside* Kubernetes that the platform depends on. These are the foundations (Proxmox hypervisor), the network perimeter (Cloudflare, AdGuard, Netbird), and the offsite backup target (AWS S3).

##### Row 1: Proxmox Hypervisor

| Panel | Type | Source | Why |
|-------|------|--------|-----|
| **Node Status** | Multi-stat (per Proxmox node) | `pve_up`, `pve_node_info` via pve-exporter | Are all hypervisor nodes online? If Proxmox is down, your K8s nodes are down. |
| **CPU / Memory / Disk per Node** | Gauge (3 per node) | `pve_cpu_usage_ratio`, `pve_memory_usage_bytes`, `pve_storage_usage_bytes` | Hypervisor-level resource pressure. K8s might look fine but if Proxmox is at 95% memory, you're one spike away from VM eviction. |
| **VM & LXC Status** | Table | `pve_guest_info` — lists all VMs and containers with status | At-a-glance inventory: which VMs/LXCs are running, stopped, or errored. Includes your AdGuard and Netbird LXCs. |
| **VM CPU/Memory** | Time series (per guest) | `pve_cpu_usage_ratio{id=~"qemu/.*"}`, `pve_memory_usage_bytes` | Per-VM resource tracking. Spot a noisy neighbor consuming all CPU. |

##### Row 2: AWS (Backup Target)

| Panel | Type | Source | Why |
|-------|------|--------|-----|
| **S3 Bucket Size** | Time series | CloudWatch `BucketSizeBytes` or S3 API | How much backup storage are you consuming in AWS? Directly tied to your backup cost. |
| **S3 Object Count** | Time series | CloudWatch `NumberOfObjects` | Growth tracking. Combined with Velero backup retention (30d TTL), this should plateau. If it keeps growing, retention isn't working. |
| **S3 Request Rate** | Time series | CloudWatch `AllRequests`, `4xxErrors`, `5xxErrors` | Are your backup uploads reaching AWS successfully? 4xx/5xx = authentication or permission issues. |
| **Estimated Monthly Cost** | Stat | Calculated from bucket size × S3 pricing tier | Budget visibility. Enterprise teams track this to prevent bill shock. |

##### Row 3: Cloudflare

| Panel | Type | Source | Why |
|-------|------|--------|-----|
| **Tunnel Status** | Multi-stat (per tunnel) | Cloudflare API / cloudflare-exporter `cloudflare_tunnel_status` | Are your Cloudflare Tunnels healthy? If a tunnel is down, external access to your services is dead. |
| **DNS Query Rate** | Time series | Cloudflare API analytics | How much DNS traffic is hitting your domains? Spikes could indicate attacks or misconfigured clients. |
| **Threat Events** | Counter + time series | Cloudflare API `firewall_events` | WAF/DDoS events blocked by Cloudflare. Security visibility into your perimeter. |
| **SSL Certificate Status** | Stat | Cloudflare API certificate status | Are Cloudflare-managed edge certificates valid? Separate from your internal cert-manager certs. |

##### Row 4: AdGuard (LXC)

| Panel | Type | Source | Why |
|-------|------|--------|-----|
| **DNS Query Rate** | Time series | AdGuard API / adguard-exporter `adguard_dns_queries_total` | DNS resolution volume across your network. |
| **Blocked Queries %** | Stat + time series | `adguard_dns_blocked_total / adguard_dns_queries_total * 100` | How effective is your ad/tracker blocking? Baseline: 15-30% is normal. |
| **Top Blocked Domains** | Table | AdGuard API top clients/domains | What's getting blocked most? Useful to spot malware phoning home. |
| **Upstream DNS Latency** | Time series | `adguard_dns_upstream_latency_seconds` | Slow DNS = slow everything. If your upstream (Cloudflare 1.1.1.1) is slow, all services feel it. |

##### Row 5: Netbird (LXC)

| Panel | Type | Source | Why |
|-------|------|--------|-----|
| **Connected Peers** | Stat + table | Netbird API `/peers` or metrics endpoint | How many nodes are connected to your mesh VPN? If a node drops off, it loses inter-cluster connectivity. |
| **Peer Status** | Multi-stat (per peer) | Netbird API peer status (connected/disconnected) | Which specific peers are online/offline? Critical for multi-site setups. |
| **Transfer Rate** | Time series (per peer) | Netbird metrics `transfer_bytes` | Network traffic through the VPN mesh. Spot bandwidth-heavy peers. |
| **Last Seen** | Table (sorted by oldest) | Netbird API `last_seen` per peer | Peers not seen in >1h may have connectivity issues. |

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

## Module 1: Backup & Disaster Recovery (Dashboard S1)

> **This is what we build first.** Everything below is the full specification for this single dashboard.

### Data Flow for Velero Metrics

```
Velero Server (port 8085, /metrics)
  │
  ├──→ Alloy prometheus.scrape "velero"     ← NEEDS TO BE ADDED
  │      │
  │      └──→ Mimir (prometheus.remote_write)
  │
  └──→ Loki (pod logs already scraped by Alloy)
```

> [!WARNING]
> **Blocker:** Your Alloy `custom-config` component does NOT currently scrape Velero. The ServiceMonitor exists but Alloy doesn't consume ServiceMonitors — it uses `discovery.relabel` + `prometheus.scrape`. We need to add a Velero scrape block to the Alloy config before any Velero dashboard will show data.

### Dashboard Layout: S1 — Backup & Disaster Recovery

The dashboard is organized into **6 rows** (collapsible). An operator opens the dashboard and sees Row 1 immediately — "are backups healthy?" If the answer is no, they expand rows below to diagnose.

---

#### Row 1: Health at a Glance

> **Design:** 5 stat panels in a horizontal strip. Green/yellow/red thresholds. No scrolling needed.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Backup SLA %** | Stat (big number) | `sum(velero_backup_success_total) / sum(velero_backup_success_total + velero_backup_failure_total + velero_backup_partial_failure_total) * 100` | ≥99% 🟢, 95-99% 🟡, <95% 🔴 | The single most important number. Enterprise SRE teams use this as their DR confidence metric. If it's red, nothing else matters until this is fixed. |
| **Failed Backups (7d)** | Stat (red if >0) | `sum(increase(velero_backup_failure_total[7d]))` | 0 🟢, 1-2 🟡, ≥3 🔴 | Trend indicator. A non-zero value demands investigation. This is the panel that would have caught your silent Velero failures. |
| **Backups in Last 24h** | Stat (count) | `sum(increase(velero_backup_attempt_total[24h]))` | ≥3 🟢 (you have 3 daily schedules), 1-2 🟡, 0 🔴 | Sanity check. You expect 3 daily backups (ssl-certs, obsidian, security). If this shows 0, the scheduler or controller is dead. |
| **Oldest Successful Backup** | Stat (hours ago) | `time() - max(velero_backup_last_successful_timestamp)` | <26h 🟢, 26-48h 🟡, >48h 🔴 | "How stale is my most recent good backup?" If this exceeds your RPO (Recovery Point Objective), you're in danger. |
| **Active Backup Now** | Stat (boolean) | `velero_backup_last_status == 6` or `count(velero_backup_last_status{phase="InProgress"})` | Running 🔵, None ⚪ | Shows if a backup is currently in progress. Useful to avoid manual operations during a run, and to spot stuck backups (running for >1h). |

---

#### Row 2: Per-Schedule Status

> **Design:** Table + timeline. The table shows the current state of each schedule. The timeline shows historical pass/fail.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Schedule Status Table** | Table | `velero_backup_last_status` grouped by `schedule` label. Columns: Schedule Name, Last Status (mapped: 1=New, 2=InProgress, 3=Uploading, 4=Completed, 6=Failed, 7=PartiallyFailed), Last Run Time, Duration, Items Backed Up | The operational control center. At a glance: "daily-obsidian: Completed 6h ago, 142 items, 3m12s" vs "daily-security: Failed 30h ago". Each row is a schedule from your 4 configured schedules. |
| **Backup History Timeline** | Time series (status-mapped bars) | `velero_backup_last_status` per schedule over 7d/30d | Pattern recognition. "daily-obsidian fails every Tuesday" or "monthly-immich hasn't run in 45 days". Enterprise teams use this to spot intermittent failures that aren't caught by point-in-time alerts. |
| **Backup Duration Trend** | Time series (lines, per schedule) | `velero_backup_duration_seconds{schedule=~".+"}` | Performance degradation tracking. If `daily-security` normally takes 2min but now takes 20min, your storage backend is degraded. Also useful for scheduling: avoid overlap between the 21:00 and 21:30 schedules. |
| **Backup Size Trend** | Time series (lines, per schedule) | `velero_backup_items_total{schedule=~".+"}` | Capacity planning. "Immich metadata backups are growing 15% monthly. At this rate, I need to increase S3 budget by Q3." |

---

#### Row 3: Backup Storage Health

> **Design:** Focuses on the BSL (Backup Storage Location) — the S3 targets. If storage is broken, ALL backups fail.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **BSL Availability** | Stat per BSL | `velero_backup_storage_location_last_validation_result{name=~".+"}` | You have an `aws` BSL (via S3 SeaweedFS → AWS). If this reports unavailable, zero backups can succeed. This is your early-warning system for S3/SeaweedFS outages. Enterprise DR teams treat BSL availability as critical as disk space. |
| **BSL Last Validation Age** | Stat (time since) | `time() - velero_backup_storage_location_last_validation_time` | If validation hasn't run in >1 hour, the Velero controller may be hung. Velero validates BSLs on a default 1-minute interval. |
| **Backup Storage Used (S3)** | Time series | SeaweedFS bucket size metrics for the Velero bucket | How much storage are your backups consuming? Ties into budget. Combined with the "Backup Size Trend" panel, you can project when you'll hit a storage limit. |
| **Items Backed Up vs Errors** | Stacked bar (per schedule) | `velero_backup_items_total` vs `velero_backup_items_errors` per schedule | **This is the silent killer.** A backup can "succeed" but have item-level errors — meaning some resources weren't captured. Partial failures create false confidence. This panel makes partial failures visible. |

---

#### Row 4: Restore Readiness

> **Design:** Enterprise DR isn't just "do backups run?" — it's "can we actually recover?" This row answers the second question.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Last Successful Restore** | Stat (age) | `time() - max(velero_restore_last_successful_timestamp)` or `velero_restore_success_total` with timestamp | Enterprise compliance and audit: "When did we last prove our backups work?" If the answer is "never" or "6 months ago", your backups are theoretical. Best practice: test restore monthly. |
| **Restore History** | Table | `velero_restore_success_total`, `velero_restore_failed_total` with timestamps | History log. After you run a restore test (which you have YAML templates for: `ssl-cert-restore`, `obsidian-restore`, etc.), this tracks the results. |
| **Restore Duration** | Time series | `velero_restore_duration_seconds` | Your RTO (Recovery Time Objective). "If Immich dies, it takes 8 minutes to restore." If this increases, investigate storage performance. |
| **Restore Warnings & Errors** | Table | `velero_restore_items_errors`, `velero_restore_items_warnings` | Even successful restores can have warnings (e.g., "CRD already exists"). Errors in a restore are critical — partial restore = partial data loss. |

---

#### Row 5: Velero Operational Health

> **Design:** Monitor the backup engine itself. If Velero is unhealthy, all panels above become meaningless.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Velero Server Status** | Stat (up/down) | `up{job="velero"}` | Is the Velero controller pod running and serving metrics? Down = no backups, no restores, no validation. |
| **Node Agent Status** | Multi-stat (per node) | `kube_pod_status_phase{namespace="backup", pod=~"node-agent.*"}` | Node agents run on each K8s node and handle file-level backups (`defaultVolumesToFsBackup: true`). Your obsidian, security, and immich schedules use this. If a node agent is down on the node where the PVC lives, that PVC's backup silently fails. |
| **Velero Error Log Stream** | Logs panel | Loki: `{namespace="backup", container="velero"} \|= "level=error" or \|= "error"` | Real-time error stream. This is where you'd see the actual root cause of your failed backups — e.g., "AccessDenied", "connection refused", "context deadline exceeded". |
| **Node Agent Log Stream** | Logs panel | Loki: `{namespace="backup", container="node-agent"} \|= "error"` | File-level backup errors. Kopia encryption issues, filesystem permission errors, etc. |
| **Velero Pod Restarts** | Time series | `kube_pod_container_status_restarts_total{namespace="backup"}` | CrashLooping Velero = intermittent backup success. If restart count is climbing, the controller has a stability issue. |

---

#### Row 6: Active Alerts

> **Design:** Shows all currently firing backup-related alerts. Backed by Mimir Ruler → Alertmanager.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `namespace="backup"` or `alertgroup="velero"` | Single pane for all active backup issues. Color-coded by severity (critical/warning/info). |

##### Alert Rules to Configure (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|-----------------|-----|----------|-------------|
| `VeleroBackupFailed` | `increase(velero_backup_failure_total[1h]) > 0` | 0m | **Critical** | A backup has failed. Immediate investigation required. |
| `VeleroBackupPartialFailure` | `increase(velero_backup_partial_failure_total[1h]) > 0` | 0m | **Warning** | A backup completed but with errors. Some resources may not be captured. |
| `VeleroBackupMissing` | `time() - velero_backup_last_successful_timestamp{schedule="daily-obsidian"} > 93600` (26h) | 15m | **Critical** | Expected daily backup hasn't run. Applied per-schedule (daily=26h, monthly=35d). |
| `VeleroBackupSlow` | `velero_backup_duration_seconds > 3 * avg_over_time(velero_backup_duration_seconds[7d])` | 5m | **Warning** | Backup taking 3× longer than 7-day average. Storage backend may be degraded. |
| `VeleroBSLUnavailable` | `velero_backup_storage_location_last_validation_result != 1` | 5m | **Critical** | Backup storage location unreachable. No backups can succeed until resolved. |
| `VeleroNodeAgentDown` | `kube_pod_status_phase{namespace="backup", pod=~"node-agent.*"} != 1` | 5m | **Warning** | Node agent pod not running. File-level backups will fail on that node. |
| `VeleroServerDown` | `up{job="velero"} == 0` | 2m | **Critical** | Velero server is down. All backup/restore operations are halted. |

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
├── dashboard-backup-dr.yaml          # ← Phase 1 (S1)
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
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-backup-dr
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
  annotations:
    grafana_folder: "SRE / Operations"  # ← Grafana folder assignment
data:
  backup-dr.json: |
    { ... dashboard JSON ... }
```

---

## Technical Prerequisites for Phase 1

Before the Backup & DR dashboard can show data, we need:

### 1. Add Velero Scrape to Alloy Config

Add to [custom-config/kustomization.yaml](file:///home/dev/platform-stack/kubernetes/apps/infrastructure/alloy/components/custom-config/kustomization.yaml):

```alloy
// Metrics: Discovery (Velero)
discovery.relabel "velero" {
  targets = discovery.kubernetes.nodes.targets
  rule {
    source_labels = ["__meta_kubernetes_service_name"]
    regex = "velero"
    action = "keep"
  }
  rule {
    source_labels = ["__meta_kubernetes_service_namespace"]
    regex = "backup"
    action = "keep"
  }
}

prometheus.scrape "velero" {
  job_name   = "velero"
  targets    = discovery.relabel.velero.output
  forward_to = [prometheus.remote_write.mimir.receiver]
  scrape_interval = "30s"
  metrics_path    = "/metrics"
}
```

### 2. Add Alert Rules to Mimir Ruler

Create a `PrometheusRule` resource or configure via Mimir ruler API with the 7 alert rules from Row 6.

### 3. Create Dashboard JSON ConfigMap

The `dashboard-backup-dr.yaml` ConfigMap containing the full Grafana dashboard JSON.

---

## Resolved Decisions

| Decision | Resolution |
|----------|------------|
| **Notification channels** | Multiple: Email + Webhook + Push. Alertmanager will be configured with **stub receivers** (no real creds). Data goes to void for now — the routing and rule structure will be in place so we just plug in creds later. |
| **Valkey vs Redis** | Valkey is the primary cache going forward. Redis (ot-container-kit) stays temporarily for hidden dependencies. DBA dashboard will track both, with Redis marked as "legacy / sunset". Redis component will be removed once the full system is functional. |
| **Portal dashboards** | 3 role-based homepages (Public, Trusted, Admin) added as Phase 8. Implementation approach (Grafana-native vs Homepage/Homarr vs hybrid) to be decided when we reach that phase. |
| **Dashboard approach** | Fully custom dashboards built from scratch. No community dashboard IDs. All dashboard JSON generated programmatically and delivered as ConfigMaps. |
| **External infrastructure** | Proxmox, AWS, Cloudflare, AdGuard (LXC), Netbird (LXC) are part of the platform. Dashboard S6 added as Phase 7. Exporters/API integrations to be set up when we reach that phase. |
