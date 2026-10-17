# OpenTofu State — What Tofu Currently Manages

> [!NOTE]
> This is a temporary tracking page until the automated OpenTofu visualization is implemented.
> See Backlog: *OpenTofu Visualization*.

---

## Stack Overview

| Stack | Location | Provider | Purpose | State Backend |
| :--- | :--- | :--- | :--- | :--- |
| [`proxmox_atlas`](../../tofu/stacks/onprem/proxmox_atlas/) | On-Prem | Proxmox VE (bpg/proxmox) | VMs, LXC containers, OS images | Local (`terraform.tfstate`) |
| [`aws_kyoto`](../../tofu/stacks/cloud/aws_kyoto/) | Cloud | AWS | S3 buckets, DynamoDB tables, IAM (users, groups, policies) | Local (`terraform.tfstate`) |
| [`cloudflare_alexandria`](../../tofu/stacks/cloud/cloudflare_alexandria/) | Cloud | Cloudflare | DNS zones & records, Zero Trust tunnels, Access apps & policies, Cache rules, Redirect rules | Local (`terraform.tfstate`) |
| [`netbird_samarkand`](../../tofu/stacks/cloud/netbird_samarkand/) | Cloud | NetBird | Groups, Setup keys, Routes, Policies, Nameserver groups, Networks & resources | Local (`terraform.tfstate`) |

---

## Per-Stack Resource Breakdown

### `proxmox_atlas` — On-Prem Infrastructure

Provisions all physical infrastructure on the Proxmox host `atlas`.

| Resource Type | What It Does |
| :--- | :--- |
| **OS Images** | Builds cloud images locally via `image_builder` module, uploads to Proxmox datastore |
| **LXC Templates** | Downloads & customizes LXC templates via `lxc_template_customizer` module |
| **Virtual Machines** | Creates VMs from `schema.tfvars` via `proxmox_vm` module (Cloud-Init, disks, networking) |
| **LXC Containers** | Creates containers from `schema.tfvars` via `proxmox_lxc` module (templates, mount points, networking) |
| **Topology (nodes)** | Normalizes the `topology` key via the `topology` module — physical hosts, the cluster primary, and each node's `storage` (pools, data disks, exports, Samba) — into inventory host vars. Hosts are **inventory-only**: Tofu never creates/destroys them. |
| **Ansible Inventory** | Auto-generates `ansible/inventory.d/proxmox_atlas.yml` with host IPs, group memberships (`proxmox_node`, `proxmox_primary`, `vm`, `lxc`, app/tag groups), node **`storage`** host vars, guest **`nas_mounts`**, and the **`topology_clusters`** global. Built from the schema's **static IPs** (not created-guest output), so it renders **without creating guests** — `task tofu:apply:node` (`tofu apply -target=module.inventory`, or combined as `task apply:node`) is DR step 1. |

**Config files:** [`schema.tfvars`](../../tofu/stacks/onprem/proxmox_atlas/schema.tfvars) (`resources` + `topology`), [`schema.secret.tfvars`](../../tofu/stacks/onprem/proxmox_atlas/schema.secret.tfvars) (credentials — Vault encrypted)

**Resource planning:** [`resource-planning-atlas.md`](./resource-planning-atlas.md) — IP allocations, storage pools, cluster sizing, templates

---

### `aws_kyoto` — AWS Global Resources

Provisions AWS infrastructure for backup and state management.

| Resource Type | What It Does |
| :--- | :--- |
| **S3 Buckets** | Creates buckets with versioning, public access blocks, lifecycle rules |
| **DynamoDB Tables** | Creates tables (e.g., for Tofu state locking) |
| **IAM Policies** | Custom IAM policies for service accounts |
| **IAM Groups** | Groups with attached policies |
| **IAM Users** | Service users (e.g., `velero-backup`) with group memberships |
| **Access Keys** | Generates Velero access keys, outputs to `ansible/inventory.d/aws_kyoto.yml` |

