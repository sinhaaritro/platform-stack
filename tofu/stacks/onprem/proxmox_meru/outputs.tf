# -----------------------------------------------------------------------------
# DIAGNOSTIC OUTPUTS
# -----------------------------------------------------------------------------
# This file contains outputs used for debugging and verifying the plan.
# -----------------------------------------------------------------------------

output "DEBUG_Diagnostic" {
  description = "A summary of the data gathering and decision-making steps."

  value = {
    # "STEP_1_GATHER_INFO" = {
    #   "a_Upstream_Checksum_URL"   = local.checksum_url
    #   "b_Proxmox_Datastore_Files" = local.existing_files_on_proxmox
    # }
    # "STEP_2_DECISION_MAKING" = {
    #   "a_Upstream_Image_Hash"        = local.upstream_image_hash
    #   "b_Target_Image_Filename"      = local.target_image_filename
    #   "c_Image_Exists_on_Proxmox"    = local.image_already_exists_on_proxmox
    #   "d_Decision_Build_Image_Count" = local.image_needs_to_be_built
    # }
    # "STEP_3_PREPARE_LOCAL_IMAGE" = {
    #   "a_Image_Prepper_Action"           = local.image_needs_to_be_built == 1 ? "Resource will be created/run." : "Skipped (image already exists on Proxmox)."
    #   "b_Local_File_Exists_Before_Apply" = fileexists(local.target_image_path)
    # }
    # "STEP_4_UPLOAD_IMAGE" = {
    #   "a_Image_Upload_Action" = local.image_needs_to_be_built == 1 ? "Image was uploaded with ID: ${proxmox_virtual_environment_file.ubuntu_custom_image[0].id}" : "Skipped (image already exists on Proxmox)."
    # }
    # "STEP_5_FLATTEN_AND_MERGE" = {
    #   # "resources"              = var.resources
    #   "a_Filtered_QEMU_Groups" = local.vm_groups
    #   "b_Filtered_LXC_Groups"  = local.lxc_groups
    #   "c_Flattened_VM_Map"     = local.flattened_vm_list
    #   "d_VM_List"              = local.final_vm_list
    # }
  }
}


output "created_qemu_vms" {
  description = "A map of all QEMU virtual machines created by this stack, keyed by their names."

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

