# Resource Planning & Allocation Guide

This document provides a comprehensive view of your physical host capacity, current resource utilization, and the proposed "Clean Slate" strategy for the specialized Kubernetes clusters.

---

## 1. Current Host Resource Availability (`moo-moo`)

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
| **.2 - .9** | **Physical Infrastructure** | Proxmox Node (moo-moo), Physical Hardware. |
| **.10 - .99** | **Static Servers** | K8s Nodes, standalone LXCs, Database VMs. |
| **.100 - .199** | **DHCP Pool** | Mobile devices, Laptops, IoT. (Router Configured) |
| **.200 - .254** | **Virtual IPs** | MetalLB Load Balancer IPs for K8s services. |

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

This layout optimizes your **32GB RAM** and utilizes the two-disk model for stability.

### Cluster `ruth` (Management & Heavy Apps)
*Hosting: Immich, Obsidian, Observability, ArgoCD*

| ID | Name | IP Address | RAM | Boot Disk | Data Disk |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1020** | **ruth-01** | `.20` | 6 GB | 12 GB | 20 GB |
| **1021** | **ruth-02** | `.21` | 4 GB | 12 GB | 40 GB |
| **1022** | **ruth-03** | `.22` | 4 GB | 12 GB | 20 GB |
| **1023** | **ruth-04** | `.23` | (TBD) | 12 GB | (TBD) |
| **1024** | **ruth-05** | `.24` | (TBD) | 12 GB | (TBD) |

### Cluster `arr` (Media Processing)
*Hosting: Sonarr, Radarr, Prowlarr, etc.*

| ID | Name | IP Address | RAM | Boot Disk | Data Disk |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1025** | **arr-01** | `.25` | 2 GB | 12 GB | 10 GB |
| **1026** | **arr-02** | `.26` | 4 GB | 12 GB | 20 GB |
| **1027** | **arr-03** | `.27` | 4 GB | 12 GB | 20 GB |
| **1028** | **arr-04** | `.28` | (TBD) | 12 GB | (TBD) |
| **1029** | **arr-05** | `.29` | (TBD) | 12 GB | (TBD) |

---

## 5. Network Strategy & Connectivity

- **Nginx Proxy Manager**: **RETIRED**. Redundant due to CF Tunnels.
- **ID/IP Linking**: All VIDs match IP suffixes (e.g., ID `1020` = `.20`).
- **Access Flow**: Internet ➡️ Cloudflare ➡️ **CF Tunnel LXC** ➡️ **Traefik (K8s)**.
- **Internal Access**: CF Tunnel LXC (ID 2050) provides access to Proxmox, AdGuard, and Zero Trust SSH.
- **Sandbox**: ID **1099** (IP `.99`) sits at the end of the static server range for isolated testing.

---

## 6. Execution Totals (New Plan)

| Metric | Provisioned | Host Capacity | Balance | Status |
| :--- | :--- | :--- | :--- | :--- |
| **RAM** | **24 GB** | 32 GB | **8 GB** | 🟢 Healthy Buffer |
| **CPU Threads** | **18 vCores** | 16 Threads | **-2** | 🟢 Healthy Over-provision |
| **Total Disk** | **242 GB** | 481 GB | **239 GB** | 🟢 Safe (Thin) |
