## Storage (Dashboard S4)

**Folder:** SRE / Operations
**Refresh:** 30s
**Audience:** You wearing the ops hat — capacity planning, volume troubleshooting, object store health.

> **Purpose:** Comprehensive visibility into the two storage layers everything else depends on — Longhorn (block storage for PVCs) and SeaweedFS (S3-compatible object storage backing Mimir, Loki, and Velero). If either is degraded, backups, metrics ingestion, and stateful application data are all at risk — this dashboard exists to catch that before S1/S2/S5 start showing symptoms without an obvious cause.

---

### Data Flow for Storage Metrics

```
Longhorn Manager (port 9500, /metrics)
  │
  ├──→ Alloy prometheus.scrape "longhorn"      ← NEEDS TO BE ADDED
  │      │
  │      └──→ Mimir (prometheus.remote_write)
  │
SeaweedFS (master :9333/metrics, volume :8080/metrics, filer :8888/metrics)
  │
  ├──→ Alloy prometheus.scrape "seaweedfs"     ← EXISTS, but dashboard is empty {}
  │      │
  │      └──→ Mimir (prometheus.remote_write)
  │
  └──→ Loki (Longhorn manager + instance-manager pod logs, already scraped by Alloy)
```

> [!WARNING]
> **Blocker 1:** Alloy's `custom-config` does not currently scrape Longhorn Manager's `/metrics` endpoint. Longhorn exposes volume, replica, and node-level metrics natively in Prometheus format (no exporter needed) — this is purely a missing scrape block, same pattern as the Velero blocker in Phase 1.
>
> **Blocker 2:** SeaweedFS *is* being scraped already, but `dashboard-seaweedfs.yaml` currently renders an empty `{}` dashboard — the ConfigMap exists as a placeholder from earlier setup but was never built out. This phase replaces that empty dashboard with the real S4 content (folded into Tab 4 below) rather than leaving two separate storage dashboards.

---

### Dashboard Layout: S4 — Storage

Organized into **6 tabs**, same "glance first, drill down after" pattern as S1/S2.

---

#### Tab 1: Health at a Glance

> **Design:** Stat strip. An operator should know if either storage layer is degraded within 5 seconds — before opening Longhorn UI or the SeaweedFS filer console.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Volumes Healthy** | Stat (fraction) | `sum(longhorn_volume_robustness{robustness="healthy"}) / count(longhorn_volume_robustness)` | 100% 🟢, <100% 🟡, degraded/faulted present 🔴 | The single most important number for block storage. A non-healthy volume means reduced or zero redundancy on that PVC right now. |
| **Volumes Degraded/Faulted** | Stat (red if >0) | `count(longhorn_volume_robustness{robustness=~"degraded\|faulted"})` | 0 🟢, ≥1 🔴 | Direct count — this is what you'd page on. Degraded means one replica down (still serving); faulted means no healthy replica (data at risk). |
| **SeaweedFS Cluster Status** | Stat (up/down) | `up{job="seaweedfs", component="master"}` combined with `min(seaweedfs_master_is_leader)` | All up + leader elected 🟢, else 🔴 | SeaweedFS backs Mimir/Loki/Velero storage — if the master cluster loses quorum, metrics ingestion and backups both silently start failing. |
| **Disk Space Free (Longhorn nodes)** | Gauge | `min(longhorn_node_storage_available_bytes / longhorn_node_storage_capacity_bytes)` across nodes | >20% 🟢, 10-20% 🟡, <10% 🔴 | Longhorn stops scheduling new replicas when a node's disk is full — this is your early warning before that happens. |
| **Replica Rebuild In Progress** | Stat (boolean) | `count(longhorn_volume_state{state="rebuilding"})` | 0 ⚪, ≥1 🔵 | Informational, not necessarily bad — but useful to know when read/write performance on a volume is temporarily reduced due to an active rebuild. |

---

#### Tab 2: Longhorn Volume Deep Dive

