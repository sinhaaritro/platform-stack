# Homelab Remote Access & Networking Architecture

This specification details the hybrid remote access architecture for the homelab environment. It is designed to bypass **ISP CGNAT (Carrier-Grade NAT)** and **Dynamic IPv4 Addresses** without port forwarding, while catering to different client security constraints (e.g., restricted office PCs, battery-sensitive mobile background sync, and heavy media streaming).

---

## 📐 Overall Architecture Overview

```mermaid
flowchart TD
    Internet["🌐 INTERNET ACCESS"] --> Zone1 & Zone2 & Zone3 & Zone4

    subgraph ExternalAccess["Remote Access Methods"]
        Zone1["Zone 1: Cloudflare Tunnel<br/><i>(Mobile & Web Apps)</i>"]
        Zone2["Zone 2: VPS + NetBird Bridge<br/><i>(Heavy Video Streaming)</i>"]
        Zone3["Zone 3: NetBird Mesh VPN<br/><i>(Dev & Admin Access)</i>"]
        Zone4["Zone 4: NetBird WASM Browser<br/><i>(Restricted Work PCs)</i>"]
    end

    Zone1 -- "cloudflared" --> Homelab
    Zone2 -- "Caddy/Nginx + NetBird" --> Homelab
    Zone3 -- "WireGuard Mesh" --> Homelab
    Zone4 -- "WebAssembly" --> Homelab

    subgraph Homelab["HOMELAB ENVIRONMENT (Behind CGNAT)"]
        Gateway["Proxmox VE Host / Gateway Peer"]
        Immich["Immich Server"]
        Jellyfin["Jellyfin Media Server"]
        Workloads["LXC Containers & VMs"]

        Gateway --> Immich & Jellyfin & Workloads
    end
```

---

## 🟢 Zone 1: Public Web Services & Mobile Sync (Cloudflare Tunnel)

### 🎯 Purpose & Scope
Designed for HTTP/HTTPS web applications and mobile background sync (e.g., **Immich**, **Nextcloud**). Provides continuous connectivity without requiring client VPN software, avoiding mobile battery drain and background process termination by mobile operating systems.

### 🏗️ Technical Diagram

```mermaid
flowchart TD
    subgraph ClientLayer["CLIENT LAYER (Remote)"]
        Mobile["📱 Mobile Phone / iPad<br/>- Immich App<br/>- https://immich.domain.com"]
        Browser["💻 Public Web Browser<br/>- Chrome / Safari<br/>- 0 Client Software"]
    end

    ClientLayer -- "HTTPS (Port 443)" --> EdgeLayer

    subgraph EdgeLayer["EDGE ACCESS LAYER"]
        CFEdge["🛡️ Cloudflare Edge Network<br/>- Anycast DNS / Global SSL / DDoS Protection<br/>- Cache Rule: BYPASS CACHE for immich.domain.com"]
    end

    EdgeLayer -- "Outbound Encrypted Tunnel<br/>(QUIC / TLS via cloudflared)" --> HomelabLayer

    subgraph HomelabLayer["HOMELAB INTERNAL LAYER (Behind CGNAT)"]
        LXC["Local Server / LXC"]
        Daemon["cloudflared Daemon"]
        Immich["Immich Server Container<br/><i>(Local IP: http://192.168.1.X:2283)</i>"]

        LXC --- Daemon
        Daemon --> Immich
    end
```

### ⚙️ Technical Specifications
* **Protocol:** HTTPS (Port 443) over QUIC/TLS outbound tunnel.
* **Client Requirements:** 0 Software / Native Mobile App.
* **CGNAT Handling:** Solved via outbound tunnel initiated from inside the homelab to Cloudflare's edge.
* **Configuration Requirement:** Create a Cloudflare **Cache Bypass Rule** (`immich.domain.com`) to avoid caching media streams on Cloudflare CDN edge nodes.

---

## 🟡 Zone 2: Heavy Media & Video Streaming (VPS + NetBird Bridge)

