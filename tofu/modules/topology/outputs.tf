# -----------------------------------------------------------------------------
# MODULE OUTPUTS - TOPOLOGY MODULE
# -----------------------------------------------------------------------------

output "final_cluster_list" {
  description = "Normalized clusters (primary/members + cluster-scoped concern scaffolds)."
  value       = local.final_cluster_list
}

output "final_node_list" {
  description = "Normalized physical nodes, keyed by name. Inventory-only host objects, each carrying its concern config (storage, vlan, ...) as host vars."
  value       = local.final_node_list
}
