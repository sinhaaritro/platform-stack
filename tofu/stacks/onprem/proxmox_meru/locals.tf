# -----------------------------------------------------------------------------
# LOCAL VARIABLES - STACK
# -----------------------------------------------------------------------------

locals {
  # Parse storage contents from the Proxmox API data lookup.
  # Handles empty/null storage data gracefully.
  proxmox_storage_content   = jsondecode(data.http.proxmox_storage_content.response_body)
  existing_files_on_proxmox = [
    for item in try(local.proxmox_storage_content.data, []) :
    basename(item.volid)
    if try(item.volid, null) != null
  ]

  # Maps the composite builder key (e.g., "ubuntu-24.04") to the uploaded path on Proxmox datastore.
  image_import_paths = {
    for key, img in module.image_builder.built_images :
    key => "${var.target_datastore}:import/${img.filename}"
  }

  # Maps the composite module key (e.g., "ubuntu-24.04") back to the
  # version-only key (e.g., "24.04") expected by the downstream VM resources.
  final_image_paths = {
    for composite_key, path in local.image_import_paths :
    (split("-", composite_key))[1] => path
    if startswith(composite_key, "ubuntu-")
  }
}
