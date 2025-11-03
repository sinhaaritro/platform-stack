# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION
# -----------------------------------------------------------------------------
# This file defines the sequence of resources to create the infrastructure
# for the 'proxmox_meru' stack. It uses data from 'data.tf' and 'locals.tf'
# to decide how to act.
# -----------------------------------------------------------------------------

# --- STEP 3: PREPARE LOCAL IMAGE ON CONTROL MACHINE (CONDITIONAL) ---
# This resource only runs if the 'image_needs_to_be_built' flag (calculated
# in 'locals.tf') is set to 1. Its job is to ensure the customized .qcow2
# file is present and ready on the local disk of the Control Machine.
resource "null_resource" "image_builder" {
  # The trigger ensures that if the upstream hash changes (forcing a rebuild),
  # this resource will be replaced, causing the provisioner to run again.
  triggers = {
    image_sha256 = local.upstream_image_hash
  }

  # The 'create' provisioner runs only when this resource is first created
  # or when it is recreated due to a trigger change.
  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      set -e

      # This is the flag passed from our locals.tf calculation
      BUILD_NEEDED=${local.image_needs_to_be_built}

      # --- First Check: Is a build needed at all? ---
      if [ "$BUILD_NEEDED" -eq 0 ]; then
        echo "Image already exists on Proxmox. All local preparation is skipped."
        exit 0
      fi

      # If we are here, a build/upload is required.
      ARTIFACT_DIR="${local.temp_artifacts_path}"
      IMAGE_FILE="${local.target_image_filename}"

      # Create the temp directory if it doesn't exist
      echo "--- Ensuring temp artifact directory exists: $ARTIFACT_DIR ---"
      mkdir -p "$ARTIFACT_DIR"
      cd "$ARTIFACT_DIR"
      
      # Step 3a: Check if the target file already exists locally.
      if [ ! -f "$IMAGE_FILE" ]; then

        # Step 3b: If not, download the base image and dependencies.
        SOURCE_URL="${local.base_url}/${local.upstream_image_filename}"
        
        echo "--- Image not found locally. Downloading from $SOURCE_URL ---"
        wget -O "$IMAGE_FILE" "$SOURCE_URL"

        echo "--- Downloading guest agent and its dependencies ---"
        apt-get download ${local.agent_package}
        for dep in ${join(" ", local.agent_dependencies)}; do
          apt-get download $dep
        done

        echo "--- Renaming downloaded packages for consistency ---"
        AGENT_DEB_SRC=$(ls ${local.agent_package}*.deb | head -n 1)
        mv "$AGENT_DEB_SRC" "guest-agent.deb"
        i=0
        for dep in ${join(" ", local.agent_dependencies)}; do
          DEP_DEB_SRC=$(ls $dep*.deb | head -n 1)
          mv "$DEP_DEB_SRC" "dependency-$i.deb"
          i=$((i+1))
        done

        # Step 3c: Run virt-customize to perform the offline installation.
        echo "--- Customizing image with virt-customize ---"
        sudo virt-customize -a "$IMAGE_FILE" \
          --upload "dependency-0.deb:/tmp/dependency-0.deb" \
          --upload "guest-agent.deb:/tmp/guest-agent.deb" \
          --run-command "dpkg -i /tmp/dependency-0.deb" \
          --run-command "dpkg -i /tmp/guest-agent.deb" \
          --timezone "Asia/Kolkata" \
          --run-command "cloud-init clean --logs --seed" \
          --run-command "truncate -s 0 /etc/machine-id"
      else
        echo "--- Image file '$IMAGE_FILE' already exists locally. Skipping download and customization. ---"
      fi
    EOT
  }

  # The 'destroy' provisioner runs when this resource is destroyed, ensuring
  # that a change in the upstream image hash cleans up the old local files.
  provisioner "local-exec" {
    when = destroy
    # command = "rm -f ubuntu-*-custom.qcow2 *.deb"
    command = <<-EOT
      echo "------------------------------------------------------------------------"
      echo "INFO: The 'image_builder' resource has been destroyed."
      echo "This usually means a new upstream image version has been detected."
      echo "The old artifact file has NOT been deleted from the shared cache:"
      echo "You can manually clean up files in the '/var/tmp/tofu-artifacts/' directory"
      echo "You can manually delete this file if you are sure it is no longer"
      echo "needed by any other OpenTofu stack."
      echo "------------------------------------------------------------------------"
    EOT
  }
}

