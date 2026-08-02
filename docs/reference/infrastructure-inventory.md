# Infrastructure Inventory & Allocation Map (Clean Slate)

This table serves as the definitive record for your fresh deployment. The **ID and IP are strictly linked** based on your network management strategy.

## 0. Templates (Proxmox Images)
| ID | Name | OS | Description | Pool |
| :--- | :--- | :--- | :--- | :--- |
| **101** | **ubuntu-2404-template** | Ubuntu 24.04 | Standard Cloud-Init Template | `local` |
| **102** | **ubuntu-2104-template** | Ubuntu 25.04 | Fast-track Template for testing | `local` |

## 1. Static Services & Management (VM / LXC)

| ID | Name | Type | IP Address | OS | Description | Storage (Pool) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1010** | **hiking-bear** | VM | `192.168.0.10` | Ubuntu 24.04 | Primary Dev/Management Workstation | 20 GB (`local-thin`) |
| **1099** | **sandbox-01** | VM | `192.168.0.99` | Ubuntu | Temporary Testing / Kind instance | 20 GB (`local-thin`) |
| **2050** | **cf-tunnel** | LXC | `192.168.0.50` | Debian 12 | Cloudflare Zero Trust Gateway | 4 GB (`local`) |
| **2051** | **adguard** | LXC | `192.168.0.51` | Debian 12 | Network-wide DNS & Ad Blocking | 1 GB (`local`) |

---

## 2. Cluster `ruth` (Management & Heavy Apps)
*Provisioned for 5 Nodes (IPs .20 - .24)*

| ID | Name | IP Address | OS | Description | Boot Disk (`local-thin`) | Data Disk (`data-storage`) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1020** | **ruth-01** | `192.168.0.20` | Ubuntu 24.04 | Master + Monitoring Brain | 16 GB | 20 GB |
| **1021** | **ruth-02** | `192.168.0.21` | Ubuntu 24.04 | Immich ML & DB Node | 16 GB | 40 GB |
| **1022** | **ruth-03** | `192.168.0.22` | Ubuntu 24.04 | Loki & Obsidian Sync Node | 16 GB | 20 GB |
| **1023** | **ruth-04** | `192.168.0.23` | Ubuntu 24.04 | Spare / Expansion Node | (TBD) | (TBD) |
| **1024** | **ruth-05** | `192.168.0.24` | Ubuntu 24.04 | Spare / Expansion Node | (TBD) | (TBD) |

---

## 3. Cluster `arr` (Media Stack)
*Provisioned for 5 Nodes (IPs .25 - .29)*

| ID | Name | IP Address | OS | Description | Boot Disk (`local-thin`) | Data Disk (`data-storage`) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1025** | **arr-01** | `192.168.0.25` | Ubuntu 24.04 | K8s Master (Media Fleet) | 12 GB | 10 GB |
| **1026** | **arr-02** | `192.168.0.26` | Ubuntu 24.04 | Media Processing Worker | 12 GB | 20 GB |
| **1027** | **arr-03** | `192.168.0.27` | Ubuntu 24.04 | Media Processing Worker | 12 GB | 20 GB |
| **1028** | **arr-04** | `192.168.0.28` | Ubuntu 24.04 | Spare / Expansion Node | (TBD) | (TBD) |
| **1029** | **arr-05** | `192.168.0.29` | Ubuntu 24.04 | Spare / Expansion Node | (TBD) | (TBD) |

---

## 💾 Storage Usage Summary
- **Total `local` (LXC/ISOs)**: ~15 GB Provisioned
- **Total `local-thin` (OS)**: ~112 GB Provisioned (Active VMs)
- **Total `data-storage` (Longhorn)**: ~130 GB Provisioned (Active K8s)
