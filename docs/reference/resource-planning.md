# Resource Planning & Allocation Guide

This document provides a comprehensive view of your physical host capacity, current resource utilization, and the proposed "Clean Slate" strategy for the specialized Kubernetes clusters.

---

## 1. Current Host Resource Availability (`atlas`)

This section tracks the physical "Headroom" remaining on your Proxmox host based on your verified hardware specs.

| Resource | **Total Physical Capacity** | **Currently Allocated** (VMs+LXCs) | **Available / Free** (Approx) |
| :--- | :--- | :--- | :--- |
| **CPU Threads** | **16 Logical Threads** | **14 vCores** (K8s) + 2 (Dev) | **0 Threads** (Fully Mapped) |
| **RAM** | **32 GB** | **18 GB** (K8s) + 4 (Others) | **~10 GB** (Host Buffer) |
| **Storage (SSD)** | **481 GB** (Calculated Sum) | **152 GB** (K8s) + 53 GB (Others) | **~276 GB** (Provisioned) |

---

## 2. Infrastructure Management Strategy (IP Ranges)

| Range | Usage | Description |
| :--- | :--- | :--- |
| **.1** | **Gateway** | Your Router. |
| **.2 - .9** | **Physical Infrastructure** | Proxmox Node (`atlas`), Physical Hardware, Switches. |
| **.10 - .99** | **Static Servers** | Admin workstations, Core & App LXCs, Standalone VMs, K8s Clusters. *(See Sub-Table Below)* |
| **.100 - .199** | **DHCP Pool** | Mobile devices, Laptops, IoT. (Router Configured) |
| **.200 - .254** | **Virtual IPs** | MetalLB Load Balancer IPs for K8s services. |

### Static Server Sub-Table (`192.168.0.10` – `192.168.0.99`)

| IP Block | Category / Group | Workloads & Purpose | Type | Proxmox ID Range | **Slots** | **Suggested Allocation** |
| :--- | :--- | :--- | :--- | :--- | :---: | :--- |
| **`.10` – `.19`** | **Admin & Dev Workstations** | Primary dev workstations, management jump boxes, runner hosts | VM | `1010` – `1019` | **10** | • 2–3 Dev Workstations<br>• 2–3 CI/CD Runners<br>• 4 Spares |
| **`.20` – `.29`** | **Core Infrastructure LXCs** | Mission-critical edge networking, DNS, VPN tunnels, auth | LXC | `1020` – `1029` | **10** | • 1 DNS (`adguard`)<br>• 1 VPN (`netbird`)<br>• 1 Ingress (`cloudflared`)<br>• 7 Spares |
| **`.30` – `.39`** | **Auxiliary & App LXCs** | Microservices, monitoring scrapers, support containers | LXC | `1030` – `1039` | **10** | • 4–6 Support / Scraper LXCs<br>• 4 Spares |
| **`.40` – `.49`** | **Standalone Server VMs** | Dedicated single-purpose VMs (Databases, Web, NAS client) | VM | `1040` – `1049` | **10** | • 1 Dev Server (`agora`, `.40`)<br>• 2 Web Servers (`.41-.42`)<br>• 2–3 DBs (`.45-.46`)<br>• 1 NAS Client (`.47`)<br>• 3 Spares |
| **`.50` – `.79`** | **Production Kubernetes Clusters** | Multi-cluster production nodes (`hyperion`, `quanta`, `elysia`) | VM | `1050` – `1079` | **30** | • 10 IPs: `hyperion` (`.50-.59`)<br>• 10 IPs: `quanta` (`.60-.69`)<br>• 10 IPs: `elysia` (`.70-.79`) |
| **`.80` – `.89`** | **Dev & Test Kubernetes Clusters** | Ephemeral, feature-testing, or lab Kubernetes nodes (Kind, K3d) | VM | `1080` – `1089` | **10** | • 2–3 Test / Kind Clusters<br>• 7 Spares |
| **`.90` – `.99`** | **Sandbox, Lab & Staging** | Disposable test beds, dirty environments, OS upgrade trials | VM / LXC | `1090` – `1099` | **10** | • 2–3 Sandboxes<br>• 7 Spares |
| **Total** | **Static Server Range** | — | — | — | **90** | — |