# -----------------------------------------------------------------------------
# STEP 4: UPLOAD IMAGE TO PROXMOX (CONDITIONAL)
# -----------------------------------------------------------------------------
# This resource takes the locally prepared .qcow2 file and uploads it to the
# Proxmox datastore. It is also controlled by the 'image_needs_to_be_built'
# flag and will be completely skipped if the image already exists on Proxmox.
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "ubuntu_custom_image" {
  # This resource only runs if the image_builder was scheduled to run.
  count = max(local.image_needs_to_be_built, length(proxmox_virtual_environment_file.ubuntu_custom_image))

  # This ensures that the file upload does not start until the local
  # image preparation script (Step 3) has finished successfully.
  # depends_on = [null_resource.image_builder]

  # --- Configuration for the upload ---
  node_name    = var.target_node
  datastore_id = var.target_datastore
  # 'import' is the correct content type for staging disk images.
  content_type = "import"

  # The source file on the local Control Machine.
  source_file {
    # This is the key: We are forcing this path to be computed only AFTER
    # the null_resource has run by including one of its attributes.
    # The id changes on every run, forcing the provider to re-evaluate the path.
    path = null_resource.image_builder.id != "" ? local.target_image_path : local.target_image_path
  }
}

# -----------------------------------------------------------------------------
# STEP 5: FLATTEN AND MERGE RESOURCE DEFINITIONS
# -----------------------------------------------------------------------------
# This section takes the complex, nested 'var.resources' map and transforms
# it into a simple, flat map of fully-resolved VM configurations that can be
# passed to our module.
# -----------------------------------------------------------------------------

locals {
  # 1. Filter the main 'resources' map into separate groups for VM and LXC,
  #    only including the ones that are marked as 'enabled'.
  vm_groups = {
    for key, group in var.resources : key => group
    if group.type == "vm"
  }
  lxc_groups = {
    for key, group in var.resources : key => group
    if group.type == "lxc"
  }

  # 2. Flatten the nested structure into an intermediate list.
  flattened_vm_list = flatten([
    for app_key, app_group in local.vm_groups : [
      for node_key, node_override in app_group.nodes : {
        app_key       = app_key
        node_key      = node_key
        app_group     = app_group
        node_override = node_override
      }
    ]
  ])

  # 3. Iterate over the flat list and build the final, clean objects.
  # We are creating a list of objects
  all_potential_vms = {
    for item in local.flattened_vm_list :
    item.node_key => {
      # For each attribute, we use coalesce() to implement the inheritance.
      # It takes the specific node value first, and if that's null,
      # it falls back to the application-level value.

      # We add the application key to the final object so we can use it for grouping.
      app_key = item.app_key

      # Main info
      name    = item.node_key
      type    = item.app_group.type
      enabled = coalesce(item.node_override.enabled, item.app_group.enabled)
      vm_id   = item.node_override.vm_id
      node_name = (
        (item.node_override.node_name != null || item.app_group.node_name != null) ?
        coalesce(item.node_override.node_name, item.app_group.node_name) :
        "ERROR: 'node_name' is not defined for VM '${item.node_key}' in application '${item.app_key}'. Please set it at the application or node level." [999]
      ),
      description = coalesce(item.node_override.description, item.app_group.description)
      tags = sort(distinct(concat(
        ["OpenTofu"],
        coalesce(item.app_group.tags, []),
        coalesce(item.node_override.tags, [])
      ))),
      on_boot = coalesce(item.node_override.on_boot, item.app_group.on_boot)
      started = coalesce(item.node_override.started, item.app_group.started)

      # Hardware
      cpu_cores   = coalesce(item.node_override.cpu_cores, item.app_group.cpu_cores)
      cpu_sockets = coalesce(item.node_override.cpu_sockets, item.app_group.cpu_sockets)
      memory_size = coalesce(item.node_override.memory_size, item.app_group.memory_size)

      # Disk
      disk_datastore_id = coalesce(item.node_override.disk_datastore_id, item.app_group.disk_datastore_id, var.target_datastore)
      # source_image_path         = proxmox_virtual_environment_file.ubuntu_custom_image[count.index],
      disk_size = coalesce(item.node_override.disk_size, item.app_group.disk_size)
      disk_ssd  = coalesce(item.node_override.disk_ssd, item.app_group.disk_ssd)

      # Network
      vlan_bridge = coalesce(item.node_override.vlan_bridge, item.app_group.vlan_bridge)
      vlan_id     = coalesce(item.node_override.vlan_id, item.app_group.vlan_id)

      # Cloud-Init
      ipv4_address = item.node_override.ipv4_address
      user_account_username = ((var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")] != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")].username != null &&
        trimspace(var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")].username) != "") ?
        var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")].username :
        "ERROR: A valid 'username' could not be found for VM '${item.node_key}'. The secret '${coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")}' is either missing from 'user_credentials' or does not contain the key 'username'." [999]
      ),
      user_account_password = ((var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")] != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")].password != null &&
        trimspace(var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")].password) != "") ?
        var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")].password :
        "ERROR: A valid 'password' could not be found for VM '${item.node_key}'. The secret '${coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")}' is either missing from 'user_credentials' or does not contain the key 'password'." [999]
      ),
      user_account_keys = ((var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")] != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")].ssh_public_keys != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")].ssh_public_keys != []) ?
        var.user_credentials[coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")].ssh_public_keys :
        "ERROR: A valid 'ssh_public_keys' could not be found for VM '${item.node_key}'. The secret '${coalesce(item.node_override.cloud_init_secret_key, item.app_group.cloud_init_secret_key, "default_user")}' is either missing from 'user_credentials' or does not contain the key 'ssh_public_keys'." [999]
      ),
    }
  }

  #    We iterate over our fully resolved list of all potential VMs.
  final_vm_list = {
    for vm in local.all_potential_vms :
    vm.name => vm
    if vm.enabled && vm.type == "vm"
  }
}

