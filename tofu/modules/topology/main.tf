# -----------------------------------------------------------------------------
# TOPOLOGY NORMALIZATION
# -----------------------------------------------------------------------------
# Normalizes the physical layer (clusters + nodes) into:
#   - final_cluster_list : scaffold map of clusters (primary/members + concerns)
#   - final_node_list    : inventory-compatible host objects (one per node),
#                          each carrying its per-concern config as host vars
#                          (storage now; vlan/firewall/replication later).
#
# There is no cluster-level storage and no global NAS contract: each node owns
# its own `storage`, and consumers reference a (provider, share) pair which the
# nas_client role resolves at run time.
#
# Hosts are INVENTORY-ONLY: OpenTofu never creates or destroys them.
# -----------------------------------------------------------------------------

locals {
  clusters = try(var.topology.clusters, {})
  nodes    = try(var.topology.nodes, {})

  # Which node is the primary of its cluster.
  node_is_primary = {
    for name, n in local.nodes : name => (
      try(n.cluster, null) != null &&
      try(local.clusters[n.cluster].primary, null) == name
    )
  }

  # ── OUTPUT: final_cluster_list (scaffold) ──────────────────────────────────
  # Cluster-scoped concerns live here and are applied by `primary` only.
  final_cluster_list = {
    for name, c in local.clusters : name => {
      name    = name
      primary = try(c.primary, null)
      members = try(c.members, [])

      # Cluster-scoped concern scaffolds (null until implemented).
      # NOTE: no `storage` here — there is no cluster-level storage (no Ceph);
      # storage is node-local and lives under nodes.<n>.storage.
      vlan        = try(c.vlan, null)
      firewall    = try(c.firewall, null)
      replication = try(c.replication, null)
    }
  }

  # ── OUTPUT: final_node_list ────────────────────────────────────────────────
  # Shape matches what the ansible_inventory module expects from a host.
  final_node_list = {
    for name, n in local.nodes : name => {
      # A physical node is not "hosted by" a hypervisor group, so it emits no
      # app_key/node_name. It is grouped by `type` (= `proxmox_node`) and any
      # explicit `groups` it declares, plus the generated `proxmox_primary`.
      #
      # `type = "proxmox_node"` gives one GENERIC physical-node group (not one
      # per node name). It must not be "node" — that would collide with the
      # `node` app tag/role (Node.js, see playbooks/20-runtimes.yml).
      app_key   = null
      name      = name
      type      = "proxmox_node"
      node_name = null
      enabled   = try(n.enabled, true)
      tags      = try(n.tags, [])

      # Ansible connection (bare IP; any "/cidr" suffix is stripped)
      ipv4_address                 = split("/", try(n.ipv4_address, "IP_PENDING"))[0]
      user_account_username        = try(n.ansible_user, "root")
      ansible_password             = try(n.ansible_password, null)
      ansible_ssh_private_key_file = try(n.ansible_ssh_private_key_file, null)

      # Group membership: explicit `groups` + a generated `proxmox_primary`
      # group for the node that owns cluster-scoped config. The list-filter
      # form keeps the object type stable regardless of primary/non-primary.
      ansible_groups = merge(
        { for g in try(n.groups, []) : replace(g, "-", "_") => {} },
        { for g in(local.node_is_primary[name] ? ["proxmox_primary"] : []) : g => {} },
      )

      # Per-host vars surfaced to Ansible (emitted by the inventory module).
      # Concerns live here: `storage` now; vlan/firewall/replication later.
      # Consumers resolve share refs against these at run time (model ii).
      host_vars = {
        topology_cluster = try(n.cluster, null)
        topology_primary = local.node_is_primary[name]
        topology_node    = name

        storage     = try(n.storage, null)
        vlan        = try(n.vlan, null)
        firewall    = try(n.firewall, null)
        replication = try(n.replication, null)
      }
    }
    if try(n.enabled, true)
  }
}