> **Design:** Per-volume detail — which PVC, which app, and its current state.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Volume Status Table** | Table | `longhorn_volume_robustness` joined with `longhorn_volume_capacity_bytes`, `longhorn_volume_actual_size_bytes` — columns: Volume, PVC/Namespace, Robustness, Capacity, Actual Size, Replica Count | The "which PVC is the problem" view. Maps directly back to the app that owns it (Immich, Obsidian, Authentik DB, etc.) — critical for triage, since Longhorn UI shows volume names but not always the owning app cleanly. |
| **Volume IOPS** | Time series (per volume) | `rate(longhorn_volume_read_iops_total[5m])`, `rate(longhorn_volume_write_iops_total[5m])` | Spot which workload is driving I/O load — useful when overall cluster storage feels slow and you need to find the noisy neighbor. |
| **Volume Throughput** | Time series (per volume) | `rate(longhorn_volume_read_throughput_bytes[5m])`, `rate(longhorn_volume_write_throughput_bytes[5m])` | Same as above but bandwidth rather than operation count — some workloads (e.g., Immich thumbnail generation) are throughput-bound rather than IOPS-bound. |
| **Volume Latency** | Time series (per volume) | `longhorn_volume_read_latency_seconds`, `longhorn_volume_write_latency_seconds` (or histogram quantile if exposed as buckets) | Latency degradation is often the *first* symptom of an underlying disk or network problem, visible here before robustness flips to degraded. |

---

#### Tab 3: Longhorn Node & Replica Health

> **Design:** One layer below individual volumes — is the underlying Longhorn infrastructure (nodes, replicas, engines) sound?

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Replica Count per Volume** | Bar gauge | `count(longhorn_volume_replica_count) by (volume)` | Confirms every volume is actually running its configured replica count (typically 2 or 3) — a volume silently running with fewer replicas than intended is a common Longhorn footgun. |
| **Node Storage Capacity** | Bar gauge (per node) | `longhorn_node_storage_capacity_bytes`, `longhorn_node_storage_available_bytes` | Per-node breakdown behind the Tab 1 "Disk Space Free" gauge — tells you *which* node is running low, since Longhorn schedules replicas per-node. |
| **Scheduled vs Actual Replicas** | Table | `longhorn_node_storage_scheduled_bytes` vs `longhorn_node_storage_available_bytes` | Longhorn's own over-scheduling can create a situation where the manager thinks there's room for a replica that the node can't actually serve — this panel exposes that gap before a rebuild fails. |
| **Instance Manager Health** | Multi-stat (per node) | `up{job="longhorn", component="instance-manager"}` | Instance managers are the per-node processes that actually run replica engines — if one crashes, every replica on that node goes offline simultaneously. |
| **Longhorn Manager Log Stream** | Logs panel | Loki: `{namespace="longhorn-system", container="longhorn-manager"} \|= "level=error"` | Root-cause stream for volume attach/detach failures, replica scheduling failures, and engine crashes. |

---

#### Tab 4: SeaweedFS Object Store

> **Design:** This tab replaces the currently-empty `dashboard-seaweedfs.yaml`. SeaweedFS backs three critical buckets: `mimir-tsdb`, `loki-chunks`, `mimir-alertmanager` — plus the Velero backup bucket referenced in S1 Tab 3.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Master/Volume/Filer Status** | Multi-stat | `up{job="seaweedfs", component=~"master\|volume\|filer"}` | SeaweedFS has three distinct process types — any one being down has a different blast radius (master = cluster coordination, volume = actual data, filer = S3 API layer). This panel tells you which layer failed. |
| **Volume Server Disk Usage** | Gauge (per volume server) | `seaweedfs_volume_server_disk_used_bytes / seaweedfs_volume_server_disk_capacity_bytes` | SeaweedFS volume servers can fill up independently of Longhorn — this is the object-store equivalent of the Longhorn node disk gauge in Tab 3. |
| **Bucket Sizes** | Bar gauge (per bucket) | `seaweedfs_filer_bucket_size_bytes{bucket=~"mimir-tsdb\|loki-chunks\|mimir-alertmanager\|velero.*"}` | Direct visibility into what's consuming object storage — ties into the "Backup Storage Used (S3)" panel already on S1 and the growth trend panel on Tab 5 here. |
| **S3 Request Rate & Errors** | Time series | `rate(seaweedfs_filer_request_total[5m])` split by status code (2xx/4xx/5xx) | A spike in 5xx here explains failed backups (S1), failed metrics writes (Mimir), or failed log writes (Loki) — this is the shared dependency underneath all three, so errors here should be checked first when any of those look wrong. |
| **Replication Status** | Stat | `seaweedfs_master_volume_replica_count` vs configured replication factor | Confirms SeaweedFS is actually maintaining its configured redundancy, same concept as Longhorn replica count above. |

---

#### Tab 5: Capacity & Growth