# -----------------------------------------------------------------------------
# STEP 6: CREATE VIRTUAL MACHINES 
# -----------------------------------------------------------------------------
# This block iterates over our final, flattened map of VMs and calls the
# 'proxmox_vm' module for each one, passing in its fully resolved configuration.
# -----------------------------------------------------------------------------
module "proxmox_vms" {
  source   = "../../../modules/proxmox_vm"
  for_each = local.final_vm_list

  depends_on = [proxmox_virtual_environment_file.ubuntu_custom_image]

  # Main info
  vm_id       = each.value.vm_id
  name        = each.value.name
  app_key     = each.value.app_key
  node_name   = each.value.node_name
  description = each.value.description
  tags        = each.value.tags
  on_boot     = each.value.on_boot
  started     = each.value.started

  # Hardware
  cpu_cores   = each.value.cpu_cores
  cpu_sockets = each.value.cpu_sockets
  memory      = each.value.memory_size

  # Disk
  disk_datastore_id = each.value.disk_datastore_id
  source_image_path = local.final_image_path
  disk_size         = each.value.disk_size
  disk_ssd          = each.value.disk_ssd

  # Network
  vlan_bridge = each.value.vlan_bridge
  vlan_id     = each.value.vlan_id

  # Cloud-Init
  ipv4_address          = each.value.ipv4_address
  user_account_username = each.value.user_account_username
  user_account_password = each.value.user_account_password
  user_account_keys     = each.value.user_account_keys
}

# -----------------------------------------------------------------------------
# STEP 7: CREATE CONTAINERS (LXC) - Placeholder for the Future
# -----------------------------------------------------------------------------
# This is where you would add a similar 'module "lxc_containers"' block.
# It would iterate over 'local.lxc_groups' and call a new 'proxmox_lxc' module.
# -----------------------------------------------------------------------------

# # -----------------------------------------------------------------------------
# # STEP 7: CREATE THE VM BY IMPORTING THE UPLOADED DISK
# # -----------------------------------------------------------------------------
# resource "proxmox_virtual_environment_vm" "vm_cloud_init" {
#   # --- General and OS Settings ---
#   node_name   = "moo-moo"
#   vm_id       = 500
#   name        = "web-server-01"
#   description = "Primary web server, managed by OpenTofu. Ubuntu 24.04."
#   tags        = ["managed-by-tofu", "web", "ubuntu"]
#   on_boot     = false
#   started     = false
#   boot_order  = ["scsi0", "net0"]


#   # --- OS and Boot Configuration ---
#   operating_system {
#     type = "l26"
#   }

#   # --- System and QEMU Agent ---
#   machine = "q35"
#   bios    = "ovmf"
#   efi_disk {
#     datastore_id      = "local-thin"
#     pre_enrolled_keys = true
#   }
#   scsi_hardware = "virtio-scsi-pci"
#   agent {
#     enabled = true
#   }

