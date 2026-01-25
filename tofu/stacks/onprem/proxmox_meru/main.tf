# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION
# -----------------------------------------------------------------------------
# This file defines the sequence of resources to create the infrastructure
# for the 'proxmox_meru' stack. It uses data from 'data.tf' and 'locals.tf'
# to decide how to act.
# -----------------------------------------------------------------------------

# STEP 3: PREPARE LOCAL IMAGE ON CONTROL MACHINE (CONDITIONAL)
# This resource only runs if the 'image_needs_to_be_built' flag (calculated
# in 'locals.tf') is set to 1. Its job is to ensure the customized .qcow2
# file is present and ready on the local disk of the Control Machine.
resource "null_resource" "image_builder" {
  for_each = local.final_image_defs

  # The trigger ensures that if the upstream hash changes (forcing a rebuild),
  # this resource will be replaced, causing the provisioner to run again.
  triggers = {
    image_sha256 = each.value.upstream_hash
    # Check physical file existence to detect manual deletion.
    # If file goes missing, this value changes (due to timestamp), forcing rebuild.
    file_state = fileexists(each.value.target_path) ? "exists" : "missing-${timestamp()}"
  }

  # The 'create' provisioner runs only when this resource is first created
  # or when it is recreated due to a trigger change.
  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      set -e

      # This is the flag passed from our locals.tf calculation
      BUILD_NEEDED=${local.build_decisions[each.key]}

      # -----------------------------------------------------------------------
      # PARTIAL FAILURE HANDLING:
      # Since we use for_each, each image build is an independent OpenTofu resource.
      # If one version fails (e.g. 24.04 succeeds, 25.04 fails):
      # 1. The successful resource is saved to state.
      # 2. The failed resource is marked 'tainted' (or not saved).
      # 3. The script cleans up the corrupted artifact (exit 1 + rm).
      # 4. On the NEXT 'tofu apply', OpenTofu will only retry the failed one.
      # -----------------------------------------------------------------------

      # First Check: Is a build needed at all?
      if [ "$BUILD_NEEDED" -eq 0 ]; then
        echo "Image for version ${each.key} already exists on Proxmox. Local preparation skipped."
        exit 0
      fi

      # If we are here, a build/upload is required.
      ARTIFACT_DIR="${local.temp_artifacts_path}"
      IMAGE_FILE="${each.value.target_path}"
      SOURCE_URL="${each.value.base_url}/${each.value.upstream_filename}"

      # Create the temp directory if it doesn't exist
      echo "Ensuring temp artifact directory exists: $ARTIFACT_DIR"
      mkdir -p "$ARTIFACT_DIR"
      cd "$ARTIFACT_DIR"

      # Step 3a: Check if the target file already exists locally.
      if [ ! -f "$IMAGE_FILE" ]; then

        echo "Image not found locally. Downloading from $SOURCE_URL"
        wget -O "$IMAGE_FILE" "$SOURCE_URL"

        echo "Downloading guest agent and its dependencies"
        apt-get download ${local.agent_package}
        for dep in ${join(" ", local.agent_dependencies)}; do
          apt-get download $dep
        done

        echo "Renaming downloaded packages for consistency"
        AGENT_DEB_SRC=$(ls ${local.agent_package}*.deb | head -n 1)
        mv "$AGENT_DEB_SRC" "guest-agent.deb"
        i=0
        for dep in ${join(" ", local.agent_dependencies)}; do
          DEP_DEB_SRC=$(ls $dep*.deb | head -n 1)
          mv "$DEP_DEB_SRC" "dependency-$i.deb"
          i=$((i+1))
        done

        # Step 3c: Build the virt-customize command dynamically
        echo "Constructing virt-customize command"

        VIRT_CMD="sudo virt-customize -a $IMAGE_FILE"

        # 1. Install Dependencies FIRST
        for deb in dependency-*.deb; do
          if [ -f "$deb" ]; then
             VIRT_CMD="$VIRT_CMD --upload $deb:/tmp/$deb --run-command 'dpkg -i /tmp/$deb'"
          fi
        done

        # 2. Install Guest Agent SECOND
        VIRT_CMD="$VIRT_CMD --upload guest-agent.deb:/tmp/guest-agent.deb --run-command 'dpkg -i /tmp/guest-agent.deb'"

        # 3. Add System Configuration changes
        # - Enable SSH (Critical Fix)
        # - Set Timezone
        # - Clean Cloud-Init logs
        VIRT_CMD="$VIRT_CMD --run-command 'mkdir -p /etc/systemd/system/multi-user.target.wants'"
        VIRT_CMD="$VIRT_CMD --run-command 'ln -sf /usr/lib/systemd/system/ssh.service /etc/systemd/system/multi-user.target.wants/ssh.service'"
        VIRT_CMD="$VIRT_CMD --timezone Asia/Kolkata"
        VIRT_CMD="$VIRT_CMD --run-command 'cloud-init clean --logs --seed'"
        VIRT_CMD="$VIRT_CMD --run-command 'truncate -s 0 /etc/machine-id'"

        # 4. Verify Installation
        VIRT_CMD="$VIRT_CMD --run-command 'dpkg -s qemu-guest-agent'"

        echo "Executing: $VIRT_CMD"
        
        # Execute and check for failure. If failed, delete the corrupt image so we don't skip build next time.
        if ! eval "$VIRT_CMD"; then
          echo "ERROR: Customization failed. Deleting corrupted artifact '$IMAGE_FILE'..."
          rm -f "$IMAGE_FILE"
          exit 1
        fi

      else
        echo "Image file '$IMAGE_FILE' already exists locally. Skipping download and customization."
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
resource "proxmox_virtual_environment_file" "custom_image_upload" {
  # Only create this resource for versions that actually need to be built/uploaded
  # Remove conditional filtering to prevent creation/deletion loop.
  # The resource must always be defined so Tofu manages it.
  for_each = local.final_image_defs

  depends_on = [null_resource.image_builder]

  # Configuration for the upload
  node_name    = var.target_node
  datastore_id = var.target_datastore
  # 'import' is the correct content type for staging disk images.
  content_type = "import"

  # The source file on the local Control Machine.
  source_file {
    # We reference the image_builder to ensure ordering, though depends_on handles it too.
    path = null_resource.image_builder[each.key].id != "" ? each.value.target_path : each.value.target_path
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
  # 1. This section splits the main 'var.resources' map into separate maps for VM and LXC
  vm_groups = {
    for key, group in var.resources : key => group
    if group.type == "vm"
  }
  lxc_groups = {
    for key, group in var.resources : key => group
    if group.type == "lxc"
  }

  # 2. Flatten the nested structure into an intermediate list.
  flattened_vms = flatten([
    for app_key, app_group in local.vm_groups : [
      for node_key, node_override in app_group.nodes : {
        app_key       = app_key
        node_key      = node_key
        app_group     = app_group
        node_override = node_override
      }
    ]
  ])
  flattened_lxcs = flatten([
    for app_key, app_group in local.lxc_groups : [
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
    for item in local.flattened_vms :
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
      cpu_cores   = coalesce(item.node_override.vm_config.cpu_cores, item.app_group.vm_config.cpu_cores)
      cpu_sockets = coalesce(item.node_override.vm_config.cpu_sockets, item.app_group.vm_config.cpu_sockets)
      memory_size = coalesce(item.node_override.vm_config.memory_size, item.app_group.vm_config.memory_size)

      # Disk
      disk_datastore_id = coalesce(item.node_override.vm_config.disk_datastore_id, item.app_group.vm_config.disk_datastore_id, var.target_datastore)
      # source_image_path         = proxmox_virtual_environment_file.custom_image_upload[count.index],
      disk_size = coalesce(item.node_override.vm_config.disk_size, item.app_group.vm_config.disk_size)
      disk_ssd  = coalesce(item.node_override.vm_config.disk_ssd, item.app_group.vm_config.disk_ssd)

      # Network
      vlan_bridge = coalesce(item.node_override.vm_config.vlan_bridge, item.app_group.vm_config.vlan_bridge)
      vlan_id     = coalesce(item.node_override.vm_config.vlan_id, item.app_group.vm_config.vlan_id)
      os_version  = coalesce(item.node_override.vm_config.os_version, item.app_group.vm_config.os_version)

      # Additional Disks
      additional_disks = (
        (item.node_override.vm_config != null && item.node_override.vm_config.additional_disks != null) ?
        item.node_override.vm_config.additional_disks :
        (item.app_group.vm_config != null && item.app_group.vm_config.additional_disks != null) ?
        item.app_group.vm_config.additional_disks :
        []
      )

      # Cloud-Init
      ipv4_address = item.node_override.vm_config.ipv4_address
      ipv4_gateway = coalesce(item.node_override.vm_config.ipv4_gateway, item.app_group.vm_config.ipv4_gateway, "192.168.0.1")
      user_account_username = ((var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].username != null &&
        trimspace(var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].username) != "") ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].username :
        "ERROR: A valid 'username' could not be found for VM '${item.node_key}'. The secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' is either missing from 'user_credentials' or does not contain the key 'username'." [999]
      ),
      user_account_password = ((var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password != null &&
        trimspace(var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password) != "") ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password :
        "ERROR: A valid 'password' could not be found for VM '${item.node_key}'. The secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' is either missing from 'user_credentials' or does not contain the key 'password'." [999]
      ),
      user_account_keys = ((var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys != []) ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys :
        "ERROR: A valid 'ssh_public_keys' could not be found for VM '${item.node_key}'. The secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' is either missing from 'user_credentials' or does not contain the key 'ssh_public_keys'." [999]
      ),
      ansible_groups = {
        for group_name in distinct(concat(keys(coalesce(item.app_group.ansible_groups, {})), keys(coalesce(item.node_override.ansible_groups, {})))) :
        group_name => merge(
          lookup(coalesce(item.app_group.ansible_groups, {}), group_name, {}),
          lookup(coalesce(item.node_override.ansible_groups, {}), group_name, {})
        )
      }
    }
  }

  all_potential_lxc = {
    for item in local.flattened_lxcs :
    item.node_key => {
      # Now, construct the final, flat object for the LXC module
      app_key = item.app_key
      name    = item.node_key
      type    = item.app_group.type
      enabled = coalesce(item.node_override.enabled, item.app_group.enabled)
      vm_id   = item.node_override.vm_id

      node_name    = coalesce(item.node_override.node_name, item.app_group.node_name, var.target_node)
      description  = coalesce(item.node_override.description, item.app_group.description)
      tags         = distinct(concat(["OpenTofu"], coalesce(item.app_group.tags, []), coalesce(item.node_override.tags, [])))
      on_boot      = coalesce(item.node_override.on_boot, item.app_group.on_boot)
      started      = coalesce(item.node_override.started, item.app_group.started)
      unprivileged = coalesce(item.node_override.lxc_config.unprivileged, item.app_group.lxc_config.unprivileged)


      # Get LXC features from the merged_config
      nesting = coalesce(item.node_override.lxc_config.nesting, item.app_group.lxc_config.nesting)
      fuse    = coalesce(item.node_override.lxc_config.fuse, item.app_group.lxc_config.fuse)
      keyctl  = coalesce(item.node_override.lxc_config.keyctl, item.app_group.lxc_config.keyctl)

      # Hardware
      cpu_cores   = coalesce(item.node_override.lxc_config.cpu_cores, item.app_group.lxc_config.cpu_cores)
      memory_size = coalesce(item.node_override.lxc_config.memory_size, item.app_group.lxc_config.memory_size)

      # Disk
      disk_datastore_id = coalesce(item.node_override.lxc_config.disk_datastore_id, item.app_group.lxc_config.disk_datastore_id, var.target_datastore)
      #  template_file_id         = proxmox_virtual_environment_file.custom_image_upload[count.index],
      os_type   = coalesce(item.node_override.lxc_config.os_type, item.app_group.lxc_config.os_type)
      disk_size = coalesce(item.node_override.lxc_config.disk_size, item.app_group.lxc_config.disk_size)

      # Network
      vlan_bridge = coalesce(item.node_override.lxc_config.vlan_bridge, item.app_group.lxc_config.vlan_bridge)
      vlan_id     = coalesce(item.node_override.lxc_config.vlan_id, item.app_group.lxc_config.vlan_id)

      # Cloud-Init
      ipv4_address = item.node_override.lxc_config.ipv4_address
      ipv4_gateway = coalesce(item.node_override.lxc_config.ipv4_gateway, item.app_group.lxc_config.ipv4_gateway, "192.168.0.1")
      user_account_password = ((var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password != null &&
        trimspace(var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password) != "") ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password :
        "ERROR: A valid 'password' could not be found for VM '${item.node_key}'. The secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' is either missing from 'user_credentials' or does not contain the key 'password'." [999]
      ),
      user_account_keys = ((var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys != []) ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys :
        "ERROR: A valid 'ssh_public_keys' could not be found for VM '${item.node_key}'. The secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' is either missing from 'user_credentials' or does not contain the key 'ssh_public_keys'." [999]
      ),
    }
  }

  #    We iterate over our fully resolved list of all potential VMs.
  final_vm_list = {
    for vm in local.all_potential_vms :
    vm.name => vm
    if vm.enabled && vm.type == "vm"
  }
  final_lxc_list = {
    for lxc in local.all_potential_lxc :
    lxc.name => lxc
    if lxc.enabled && lxc.type == "lxc"
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

  depends_on = [proxmox_virtual_environment_file.custom_image_upload]

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
  source_image_path = local.final_image_paths[each.value.os_version]


  # Network
  vlan_bridge = each.value.vlan_bridge
  vlan_id     = each.value.vlan_id

  # Cloud-Init
  ipv4_address          = each.value.ipv4_address
  ipv4_gateway          = each.value.ipv4_gateway
  user_account_username = each.value.user_account_username
  user_account_password = each.value.user_account_password
  user_account_keys     = each.value.user_account_keys

  # Aditional Disks
  additional_disks = each.value.additional_disks
}

# -----------------------------------------------------------------------------
# STEP 7: CREATE CONTAINERS (LXC)
# -----------------------------------------------------------------------------
# This is where you would add a similar 'module "lxc_containers"' block.
# It would iterate over 'local.lxc_groups' and call a new 'proxmox_lxc' module.
# -----------------------------------------------------------------------------
module "module_lxc" {
  source   = "../../../modules/proxmox_lxc"
  for_each = local.final_lxc_list

  depends_on = [proxmox_virtual_environment_file.custom_image_upload]

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
  nesting = true
  fuse    = true
  keyctl  = true

  # --- OS Template ---
  template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  os_type          = "debian"

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
}

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
#     import_from  = proxmox_virtual_environment_file.custom_image_upload.id
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
