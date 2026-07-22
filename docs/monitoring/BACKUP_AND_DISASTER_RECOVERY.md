## S1 - Backup & Disaster Recovery

> **Purpose:** Comprehensive visibility into Velero backup execution, storage target health, schedule compliance, and recovery point validation.

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

The dashboard is organized into **6 tabs** (collapsible). An operator opens the dashboard and sees Tab 1 immediately — "are backups healthy?" If the answer is no, they expand tabs below to diagnose.

---

#### Tab 1: Health at a Glance

> **Design:** 5 stat panels in a horizontal strip. Green/yellow/red thresholds. No scrolling needed.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Backup SLA %** | Stat (big number) | `sum(velero_backup_success_total) / sum(velero_backup_success_total + velero_backup_failure_total + velero_backup_partial_failure_total) * 100` | ≥99% 🟢, 95-99% 🟡, <95% 🔴 | The single most important number. Enterprise SRE teams use this as their DR confidence metric. If it's red, nothing else matters until this is fixed. |
| **Failed Backups (7d)** | Stat (red if >0) | `sum(increase(velero_backup_failure_total[7d]))` | 0 🟢, 1-2 🟡, ≥3 🔴 | Trend indicator. A non-zero value demands investigation. This is the panel that would have caught your silent Velero failures. |
| **Backups in Last 24h** | Stat (count) | `sum(increase(velero_backup_attempt_total[24h]))` | ≥3 🟢 (you have 3 daily schedules), 1-2 🟡, 0 🔴 | Sanity check. You expect 3 daily backups (ssl-certs, obsidian, security). If this shows 0, the scheduler or controller is dead. |
| **Oldest Successful Backup** | Stat (hours ago) | `time() - max(velero_backup_last_successful_timestamp)` | <26h 🟢, 26-48h 🟡, >48h 🔴 | "How stale is my most recent good backup?" If this exceeds your RPO (Recovery Point Objective), you're in danger. |
| **Active Backup Now** | Stat (boolean) | `velero_backup_last_status == 6` or `count(velero_backup_last_status{phase="InProgress"})` | Running 🔵, None ⚪ | Shows if a backup is currently in progress. Useful to avoid manual operations during a run, and to spot stuck backups (running for >1h). |

---

#### Tab 2: Per-Schedule Status

> **Design:** Table + timeline. The table shows the current state of each schedule. The timeline shows historical pass/fail.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Schedule Status Table** | Table | `velero_backup_last_status` grouped by `schedule` label. Columns: Schedule Name, Last Status (mapped: 1=New, 2=InProgress, 3=Uploading, 4=Completed, 6=Failed, 7=PartiallyFailed), Last Run Time, Duration, Items Backed Up | The operational control center. At a glance: "daily-obsidian: Completed 6h ago, 142 items, 3m12s" vs "daily-security: Failed 30h ago". Each row is a schedule from your 4 configured schedules. |
| **Backup History Timeline** | Time series (status-mapped bars) | `velero_backup_last_status` per schedule over 7d/30d | Pattern recognition. "daily-obsidian fails every Tuesday" or "monthly-immich hasn't run in 45 days". Enterprise teams use this to spot intermittent failures that aren't caught by point-in-time alerts. |
| **Backup Duration Trend** | Time series (lines, per schedule) | `velero_backup_duration_seconds{schedule=~".+"}` | Performance degradation tracking. If `daily-security` normally takes 2min but now takes 20min, your storage backend is degraded. Also useful for scheduling: avoid overlap between the 21:00 and 21:30 schedules. |
| **Backup Size Trend** | Time series (lines, per schedule) | `velero_backup_items_total{schedule=~".+"}` | Capacity planning. "Immich metadata backups are growing 15% monthly. At this rate, I need to increase S3 budget by Q3." |

> [NOTE]
> For Schedule Status Table, to have non binary values then we will need to modify kube-state-metric to scrape values. But the last failed backup can be found at Failed Backups (7d), Backup SLA %, Backup History Timeline, Items Backed Up vs Errors, Velero Error Log Stream, Firing Alerts Table panel. So we decided to keep it simple here. The question is does this pass the crieteria and target of this whole group, dashboard. And make sense in removing the info from the monitoring feature prospective?

