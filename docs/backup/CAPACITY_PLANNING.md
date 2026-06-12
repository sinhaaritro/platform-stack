# Backup Capacity & Cost Planning

> **Scope:** Backup size estimation, local storage impact, AWS S3 cost model, and lifecycle policy design. For the storage capacity planning (non-backup), see [`docs/storage/CAPACITY_PLANNING.md`](../storage/CAPACITY_PLANNING.md).

---

## Backup Size Estimation

Backup sizes are estimated per app, following the platform's percentage-based capacity model:

| App Type | Velero Backup Content | Estimated Raw Size | Kopia Dedup Ratio | Effective Size Per Backup |
|---|---|---|---|---|
| Auth provider (e.g., Authentik) | K8s resources + DB dump PVC | ~500 MB | ~2× dedup | ~250 MB |
| Photo manager DB (e.g., Immich) | K8s resources + DB dump + config PVC | ~1-5 GB | ~2× dedup | ~0.5-2.5 GB |
| Notes app (e.g., Obsidian) | K8s resources + config PVC | ~200 MB | ~3× dedup (text) | ~70 MB |
| SSL Certificates | K8s Secrets only | ~5 MB | ~1× (small) | ~5 MB |

> **Note:** Kopia (Velero's uploader) uses content-addressable deduplication. Daily incremental backups of mostly-unchanged PVCs are very efficient — only changed blocks are stored. The effective size per backup drops significantly after the first full backup.

---

## Retention Multiplier

Total backup storage = `effective_size_per_backup × retention_count`

| Retention Policy | Backup Count | When to Use |
|---|---|---|
| 7 days | 7 backups | Dev/staging clusters |
| 30 days (current) | 30 backups | Production (current default) |
| 90 days | 90 backups | Compliance or regulated workloads |

---

## Local Storage Impact (SeaweedFS BSL)

When the SeaweedFS BSL is activated, backup data will consume SSD-tier capacity via Longhorn:

```
SeaweedFS BSL storage = Σ (effective_app_backup × retention_days)
```

**Budget guidance:** Reserve **5-10% of SSD-tier capacity** for backup data on the SeaweedFS BSL. This is in addition to the existing SeaweedFS budget in [`CAPACITY_PLANNING.md`](../storage/CAPACITY_PLANNING.md).

| Scenario | Estimated BSL Usage | Impact on SSD Budget |
|---|---|---|
| Current 4 apps × 30 days | ~5-15 GB | Minimal — fits within existing SeaweedFS headroom |
| 10 apps × 30 days | ~20-50 GB | Noticeable — plan SSD-tier expansion |
| 10 apps × 90 days | ~60-150 GB | Significant — dedicated SSD budget line needed |

---

## Cloud Storage Cost Model (AWS S3, ap-south-1 Mumbai)

### Storage Costs

| S3 Tier | $/GB/month | Min Duration | Best For |
|---|---|---|---|
| **Standard** | ~$0.025 | None | Critical clusters, frequent restores |
| **Glacier Instant Retrieval** | ~$0.005 | 90 days | Important clusters, rare restores |
| **Glacier Flexible Retrieval** | ~$0.004 | 90 days | Lower-priority clusters |
| **Glacier Deep Archive** | ~$0.001 | 180 days | Long-term compliance only |

### Data Transfer Costs

| Direction | Cost |
|---|---|
| **Upload** (backup → S3) | Free (no ingress charges) |
| **Download** (S3 → restore) | ~$0.01/GB (first 10TB) |
| **Glacier retrieval** | Additional $0.01-$0.03/GB depending on speed |

### Cost Projection Formula

```
Monthly cloud cost = Σ per app:
  (effective_backup_size × retention_versions × s3_tier_rate)
  + (estimated_restore_per_month × download_rate)
```

### Example Cost Projections (Single Cluster, 30-Day Retention)

| Scenario | S3 Standard | Glacier Instant | Glacier Flexible |
|---|---|---|---|
| 4 apps, ~10 GB total backup | $0.25/mo | $0.05/mo | $0.04/mo |
| 10 apps, ~50 GB total backup | $1.25/mo | $0.25/mo | $0.20/mo |
| 10 apps + NFS rclone (500 GB) | $13.75/mo | $2.75/mo | $2.20/mo |

> **Key insight:** The Velero backups (K8s state + PVCs) are cheap regardless of S3 tier. The cost driver is **NFS user data via rclone** — especially photos and videos. This is why per-app rclone with independent policies is critical: back up irreplaceable photos daily, but skip re-downloadable media entirely.

---

## S3 Lifecycle Policy Design

Use S3 Lifecycle rules to automatically transition older backups to cheaper tiers:

```json
{
  "Rules": [
    {
      "ID": "velero-lifecycle",
      "Status": "Enabled",
      "Filter": { "Prefix": "backups/" },
      "Transitions": [
        { "Days": 30, "StorageClass": "GLACIER_IR" },
        { "Days": 90, "StorageClass": "DEEP_ARCHIVE" }
      ],
      "Expiration": { "Days": 365 }
    }
  ]
}
```

**How it works:**
-   Days 0-30: S3 Standard (fast restore for recent backups)
-   Days 31-90: Glacier Instant Retrieval (cost reduction, still fast)
-   Days 91-365: Deep Archive (archival, slow restore)
-   After 365 days: Expired (deleted)

> **⚠️ Caution:** If your TTL in Velero is 30 days, Velero will delete the backup metadata at day 30. The S3 objects may persist longer due to lifecycle rules, but Velero won't know about them. Align Velero TTL with S3 lifecycle expiration to avoid orphaned objects.

---

## Monitoring Thresholds

| Metric | Warning | Critical | Action |
|---|---|---|---|
| SeaweedFS BSL usage | > 70% of allocated budget | > 85% | Expand SeaweedFS PVC or reduce retention |
| AWS S3 monthly cost | > projected budget | > 2× projected | Review app backup policies, enable Glacier |
| Backup size growth rate | > 20% month-over-month | > 50% | Investigate data growth source |

---

## Related Documentation

| Document | Relationship |
|---|---|
| [README.md](./README.md) | Backup overview, retention policies this doc sizes for |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | BSL configuration, S3 tier selection per cluster |
| [MONITORING.md](./MONITORING.md) | Alerts that trigger when capacity thresholds are breached |
| [`docs/storage/CAPACITY_PLANNING.md`](../storage/CAPACITY_PLANNING.md) | SSD-tier budget — backup BSL draws from this budget |
