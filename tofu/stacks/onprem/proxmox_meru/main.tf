# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION
# -----------------------------------------------------------------------------
# This file defines the sequence of resources to create the infrastructure
# for the 'proxmox_meru' stack. It uses data from 'data.tf' and 'locals.tf'
# to decide how to act.
# -----------------------------------------------------------------------------

# ─── Step 1: Normalize Resources ─────────────────────────────────────────────
module "normalizer" {
  source             = "../../../modules/resource_normalizer"
  resources          = var.resources
  user_credentials   = var.user_credentials
  target_node        = var.target_node
  target_datastore   = var.target_datastore
  default_os_type    = "ubuntu"
  default_os_version = "24.04"
  enable_debug       = var.enable_debug
}

# ─── Step 2: Build OS Images Locally (Generic) ───────────────────────────────
# Downloads cloud images from upstream and customizes them with virt-customize.
# Hypervisor independent. Outputs local qcow2 file paths.
module "image_builder" {
  source           = "../../../modules/image_builder"
  requested_images = module.normalizer.requested_os_images
  existing_images  = local.existing_files_on_proxmox
  local_cache_dir  = "/var/tmp/tofu-artifacts/"
}

# ─── Step 3: Upload Custom Images to Proxmox (Proxmox-Specific Glue) ──────────
# Uploads the locally built and customized qcow2 images to the designated
# Proxmox storage datastore.
resource "proxmox_virtual_environment_file" "image_upload" {
  for_each   = module.image_builder.built_images
  depends_on = [module.image_builder]

  node_name    = var.target_node
  datastore_id = var.target_datastore
  content_type = "import"

  source_file {
    path = each.value.local_path
  }
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
