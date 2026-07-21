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