### 🎯 Purpose & Scope
Designed for high-bandwidth video streaming (e.g., **Jellyfin**, **Plex**). Completely bypasses Cloudflare’s CDN Terms of Service and bandwidth caps while giving external clients (Smart TVs, family/friends) direct public HTTPS access without requiring VPN software.

### 🏗️ Technical Diagram

```mermaid
flowchart TD
    subgraph ClientLayer["CLIENT LAYER (Remote)"]
        SmartTV["📺 Smart TV / Firestick<br/>- Jellyfin Native App"]
        Friends["👥 External Friends & Family<br/>- Standard Web Browser"]
    end

    ClientLayer -- "Standard Public HTTPS (Port 443)" --> VPSLayer

    subgraph VPSLayer["VPS EDGE BRIDGE LAYER"]
        VPS["☁️ Cheap VPS / Oracle Cloud Free Tier<br/><i>Public IP: 1.2.3.4</i>"]
        Proxy["Caddy / Nginx Reverse Proxy"]
        VPSPeer["NetBird Client Node<br/><i>Mesh IP: 100.64.0.10</i>"]

        VPS --- Proxy
        Proxy --- VPSPeer
    end

    VPSLayer -- "Private Encrypted WireGuard Tunnel<br/>(P2P / STUN Relay over NetBird)" --> HomelabLayer

    subgraph HomelabLayer["HOMELAB INTERNAL LAYER (Behind CGNAT)"]
        HomelabPeer["NetBird Client Node<br/><i>Mesh IP: 100.64.0.5</i>"]
        Jellyfin["Jellyfin Media Server<br/><i>Local IP: http://192.168.1.Y:8096</i>"]

        HomelabPeer --> Jellyfin
    end
```

### ⚙️ Technical Specifications
* **Traffic Flow:** Client `(Public HTTPS)` ➔ VPS `(Proxy)` ➔ NetBird Mesh Tunnel ➔ Homelab Jellyfin Server.
* **Client Requirements:** 0 Software installed.
* **CGNAT Handling:** The homelab connects outbound to the NetBird control plane and establishes a WireGuard bridge to the VPS.
* **Bandwidth Cap:** Uncapped (limited only by home ISP upload speed and VPS bandwidth quota).

---

## 🔵 Zone 3: Full Network Administration & Dev (NetBird Mesh VPN)

### 🎯 Purpose & Scope
Designed for administrative access (e.g., **Proxmox VE UI**, **Kubernetes API/kubectl**, **Native SSH/RDP**, **NFS/SMB shares**) from owned personal devices (laptops, personal phones). Provides direct Layer 3 network-level access inside the homelab.

### 🏗️ Technical Diagram

```mermaid
flowchart TD
    subgraph ClientLayer["CLIENT LAYER (Personal Devices)"]
        PersonalLaptop["💻 Personal Laptop / Mobile Device<br/>- NetBird Client App Running<br/>- Mesh IP: 100.64.0.2"]
    end

    ClientLayer -- "Direct Peer-to-Peer WireGuard Tunnel<br/>(STUN/TURN NAT Traversal)" --> GatewayNode

    subgraph HomelabLayer["HOMELAB INTERNAL LAYER (Behind CGNAT)"]
        GatewayNode["🖥️ Proxmox VE Host / Subnet Router Gateway<br/>- NetBird Client Node (Mesh IP: 100.64.0.5)<br/>- Enabled Route: 192.168.1.0/24<br/>- IP Forwarding: sysctl net.ipv4.ip_forward=1"]

        subgraph SubnetRouting["SUBNET ROUTED ACCESS"]
            PVE["Proxmox VE UI<br/><i>192.168.1.100:8006</i>"]
            K8sAPI["Kubernetes API<br/><i>192.168.1.150:6443</i>"]
            LXCs["Linux LXCs<br/><i>192.168.1.X:22</i>"]
            VMs["Windows VMs<br/><i>192.168.1.Z:3389</i>"]
        end

        GatewayNode --> PVE & K8sAPI & LXCs & VMs
    end
```

### ⚙️ Technical Specifications
* **Protocol:** WireGuard P2P (UDP) with STUN/TURN relay fallback for CGNAT traversal.
* **Client Requirements:** NetBird Client Application installed.
* **Subnet Routing:** Active on the gateway node to route all local LAN IPs (`192.168.1.0/24`) over the virtual interface without requiring client installation inside individual VMs/containers.

