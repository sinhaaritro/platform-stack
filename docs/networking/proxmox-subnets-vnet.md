# Proxmox VE SDN, VNets & Subnet Architecture

This document defines the internal network virtualization, subnet segmentation, Software Defined Networking (SDN) design, and IPAM (IP Address Management) scheme for the homelab infrastructure hosted on Proxmox VE.

---

## 📐 Proxmox Network Architecture Overview

The homelab uses a layered network model: physical network interfaces are aggregated into Linux Bridges, which are managed via **Proxmox SDN (Software Defined Networking)** into isolated **Virtual Networks (VNets)** and 802.1q **VLANs**.

```mermaid
flowchart TD
    subgraph PhysicalHardware["PHYSICAL HARDWARE LAYER"]
        NIC1["Physical NIC 1 (10GbE / 1GbE)"]
        NIC2["Physical NIC 2 (10GbE / 1GbE)"]
        Bond0["Linux Network Bond (bond0)<br/><i>Mode: LACP (802.3ad) / Active-Backup</i>"]

        NIC1 & NIC2 --> Bond0
    end

    subgraph HypervisorBridges["PROXMOX HYPERVISOR BRIDGES"]
        VMBR0["Linux Bridge: vmbr0<br/><i>(VLAN Aware: Enabled)</i>"]
        VMBR1["Linux Bridge: vmbr1<br/><i>(Private / Storage Network)</i>"]

        Bond0 --> VMBR0
    end

    subgraph ProxmoxSDN["PROXMOX SDN ZONES & VNETS"]
        ZoneVLAN["SDN Zone: ZoneVlan (802.1q Tagged)"]

        VMBR0 --> ZoneVLAN

        VNet10["VNet: vnet-mgmt (VLAN 10)<br/>192.168.10.0/24"]
        VNet20["VNet: vnet-dmz (VLAN 20)<br/>192.168.20.0/24"]
        VNet30["VNet: vnet-k8s-nodes (VLAN 30)<br/>192.168.30.0/24"]
        VNet40["VNet: vnet-services (VLAN 40)<br/>192.168.40.0/24"]
        VNet50["VNet: vnet-storage (VLAN 50)<br/>192.168.50.0/24"]
        VNet60["VNet: vnet-isolated (VLAN 60)<br/>10.60.0.0/24"]

        ZoneVLAN --> VNet10 & VNet20 & VNet30 & VNet40 & VNet50 & VNet60
    end

    subgraph Workloads["VIRTUAL WORKLOADS (VMs & LXCs)"]
        Workload10["Proxmox Hosts, IPMI, Router"]
        Workload20["cloudflared LXC, VPS Bridge Target"]
        Workload30["K8s Master & Worker VMs"]
        Workload40["Authentik, Immich, AdGuard, Arr-Stack"]
        Workload50["TrueNAS NFS, Longhorn Storage Sync"]
        Workload60["Untrusted IoT & Sandbox VMs"]

        VNet10 --> Workload10
        VNet20 --> Workload20
        VNet30 --> Workload30
        VNet40 --> Workload40
        VNet50 --> Workload50
        VNet60 --> Workload60
    end

    style PhysicalHardware fill:#f4f4f4,stroke:#333,stroke-width:1px
    style ProxmoxSDN fill:#eef6ff,stroke:#0066cc,stroke-width:1px
    style Workloads fill:#f0fff0,stroke:#00aa00,stroke-width:1px
```

---

## 🌐 Proxmox SDN Zones & VNets Configuration

Proxmox VE Software Defined Networking (SDN) allows central management of subnets, virtual interfaces, and routing across multiple hypervisor nodes (`asgard-atlas`, `asgard-prometheus`, `asgard-godzilla`).

### 1. Zone Definitions

| Zone Name | Zone Type | Underlying Bridge | MTU | Description |
| :--- | :--- | :--- | :--- | :--- |
| `ZoneVlan` | **VLAN** | `vmbr0` | 1500 | Main 802.1q VLAN tagged network for inter-subnet routing |
| `ZoneStorage` | **VLAN** | `vmbr1` | 9000 | Dedicated Jumbo Frame storage network for NFS & Longhorn |
| `ZoneSimple` | **Simple** | N/A | 1500 | Isolated single-node NAT network for ephemeral build runners |
| `ZoneOverlay` | **VXLAN / EVPN** | `vmbr0` | 1450 | Multi-node hypervisor overlay mesh for cross-site VM migration |

