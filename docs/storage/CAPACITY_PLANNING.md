# Capacity Planning — Storage Categories & Growth

> **Purpose:** This document provides guidance for thinking about storage budgets, expansion strategies, and constraints. It uses **storage categories** (SSD-tier, HDD-tier, Object-tier) instead of hardcoded sizes, because the system is designed to expand horizontally as hardware is added.

---

## Storage Categories

All storage in the platform falls into one of three physical categories. Each has distinct performance characteristics and cost profiles.

### Category Definitions

| Category | Physical Media | Tiers Served | Key Characteristic | Cost Profile |
|---|---|---|---|---|
| **SSD-tier** | Solid State Drives (SATA/NVMe) | Tier 1 (Proxmox) + Tier 2 (Longhorn) | High IOPS, low latency | Higher $/GB |
| **HDD-tier** | Hard Disk Drives (SATA) | Tier 4 (NFS/TrueNAS) | High capacity, sequential throughput | Lower $/GB |
| **Object-tier** | Logical — backed by SSD-tier via Longhorn | Tier 3 (SeaweedFS) | S3-compatible, retention-managed | Inherited from SSD-tier |

> **Key insight:** The Object-tier is not a separate physical category. It consumes SSD-tier capacity via Longhorn PVCs. When sizing the SSD-tier, account for both Longhorn direct PVCs and SeaweedFS's underlying storage needs.

### Category Characteristics

| Metric | SSD-tier | HDD-tier |
|---|---|---|
| **Random IOPS** | 10,000-100,000+ | 100-200 |
| **Sequential Throughput** | 500-3,500 MB/s | 150-250 MB/s |
| **Latency** | <1ms | 5-15ms |
| **Endurance** | Limited write cycles (TBW) | Mechanical wear |
| **Failure mode** | Sudden (no warning) | Gradual (S.M.A.R.T. alerts) |
| **Best for** | Databases, app configs, OS, metadata | Media files, documents, bulk storage |

---

## SSD-Tier Budget Allocation

The SSD-tier hosts everything from Proxmox OS to Kubernetes workloads. Budget allocation follows a percentage-based model to remain size-agnostic.

### Allocation Model

| Consumer | Budget % | What It Stores | Notes |
|---|---|---|---|
| **Proxmox OS + ISOs** | ~10-15% | Hypervisor OS, ISO images, Proxmox configs | Relatively fixed — doesn't grow much |
| **VM Operating Systems** | ~15-20% | Kubernetes node OS, system packages | Per-VM base (~8-15GB each) |
| **Longhorn Pool (Apps)** | ~40-50% | Application PVCs (databases, configs) | Grows with app count and data |
| **Longhorn Pool (SeaweedFS)** | ~15-25% | SeaweedFS PVCs (logs, metrics storage) | Grows with log volume and retention |
| **Reserve** | ~5-10% | Headroom for spikes, temporary files | Never allocate 100% — leave breathing room |

### Example Allocation (Illustrative Only)

> **Note:** These numbers are for illustration. The system is designed to work at any scale.

| SSD Capacity | Proxmox/ISOs | VM OS (3 VMs) | Longhorn (Apps) | Longhorn (SeaweedFS) | Reserve |
|---|---|---|---|---|---|
| Small SSD | 12% | 18% | 40% | 20% | 10% |
| Medium SSD | 8% | 12% | 45% | 25% | 10% |
| Large SSD | 5% | 8% | 50% | 30% | 7% |

### Monitoring Thresholds

| Metric | Warning | Critical | Action |
|---|---|---|---|
| Proxmox host disk usage | > 80% | > 90% | Expand disk or clean ISOs |
| Longhorn node storage usage | > 75% | > 85% | Add disk or node |
| Individual PVC usage | > 85% | > 95% | Resize PVC |
| VM disk usage | > 80% | > 90% | Expand VM disk |

---

## HDD-Tier Budget Allocation

The HDD-tier stores user-visible data via NFS/TrueNAS. Budget allocation depends on the workload mix.

### Allocation Model

| Consumer | Budget % | What It Stores | Growth Rate |
|---|---|---|---|
| **Media library** (Jellyfin) | ~40-60% | Movies, TV shows, music | Moderate — depends on collection size |
| **Photo library** (Immich) | ~15-25% | Photos, videos, thumbnails | High — continuous user uploads |
| **Documents** (Obsidian, Nextcloud) | ~5-10% | Markdown, PDFs, office docs | Low — text is small |
| **Downloads** (qBittorrent) | ~10-20% | Active/completed downloads | Variable — depends on usage |
| **ZFS overhead** | ~5-10% | Metadata, checksums, snapshots | Proportional to data size |
| **Reserve** | ~5-10% | Headroom | Critical for ZFS performance |

### ZFS Usable Capacity

ZFS consumes some raw capacity for metadata, checksums, and the redundancy mechanism. Account for this when sizing:

