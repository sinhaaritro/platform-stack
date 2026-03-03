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
