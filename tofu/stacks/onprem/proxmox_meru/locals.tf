# -----------------------------------------------------------------------------
# LOCAL VARIABLES - STACK
# -----------------------------------------------------------------------------

locals {
  # Parse storage contents from the native Proxmox data lookup.
  existing_files_on_proxmox = [
    for item in data.proxmox_files.proxmox_files.files :
    item.file_name
  ]

  # Maps the composite builder key (e.g., "ubuntu-24.04") to the uploaded path on Proxmox datastore.
  image_import_paths = {
    for key, img in module.image_builder.built_images :
    key => "${var.target_datastore}:import/${img.filename}"
  }
}
