# E2 — Capacity & Trends

| | |
|---|---|
| **Folder** | Executive |
| **Dashboard ID** | E2 |
| **Refresh** | 1 min |
| **Audience** | You (platform owner) — growth tracking, budget forecasting, capacity planning |

> **Purpose:** Long-range trend analysis across the entire platform. While [E1 — Platform Overview](PLATFORM_OVERVIEW.md) answers "is everything healthy *right now*?", E2 answers "are we running out of *anything* over the next 30-90 days?" This dashboard aggregates growth data from storage (Longhorn + SeaweedFS), databases (PostgreSQL), backups (Velero/S3), compute (CPU/memory), and workload count (pods) into a single forward-looking view. No operational drill-down — purely strategic.

**← Back to [Dashboard Catalog](../README.md#-executive-2-dashboards)**

---

## Design Philosophy

E2 is **not tabbed** — same as [E1](PLATFORM_OVERVIEW.md). Everything on one scrollable screen, arranged by resource type. All panels default to a `now-30d` or `now-90d` time range to show trends, not point-in-time status. Where possible, panels include a linear projection line showing "days until full" or "projected value in 30 days."

---

## Dependencies

E2 is a **rollup of growth data from every other phase**:

- **Storage growth** → data from [S4 — Storage](../sre/STORAGE.md) (Longhorn volumes, SeaweedFS buckets)
- **Database growth** → data from [B1 — PostgreSQL](../dba/POSTGRESQL.md) (database sizes)
- **Backup storage** → data from [S1 — Backup & DR](../sre/BACKUP_AND_DISASTER_RECOVERY.md) (BSL/S3 usage)
- **Compute usage** → data from [S2 — Cluster & Node Health](../sre/CLUSTER_AND_NODE_HEALTH.md) (CPU/memory)
- **Workload count** → data from S2 (pod count)

All data sources should be flowing by this point in the build order.

---

## Dashboard Layout

Single-screen, no tabs. Panels organized by resource type, each with a current value + trend + projection.

---

### Section 1: Storage Growth

| Panel | Type | Query (PromQL) | Rationale |
|-------|------|----------------|-----------|
| **Longhorn Total Used (30/90d)** | Time series + linear projection | `sum(longhorn_volume_actual_size_bytes)` over time, with `predict_linear(sum(longhorn_volume_actual_size_bytes)[30d:1h], 30*86400)` overlay | Block storage growth — "at current rate, we'll use X GB in 30 days." This is the primary signal for when to add disks to Proxmox nodes. |
| **SeaweedFS Total Bucket Growth (30/90d)** | Time series + linear projection | `sum(seaweedfs_filer_bucket_size_bytes)` over time | Object storage growth for Mimir, Loki, and Velero. Growth rate here directly impacts retention policy decisions. |
| **Per-Bucket Growth Breakdown** | Time series (stacked) | `seaweedfs_filer_bucket_size_bytes` by bucket | Which bucket is driving object storage growth? If `loki-chunks` is growing 3× faster than `mimir-tsdb`, adjusting Loki retention is more impactful than Mimir retention. |
| **Backup Storage (AWS S3)** | Time series + linear projection | CloudWatch `BucketSizeBytes` for Velero bucket | Offsite backup storage growth — directly tied to AWS cost. Combined with Velero retention (30d TTL), this should plateau. If not, retention isn't working. |

---

### Section 2: Database Growth

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Database Size Trend (30d)** | Time series (per database) | `pg_database_size_bytes` over time | Per-database growth for Authentik (PG14) and Immich (PG18). Immich will likely dominate due to media metadata storage. |
| **Database Projected Size (30d)** | Stat (per database) | `predict_linear(pg_database_size_bytes[30d:1h], 30*86400)` | "In 30 days, the Immich database will be X GB." Cross-reference with the PVC capacity from [S4](../sre/STORAGE.md) to know if the volume needs resizing. |
| **Cache Storage (Valkey + CouchDB)** | Time series | `redis_memory_used_bytes{job="valkey"}`, `couchdb_database_disk_size_bytes` | Non-relational data store growth. Valkey memory usage should be stable (cache with TTLs); CouchDB disk size tracks Obsidian note volume. |

---

### Section 3: Compute Usage Trends

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Cluster CPU Usage Trend (30d)** | Time series + projection | `sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) / sum(rate(node_cpu_seconds_total[5m])) * 100` over time | Is the cluster trending toward CPU saturation? A steadily climbing baseline means workloads are growing faster than capacity — time to add a node or right-size resource requests. |
| **Cluster Memory Usage Trend (30d)** | Time series + projection | `1 - (sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))` over time | Same as above for memory. Memory is typically the first constraint in a homelab K8s cluster because workloads often have generous memory requests. |
| **Per-Node Resource Comparison** | Table | Current CPU %, Memory %, Disk % per node (point-in-time) + 30-day average | Side-by-side node comparison — identifies which nodes are approaching capacity and which have headroom for new workloads. |

---

### Section 4: Workload Growth

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Pod Count Trend (30d)** | Time series | `count(kube_pod_info)` over time | Are you deploying more workloads? Pod count is a proxy for platform complexity — each new pod consumes CPU, memory, and network. |
| **Namespace Count** | Stat | `count(count(kube_pod_info) by (namespace))` | How many namespaces exist? Useful as a governance signal — too many namespaces may indicate organizational sprawl. |
| **Pod Count by Namespace (Top 10)** | Bar gauge | `topk(10, count(kube_pod_info) by (namespace))` | Which namespaces have the most pods? Often reveals an unexpected workload that scaled up without planning. |

---

### Section 5: Cost Indicators

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **AWS S3 Estimated Monthly Cost** | Stat | Calculated from bucket size × S3 pricing tier | The only external cloud cost on the platform. Track monthly to prevent bill shock. |
| **Total Storage Consumed** | Stat | Sum of Longhorn used + SeaweedFS total + AWS S3 | Single number for total platform storage — useful for annual capacity planning. |
| **Resource Headroom Summary** | Table | CPU %, Memory %, Disk % across cluster, with "days until 85%" projection | Executive summary: "we have X days of CPU headroom, Y days of memory headroom, Z days of disk headroom." The single most actionable table on the dashboard. |

---

**← Back to [Dashboard Catalog](../README.md#-executive-2-dashboards)** | **Previous: [E1 — Platform Overview](PLATFORM_OVERVIEW.md)**