### 2. VNet & Subnet Mapping

```mermaid
flowchart TD
    SDN["⚙️ PROXMOX SDN CONTROLLER"]

    SDN --> V1 & V2 & V3 & V4 & V5

    V1["vnet-mgmt<br/><i>VLAN 10</i><br/>192.168.10.0/24"]
    V2["vnet-dmz<br/><i>VLAN 20</i><br/>192.168.20.0/24"]
    V3["vnet-k8s<br/><i>VLAN 30</i><br/>192.168.30.0/24"]
    V4["vnet-services<br/><i>VLAN 40</i><br/>192.168.40.0/24"]
    V5["vnet-storage<br/><i>VLAN 50</i><br/>192.168.50.0/24"]
```

---

## 📊 IP Address Management (IPAM) & Subnet Allocations

Below is the single source of truth for IPv4 address reservations across all Proxmox subnets and overlay networks.

| VNet Name | VLAN Tag | Subnet CIDR | Gateway | DHCP Range | Primary Purpose & Allocated Workloads |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `vnet-mgmt` | `10` | `192.168.10.0/24` | `192.168.10.1` | Static Only | Proxmox hypervisor nodes (`atlas`, `prometheus`, `godzilla`), IPMI/iDRAC, switches, core router. |
| `vnet-dmz` | `20` | `192.168.20.0/24` | `192.168.20.1` | `192.168.20.100-200` | Ingress proxies, `cloudflared` tunnel connectors, VPS NetBird bridge targets, Nginx reverse proxy. |
| `vnet-k8s-nodes`| `30` | `192.168.30.0/24` | `192.168.30.1` | Static Only | Kubernetes control plane and worker VMs (`orion-master-01`, `orion-worker-01..03`). |
| `vnet-services` | `40` | `192.168.40.0/24` | `192.168.40.1` | `192.168.40.100-250` | Core LXC containers and VMs: Authentik, AdGuard Home, Immich, Nextcloud, Arr-stack. |
| `vnet-storage` | `50` | `192.168.50.0/24` | None (No GW) | Static Only | High-performance storage network: TrueNAS NFS exports, Longhorn block sync, SeaweedFS traffic. |
| `vnet-isolated` | `60` | `10.60.0.0/24` | `10.60.0.1` | `10.60.0.100-200` | Untrusted IoT devices, isolated sandbox VMs, security test containers. |
| *(Overlay)* | N/A | `10.244.0.0/16` | Internal CNI | Pod IPs | Kubernetes Pod-to-Pod virtual container overlay network (managed by Cilium / Flannel CNI). |
| `samarkand` | Overlay | `100.64.0.0/16` | NetBird Signal | Dynamic CGNAT | NetBird Mesh VPN overlay for remote administrative devices and inter-site peer bridging. |

---

## 🔀 Inter-VNet Routing & Firewall Rules

All inter-VNet routing is handled at the Proxmox VE Gateway node / firewall level. The default security posture is **STRICT DENY** between internal VNets unless explicitly whitelisted.

```mermaid
flowchart LR
    subgraph ManagementZone["Management (VLAN 10)"]
        Admin["Admin Workstation / NetBird Mesh"]
    end

    subgraph DMZZone["DMZ / Ingress (VLAN 20)"]
        CFConnector["cloudflared LXC"]
        VPSBridge["VPS Bridge Peer"]
    end

    subgraph InternalServices["Services (VLAN 40)"]
        ImmichApp["Immich Server (Port 2283)"]
        JellyfinApp["Jellyfin Server (Port 8096)"]
        AuthentikApp["Authentik Auth (Port 9443)"]
    end

    subgraph StorageZone["Storage Network (VLAN 50)"]
        NAS["TrueNAS / Storage LXC"]
    end

    %% Allowed Routing Flows
    Admin -- "ALLOW: Full Management Access (SSH, PVE, K8s API)" --> DMZZone & InternalServices & StorageZone
    CFConnector -- "ALLOW: Port 2283 Only" --> ImmichApp
    VPSBridge -- "ALLOW: Port 8096 Only" --> JellyfinApp
    InternalServices -- "ALLOW: NFS / iSCSI Traffic Only" --> NAS

    %% Blocked Flows
    DMZZone -. "DENY: Direct Management Access" .-> ManagementZone
    StorageZone -. "DENY: No Internet Routing" .-> Internet["🌐 External Internet"]

    style ManagementZone fill:#eef6ff,stroke:#0066cc,stroke-width:1px
    style DMZZone fill:#fff0f0,stroke:#cc0000,stroke-width:1px
    style StorageZone fill:#f9f9f9,stroke:#666,stroke-width:1px
```

