# -----------------------------------------------------------------------------
# INPUT VARIABLES - TOPOLOGY MODULE
# -----------------------------------------------------------------------------

variable "topology" {
  description = <<-EOT
    Physical topology: clusters and nodes.

      topology = {
        clusters = { <name> = { primary, members, vlan?, firewall?, replication? } }   # no cluster-level storage
        nodes    = { <name> = { cluster, ipv4_address, ansible_user, groups,
                                storage?, vlan?, firewall?, replication? } }
      }

    Cluster-scoped concern keys are applied by `primary` only; node-scoped
    concern keys (e.g. `storage`) are applied on that node and surface as host
    vars. Consumers reference a (provider, share) pair and resolve at run time.
    Passed as `any` so the schema stays open — adding a concern is a data change.
  EOT
  type        = any
  default     = {}
}
