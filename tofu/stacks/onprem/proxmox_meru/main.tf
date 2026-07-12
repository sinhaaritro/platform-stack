# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION
# -----------------------------------------------------------------------------
# This file defines the sequence of resources to create the infrastructure
# for the stack.
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

# ─── Data Sources ────────────────────────────────────────────────────────────
data "proxmox_files" "proxmox_files" {
  node_name    = var.target_node
  datastore_id = var.target_datastore
}

# ─── Build OS Images Locally ──────────────────────────────────────────────────
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

# ─── Step 4: Create Virtual Machines (VMs) ───────────────────────────────────
# This block iterates over our final, flattened map of VMs and calls the
# proxmox_vm module passing in its resolved configuration.
module "proxmox_vms" {
  source   = "../../../modules/proxmox_vm"
  for_each = module.normalizer.final_vm_list

  depends_on = [proxmox_virtual_environment_file.image_upload]

  # Main info
  vm_id          = each.value.vm_id
  name           = each.value.name
  app_key        = each.value.app_key
  node_name      = each.value.node_name
  description    = each.value.description
  tags           = each.value.tags
  on_boot        = each.value.on_boot
  started        = each.value.started
  ansible_groups = each.value.ansible_groups

  # Hardware
  cpu_cores   = each.value.cpu_cores
  cpu_sockets = each.value.cpu_sockets
  memory      = each.value.memory_size

  # Disk
  disk_datastore_id = each.value.disk_datastore_id
  disk_size         = each.value.disk_size
  disk_ssd          = each.value.disk_ssd
  source_image_path = local.image_import_paths["${each.value.os_type}-${each.value.os_version}"]


  # Network
  vlan_bridge = each.value.vlan_bridge
  vlan_id     = each.value.vlan_id

  # Cloud-Init
  ipv4_address          = each.value.ipv4_address
  ipv4_gateway          = each.value.ipv4_gateway
  user_account_username = each.value.user_account_username
  user_account_password = each.value.user_account_password
  user_account_keys     = each.value.user_account_keys

  # Additional Disks
  additional_disks = each.value.additional_disks

  # DNS
  dns_servers = ["8.8.8.8"]
}

# ─── Step 5: Create Containers (LXC) ─────────────────────────────────────────
# This block iterates over our final, flattened map of LXCs and calls the
# proxmox_lxc module passing in its resolved configuration.
module "module_lxc" {
  source   = "../../../modules/proxmox_lxc"
  for_each = module.normalizer.final_lxc_list

  depends_on = [proxmox_virtual_environment_file.image_upload]

  # Main info
  vm_id       = each.value.vm_id
  app_key     = each.value.app_key
  node_name   = each.value.node_name
  description = each.value.description
  tags        = each.value.tags
  on_boot     = each.value.on_boot
  started     = each.value.started

  unprivileged = each.value.unprivileged

  # Features 
  nesting = each.value.nesting
  fuse    = each.value.fuse
  keyctl  = each.value.keyctl

  # --- OS Template ---
  template_file_id = each.value.template_file_id
  os_type          = each.value.os_type

  # Hardware
  cpu_cores = each.value.cpu_cores
  memory    = each.value.memory_size

  # Disk
  disk_datastore_id = each.value.disk_datastore_id
  disk_size         = each.value.disk_size

  # Network
  vlan_bridge = each.value.vlan_bridge
  vlan_id     = each.value.vlan_id

  # Cloud-Init
  hostname              = each.value.name
  ipv4_address          = each.value.ipv4_address
  ipv4_gateway          = each.value.ipv4_gateway
  user_account_password = each.value.user_account_password
  user_account_keys     = each.value.user_account_keys

  # DNS
  dns_servers = ["8.8.8.8"]
}

# ─── Step 6: Generate Ansible Inventory ───────────────────────────────────────
# Instantiates the shared ansible_inventory module to write the dynamic hosts
# inventory file for this stack.
module "inventory" {
  source        = "../../../modules/ansible_inventory"
  stack_name    = "proxmox_meru"
  vm_list       = module.normalizer.final_vm_list
  vm_outputs    = { for k, v in module.proxmox_vms : k => v.vm_details }
  inventory_dir = "${path.root}/../../../../ansible/inventory.d"
}

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