---

## 🔴 Zone 4: Clientless Browser Access for Restricted PCs (NetBird WASM)

### 🎯 Purpose & Scope
Designed for corporate/office machines or restricted computers where software installation, elevated privileges, and VPN clients are blocked by IT policy. Allows in-browser interactive **SSH terminals** and **Windows Remote Desktops (RDP)**.

### 🏗️ Technical Diagram

```mermaid
flowchart TD
    subgraph ClientLayer["RESTRICTED CLIENT LAYER (Office PC)"]
        OfficePC["🔒 Locked-Down Work Laptop / Unknown PC<br/>- No Admin Privileges (No VPN/SSH Client)<br/>- Standard Browser (Chrome/Edge/Firefox)"]
    end

    OfficePC -- "HTTPS / WebAssembly Sandbox<br/>URL: https://app.netbird.io" --> NetBirdControl

    subgraph NetBirdControl["NETBIRD CONTROL PLANE"]
        ControlServer["⚡ NetBird Signal / Dashboard Server<br/>- Serves WASM WireGuard & IronRDP Renderer"]
    end

    NetBirdControl -- "Ephemeral Session<br/>(WASM P2P Tunnel)" --> TargetPeer

    subgraph HomelabLayer["HOMELAB INTERNAL LAYER (Behind CGNAT)"]
        TargetPeer["🎯 Target Homelab Peer / Server Node<br/>- NetBird Client Agent Active<br/>- Embedded NetBird SSH Server Enabled<br/>- Local RDP Service Active (Windows Port 3389)"]
    end
```

### ⚙️ Technical Specifications
* **Protocol:** In-Browser WebAssembly (WASM) running an ephemeral `wireguard-go` peer and `IronRDP` canvas renderer.
* **Client Requirements:** Standard web browser only (0 local software installation).
* **Access Method:** Log in to `app.netbird.io` ➔ Navigate to **Peers** ➔ Click **Connect via SSH** or **Connect via RDP**.

---

## 📊 Feature Comparison & Decision Matrix

| Metric / Feature | **Zone 1: CF Tunnel** | **Zone 2: VPS Bridge** | **Zone 3: NetBird Mesh** | **Zone 4: NetBird WASM** |
| :--- | :--- | :--- | :--- | :--- |
| **Primary Use Case** | Immich / Mobile Apps | Jellyfin / 4K Video | Admin / Dev / K8s / Subnet | Work PC Terminal / RDP |
| **Client Installation** | None Required | None Required | NetBird Client App | None (Browser WASM) |
| **CGNAT Handling** | Outbound HTTP Tunnel | VPS Reverse Proxy | STUN/TURN WireGuard | STUN/TURN WireGuard |
| **Public Exposure** | Exposed via Domain | Exposed via Domain | Completely Private | Private via Dashboard |
| **Supported Traffic** | HTTP / HTTPS | HTTP / HTTPS | All L3/L4 Traffic | Interactive SSH & RDP |
| **Bandwidth Limit** | CDN Upload Limits | VPS Allocation Limit | ISP Upload Unlimited | ISP Upload Unlimited |

---

## 🔒 Security Best Practices Checklist

1. **Cloudflare Cache Bypass:** Always create Cache Bypass rules for self-hosted apps handling private media (e.g., Immich, Nextcloud) to prevent private data caching on edge servers.
2. **NetBird Subnet Router Isolation:** Enable Linux Kernel IP forwarding (`sysctl net.ipv4.ip_forward=1`) strictly on the designated gateway peer. Use NetBird Access Control Lists (ACLs) to restrict subnet route privileges to admin users.
3. **VPS Security Hardening:** For Zone 2, configure firewall rules on the VPS (`ufw`) allowing incoming ports `80`/`443` only, blocking all internal management ports from public exposure.
4. **NetBird SSH Authentication:** Require explicit user authorization in the NetBird Control Plane prior to initiating Zone 4 WASM browser sessions.