---

#### Tab 3: Backup Storage Health

> **Design:** Focuses on the BSL (Backup Storage Location) — the S3 targets. If storage is broken, ALL backups fail.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **BSL Availability** | Stat per BSL | `velero_backup_storage_location_last_validation_result{name=~".+"}` | You have an `aws` BSL (via S3 SeaweedFS → AWS). If this reports unavailable, zero backups can succeed. This is your early-warning system for S3/SeaweedFS outages. Enterprise DR teams treat BSL availability as critical as disk space. |
| **BSL Last Validation Age** | Stat (time since) | `time() - velero_backup_storage_location_last_validation_time` | If validation hasn't run in >1 hour, the Velero controller may be hung. Velero validates BSLs on a default 1-minute interval. |
| **Backup Storage Used (S3)** | Time series | SeaweedFS bucket size metrics for the Velero bucket | How much storage are your backups consuming? Ties into budget. Combined with the "Backup Size Trend" panel, you can project when you'll hit a storage limit. |
| **Items Backed Up vs Errors** | Stacked bar (per schedule) | `velero_backup_items_total` vs `velero_backup_items_errors` per schedule | **This is the silent killer.** A backup can "succeed" but have item-level errors — meaning some resources weren't captured. Partial failures create false confidence. This panel makes partial failures visible. |

---

#### Tab 4: Restore Readiness

> **Design:** Enterprise DR isn't just "do backups run?" — it's "can we actually recover?" This Tab answers the second question.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Last Successful Restore** | Stat (age) | `time() - max(velero_restore_last_successful_timestamp)` or `velero_restore_success_total` with timestamp | Enterprise compliance and audit: "When did we last prove our backups work?" If the answer is "never" or "6 months ago", your backups are theoretical. Best practice: test restore monthly. |
| **Restore History** | Table | `velero_restore_success_total`, `velero_restore_failed_total` with timestamps | History log. After you run a restore test (which you have YAML templates for: `ssl-cert-restore`, `obsidian-restore`, etc.), this tracks the results. |
| **Restore Duration** | Time series | `velero_restore_duration_seconds` | Your RTO (Recovery Time Objective). "If Immich dies, it takes 8 minutes to restore." If this increases, investigate storage performance. |
| **Restore Warnings & Errors** | Table | `velero_restore_items_errors`, `velero_restore_items_warnings` | Even successful restores can have warnings (e.g., "CRD already exists"). Errors in a restore are critical — partial restore = partial data loss. |

---

#### Tab 5: Velero Operational Health

> **Design:** Monitor the backup engine itself. If Velero is unhealthy, all panels above become meaningless.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Velero Server Status** | Stat (up/down) | `up{job="velero"}` | Is the Velero controller pod running and serving metrics? Down = no backups, no restores, no validation. |
| **Node Agent Status** | Multi-stat (per node) | `kube_pod_status_phase{namespace="backup", pod=~"node-agent.*"}` | Node agents run on each K8s node and handle file-level backups (`defaultVolumesToFsBackup: true`). Your obsidian, security, and immich schedules use this. If a node agent is down on the node where the PVC lives, that PVC's backup silently fails. |
| **Velero Error Log Stream** | Logs panel | Loki: `{namespace="backup", container="velero"} \|= "level=error" or \|= "error"` | Real-time error stream. This is where you'd see the actual root cause of your failed backups — e.g., "AccessDenied", "connection refused", "context deadline exceeded". |
| **Node Agent Log Stream** | Logs panel | Loki: `{namespace="backup", container="node-agent"} \|= "error"` | File-level backup errors. Kopia encryption issues, filesystem permission errors, etc. |
| **Velero Pod Restarts** | Time series | `kube_pod_container_status_restarts_total{namespace="backup"}` | CrashLooping Velero = intermittent backup success. If restart count is climbing, the controller has a stability issue. |

---

#### Tab 6: Active Alerts

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