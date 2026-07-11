# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION
# -----------------------------------------------------------------------------
# This file defines the sequence of resources to create the infrastructure
# for the 'proxmox_meru' stack. It uses data from 'data.tf' and 'locals.tf'
# to decide how to act.
# -----------------------------------------------------------------------------

# STEP 3: RUN IMAGE PREPARATION AND UPLOAD VIA MODULE
# This module orchestrates image download, offline package customization (qemu-guest-agent),
# and file uploads to the target Proxmox datastore.
# TODO: To remove bpg/proxmox as a provider. We need to handle upload here. Image prep can be handled in the module
module "image_pipeline" {
  source = "../../../modules/proxmox_image_pipeline"

  resources          = var.resources
  target_node        = var.target_node
  target_datastore   = var.target_datastore
  proxmox_connection = var.proxmox_connection
}

# -----------------------------------------------------------------------------
# STEP 5: FLATTEN AND MERGE RESOURCE DEFINITIONS
# -----------------------------------------------------------------------------
# Logic extracted to: resource_normalization.tf
# 
# Input:
#   local.final_image_defs  → map of enabled images, keyed by version
#
# Output:
#   local.final_vm_list   → map of enabled VMs,  keyed by node name
#   local.final_lxc_list  → map of enabled LXCs, keyed by node name
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# STEP 6: VM AND LXC CREATION
# -----------------------------------------------------------------------------
# Logic extracted to: proxmox_resources.tf
# 
# Input:
#   local.final_vm_list   → map of enabled VMs,  keyed by node name
#   local.final_lxc_list  → map of enabled LXCs, keyed by node name
# 
# Output:
#   module "proxmox_vms"   → VM resources
#   module "module_lxc"    → LXC resources
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# STEP 7: TERRAFORM OUTPUT
# -----------------------------------------------------------------------------
# Logic extracted to: outputs.tf
# 
# Input:
#   local.final_vm_list   → map of enabled VMs,  keyed by node name
#   local.final_lxc_list  → map of enabled LXCs, keyed by node name
# 
# Output:
#   cli_outputs
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# STEP 8: ANSIBLE OUTPUT
# -----------------------------------------------------------------------------
# Logic extracted to: ansible.tf
# 
# Input:
#   local.final_vm_list   → map of enabled VMs,  keyed by node name
#   local.final_lxc_list  → map of enabled LXCs, keyed by node name
# 
# Output:
#   ansible/inventory.yml
# -----------------------------------------------------------------------------