**Config files:** [`schema.tfvars`](../../tofu/stacks/cloud/aws_kyoto/schema.tfvars) (resources), [`schema.secret.tfvars`](../../tofu/stacks/cloud/aws_kyoto/schema.secret.tfvars) (credentials — Vault encrypted)

---

### `cloudflare_alexandria` — DNS & Zero Trust

Manages all Cloudflare DNS, tunnels, and access control.

| Resource Type | What It Does |
| :--- | :--- |
| **Zones** | Manages DNS zones (with `prevent_destroy` lifecycle) |
| **DNS Records** | Creates explicit records + auto-generated tunnel CNAME records |
| **Zero Trust Tunnels** | Creates `cloudflared` tunnels with ingress rule configurations |
| **Access Applications** | Zero Trust access apps with session duration settings |
| **Access Policies** | Per-app policies (email/domain-based allow rules) |
| **Cache Rules** | Per-zone cache bypass/override rulesets |
| **Redirect Rules** | Account-level dynamic redirect rulesets (e.g., maintenance pages) |
| **Ansible Inventory** | Auto-generates `ansible/inventory.d/cloudflare_alexandria.yml` with tunnel tokens, IDs, zone IDs |

**Config files:** [`schema.tfvars`](../../tofu/stacks/cloud/cloudflare_alexandria/schema.tfvars) (resources), [`schema.secret.tfvars`](../../tofu/stacks/cloud/cloudflare_alexandria/schema.secret.tfvars) (credentials — Vault encrypted)

---

### `netbird_samarkand` — Mesh VPN

Manages the NetBird mesh VPN overlay network.

| Resource Type | What It Does |
| :--- | :--- |
| **Groups** | Peer groups for policy targeting |
| **Setup Keys** | Enrollment keys (ephemeral, usage-limited) for auto-joining peers |
| **Routes** | Network routes with masquerading and access control |
| **Policies** | Firewall policies with bidirectional rules (sources → destinations) |
| **Nameserver Groups** | DNS resolution configuration for VPN peers |
| **Networks** | Virtual network definitions |
| **Network Routers** | Routers linking peer groups to networks |
| **Network Resources** | Named resources (IPs/CIDRs) exposed via networks |
| **Ansible Inventory** | Auto-generates `ansible/inventory.d/netbird_samarkand.yml` with setup keys |

**Config files:** [`schema.tfvars`](../../tofu/stacks/cloud/netbird_samarkand/schema.tfvars) (resources), [`schema.secret.tfvars`](../../tofu/stacks/cloud/netbird_samarkand/schema.secret.tfvars) (credentials — Vault encrypted)

---

## Cross-Stack Integration

All four stacks share a common pattern: **Tofu outputs feed Ansible inputs**.

```
proxmox_atlas  ──→  ansible/inventory.d/proxmox_atlas.yml          (host IPs, groups, node storage, guest nas_mounts)
aws_kyoto      ──→  ansible/inventory.d/aws_kyoto.yml              (Velero access keys)
cloudflare     ──→  ansible/inventory.d/cloudflare_alexandria.yml   (tunnel tokens, zone IDs)
netbird        ──→  ansible/inventory.d/netbird_samarkand.yml       (setup keys)
```

## File Layout

```
tofu/
├── modules/                        # Shared reusable modules
│   ├── ansible_inventory/          # Generates Ansible YAML from host lists
│   ├── image_builder/              # Builds & customizes OS images
│   ├── lxc_template_customizer/    # Downloads & customizes LXC templates
│   ├── proxmox_lxc/                # Creates Proxmox LXC containers
│   ├── proxmox_vm/                 # Creates Proxmox VMs
│   ├── resource_normalizer/        # Normalizes tfvars into flat resource maps (VMs/LXCs)
│   └── topology/                   # Normalizes the `topology` key (nodes/clusters) into inventory host vars
└── stacks/
    ├── onprem/
    │   └── proxmox_atlas/          # On-prem VM/LXC provisioning
    └── cloud/
        ├── aws_kyoto/              # AWS S3, DynamoDB, IAM
        ├── cloudflare_alexandria/  # DNS, Tunnels, Zero Trust
        └── netbird_samarkand/      # Mesh VPN overlay
```
