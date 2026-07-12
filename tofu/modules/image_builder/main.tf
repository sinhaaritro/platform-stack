# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION - IMAGE BUILDER MODULE
# -----------------------------------------------------------------------------
# This file defines the flow for download and customization of requested OS
# cloud images locally on the control machine.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# STEP 1: PREPARE LOCAL IMAGE ON CONTROL MACHINE
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

  # Destroy notification message
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
