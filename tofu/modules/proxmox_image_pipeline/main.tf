# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION - IMAGE PIPELINE MODULE
# -----------------------------------------------------------------------------
# This file defines the flow for download, customization, and upload of
# requested OS cloud images.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# STEP 1: GATHER INFORMATION
# -----------------------------------------------------------------------------
# Logic defined in: data.tf
#
# Input:
#   var.proxmox_connection   → connection endpoint and authentication credentials
#   var.target_node          → Proxmox target node name
#   var.target_datastore     → Proxmox storage identifier
#
# Output:
#   data.http.checksums      → fetched SHA256/SHA512 checksums from upstream CDNs
#   data.http.proxmox_storage_content → list of existing files on the Proxmox target datastore
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# STEP 2: DEFINE DESIRED STATE AND MAKE BUILD DECISIONS
# -----------------------------------------------------------------------------
# Logic defined in: locals.tf
#
# Input:
#   var.resources            → scanned to identify VM os_type and os_version
#   data.http.checksums      → parses upstream image manifest hashes
#   data.http.proxmox_storage_content → checks if image already exists on Proxmox
#
# Output:
#   local.final_image_defs   → configurations containing base URL, target names, paths
#   local.build_decisions    → maps versions to 0 (skip build) or 1 (run customizer)
#   local.image_paths        → final import paths returned as module output
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# STEP 3: PREPARE LOCAL IMAGE ON CONTROL MACHINE
# -----------------------------------------------------------------------------
# Implemented below. Uses the build decisions to conditionally download the
# upstream base image, download dependencies, and customize the image offline
# with the QEMU guest agent using virt-customize via templates.
# -----------------------------------------------------------------------------
resource "null_resource" "image_builder" {
  for_each = local.final_image_defs

  # Rebuild if the hash of the upstream manifest changes, or if the physical
  # file is deleted locally.
  triggers = {
    image_sha256 = each.value.upstream_hash
    file_state   = fileexists(each.value.target_path) ? "exists" : "missing-${timestamp()}"
  }

  # Run customization script using a template file
  provisioner "local-exec" {
    when = create
    command = templatefile("${path.module}/templates/${each.value.customize_script}", {
      image_file         = each.value.target_path
      source_url         = "${each.value.base_url}/${each.value.upstream_filename}"
      temp_dir           = var.local_cache_dir
      agent_package      = each.value.agent_package
      agent_dependencies = join(" ", each.value.dependencies)
      build_needed       = local.build_decisions[each.key]
    })
  }

  # Destroy notification message matching original stack behavior
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "------------------------------------------------------------------------"
      echo "INFO: The 'image_builder' resource has been destroyed."
      echo "This usually means a new upstream image version has been detected."
      echo "The old artifact file has NOT been deleted from the shared cache."
      echo "You can manually clean up files in the '${self.triggers.file_state}' directory."
      echo "------------------------------------------------------------------------"
    EOT
  }
}

# -----------------------------------------------------------------------------
# STEP 4: UPLOAD IMAGE TO PROXMOX
# -----------------------------------------------------------------------------
# Implemented below. Uploads the locally prepared and customized disk image (.qcow2)
# to the designated Proxmox datastore.
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "custom_image_upload" {
  for_each = local.final_image_defs

  depends_on = [null_resource.image_builder]

  node_name    = var.target_node
  datastore_id = var.target_datastore
  content_type = "import"

  source_file {
    # Reference the null_resource to guarantee ordering, matching original main.tf
    path = null_resource.image_builder[each.key].id != "" ? each.value.target_path : each.value.target_path
  }
}