| Pool Layout | Raw Capacity | Usable Capacity | ZFS Overhead |
|---|---|---|---|
| Mirror (2 disks) | 2× disk size | ~47% of raw | ~3% metadata + 50% mirror |
| RAIDZ1 (3 disks) | 3× disk size | ~62% of raw | ~5% metadata + 33% parity |
| RAIDZ1 (4 disks) | 4× disk size | ~72% of raw | ~3% metadata + 25% parity |
| RAIDZ2 (4 disks) | 4× disk size | ~47% of raw | ~3% metadata + 50% parity |

### ZFS Performance Constraint

> **⚠️ Critical:** ZFS performance degrades significantly when pool usage exceeds **80%**. This is because ZFS uses a copy-on-write mechanism that requires free space to write new blocks before updating pointers.
>
> **Rule of thumb:** Plan capacity so that the pool never exceeds 80% usage under normal operations. Set monitoring alerts at 70% (warning) and 80% (critical).

### Monitoring Thresholds

| Metric | Warning | Critical | Action |
|---|---|---|---|
| ZFS pool usage | > 70% | > 80% | Add disk(s) to pool or prune data |
| NFS export space | > 75% | > 85% | Expand underlying pool |
| ZFS scrub errors | Any non-zero | Uncorrectable errors | Replace failing disk immediately |
| S.M.A.R.T. status | Reallocated sectors > 0 | Pending sectors > 0 | Plan disk replacement |

---

## Object-Tier Sizing (Retention Impact)

The Object-tier (SeaweedFS) size is primarily driven by observability data volume and retention policies. Since the Object-tier consumes SSD-tier capacity (via Longhorn PVCs), sizing it correctly is important to avoid SSD-tier exhaustion.

### Sizing Formula

```
Object-tier storage = Σ (daily_ingest × retention_days × compression_ratio)
                      for each tenant
```

### Retention Profiles Impact

| Profile | Log Retention | Daily Log Ingest (estimate) | Log Storage | Metric Retention | Daily Metric Ingest (estimate) | Metric Storage |
|---|---|---|---|---|---|---|
| `personal` | 30 days | ~50 MB/day | ~1.5 GB | 90 days | ~20 MB/day | ~1.8 GB |
| `business-standard` | 365 days | ~200 MB/day | ~73 GB | 365 days | ~50 MB/day | ~18 GB |
| `business-regulated` | 1825 days | ~200 MB/day | ~365 GB | 1825 days | ~50 MB/day | ~91 GB |

> **Note:** These are estimates. Actual ingest rates depend on application verbosity, number of pods, and metric cardinality. Monitor actual usage and adjust.

### Compression

Both Loki and Mimir compress data before writing to S3:
-   **Loki:** gzip/snappy compression on log chunks → typically 5-10× compression ratio.
-   **Mimir:** Block compression → typically 10-20× compression ratio for metrics.

This means the actual disk usage on SeaweedFS is significantly lower than the raw data volume. The estimates above account for compression.

### Right-Sizing SeaweedFS PVCs

| SeaweedFS Component | Sizing Guidance | Growth Pattern |
|---|---|---|
| **Volume Server PVC** | Largest PVC — holds all actual data. Size = total expected Object-tier storage + 30% headroom. | Grows with data ingest × retention |
| **Filer PVC** | Small — holds only the file catalog (LevelDB). Typically <1GB for millions of entries. | Grows slowly with file count |
| **Master PVC** | Very small — holds cluster metadata. Typically <500MB. | Almost static |

---

## Expansion Playbooks

### Expanding the SSD-Tier

**Scenario:** The SSD-tier is running low on capacity.

**Option A: Add a Disk to the Proxmox Host**

1.  Install the new SSD physically.
2.  In Proxmox: Create a new storage pool (Directory or LVM) for the new disk.
3.  Move/create VM disks on the new pool.
4.  In Longhorn: Add the new disk to the node (Longhorn UI → Node → Add Disk).
5.  Longhorn automatically includes the new capacity in its scheduling pool.

**Option B: Replace with a Larger Disk**

1.  If using RAID1/ZFS mirror: Add the new larger disk as a mirror, let it resilver, remove the old disk. Repeat for the second disk.
2.  If single disk (no RAID): Backup VM data, replace disk, restore. Longhorn rebalances on restart.

**Option C: Add a New Proxmox Node**

1.  Install Proxmox on the new server.
2.  Use OpenTofu to provision a new K8s VM on the new host.
3.  Use Ansible to join the VM to the K8s cluster.
4.  Longhorn Manager daemonset deploys automatically to the new node.
5.  New PVCs can be scheduled on the new node. Existing volumes can add replicas.

### Expanding the HDD-Tier

**Scenario:** The ZFS pool on TrueNAS is approaching 80% usage.

**Option A: Add a Vdev to the Pool**

1.  Install new HDD(s).
2.  In TrueNAS: Add a new vdev (e.g., a new mirror pair) to the existing pool.
3.  ZFS automatically stripes new data across all vdevs.
4.  No NFS configuration changes needed — the pool is transparently larger.

