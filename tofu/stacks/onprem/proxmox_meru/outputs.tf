# -----------------------------------------------------------------------------
# DIAGNOSTIC OUTPUTS
# -----------------------------------------------------------------------------
# This file contains outputs used for debugging and verifying the plan.
# -----------------------------------------------------------------------------

# output "DEBUG_Diagnostic" {
#   description = "A summary of the data gathering and decision-making steps."

#   value = {
#     "STEP_1_GATHER_INFO" = {
#       "a_OS_Images_Config"        = local.os_images
#       "b_Proxmox_Datastore_Files" = local.existing_files_on_proxmox
#     }
#     "STEP_2_DECISION_MAKING" = {
#       "a_Image_State_Hashes"       = local.image_state
#       "b_Target_Image_Definitions" = local.final_image_defs
#       "c_Build_Decisions" = {
#         for k, v in local.build_decisions : k => (v == 1 ? "Build Required" : "No Build Needed")
#       }
#     }
#     "STEP_3_PREPARE_LOCAL_IMAGE" = {
#       "a_Description" = "Check 'null_resource.image_builder' state for per-version build status."
#     }
#     "STEP_4_UPLOAD_IMAGE" = {
#       "a_Description" = "Check 'proxmox_virtual_environment_file.custom_image_upload' state for per-version upload status."
#     }
#     "STEP_5_FLATTEN_AND_MERGE" = {
#       # Phase 1: normalized_resources is the pre-filter view (all clusters with defaults applied)
#       "a_Normalized_Resources" = local.normalized_resources
#       # Phase 2: split by type + flattened to per-node items
#       "b_VM_Groups"      = local._vm_groups
#       "c_LXC_Groups"     = local._lxc_groups
#       "d_Flattened_VMs"  = local._flattened_vms
#       "e_Flattened_LXCs" = local._flattened_lxcs
#       # Phase 3: final outputs (enabled-only, fully resolved)
#       "f_Final_VM_List"  = local.final_vm_list
#       "g_Final_LXC_List" = local.final_lxc_list
#     }
#   }
# }


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