#   # --- Disk Configuration ---
#   disk {
#     interface    = "scsi0"
#     datastore_id = "local-thin"
#     import_from  = proxmox_virtual_environment_file.ubuntu_custom_image.id
#     size         = 10
#     cache        = "writeback"
#     discard      = "on"
#     ssd          = true
#   }

#   # --- CPU Configuration ---
#   cpu {
#     cores   = 2
#     sockets = 1
#     type    = "host"
#   }

#   # --- Memory Configuration ---
#   memory {
#     dedicated = 2048
#     floating  = 2048
#   }

#   # --- Network Configuration ---
#   network_device {
#     bridge   = "vmbr0"
#     vlan_id  = 1
#     firewall = true
#     model    = "virtio"
#   }

#   # --- Serial and VGA Configuration for Console Access ---
#   serial_device {}
#   vga {
#     type = "serial0"
#   }

#   # --- Cloud-Init Configuration (as top-level arguments) ---
#   initialization {
#     datastore_id = "local-thin"
#     interface    = "ide0"

#     ip_config {
#       ipv4 {
#         address = "dhcp"
#       }
#     }

#     user_account {
#       keys     = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwC01G8nJScuxp7Cga8uUsnHUW2IpXXiiTw1gzhEL4P RyzenWindows"]
#       password = "devdevdev"
#       username = "dev"
#     }
#   }

#   # This block tells OpenTofu to ignore changes to the 'import_from'
#   # attribute after the VM has been created.
#   lifecycle {
#     ignore_changes = [
#       disk[0].import_from,
#     ]
#   }
# }


# # # -----------------------------------------------------------------------------
# # # RESOURCE: EXAMPLE WEB SERVER VM (ID 500)
# # # -----------------------------------------------------------------------------
# # # This resource defines a single, statically configured QEMU virtual machine.
# # # It includes comprehensive settings for hardware, cloud-init for automation.
# # # -----------------------------------------------------------------------------

# resource "proxmox_virtual_environment_vm" "vm" {
#   # --- General and OS Settings ---
#   node_name   = "moo-moo"
#   vm_id       = 500
#   name        = "web-server-01"
#   description = "Primary web server, managed by OpenTofu. Ubuntu 24.04."
#   tags        = ["managed-by-tofu", "web", "ubuntu"]
#   on_boot     = true # Automatically start the VM on node boot
#   boot_order  = ["scsi0", "net0", "ide2"]


#   # --- OS and Boot Configuration ---
#   operating_system {
#     type = "l26" # l26 corresponds to Linux Kernel 6.x / 5.x
#   }
#   cdrom {
#     file_id   = "data-storage:iso/ubuntu-24.04.3-live-server-amd64.iso"
#     interface = "ide2"
#   }

#   # --- System and QEMU Agent ---
#   machine = "q35"
#   bios    = "ovmf" # Use UEFI BIOS, common for modern OSes
#   efi_disk {
#     datastore_id      = "local-thin"
#     pre_enrolled_keys = true
#   }
#   scsi_hardware = "virtio-scsi-pci" # Recommended SCSI controller
#   agent {
#     enabled = true # Enable the QEMU Guest Agent for better management
#     trim    = true # Allows the guest to send TRIM commands to the storage
#     type    = "virtio"
#   }

#   # --- Disk Configuration ---
#   disk {
#     interface    = "scsi0"
#     datastore_id = "local-thin"
#     # import_from  = "local-thin:"
#     size = 8
#     # file_format = "qcow2"
#     cache    = "writeback"
#     discard  = "on"
#     iothread = true
#     ssd      = true
#   }

#   # --- CPU Configuration ---
#   cpu {
#     cores   = 2
#     sockets = 1
#     type    = "host" # Pass through the host CPU type for best performance
#   }

#   # --- Memory Configuration ---
#   memory {
#     dedicated = 2048
#     floating  = 2048 # Allow memory to shrink if needed
#   }

#   # --- Network Configuration ---
#   network_device {
#     bridge   = "vmbr0"
#     vlan_id  = 1
#     firewall = true
#     model    = "virtio"
#     # mac_address = "BC:24:11:1A:2B:3C"
#   }



#   # # --- Cloud-Init Configuration (as top-level arguments) ---
#   # cloud_init_user            = var.user_profile.username
#   # cloud_init_password        = var.user_credentials.password
#   # cloud_init_ssh_public_keys = var.user_credentials.ssh_public_keys
#   # cloud_init_dns_domain      = "local" # Example value, can be customized
#   # cloud_init_ip_v4 {
#   #   dhcp = true
#   # }

# }