> **⚠️ Warning:** You cannot add a single disk to an existing vdev (e.g., you can't turn a 2-disk mirror into a 3-disk RAIDZ). You add a *new vdev* to the pool. Plan initial vdev type carefully.

**Option B: Replace with Larger Disks**

1.  Replace one disk at a time. ZFS resilvers (rebuilds) the data onto the new disk.
2.  Repeat for each disk in the vdev.
3.  Once all disks are replaced, use `zpool online -e` to expand the vdev to use the full new disk size.

### Expanding the Object-Tier

**Scenario:** SeaweedFS is running low on Volume server storage.

1.  **Resize the Longhorn PVC:** Expand the Volume server's PVC (see [LONGHORN.md → Resizing an Existing Volume](./LONGHORN.md#resizing-an-existing-volume)).
2.  **Or add a Volume server:** Scale the SeaweedFS Volume StatefulSet replica count. Each new replica gets its own Longhorn PVC.
3.  **Rebalance:** The SeaweedFS Worker automatically balances data across Volume servers.

---

## Constraints & Gotchas

### Longhorn Overprovisioning

Longhorn allows overprovisioning — you can request more storage in PVCs than physically exists. This is controlled by:

```yaml
defaultSettings:
  storageOverProvisioningPercentage: 200  # Allow 2× actual capacity
```

**Risk:** If all PVCs actually fill to their requested size, Longhorn will run out of disk space. Thin provisioning assumes most volumes won't use their full allocation.

**Mitigation:** Monitor `longhorn_node_storage_usage_bytes` and set alerts at 75% of *physical* capacity (not provisioned capacity).

### SeaweedFS minFreeSpacePercent

SeaweedFS Volume servers stop accepting writes when disk usage exceeds a threshold:

```yaml
volume:
  minFreeSpacePercent: 1  # Stop writing at 99% full
```

**Risk:** Setting this too low (like 1%) can cause write failures under burst conditions. The Volume server may reject writes before Longhorn or Proxmox reports the disk as full.

**Recommendation:** Set to `5` (5% minimum free space) for production. This gives a buffer for vacuum operations and burst writes.

### NFS Quota Limitations

With `nfs-subdir-external-provisioner`, there are **no per-PVC quotas**. A single app can consume the entire NFS share.

**Mitigation for interim (LXC-NFS):**
-   Set filesystem-level quotas on the NFS server (limited, per-user not per-directory).
-   Monitor per-app usage via Prometheus exporters.

**Solution for target (TrueNAS):**
-   `democratic-csi` creates ZFS datasets per PVC with configurable quotas.
-   ZFS enforces quotas at the filesystem level — an app physically cannot exceed its limit.

### ZFS Performance Cliff at >80%

As mentioned in the HDD-tier section, ZFS performance degrades sharply above 80% pool usage. This is not a bug — it's inherent to copy-on-write filesystems.

**Root cause:** ZFS needs contiguous free space to write new blocks. As the pool fills, finding contiguous space becomes an O(n) search, causing exponential latency increases.

**Mitigation:** Never plan for >80% steady-state usage. Set alerts at 70% (warning) and 80% (critical).

---

## Monitoring & Alerts Summary

### Prometheus Queries

```promql
# SSD-tier: Longhorn node storage usage (per node)
longhorn_node_storage_usage_bytes / longhorn_node_storage_capacity_bytes * 100 > 80

# SSD-tier: Longhorn volume health (any degraded/faulted volume)
longhorn_volume_robustness{robustness!="healthy"} > 0

# Object-tier: SeaweedFS volume server free space
# (Requires SeaweedFS metrics exporter)
seaweedfs_volume_server_free_space_bytes < threshold

# HDD-tier: ZFS pool usage (requires node_exporter with ZFS collector)
node_zfs_zpool_allocated_bytes / node_zfs_zpool_size_bytes * 100 > 70
```

### Alert Rules Summary

| Alert | Severity | Threshold | Response |
|---|---|---|---|
| `LonghornNodeStorageHigh` | Warning | > 75% used | Plan expansion (add disk/node) |
| `LonghornNodeStorageCritical` | Critical | > 85% used | Immediate expansion or eviction |
| `LonghornVolumeDegraded` | Critical | Any `degraded` volume | Investigate node health |
| `ZFSPoolUsageHigh` | Warning | > 70% used | Plan disk addition |
| `ZFSPoolUsageCritical` | Critical | > 80% used | Urgent disk addition, prune data |
| `ZFSScrubErrors` | Critical | > 0 uncorrectable | Replace disk immediately |
| `SeaweedFSVolumeNearFull` | Warning | < 5% free | Resize PVC or add Volume server |

---

## Related Documentation

| Document | Relationship |
|---|---|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Storage category → tier mapping |
| [LONGHORN.md](./LONGHORN.md) | SSD-tier expansion playbooks, overprovisioning details |
| [SEAWEEDFS.md](./SEAWEEDFS.md) | Object-tier retention profiles, vacuum process |
| [NFS.md](./NFS.md) | HDD-tier ZFS pool design, quota details |
