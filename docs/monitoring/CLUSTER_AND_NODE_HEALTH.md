## S2 — Cluster & Node Health

**Folder:** SRE / Operations
**Refresh:** 30s
**Audience:** You wearing the ops hat — on-call, troubleshooting, capacity watch.

### Data Flow for Node/Pod Metrics

```
node-exporter (DaemonSet, port 9100/metrics)   ← already scraped ✅
kube-state-metrics (Deployment, port 8080)     ← NEEDS TO BE ADDED
kubelet /metrics/cadvisor (per-node, :10250)   ← NEEDS TO BE ADDED
  │
  ├──→ Alloy prometheus.scrape "node-exporter"       (existing)
  ├──→ Alloy prometheus.scrape "kube-state-metrics"  (new)
  ├──→ Alloy prometheus.scrape "cadvisor"            (new)
  │      │
  │      └──→ Mimir (prometheus.remote_write)
  │
  └──→ Loki (kubelet/system logs, already scraped by Alloy)
```

> [!WARNING]
> **Blocker:** Node-exporter data is already flowing (fleet-level CPU/mem/disk/network is fine today), but **pod-level** panels (pod restarts, pod distribution per node, OOM kills, per-pod resource usage) need two things that are not yet in Alloy's `custom-config`:
> 1. `kube-state-metrics` deployed to the cluster (if not already present) and scraped — this is where `kube_pod_status_phase`, `kube_pod_container_status_restarts_total`, and `kube_pod_container_status_last_terminated_reason` come from.
> 2. A `cadvisor` scrape block pointed at each kubelet's `/metrics/cadvisor` endpoint — this is where per-pod/per-container CPU and memory usage (as opposed to per-node totals) come from.
>
> Without these two, S2 can still ship with node-level panels fully populated, but pod-level panels will be empty. Recommend adding both scrape blocks as the first task of this phase — same pattern as the Velero blocker in Phase 1.

### Dashboard Layout: S2 — Cluster & Node Health

Organized into **5 tabs**, following the same "glance first, drill down after" pattern as S1.

---

#### Tab 1: Fleet Health at a Glance

> **Design:** Stat strip, identical philosophy to S1 Tab 1 — an operator should know if the cluster is fine within 5 seconds.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Nodes Ready** | Stat (fraction) | `sum(kube_node_status_condition{condition="Ready", status="true"}) / count(kube_node_info)` | 100% 🟢, <100% 🔴 | Any node not Ready is a cluster-capacity problem. This is your "is the fleet intact" number. |
| **Pods Not Running** | Stat (count, red if >0) | `sum(kube_pod_status_phase{phase!~"Running\|Succeeded"})` | 0 🟢, 1-3 🟡, >3 🔴 | Catches CrashLoopBackOff, Pending, and Unknown pods cluster-wide before they page you individually. |
| **Cluster CPU Utilization** | Gauge | `sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) / sum(rate(node_cpu_seconds_total[5m])) * 100` | <70% 🟢, 70-85% 🟡, >85% 🔴 | Headroom check. Sustained high CPU across the fleet is your early signal to add nodes or right-size workloads. |
| **Cluster Memory Utilization** | Gauge | `1 - (sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))` | <70% 🟢, 70-85% 🟡, >85% 🔴 | Same as above for memory. Memory pressure is usually the first thing to cause node instability. |
| **OOM Kills (1h)** | Stat (red if >0) | `sum(increase(node_vmstat_oom_kill[1h]))` | 0 🟢, ≥1 🔴 | A silent-killer metric — a workload can be repeatedly OOM-killed and restart fast enough that nobody notices without this panel. |

---

#### Tab 2: Per-Node Deep Dive

> **Design:** A table for at-a-glance comparison across nodes, plus time series for trend-spotting on any single node.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Node Summary Table** | Table | `kube_node_info` joined with `node_load1`, CPU %, memory %, disk % per node (via `$__cell` transforms or multi-query table panel) — columns: Node, Ready, CPU %, Mem %, Disk %, Load1, Pod Count, Kernel Version | The "which node is the problem child" view. Sortable by any column — instantly spot the one node running hot. |
| **Per-Node CPU/Memory** | Time series (one line per node) | `rate(node_cpu_seconds_total{mode!="idle"}[5m])` and `node_memory_MemAvailable_bytes` grouped by `instance` | Trend over time per node — useful to correlate a node's degradation with when a specific workload landed on it. |
| **Per-Node Disk Space** | Time series (one line per node) | `node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}` per node/mount | Disk exhaustion is one of the most common causes of node NotReady. Watch this alongside Longhorn/SeaweedFS panels in S4 (Phase 3). |
| **Per-Node Network I/O** | Time series (rx/tx per node) | `rate(node_network_receive_bytes_total[5m])`, `rate(node_network_transmit_bytes_total[5m])` | Spot a node saturating its NIC — common cause of intermittent pod-to-pod timeouts that look like application bugs. |
| **System Load (1/5/15m)** | Time series (per node) | `node_load1`, `node_load5`, `node_load15` | Classic Linux health signal; a load average consistently above core count means the node is CPU-saturated even if the CPU % gauge looks moderate (I/O wait counts too). |