### Proxmox VE Firewall Policy Rules

1. **Management VNet (`VLAN 10`)**:
   - Outbound: Allowed to Internet (software updates, NTP).
   - Inbound: Restricted to local LAN and authorized NetBird VPN peers (`100.64.0.0/16`).
2. **DMZ VNet (`VLAN 20`)**:
   - Outbound: Allowed to Cloudflare Edge Network (QUIC/HTTPS outbound) and NetBird Relay servers.
   - Inbound from Internet: Strictly **0 open inbound ports** on home ISP connection.
   - Inbound to Internal VNets: Restricted to specific target IP and port mappings (e.g., `cloudflared` ➔ `192.168.40.50:2283`).
3. **Kubernetes Node VNet (`VLAN 30`)**:
   - Node-to-Node: Unrestricted inside `VLAN 30` for etcd, Kubelet, and BGP/overlay traffic.
   - Access to Storage: Allowed to `VLAN 50` for Longhorn volume sync and NFS mounts.
4. **Storage VNet (`VLAN 50`)**:
   - Routing: **Non-routable subnet** (no default gateway configured). Traffic cannot leave the local switch / bridge layer.

---

## 🌐 NetBird Mesh Integration with Proxmox VNets

NetBird operates as the primary administrative overlay network (`samarkand`). Rather than installing the NetBird client on every lightweight LXC or VM, designated **Proxmox Gateway Peers** act as **Subnet Routers**.

```mermaid
flowchart TD
    subgraph RemoteClient["Remote Admin Device"]
        Laptop["💻 Personal Laptop<br/><i>NetBird IP: 100.64.0.2</i>"]
    end

    Laptop -- "WireGuard Mesh Tunnel (UDP)" --> NetBirdGateway

    subgraph ProxmoxHost["Proxmox Host (asgard-atlas)"]
        NetBirdGateway["NetBird Gateway Peer<br/><i>NetBird IP: 100.64.0.5</i><br/><i>LAN IP: 192.168.10.5</i>"]

        subgraph LinuxKernel["Linux Kernel Routing"]
            IPForward["sysctl net.ipv4.ip_forward=1"]
            IPTables["iptables FORWARD Rules"]

            IPForward --- IPTables
        end

        NetBirdGateway --> LinuxKernel
    end

    LinuxKernel -- "Subnet Route: 192.168.10.0/24" --> ManagementVNet["vnet-mgmt (VLAN 10)"]
    LinuxKernel -- "Subnet Route: 192.168.30.0/24" --> K8sVNet["vnet-k8s-nodes (VLAN 30)"]
    LinuxKernel -- "Subnet Route: 192.168.40.0/24" --> ServicesVNet["vnet-services (VLAN 40)"]
```

### Subnet Routing Requirements

To enable seamless Layer 3 access into Proxmox subnets from remote NetBird clients:

1. **Kernel IP Forwarding**: Enable IPv4 forwarding on the Proxmox gateway node:
   ```bash
   sysctl -w net.ipv4.ip_forward=1
   echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-netbird.conf
   ```
2. **NetBird Route Advertisement**:
   ```bash
   netbird up --management-url https://netbird.domain.com --network-monitor --advertised-routes 192.168.10.0/24,192.168.30.0/24,192.168.40.0/24
   ```
3. **Access Control Lists (ACLs)**: In the NetBird management dashboard, create ACLs restricting subnet access to admin users only.

---

## 🔒 Best Practices Checklist

1. **Jumbo Frames for Storage:** Enable MTU `9000` on `vmbr1` and `vnet-storage` to maximize throughput and lower CPU overhead for TrueNAS NFS and Longhorn data replication.
2. **VLAN Awareness:** Always check `VLAN Aware: Yes` on `vmbr0` in Proxmox VE UI / OpenTofu configuration so VM interfaces can dynamically assign VLAN tags.
3. **Storage Network Isolation:** Do NOT assign a default gateway to `vnet-storage` (`192.168.50.0/24`). Storage traffic must remain strictly isolated on Layer 2 / internal switch fabric.
4. **Proxmox SDN Backup:** Export SDN configuration files (`/etc/pve/sdn/`) into OpenTofu / GitOps repo for automated environment rebuilds.
