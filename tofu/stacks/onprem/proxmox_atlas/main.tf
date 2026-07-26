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

data "proxmox_files" "proxmox_files" {
  # Get a list of exiting files present in the target datastore, to prevent
  # rebuilding images that already exist.
  node_name    = var.target_node
  datastore_id = var.target_datastore
}

locals {
  # Parse storage contents from the native Proxmox data lookup.
  existing_files_on_proxmox = [
    for item in data.proxmox_files.proxmox_files.files :
    item.file_name
  ]
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

# ─── Download LXC Templates (if template_url is provided) ─────────────────────
locals {
  lxc_templates_to_download = {
    for name, lxc in module.normalizer.final_lxc_list :
    name => lxc
    if lxc.template_url != null
  }
}

resource "null_resource" "lxc_template_customizer" {
  for_each = local.lxc_templates_to_download

  triggers = {
    url        = each.value.template_url
    file_state = fileexists("/var/tmp/tofu-artifacts/ssh-${basename(each.value.template_url)}") ? "exists" : "missing-${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      CACHE_DIR="/var/tmp/tofu-artifacts"
      mkdir -p "$CACHE_DIR"
      URL="${each.value.template_url}"
      FILENAME=$(basename "$URL")
      CUSTOM_FILENAME="ssh-$FILENAME"
      TARGET_PATH="$CACHE_DIR/$CUSTOM_FILENAME"

      if [ ! -f "$TARGET_PATH" ]; then
        WORK_DIR=$(mktemp -d)
        curl -fsSL "$URL" -o "$WORK_DIR/base.tar.xz"
        mkdir -p "$WORK_DIR/rootfs"
        tar -xf "$WORK_DIR/base.tar.xz" -C "$WORK_DIR/rootfs/"
        sudo cp /etc/resolv.conf "$WORK_DIR/rootfs/etc/resolv.conf" 2>/dev/null || true
        
        sudo mount --bind /dev "$WORK_DIR/rootfs/dev"
        sudo mount --bind /proc "$WORK_DIR/rootfs/proc"

        if [ -f "$WORK_DIR/rootfs/sbin/apk" ]; then
          sudo chroot "$WORK_DIR/rootfs" /bin/sh -c "apk add --no-cache openssh sudo python3 && ssh-keygen -A"
          sudo mkdir -p "$WORK_DIR/rootfs/var/empty" "$WORK_DIR/rootfs/root/.ansible/tmp"
          sudo chown root:root "$WORK_DIR/rootfs/var/empty" "$WORK_DIR/rootfs/root/.ansible/tmp"
          sudo chmod 755 "$WORK_DIR/rootfs/var/empty"
          sudo chmod 700 "$WORK_DIR/rootfs/root/.ansible/tmp"
          sudo sh -c "echo 'rc_sys=\"lxc\"' >> '$WORK_DIR/rootfs/etc/rc.conf'"
          sudo sh -c "echo 'PermitRootLogin yes' >> '$WORK_DIR/rootfs/etc/ssh/sshd_config'"
          sudo sh -c "echo 'PasswordAuthentication yes' >> '$WORK_DIR/rootfs/etc/ssh/sshd_config'"
          sudo ln -sf /etc/init.d/sshd "$WORK_DIR/rootfs/etc/runlevels/default/sshd"
        elif [ -f "$WORK_DIR/rootfs/usr/bin/apt-get" ]; then
          sudo chroot "$WORK_DIR/rootfs" /bin/sh -c "apt-get update && apt-get install -y openssh-server sudo && systemctl enable ssh"
        fi

        sudo umount "$WORK_DIR/rootfs/proc" 2>/dev/null || true
        sudo umount "$WORK_DIR/rootfs/dev" 2>/dev/null || true

        (cd "$WORK_DIR/rootfs" && sudo tar -cf - . | xz -9 -T0 > "$TARGET_PATH")
        sudo rm -rf "$WORK_DIR"
      fi
    EOT
  }
}

resource "proxmox_virtual_environment_file" "lxc_template" {
  for_each   = local.lxc_templates_to_download
  depends_on = [null_resource.lxc_template_customizer]

  content_type = "vztmpl"
  datastore_id = each.value.template_datastore_id
  node_name    = each.value.node_name

  source_file {
    path = "/var/tmp/tofu-artifacts/ssh-${basename(each.value.template_url)}"
  }
}


# ─── Step 4: Create Virtual Machines (VMs) ───────────────────────────────────
# This block iterates over our final, flattened map of VMs and calls the
# proxmox_vm module passing in its resolved configuration.

locals {
  # Maps the composite builder key (e.g., "ubuntu-24.04") to the uploaded path on Proxmox datastore.
  image_import_paths = {
    for key, img in module.image_builder.built_images :
    key => "${var.target_datastore}:import/${img.filename}"
  }
}

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
module "proxmox_lxc" {
  source   = "../../../modules/proxmox_lxc"
  for_each = module.normalizer.final_lxc_list

  depends_on = [proxmox_virtual_environment_file.lxc_template, proxmox_virtual_environment_file.image_upload]


  # Main info
  vm_id          = each.value.vm_id
  app_key        = each.value.app_key
  node_name      = each.value.node_name
  description    = each.value.description
  tags           = each.value.tags
  on_boot        = each.value.on_boot
  started        = each.value.started
  ansible_groups = each.value.ansible_groups

  unprivileged = each.value.unprivileged

  # Features 
  nesting = each.value.nesting
  fuse    = each.value.fuse
  keyctl  = each.value.keyctl

  # --- OS Template ---
  template_file_id = try(proxmox_virtual_environment_file.lxc_template[each.key].id, each.value.template_file_id)
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
  user_account_username = each.value.user_account_username
  user_account_password = each.value.user_account_password
  user_account_keys     = each.value.user_account_keys


  # DNS
  dns_servers = ["8.8.8.8"]
}

# ─── Step 6: Generate Ansible Inventory ───────────────────────────────────────
# Instantiates the shared ansible_inventory module to write the dynamic hosts
# inventory file for this stack. Includes both VMs and LXCs in a unified list.

locals {
  # Create a unified list of all hosts (VMs + LXCs) for the inventory module.
  # Each host object contains all necessary fields regardless of type.
  unified_host_list = concat(
    [for name, vm in module.normalizer.final_vm_list : merge(
      vm,
      {
        ipv4_address          = try([for addr in flatten(module.proxmox_vms[name].vm_details.ipv4_addresses) : addr if addr != "127.0.0.1"][0], "IP_PENDING")
        user_account_username = vm.user_account_username
      }
    )],
    [for name, lxc in module.normalizer.final_lxc_list : merge(
      lxc,
      {
        ipv4_address          = try([for addr in flatten(module.proxmox_lxc[name].lxc_details.ipv4_addresses) : addr if addr != "127.0.0.1"][0], "IP_PENDING")
        user_account_username = "root"
        ansible_password      = lxc.user_account_password
      }
    )]
  )
}
module "inventory" {
  source        = "../../../modules/ansible_inventory"
  stack_name    = "proxmox_atlas"
  host_list     = local.unified_host_list
  inventory_dir = "${path.root}/../../../../ansible/inventory.d"
}

# ─── Step 7: Diagnostic and Resource Outputs ─────────────────────────────────
output "DEBUG_Diagnostic" {
  description = "A summary of the data gathering, decision-making, and normalization steps."
  sensitive   = true
  value = {
    status      = var.enable_debug ? "active" : "disabled"
    environment = "proxmox_atlas"
    message     = var.enable_debug ? "Diagnostic debugging output is active." : "Diagnostic debugging output is disabled. Set 'enable_debug = true' in your tfvars to enable."
    data = var.enable_debug ? {
      "IMAGE_PIPELINE"           = module.image_builder.debug_info
      "STEP_5_FLATTEN_AND_MERGE" = module.normalizer.debug_info
    } : null
  }
}

output "created_vms" {
  description = "A map of all virtual machines created by this stack, keyed by their names."
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
  sensitive = false
}

output "created_lxcs" {
  description = "A map of all LXC containers created by this stack, keyed by their names."
  value = {
    for lxc_name, lxc_instance in module.proxmox_lxc :
    lxc_name => {
      id        = lxc_instance.lxc_details.id
      name      = lxc_name
      node_name = lxc_instance.lxc_details.node_name
      tags      = lxc_instance.lxc_details.tags
    }
  }
  sensitive = false
}