---

#### Tab 3: Pod Health & Distribution

> **Design:** Depends on the kube-state-metrics blocker above. This tab answers "are workloads landing evenly and staying up?"

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Pod Distribution per Node** | Bar gauge (per node) | `count(kube_pod_info) by (node)` | Spot scheduling imbalance — e.g., one node running 40 pods while another runs 5, which usually means a taint/affinity/resource-request issue. |
| **Pod Restarts (24h)** | Table, sorted descending | `sum(increase(kube_pod_container_status_restarts_total[24h])) by (namespace, pod)` | The single best "what broke recently" panel. A pod with 15 restarts in a day is your investigation starting point, before users even complain. |
| **Pods by Phase** | Pie / stacked bar | `count(kube_pod_status_phase) by (phase)` | Running vs Pending vs Failed vs Unknown, cluster-wide. A rising "Pending" count usually means insufficient schedulable resources. |
| **Top Restart Reasons** | Table | `kube_pod_container_status_last_terminated_reason` grouped by reason | OOMKilled vs Error vs Completed — tells you *why* pods are restarting without opening `kubectl describe` for every one. |

---

#### Tab 4: Kubelet & System Health

> **Design:** "Is the container runtime and node agent itself healthy?" — one level below pods.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Kubelet Up** | Multi-stat (per node) | `up{job="kubelet"}` | If a kubelet is down, that node silently stops reporting pod status — this catches it before pods on that node start looking "stuck" rather than obviously failed. |
| **Kubelet Pod Sync Errors** | Time series | `rate(kubelet_pod_worker_duration_seconds_count{job="kubelet"}[5m])` combined with `kubelet_pleg_relist_duration_seconds` | Slow/erroring pod sync loops are an early indicator of kubelet degradation, often before it fully stops responding. |
| **Container Runtime Ops** | Time series | `rate(kubelet_runtime_operations_total[5m])` and `rate(kubelet_runtime_operations_errors_total[5m])` | Errors here point to containerd/CRI issues rather than application issues — an important triage fork. |
| **Node Filesystem inode Usage** | Gauge (per node) | `1 - (node_filesystem_files_free / node_filesystem_files)` | Frequently overlooked capacity dimension — a node can have free disk space bytes-wise but be inode-exhausted (common with many small files, e.g., log-heavy workloads), which fails silently until pods can't be created. |

---

#### Tab 5: Active Alerts

> **Design:** Same pattern as S1 Tab 6 — a single table of currently firing cluster/node alerts, backed by Mimir Ruler → Alertmanager.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `alertgroup="cluster"` or `alertgroup="node"` | Single pane for active infrastructure issues, color-coded by severity. |

##### Alert Rules to Configure (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|-------------------|-----|----------|-------------|
| `NodeNotReady` | `kube_node_status_condition{condition="Ready", status="true"} == 0` | 5m | **Critical** | A node has dropped out of Ready state. Workloads scheduled there may be unreachable. |
| `NodeHighCPU` | `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85` | 10m | **Warning** | Sustained high CPU on a single node — right-size or rebalance workloads. |
| `NodeHighMemory` | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.85` | 10m | **Warning** | Sustained high memory pressure — risk of OOM kills or node instability. |
| `NodeDiskSpaceLow` | `node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes < 0.10` | 5m | **Critical** | Under 10% disk free on a node — imminent risk of eviction / NotReady. |
| `NodeOOMKill` | `increase(node_vmstat_oom_kill[15m]) > 0` | 0m | **Warning** | A process was OOM-killed on this node. Investigate the workload's memory limits. |
| `PodCrashLooping` | `increase(kube_pod_container_status_restarts_total[15m]) > 3` | 5m | **Warning** | A pod is restarting repeatedly — likely a bad deploy, misconfiguration, or resource limit issue. |
| `KubeletDown` | `up{job="kubelet"} == 0` | 2m | **Critical** | Kubelet on a node is unreachable — node health reporting has stopped. |

---