---

## 3. Storage Pool Strategy (The Two-Disk Model)

To prevent data usage from crashing your Operating Systems, every Kubernetes node uses two separate virtual disks.

### Pool A: `local-thin` (161 GB)
**Role**: **Boot / Root Disk (OS)**
- Each VM gets a **12 GB** root disk from this pool.
- **Total Provisioned**: ~112 GB (10 K8s Nodes + Dev VM + Sandbox).
- **Free**: 49 GB (Buffer). **Note: Sustainable.**

### Pool B: `data-storage` (220 GB)
**Role**: **Persistent Data (Longhorn)**
- Secondary disk mounted at `/data/storage`.
- **Total Provisioned**: 130 GB (Initial Active Nodes).
- **Free**: 90 GB (Room for growth).

---

## 4. Proposed "Clean Slate" Allocation

This layout optimizes your **32GB RAM** and utilizes the two-disk model for stability across your Kubernetes clusters.

### Cluster `hyperion` (Core & Observability)
*Hosting: Immich, Obsidian, Observability, ArgoCD*

| ID | Name | IP Address | RAM | Boot Disk | Data Disk |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1050** | **hyperion-01** | `.50` | 6 GB | 12 GB | 20 GB |
| **1051** | **hyperion-02** | `.51` | 4 GB | 12 GB | 40 GB |
| **1052** | **hyperion-03** | `.52` | 4 GB | 12 GB | 20 GB |
| **1053** | **hyperion-04** | `.53` | (TBD) | 12 GB | (TBD) |
| **1054** | **hyperion-05** | `.54` | (TBD) | 12 GB | (TBD) |

### Cluster `quanta` (Media & Entertainment Stack)
*Hosting: Sonarr, Radarr, Prowlarr, Jellyfin, Torrents*

| ID | Name | IP Address | RAM | Boot Disk | Data Disk |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1060** | **quanta-01** | `.60` | 2 GB | 12 GB | 10 GB |
| **1061** | **quanta-02** | `.61` | 4 GB | 12 GB | 20 GB |
| **1062** | **quanta-03** | `.62` | 4 GB | 12 GB | 20 GB |
| **1063** | **quanta-04** | `.63` | (TBD) | 12 GB | (TBD) |
| **1064** | **quanta-05** | `.64` | (TBD) | 12 GB | (TBD) |

### Cluster `elysia` (Management & Multi-Tenant Staging)
*Hosting: Management Hub, Fleet Operations, Staging Workloads*

| ID | Name | IP Address | RAM | Boot Disk | Data Disk |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1070** | **elysia-01** | `.70` | 4 GB | 12 GB | 10 GB |
| **1071** | **elysia-02** | `.71` | 4 GB | 12 GB | 20 GB |
| **1072** | **elysia-03** | `.72` | 4 GB | 12 GB | 20 GB |
| **1073** | **elysia-04** | `.73` | (TBD) | 12 GB | (TBD) |
| **1074** | **elysia-05** | `.74` | (TBD) | 12 GB | (TBD) |

---

## 5. Network Strategy & Connectivity

- **Nginx Proxy Manager**: **RETIRED**. Redundant due to CF Tunnels.
- **ID/IP Linking**: All VIDs match IP suffixes (e.g., ID `1050` = `.50`).
- **Access Flow**: Internet ➡️ Cloudflare ➡️ **CF Tunnel LXC (ID 1022)** ➡️ **Traefik (K8s)**.
- **Internal Access**: CF Tunnel LXC (`.22`) and NetBird (`.21`) provide access to Proxmox, AdGuard (`.20`), and Zero Trust SSH.
- **Sandbox**: ID **1099** (IP `.99`) sits at the end of the static server range for isolated testing.

---

## 6. Execution Totals (New Plan)

| Metric | Provisioned | Host Capacity | Balance | Status |
| :--- | :--- | :--- | :--- | :--- |
| **RAM** | **28 GB** | 32 GB | **4 GB** | 🟢 Safe Buffer |
| **CPU Threads** | **20 vCores** | 16 Threads | **-4** | 🟢 Healthy Over-provision |
| **Total Disk** | **258 GB** | 481 GB | **223 GB** | 🟢 Safe (Thin) |
