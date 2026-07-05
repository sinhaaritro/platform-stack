
# Naming Conventions

This document is the single source of truth for naming all resources within the homelab infrastructure. Adhering to these conventions is crucial for maintaining a clean, manageable, and automation-friendly environment based on GitOps principles.

## Table of Contents

1.  [Core Philosophy](#1-core-philosophy)
2.  [The Naming Strategy: Thematic vs. Descriptive](#2-the-naming-strategy-thematic-vs-descriptive)
3.  [Approved Themes & Codenames](#3-approved-themes--codenames)
4.  [Identity & Access Management](#4-identity--access-management)
5.  [Physical & Virtual Infrastructure](#5-physical--virtual-infrastructure)
6.  [Networking & Connectivity](#6-networking--connectivity)
7.  [Kubernetes Cluster Resources](#7-kubernetes-cluster-resources)
8.  [Home Automation & IoT](#8-home-automation--iot)
9.  [Cloud & External Services](#9-cloud--external-services)
10. [Automation & Code (GitOps)](#10-automation--code-gitops)
11. [Observability & Monitoring](#11-observability--monitoring)
12. [Metadata & Process](#12-metadata--process)

---

## 1. Core Philosophy

-   **Clarity over Brevity:** Names should be easy to understand for all users.
-   **Logical Hierarchy:** It should be possible to guess the name and function of a related resource.
-   **Automation-Friendly:** Both `kebab-case` and `snake_case` are acceptable depending on the context. Use `kebab-case` for Kubernetes, DNS, hostnames, and URLs (where underscores are illegal). Use `snake_case` for Ansible variables/groups and OpenTofu variables/modules (where hyphens are illegal or cause templating issues).
-   **Clarity through Documentation:** All chosen thematic names **must** be documented in the tables below before being used.

---

## 2. The Naming Strategy: Thematic vs. Descriptive

We use a hybrid approach to get the best of both worlds: personality and clarity.

1.  **Thematic Names:** Used for unique, low-count, foundational resources (e.g., physical servers, Kubernetes clusters, user groups). These names add character and are easy to remember.
2.  **Descriptive Names:** Used for high-count, functional resources (e.g., cameras, smart plugs, most VMs, Kubernetes deployments). These names provide immediate clarity and are infinitely scalable.

---

## 3. Approved Themes & Codenames

Themes are not limited to ancient mythology. Names from anime, sci-fi, video games, and literature are highly encouraged.

### Theme Table: Locations (Physical & Cloud)
*   **Purpose:** Identifies a distinct physical site or cloud environment.
*   **Source Ideas:** Mythological Realms, Legendary Cities, Fictional Planets.

| Codename      | Source / Universe | Description                    |
| :------------ | :---------------- | :----------------------------- |
| `asgard`      | Norse Mythology   | Main homelab location          |
| `babylon`     | History           | AWS cloud environment          |
| `wano`        | One Piece         | Second homelab location        |
| `coruscant`   | Star Wars         | Oracle Cloud environment       |
| `olympus`     | Greek Mythology   | Primary cloud / management region |
| `delphi`      | Greek Mythology   | Monitoring or staging location |
| `elysium`     | Greek Mythology   | Backup or disaster recovery location |
| *(add more)*  |                   |                                |

### Theme Table: Physical Hosts (Servers, NAS)
*   **Purpose:** The bare-metal machines that are the foundation of a location.
*   **Source Ideas:** Titans, Mythical Creatures, Legendary Beings, Giant Robots/Kaiju.

| Codename      | Source / Universe | Host Machine                   |
| :------------ | :---------------- | :----------------------------- |
| `atlas`       | Greek Mythology   | First Proxmox host in `asgard` |
| `prometheus`  | Greek Mythology   | Second Proxmox host in `asgard`|
| `zunesha`     | One Piece         | TrueNAS server in `wano`       |
| `godzilla`    | Toho              | Proxmox host with a GPU        |
| `yggdrasil`   | Norse Mythology   | Hypervisor host supporting multiple VMs |
| `sleipnir`    | Norse Mythology   | High-speed network node / gateway host |
| `fenrir`      | Norse Mythology   | High-performance compute / GPU node |
| `jormungandr` | Norse Mythology   | Large-capacity storage / backup server |
| *(add more)*  |                   |                                |

### Other Approved Themes

| Category                | Theme Suggestions                               | Example          |
| :---------------------- | :---------------------------------------------- | :--------------- |
| **Kubernetes Clusters** | Constellations, Sci-Fi Fleets                   | `orion`          |
| **Kubernetes Namespaces** | Deities, Starship Classes, Elements             | `zeus-ns`        |
| **Networking (VLANs)**  | Mythical Rivers, Sci-Fi Gates/Relays            | `styx-vlan`      |

### Theme Table: Kubernetes Clusters
*   **Purpose:** Names logical clusters running containerized workloads.
*   **Source Ideas:** Constellations, Sci-Fi Fleets (must not overlap with Hardware Node themes).

| Codename      | Source / Universe | Description / Role             |
| :------------ | :---------------- | :----------------------------- |
| `orion`       | Constellations    | Primary development cluster    |
| `andromeda`   | Constellations    | Production cluster             |
| `pegasus`     | Constellations    | Staging or auxiliary cluster   |
| `enterprise`  | Star Trek         | Multi-tenant cluster           |
| *(add more)*  |                   |                                |

### Theme Table: Kubernetes Namespaces
*   **Purpose:** Isolates workloads logically inside a cluster.
*   **Source Ideas:** Deities, Starship Classes, Elements.

| Codename      | Source / Universe | Description / Role             |
| :------------ | :---------------- | :----------------------------- |
| `zeus-ns`     | Greek Deities     | Core networking & ingress      |
| `freya-ns`    | Norse Deities     | Media, storage & streaming     |
| `apollo-ns`   | Greek Deities     | Observability & monitoring     |
| `defiant-ns`  | Star Trek         | Isolated or DMZ security       |
| *(add more)*  |                   |                                |

### Theme Table: Networking (VLANs)
*   **Purpose:** Segments network traffic physically or virtually.
*   **Source Ideas:** Mythical Rivers, Sci-Fi Gates/Relays.

| Codename       | Source / Universe | Description / Role             |
| :------------- | :---------------- | :----------------------------- |
| `styx-vlan`    | Greek Mythology   | Isolated database/backend VLAN |
| `bifrost-vlan` | Norse Mythology   | Primary transit/gateway VLAN   |
| `lethe-vlan`   | Greek Mythology   | Untrusted guest/IoT VLAN       |
| `rubicon-vlan` | History / Sci-Fi  | DMZ/ingress entry network VLAN |
| *(add more)*   |                   |                                |

---

## 4. Identity & Access Management

#### 4.1. User Accounts
*Naming for human users and shared/dummy accounts.*
-   **Human:** `{username}` (e.g., `alex`).
-   **Shared/Admin:** Thematic names (`hermes`, `thoth`).

#### 4.2. User Groups
*Groups that define permission levels and roles.*
-   **Pattern:** `{thematic-name}-group`
-   **Theme:** Mythological Factions (`olympians-group`).

#### 4.3. Service Accounts
*Non-human accounts used by applications and automation scripts.*
-   **Pattern:** `sa-{service/purpose}`
-   **Example:** `sa-github-runner`, `sa-backup-script`.

---

## 5. Physical & Virtual Infrastructure

#### 5.1. Hardware Assets & Proxmox Nodes
*The physical bare-metal servers, GPUs, network cards, and the Proxmox VE hypervisor running on them.*
-   **Pattern:** `{location-codename}-{host-codename}`
-   **Example:** `asgard-atlas`

#### 5.2. Virtual Machines (VMs) & LXC Containers
*All virtual machines and LXC containers, including Kubernetes nodes, utility servers, and Home Assistant instances.*
*VMs and LXC containers are mobile — they can migrate between hardware nodes and locations during failover. Therefore, names must be **location-agnostic**. Track location via labels/tags (see §12.4).*
-   **K8s Node VMs:** `{cluster-name}-{role}-{instance}`
    -   **Examples:** `ruth-master-01`, `ruth-worker-02`, `orion-worker-01`
-   **Standalone VMs & LXC Containers:** `{env}-{purpose}-{instance}`
    -   **Notes:** `env` is omitted for `prod`. `instance` is `01`, `02`, etc. LXC containers are always treated as standalone hosts.
    -   **Examples:** `web-server-01`, `dev-authentik-01`, `adguard-01`

#### 5.3. VM Templates
*The base 'golden images' used by OpenTofu or Proxmox to provision new VMs.*
-   **Pattern:** `tpl-{os-name}-{os-version}-{YYYY-MM-DD}`
-   **Example:** `tpl-ubuntu-server-2404-2025-09-28`

#### 5.4. Storage Pools
*High-level storage aggregates, like ZFS pools on Proxmox or TrueNAS.*
-   **Pattern:** `{location-codename}-{host-codename}-{thematic-name}`
-   **Theme:** Geological Terms (`bedrock`, `strata`).
-   **Example:** `asgard-atlas-bedrock`

#### 5.5. Storage Datasets & Shares
*Specific datasets, folders, or network shares (NFS/SMB) created within a storage pool.*
-   **Pattern:** `{pool-name}-{purpose}`
-   **Examples:** `bedrock-k8s-volumes`, `bedrock-media-tv`, `bedrock-backups`

#### 5.6. Backup Jobs & Snapshots
*Naming for backup tasks, snapshot schedules, and the resulting data artifacts.*
-   **Jobs:** `{resource-type}-{resource-name}-{frequency}`
    -   **Example:** `vm-ruth-master-01-daily`
-   **Snapshots:** `{resource-name}-{timestamp}` (often automated).
    -   **Example:** `ruth-master-01-20250928T180000Z`


---

## 6. Networking & Connectivity

#### 6.1. Networks (VLANs)
*Virtual LANs, bridges, and virtual switches used to segment network traffic.*
-   **Pattern:** `{thematic-name}-{purpose}-vlan`
-   **Theme:** Mythical Rivers (`styx`, `bifrost`).
-   **Example:** `styx-servers-vlan`, `bifrost-iot-vlan`

#### 6.2. Hostnames & FQDNs
*Fully Qualified Domain Names for all physical and virtual machines.*
-   **Internal FQDNs:** Used inside the local network for routing, SSH, or RDP.
    -   *Fixed Physical Hosts:* `{host-codename}.{location}.{domain}` (e.g., `atlas.olympus.example.com`)
    -   *Mobile VMs & LXCs:* `{hostname}.{location}.{domain}` (e.g., `k8s-node-01.olympus.example.com`)
-   **External FQDNs (Public SSH/RDP):** Used when direct host access is exposed to the internet.
    -   *Obfuscation Rule:* Never use the internal hostname or location in public DNS. Use a generic, randomized, or abstract alias to prevent mapping/probing of your infrastructure.
    -   *Example:* Exposing `k8s-node-01` via `bastion-alpha.your.domain` instead of exposing the cluster name.

#### 6.3. IP Address Reservations
*A scheme for assigning static IPs or managing DHCP reservations for stable network addresses.*
-   **Pattern:** Use a structured description field in your DHCP server: `{hostname} - {owner}`
-   **Example:** `ruth-master-01 - Alex`

#### 6.4. DNS Records
*The `A`, `CNAME`, `TXT`, and other records managed in your domain.*
-   **Internal DNS Records:** Map services directly using their functional names.
    -   *Pattern:* `{service-name}.{location}.{domain}` (e.g., `grafana.olympus.example.com`)
-   **Public DNS Records (Obfuscated):** Used for services exposed externally via Cloudflare Tunnels.
    -   *Obfuscation Rule:* Publicly resolved endpoints should mask specific product names, clusters, or hosting nodes. Use generic role names or abstract codenames.
    -   *Generic Role Name Example:* `dash.your.domain` (masks that it is Grafana running on cluster `ruth`)
    -   *Abstract Codename Example:* `solaris.your.domain` (fully obfuscates access to a Proxmox Web UI or a critical service)

#### 6.5. Cloudflare Tunnels
*The specific tunnel configurations providing secure, external access to internal services.*
-   **Pattern:** `{location-codename}-tunnel`
-   **Example:** `asgard-tunnel`


---

## 7. Kubernetes Cluster Resources

#### 7.1. Clusters
*The Kubernetes clusters themselves, which orchestrate containerized applications.*
*Clusters are logical — they can span hardware nodes and even locations. Names must be **location-agnostic**.*
-   **Pattern:** `{thematic-name}`
-   **Theme:** Constellations, Sci-Fi Fleets (must **not** overlap with Hardware Node themes).
-   **Examples:** `ruth`, `orion`, `andromeda`

#### 7.2. Nodes
*The worker and control-plane VMs that form the cluster.*
-   The Kubernetes node name **must** match the VM hostname (see §5.2).
-   **Pattern:** `{cluster-name}-{role}-{instance}`
-   **Examples:** `ruth-master-01`, `ruth-worker-01`, `orion-worker-03`

#### 7.3. Namespaces
*Virtual clusters within Kubernetes used to separate applications and environments.*
-   **Pattern:** `{thematic-name}-ns`
-   **Theme:** Deities.
-   **Example:** `zeus-ns` (networking), `freya-ns` (media).

#### 7.4. Workloads, Services, Ingresses, ConfigMaps, Secrets
*All the core Kubernetes objects that define a running application.*
-   **Helm Chart Apps:** Names are auto-generated by the chart via Kustomize `helmCharts`. The chart controls the naming (typically `{releaseName}-{component}`). Do not override these.
-   **Hand-written Manifests (Docker→K8s):** When converting a Docker app to a Kubernetes manifest, use the following pattern:
    -   **Pattern:** `{app-name}-{resource-type}`
    -   **Examples:** `jellyfin-deployment`, `jellyfin-service`, `jellyfin-ingressroute`
    -   **Labels:** Use `app: {app-name}` as the primary selector label.

#### 7.5. Persistent Volume Claims (PVCs)
*Requests for storage made by applications running in the cluster.*
-   **Pattern:** `{app-name}-{purpose}`
-   **Examples:** `immich-library`, `immich-db-backup`, `obsidian-config`, `qbittorrent-downloads`


---

## 8. Home Automation & IoT

#### 8.1. Home Assistant Instances
*The primary controller application (as a VM or container) for home automation.*
-   **Pattern:** `{location-codename}-{thematic-name}-ha`
-   **Theme:** Mythical Sprites (`pixie`, `gnome`).
-   **Example:** `asgard-pixie-ha`

#### 8.2. IoT Devices (Physical Asset Tag)
*A unique physical identifier/label for inventory tracking of devices like cameras and sensors.*
-   **Pattern:** `IOT-{TYPE}-{ID}` (e.g., `IOT-CAM-001`).

#### 8.3. IoT Device Hostnames
*The network name for each device (e.g., cameras, sensors, smart plugs).*
-   **Pattern:** `{type}-{room}-{position}`
-   **Examples:** `cam-livingroom-ceiling`, `plug-office-desk`

#### 8.4. Home Assistant Entities
*The entity IDs within Home Assistant that represent device functions (e.g., `light.living_room_main`).*
-   **Pattern:** `{domain}.{device_hostname}`. Clean up after discovery.
-   **Example:** `switch.plug_office_desk`

#### 8.5. Integrations
*Naming for configured integrations like Zigbee2MQTT, Z-Wave JS, or ESPHome.*
-   **Pattern:** `{protocol/brand}-{purpose}`
-   **Example:** `zwave-main-controller`, `esphome-devices`

#### 8.6. Automations, Scripts & Scenes
*The logic created within Home Assistant to automate tasks.*
-   **Pattern:** `[{Room/Area}] - {Description}`
-   **Example:** `[Living Room] - Turn on lights at sunset`.


---

## 9. Cloud & External Services

#### 9.1. Cloud VMs
*Virtual machines running on AWS, Oracle, or other cloud providers.*
-   Follows the same pattern as local VMs.
-   **Example:** `babylon-web-server-01`

#### 9.2. Cloud Storage
*Storage buckets and volumes in the cloud (e.g., AWS S3, EBS).*
-   **Pattern:** `{org/user}-{location}-{purpose}-storage`
-   **Example:** `homelab-babylon-backups-storage`


---

## 10. Automation & Code (GitOps)

#### 10.1. Git Repositories
*The naming of the Git repos themselves that hold our configurations.*
-   **Pattern:** `{purpose}-{tech}`
-   **Examples:** `homelab-gitops-kubernetes`, `homelab-automation-ansible`

#### 10.2. Git Branches & Tags
*A strategy for branch naming and versioning infrastructure code.*
-   **Branches:** `main`, `develop`, `feat/GH-12-add-thing`.
-   **Tags (Releases):** `v{semver}` (e.g., `v1.0.0`).

#### 10.3. Container Image Tagging
*A policy for how you tag Docker/OCI images.*
-   **Pattern:** `{git-branch}` for dev images, `v{semver}` for release images.
-   **Examples:** `main`, `feat-add-grafana`, `v1.2.3`.

#### 10.4. Directory Structure
*The folder layout within the GitOps repository is a form of convention.*
-   Use a logical structure, e.g., `/kubernetes/clusters/{cluster}/{app-name}`.

#### 10.5. Commit Messages
*A standardized format for Git commit messages to ensure a clean, readable history.*
-   Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.

#### 10.6. Ansible, OpenTofu & Taskfile
*Naming for the components of our automation tools (roles, modules, tasks).*
-   **Ansible Roles:** `k8s-node`.
-   **OpenTofu Modules:** `proxmox-vm`.
-   **Taskfile Targets:** `task setup:vm`.


---

## 11. Observability & Monitoring

#### 11.1. Grafana Dashboards
*How we name and organize dashboards for visualizing metrics.*
-   **Pattern:** `[{Area}] - {Specifics}`
-   **Example:** `[Kubernetes] - Cluster Overview`.

#### 11.2. Prometheus Metrics & Labels
*A consistent scheme for custom metrics to simplify querying and alerting.*
-   Follow the `snake_case` standard for metrics and labels.

#### 11.3. Alerting Rules
*Names for the specific alerts defined in Prometheus/Alertmanager.*
-   **Pattern:** `[{Severity}] - {Service} - {Alert Condition}`
-   **Example:** `[Critical] - Proxmox - Host Down`

---

## 12. Metadata & Process (Cross-Cutting)

#### 12.1. Environments
*A clear name for each stage of deployment (`prod`, `dev`, etc.).*
-   `prod` (default, omitted from names), `dev`, `staging`, `mgmt`.

#### 12.2. Tenants / User Prefixes
*A prefix for resources belonging to a specific user to prevent conflicts.*
-   **Example:** `alex-dev-namespace`, `bob-test-vm-01`.

#### 12.3. Application Stacks
*A name for a collection of related services (e.g., the 'arr-stack').*
-   Referred to by its primary component or Helm release name.
-   **Example:** The "arr stack", the "monitoring stack".

#### 12.4. Universal Tagging & Labeling Scheme
*A consistent set of key-value tags to be applied to all resources for filtering and automation.*
-   All resources **must** be tagged/labeled with:
    -   `managed-by`: `ansible`, `terraform`, `argocd`.
    -   `environment`: `prod`, `dev`.
    -   `owner`: `alex`, `valkyries-group`.
    -   `repo`: The Git repository URL that defines the resource.