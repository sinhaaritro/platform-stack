# Backup Monitoring & Verification

> **Scope:** Periodic restore drills, Velero alerting rules, and Grafana dashboard recommendations. For backup architecture, see [ARCHITECTURE.md](./ARCHITECTURE.md). For restore procedures, see [RUNBOOKS.md](./RUNBOOKS.md).

---

## Periodic Restore Drill

**Cadence:** Monthly

**Purpose:** Verify that backups are restorable and data is intact. An untested backup is not a backup.

### Procedure

1.  Pick one app from the current schedule rotation (rotate monthly).
2.  Execute the appropriate restore template (B, C, or D from [RUNBOOKS.md](./RUNBOOKS.md)) into the `restore` namespace.
3.  Verify the restored data:
    -   For databases: run a query to count rows or check schema integrity.
    -   For PVC data: compare file counts and sizes against the live PVC.
    -   For NFS data: spot-check a sample of files.
4.  Document the result (pass/fail, duration, issues encountered).
5.  Clean up the `restore` namespace.

### Drill Rotation

| Month | App to Test | Template | Verification |
|---|---|---|---|
| Jan, May, Sep | Auth provider (e.g., Authentik) | Template C | DB row count, SSO login test |
| Feb, Jun, Oct | Photo manager (e.g., Immich) | Template D | DB tables, spot-check photos on NFS |
| Mar, Jul, Nov | Notes app (e.g., Obsidian) | Template B | File count, open a vault |
| Apr, Aug, Dec | SSL Certificates | Template A | Cert validity, TLS handshake |

> **Adapt this rotation** as new apps are added. The goal is that every backed-up app is restore-tested at least 3× per year.

---

## Alerting Design

The following PrometheusRules should be deployed to detect backup failures proactively:

### Alert Definitions

| Alert Name | Condition | Severity | Meaning |
|---|---|---|---|
| `VeleroBackupFailed` | `increase(velero_backup_failure_total[24h]) > 0` | 🔴 Critical | A scheduled backup failed completely |
| `VeleroBackupPartialFailure` | `increase(velero_backup_partial_failure_total[24h]) > 0` | 🟠 Warning | Backup completed but some items were skipped |
| `VeleroBackupStale` | `time() - velero_backup_last_successful_timestamp > 93600` | 🔴 Critical | No successful backup in 26 hours (24h schedule + 2h grace) |
| `VeleroBSLUnavailable` | `velero_backup_storage_location_available == 0` | 🔴 Critical | A BSL is unreachable (S3 creds expired, network issue) |
| `VeleroRestoreFailed` | `increase(velero_restore_failure_total[1h]) > 0` | 🟠 Warning | A restore operation failed |

### PrometheusRule Manifest

```yaml
# Deploy to: kubernetes/apps/infrastructure/velero/components/metrics/
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: velero-alerts
  namespace: backup
  labels:
    app.kubernetes.io/name: velero
    app.kubernetes.io/instance: velero
spec:
  groups:
    - name: velero.rules
      rules:
        - alert: VeleroBackupFailed
          expr: increase(velero_backup_failure_total[24h]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Velero backup failed"
            description: "A Velero backup has failed in the last 24 hours."

        - alert: VeleroBackupPartialFailure
          expr: increase(velero_backup_partial_failure_total[24h]) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Velero backup partial failure"
            description: "A Velero backup completed with partial failures in the last 24 hours."

        - alert: VeleroBackupStale
          expr: time() - velero_backup_last_successful_timestamp{schedule!=""} > 93600
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "Velero backup is stale"
            description: "No successful backup for schedule {{ $labels.schedule }} in over 26 hours."

        - alert: VeleroBSLUnavailable
          expr: velero_backup_storage_location_available == 0
          for: 15m
          labels:
            severity: critical
          annotations:
            summary: "Velero BSL unavailable"
            description: "Backup Storage Location {{ $labels.name }} is unreachable."

        - alert: VeleroRestoreFailed
          expr: increase(velero_restore_failure_total[1h]) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Velero restore failed"
            description: "A Velero restore operation has failed in the last hour."
```

---

## Grafana Dashboard

Import the community Velero dashboard (ID: `11055`) or build a custom one tracking:

-   Backup success/failure rate over time
-   Backup duration per schedule
-   Backup size per schedule
-   BSL availability
-   Last successful backup age per schedule

### Key Panels

| Panel | PromQL | Purpose |
|---|---|---|
| Last successful backup age | `time() - velero_backup_last_successful_timestamp` | Stale backup detection |
| Backup duration | `velero_backup_duration_seconds` | Performance tracking |
| Backup size | `velero_backup_items_total` | Growth monitoring |
| BSL health | `velero_backup_storage_location_available` | Infrastructure health |
| Failure rate | `rate(velero_backup_failure_total[7d])` | Trend analysis |

---

## Related Documentation

| Document | Relationship |
|---|---|
| [README.md](./README.md) | Backup overview, RPO/RTO targets this monitoring enforces |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Velero ServiceMonitor configuration |
| [RUNBOOKS.md](./RUNBOOKS.md) | Restore procedures triggered when alerts fire |
| [CAPACITY_PLANNING.md](./CAPACITY_PLANNING.md) | Backup size trends inform capacity alerts |