> **Design:** Trend lines rather than point-in-time status — feeds directly into the platform-wide Capacity & Trends dashboard (E2, Phase 6).

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Longhorn Total Used Storage (30/90d)** | Time series | `sum(longhorn_volume_actual_size_bytes)` over time | Block storage growth trend — answers "at current growth, when do we need bigger/more disks." |
| **SeaweedFS Total Bucket Growth (30/90d)** | Time series | `sum(seaweedfs_filer_bucket_size_bytes)` over time | Object storage growth trend, same purpose as above but for the S3 layer. |
| **Per-Bucket Growth Rate** | Time series (stacked, per bucket) | `deriv(seaweedfs_filer_bucket_size_bytes[1d])` | Identifies *which* bucket is driving growth — e.g., is Loki chunk growth outpacing Mimir TSDB growth, which changes retention-tuning priorities. |
| **Projected Days to Full** | Stat | `(node_filesystem_avail_bytes) / (deriv(node_filesystem_avail_bytes[7d]) * -1)` per relevant mount | Linear projection turning a raw growth trend into an actionable number — "37 days until the SeaweedFS volume mount is full" is far more useful than a raw graph. |

---

#### Tab 6: Active Alerts

> **Design:** Same pattern as S1/S2 — a single table of currently firing storage alerts, backed by Mimir Ruler → Alertmanager.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `alertgroup="storage"` (covers both Longhorn and SeaweedFS) | Single pane for active storage issues, color-coded by severity. |

##### Alert Rules to Configure (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|-------------------|-----|----------|-------------|
| `LonghornVolumeDegraded` | `longhorn_volume_robustness{robustness="degraded"} == 1` | 5m | **Warning** | A volume is running with reduced redundancy — one replica down. Investigate before a second failure causes data loss risk. |
| `LonghornVolumeFaulted` | `longhorn_volume_robustness{robustness="faulted"} == 1` | 0m | **Critical** | A volume has no healthy replica. Immediate data-loss risk on that PVC. |
| `LonghornNodeDiskLow` | `longhorn_node_storage_available_bytes / longhorn_node_storage_capacity_bytes < 0.10` | 10m | **Critical** | A Longhorn node is under 10% free disk — new replica scheduling will start failing soon. |
| `LonghornInstanceManagerDown` | `up{job="longhorn", component="instance-manager"} == 0` | 2m | **Critical** | An instance manager is down — every replica on that node is offline. |
| `SeaweedFSMasterNotLeader` | `sum(seaweedfs_master_is_leader) == 0` | 2m | **Critical** | No SeaweedFS master has leader status — cluster coordination is broken, writes will fail. |
| `SeaweedFSVolumeDiskLow` | `seaweedfs_volume_server_disk_used_bytes / seaweedfs_volume_server_disk_capacity_bytes > 0.90` | 10m | **Warning** | A volume server is over 90% full — approaching object-store write failures. |
| `SeaweedFSHighErrorRate` | `rate(seaweedfs_filer_request_total{status=~"5.."}[5m]) > 0` | 5m | **Critical** | S3 API layer returning server errors — this is the shared dependency behind Mimir, Loki, and Velero, so treat as high priority regardless of which downstream symptom appears first. |

---

### Phase 3 Task Checklist (Storage)

1. Add `longhorn` scrape block to Alloy `custom-config`, pointed at Longhorn Manager's `/metrics` (port 9500).
2. Confirm existing SeaweedFS scrape block covers all three components (master, volume, filer) — add any missing target.
3. Build **S4 — Storage** dashboard JSON (6 tabs as above), replacing the current empty `dashboard-seaweedfs.yaml` content and delivering as `dashboard-storage.yaml` ConfigMap, folder annotation `grafana_folder: "SRE / Operations"`.
4. Retire or repoint `dashboard-seaweedfs.yaml` so SeaweedFS content lives only in S4 Tab 4 — avoid having two competing storage dashboards.
5. Add the 7 storage alert rules to Mimir Ruler, routed through the existing stub Alertmanager receivers from Phase 1.
6. Verify Firing Alerts Table on S4 Tab 6 correctly surfaces the new alert rules (test with a synthetic Longhorn replica removal or a filer restart).
7. Update `kustomization.yaml` in `kubernetes/apps/infrastructure/grafana/components/dashboards/` to include the new ConfigMap and remove the empty placeholder reference if it was tracked separately.