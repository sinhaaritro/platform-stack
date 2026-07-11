# -----------------------------------------------------------------------------
# DIAGNOSTIC OUTPUTS
# -----------------------------------------------------------------------------
# This file contains outputs used for debugging and verifying the plan.
# -----------------------------------------------------------------------------

output "DEBUG_Diagnostic" {
  description = "A summary of the data gathering, decision-making, and normalization steps."
  value = {
    status      = var.enable_debug ? "active" : "disabled"
    environment = "proxmox_meru"
    message     = var.enable_debug ? "Diagnostic debugging output is active." : "Diagnostic debugging output is disabled. Set 'enable_debug = true' in your tfvars to enable."
    data = var.enable_debug ? {
      "IMAGE_PIPELINE" = module.image_pipeline.debug_info
      "STEP_5_FLATTEN_AND_MERGE" = {
        "a_Normalized_Resources" = local.normalized_resources
        "b_VM_Groups"            = local._vm_groups
        "c_LXC_Groups"           = local._lxc_groups
        "d_Flattened_VMs"        = local._flattened_vms
        "e_Flattened_LXCs"       = local._flattened_lxcs
        "f_Final_VM_List"        = local.final_vm_list
        "g_Final_LXC_List"       = local.final_lxc_list
      }
    } : null
  }
}


output "created_vms" {
  description = "A map of all virtual machines created by this stack, keyed by their names."

  # This 'for' expression iterates over the 'proxmox_vms' module instances.
  # For each instance, it creates an entry in the output map.
  value = {
    for vm_name, vm_instance in module.proxmox_vms :
    vm_name => {
      id         = vm_instance.vm_details.id
      name       = vm_instance.vm_details.name
      node_name  = vm_instance.vm_details.node_name
      tags       = vm_instance.vm_details.tags
      ip_address = try([for addr in flatten(vm_instance.vm_details.ipv4_addresses) : addr if addr != "127.0.0.1"][0], "pending")
    }
  }

  # Mark the output as sensitive if it contains sensitive data.
  # Since the module output includes the cloud-init user/pass, this is crucial.
  sensitive = false
}
