# -----------------------------------------------------------------------------
# LOCAL VARIABLES
# -----------------------------------------------------------------------------
# Replaced logic: Image calculations moved to modules/proxmox_image_pipeline.
# This file now maps the module outputs to ensure backward compatibility.
# -----------------------------------------------------------------------------

locals {
  # Map the composite module output key (e.g., "ubuntu-24.04") back to the
  # version-only key (e.g., "24.04") expected by the downstream VM resources.
  final_image_paths = {
    for composite_key, path in module.image_pipeline.image_paths :
    split("-", composite_key)[1] => path
    if startswith(composite_key, "ubuntu-")
  }
}
