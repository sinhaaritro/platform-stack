# S6 — External Infrastructure

| | |
|---|---|
| **Folder** | SRE / Operations |
| **Dashboard ID** | S6 |
| **Refresh** | 30s |
| **Audience** | You wearing the ops hat — hypervisor health, cloud costs, network perimeter |

> **Purpose:** Visibility into everything *outside* Kubernetes that the platform depends on. These are the foundations (Proxmox hypervisor), the network perimeter (Cloudflare, AdGuard, Netbird), and the offsite backup target (AWS S3). If any of these fail, the K8s cluster itself may appear healthy while services are unreachable, backups aren't landing offsite, or DNS is broken for your entire network.

**← Back to [Dashboard Catalog](../README.md#-sre--operations-6-dashboards)**

---

## Data Flow

```
Proxmox VE (API: https://<proxmox>:8006/api2/json)
  │
  └──→ pve-exporter (standalone, port 9221/metrics)       ← NEEDS TO BE DEPLOYED
        │
AWS S3 (CloudWatch / S3 API)
  │
  └──→ yet-another-cloudwatch-exporter (port 5000/metrics) ← NEEDS TO BE DEPLOYED
        │    OR: aws-s3-exporter (simpler, S3-only)
        │
Cloudflare (API: api.cloudflare.com)
  │
  └──→ cloudflare-exporter (port 8080/metrics)             ← NEEDS TO BE DEPLOYED
        │
AdGuard Home (API: http://<adguard-lxc>:3000/api)
  │
  └──→ adguard-exporter (port 9617/metrics)                ← NEEDS TO BE DEPLOYED
        │
Netbird (API: https://api.netbird.io or self-hosted)
  │
  └──→ Custom scrape / API poller                          ← NEEDS TO BE BUILT
        │
        ├──→ Alloy prometheus.scrape (one block per exporter) ← NEEDS TO BE ADDED
        │      │
        │      └──→ Mimir (prometheus.remote_write)
        │
        └──→ Loki (exporter pod logs, already scraped by Alloy)
```

> [!WARNING]
> **Blockers:** This phase has the most deployment work — five separate exporters need to be deployed and scraped:
> 1. **pve-exporter** — Python-based, scrapes Proxmox API. Needs a read-only PVE API token. Deploy as a standalone pod or LXC-resident process.
> 2. **cloudflare-exporter** — Needs a Cloudflare API token with `Zone:Read`, `Analytics:Read`, and `Cloudflare Tunnel:Read` permissions.
> 3. **adguard-exporter** — Needs AdGuard Home admin credentials. The exporter runs outside the AdGuard LXC (as a K8s pod) and scrapes the AdGuard HTTP API.
> 4. **aws-s3-exporter** (or YACE) — Needs AWS IAM credentials with `s3:ListBucket`, `s3:GetBucketLocation`, `cloudwatch:GetMetricData` permissions.
> 5. **Netbird** — No mature Prometheus exporter exists. Options: (a) write a lightweight API poller that exposes `/metrics`, (b) use Alloy's `prometheus.exporter.json` to scrape the Netbird management API, or (c) skip Netbird metrics initially and add them when an exporter matures.

> [!NOTE]
> **Cloudflare tunnel *health* vs *account analytics*:** Tunnel connection status (`cloudflared_tunnel_ha_connections`) is already covered on [S3 — Networking](NETWORKING.md#tab-4-metallb--dnstunnel) because it's part of the ingress request path. S6 covers Cloudflare *account-level* data: DNS analytics, WAF/firewall events, and edge certificate status — the things that affect the platform from outside the cluster.

---

## Dashboard Layout

Unlike other SRE dashboards, S6 uses **rows** rather than tabs — each row is a distinct external system with its own exporter and data source. There is no shared "Health at a Glance" tab because these systems have no common metrics. An **Active Alerts** row at the bottom collects alerts from all five systems.

---

### Row 1: Proxmox Hypervisor

> **Design:** The foundation layer. If Proxmox dies, every K8s node (which are Proxmox VMs) dies with it. This row answers "is the hypervisor healthy?" independently of what K8s reports.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Node Status** | Multi-stat (per Proxmox node) | `pve_up{node=~".+"}` | 1 🟢, 0 🔴 | Are all hypervisor nodes online? A downed Proxmox node means all VMs on it are gone — K8s will show them as NotReady, but only this panel shows *why*. |
| **Node CPU Usage** | Gauge (per node) | `pve_cpu_usage_ratio{node=~".+"}` | <70% 🟢, 70-85% 🟡, >85% 🔴 | Hypervisor-level CPU — K8s sees its allocated vCPUs, but if the hypervisor is at 95%, VM CPU scheduling becomes unreliable and latency spikes appear without a clear K8s-level explanation. |
| **Node Memory Usage** | Gauge (per node) | `pve_memory_usage_bytes{node=~".+"} / pve_memory_size_bytes{node=~".+"}` | <80% 🟢, 80-90% 🟡, >90% 🔴 | Memory overcommit is common in homelabs — this catches the moment the hypervisor starts swapping, which tanks every VM simultaneously. |
| **Node Storage Usage** | Gauge (per storage pool) | `pve_storage_usage_bytes / pve_storage_size_bytes` per storage ID | <70% 🟢, 70-85% 🟡, >85% 🔴 | Proxmox storage pools (local-lvm, NFS, ZFS) filling up prevent VM snapshots, ISO uploads, and potentially VM disk writes. |
| **VM & LXC Status Table** | Table | `pve_guest_info` — columns: VMID, Name, Type (qemu/lxc), Status, Node, CPU %, Memory % | informational | Full inventory: which VMs and LXCs are running, stopped, or errored. Includes the K8s node VMs, AdGuard LXC, and Netbird LXC. |
| **VM CPU/Memory Trend** | Time series (per guest) | `pve_cpu_usage_ratio{id=~"qemu/.*"}`, `pve_memory_usage_bytes{id=~"qemu/.*"}` | informational | Per-VM resource tracking over time. Spot a noisy neighbor (e.g., a K8s worker consuming all CPU during a build) or a memory leak in a VM. |
| **Proxmox Uptime** | Stat (per node) | `pve_node_info` uptime field or `time() - pve_node_boot_time_seconds` | informational | How long since last reboot? Unexpected reboots (short uptime) indicate instability. Expected long uptimes confirm the hypervisor is stable. |

---

### Row 2: AWS (Backup Target)

> **Design:** The offsite backup layer. AWS S3 is the ultimate backup destination for Velero — if this is broken, you have local backups (SeaweedFS) but no offsite DR. This row also tracks cost, since AWS is the only cloud expense.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **S3 Bucket Size** | Time series + stat | `aws_s3_bucket_size_bytes{bucket=~"velero.*"}` (via aws-s3-exporter or YACE) | informational | How much backup storage is consumed in AWS? Directly tied to monthly cost. Combined with Velero retention (30d TTL from [S1](BACKUP_AND_DISASTER_RECOVERY.md)), this should plateau — if it keeps climbing, retention isn't working. |
| **S3 Object Count** | Time series | `aws_s3_bucket_object_count{bucket=~"velero.*"}` | informational | Growth tracking. Each Velero backup creates multiple objects. A plateau confirms retention is cleaning up old backups; continuous growth means objects aren't being deleted. |
| **S3 Request Rate** | Time series | `aws_s3_requests_total` or CloudWatch `AllRequests`, split by `4xx`/`5xx` | 5xx > 0 🔴 | Are backup uploads reaching AWS? 4xx errors usually mean expired/invalid credentials; 5xx means AWS-side issues (rare but impactful). |
| **Estimated Monthly Cost** | Stat | `aws_s3_bucket_size_bytes * <rate_per_byte>` (calculated, or from CloudWatch Billing if enabled) | informational (with trend arrow) | The only external cloud cost on the platform. Enterprise teams track this to prevent bill shock. Even at homelab scale, S3 costs can surprise you if retention isn't working. |

---

### Row 3: Cloudflare (Account-Level)

> **Design:** Edge security and DNS analytics. Tunnel *health* is on [S3](NETWORKING.md); this row covers account-level data that affects the platform from outside.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **DNS Query Rate** | Time series | `cloudflare_zone_dns_queries_total` (via cloudflare-exporter) | informational | DNS resolution volume hitting your domains at the Cloudflare edge. Spikes could indicate an attack, a misconfigured client doing tight-loop lookups, or a newly popular service. |
| **DNS Query Breakdown** | Time series (stacked) | `cloudflare_zone_dns_queries_total` by `query_type` (A, AAAA, CNAME, MX, etc.) | informational | Which query types dominate? Unusual query types (TXT, ANY) at high rates could indicate DNS-based data exfiltration or abuse. |
| **Threats Blocked** | Counter + time series | `cloudflare_zone_threats_total` | informational (but notable if suddenly high) | WAF/DDoS events blocked by Cloudflare. Security visibility into your perimeter — a sudden spike warrants investigation even if Cloudflare handled it automatically. |
| **Bandwidth (cached vs uncached)** | Time series (stacked) | `cloudflare_zone_bandwidth_total` by `cached` (true/false) | informational | Cache hit ratio at the edge. High cached ratio means Cloudflare is offloading traffic from your cluster. Low ratio means most requests reach your origin — check if caching rules need tuning. |
| **Edge SSL Certificate Status** | Stat | `cloudflare_zone_ssl_status` or API certificate status | Valid 🟢, Expiring 🟡, Invalid 🔴 | Cloudflare-managed edge certificates — separate from your internal cert-manager certs on [S3](NETWORKING.md#tab-3-tls--certificates-cert-manager). These renew automatically, but failures here break HTTPS for all external users. |

---

### Row 4: AdGuard Home (LXC)

> **Design:** DNS filtering for the entire network. AdGuard runs as an LXC container on Proxmox (not in K8s). If AdGuard fails, DNS resolution fails for everything on the local network.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **AdGuard Up** | Stat | `up{job="adguard"}` or `adguard_running` | 1 🟢, 0 🔴 | Is the DNS filter alive? If AdGuard is down and it's configured as the network's DNS server, *everything* stops resolving — not just the K8s cluster. |
| **DNS Query Rate** | Time series | `rate(adguard_dns_queries_total[5m])` | informational | DNS resolution volume across your network. Baseline varies by household size and device count. A sudden drop could indicate client-side DNS misconfiguration; a spike could indicate a DNS amplification issue. |
| **Blocked Queries %** | Stat + time series | `adguard_dns_blocked_total / adguard_dns_queries_total * 100` | 15-30% 🟢 (normal range), <10% 🟡, >50% 🟡 | Ad/tracker blocking effectiveness. Below 10% might mean blocklists are outdated; above 50% might mean legitimate domains are being blocked. |
| **Top Blocked Domains (24h)** | Table, top 10 | AdGuard API top blocked domains (exposed via exporter or custom query) | informational | What's getting blocked most? Useful to spot malware phoning home (e.g., a compromised IoT device repeatedly hitting a known C2 domain), or to identify false-positive blocks on legitimate services. |
| **Upstream DNS Latency** | Time series | `adguard_dns_upstream_latency_seconds` | <50ms 🟢, 50-200ms 🟡, >200ms 🔴 | Slow upstream DNS = slow everything on the network. If Cloudflare 1.1.1.1 or Google 8.8.8.8 is slow, all services feel it — including K8s pod DNS resolution if pods use the host's DNS. |
| **Top Queried Domains (24h)** | Table, top 10 | AdGuard API top queried domains | informational | What's generating the most DNS traffic? Useful for identifying chatty devices or services making excessive DNS lookups. |

---

### Row 5: Netbird (LXC)

> **Design:** Mesh VPN connecting all nodes. Netbird runs as an LXC container (management server) and as agents on each node. If the mesh breaks, inter-node communication fails — K8s pods on different nodes can't talk to each other.

> [!NOTE]
> **Exporter maturity:** No widely-adopted Prometheus exporter exists for Netbird as of this writing. The panels below are designed for either a custom API poller (recommended: a lightweight Go/Python script that calls the Netbird management API and exposes `/metrics`) or Alloy's `prometheus.exporter.json` component pointed at the Netbird API. Metric names are illustrative — adjust to match whatever exporter is built.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Connected Peers** | Stat | `netbird_peers_connected` or `count(netbird_peer_status{status="connected"})` | Expected count 🟢, <expected 🔴 | How many nodes are connected to the mesh? If a node drops off, it loses inter-cluster connectivity — pods on that node become network-isolated. |
| **Peer Status Table** | Table | `netbird_peer_status` — columns: Peer Name, IP, Status (connected/disconnected), OS, Version, Last Seen | informational | Which specific peers are online/offline? Maps directly to your K8s nodes + Proxmox hosts + any external devices in the mesh. |
| **Peer Status Map** | Multi-stat (per peer) | `netbird_peer_status{status="connected"}` mapped to 1/0 | Connected 🟢, Disconnected 🔴 | Visual grid — an operator sees instantly which peers are missing without reading a table. |
| **Transfer Rate (per peer)** | Time series | `rate(netbird_peer_transfer_bytes_total[5m])` by peer and direction (rx/tx) | informational | Network traffic through the VPN mesh. Spot bandwidth-heavy peers or unusual traffic patterns (e.g., a peer suddenly sending 10× normal traffic could indicate data exfiltration). |
| **Last Seen (stale peers)** | Table, sorted by oldest last_seen | `time() - netbird_peer_last_seen_seconds` — columns: Peer Name, Last Seen (ago), Status | >1h 🟡, >24h 🔴 | Peers not seen recently may have connectivity issues, be powered off, or have a crashed Netbird agent. The age threshold helps distinguish "just rebooting" from "actually broken." |

---

### Row 6: Active Alerts

> **Design:** Same pattern as all other dashboards — a single table of currently firing external infrastructure alerts.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `alertgroup="external-infra"` | Single pane for all external infrastructure issues, color-coded by severity. |

#### Alert Rules (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|------------------|-----|----------|-------------|
| `ProxmoxNodeDown` | `pve_up == 0` | 2m | **Critical** | A Proxmox hypervisor node is unreachable — all VMs on it are likely down. |
| `ProxmoxHighCPU` | `pve_cpu_usage_ratio > 0.85` | 10m | **Warning** | Sustained high CPU on the hypervisor — VM scheduling performance will degrade. |
| `ProxmoxHighMemory` | `pve_memory_usage_bytes / pve_memory_size_bytes > 0.90` | 10m | **Warning** | Hypervisor memory above 90% — risk of swapping, which tanks all VM performance. |
| `ProxmoxStorageLow` | `pve_storage_usage_bytes / pve_storage_size_bytes > 0.85` | 10m | **Warning** | A Proxmox storage pool is above 85% — VM snapshots and disk operations may fail. |
| `AWSS3UploadErrors` | `rate(aws_s3_requests_total{status=~"5.."}[15m]) > 0` | 15m | **Critical** | S3 uploads are failing — offsite backups are not landing. Check AWS credentials and service health. |
| `AdGuardDown` | `up{job="adguard"} == 0` | 2m | **Critical** | AdGuard Home is unreachable — DNS resolution for the entire local network may be broken. |
| `AdGuardHighLatency` | `adguard_dns_upstream_latency_seconds > 0.2` | 10m | **Warning** | Upstream DNS latency over 200ms — all services will feel slower DNS resolution. |
| `NetbirdPeerDisconnected` | `netbird_peer_status{status="connected"} == 0` | 5m | **Warning** | A Netbird peer has been disconnected for >5 minutes — inter-node connectivity may be broken for that host. |

---

**← Back to [Dashboard Catalog](../README.md#-sre--operations-6-dashboards)** | **Previous: [S4 — Storage](STORAGE.md)**
