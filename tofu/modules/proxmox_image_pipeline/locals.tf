# -----------------------------------------------------------------------------
# LOCAL VARIABLES
# -----------------------------------------------------------------------------
# Processes inputs and determines the image metadata, download configurations,
# and build/upload decisions.
# -----------------------------------------------------------------------------

locals {
  # 1. Scan var.resources directly for target VM OS types and versions.
  # This decouples the image pipeline from the main normalization logic.
  raw_requested_images = distinct(concat(
    # Scan cluster-level config
    [
      for group in var.resources : {
        os_type    = try(group.vm_config.os_type, var.default_os_type)
        os_version = try(group.vm_config.os_version, null)
      }
      if try(group.type, "") == "vm" && try(group.vm_config.os_version, null) != null
    ],
    # Scan node-level overrides
    flatten([
      for group in var.resources : [
        for node in try(group.nodes, {}) : {
          os_type    = try(node.vm_config.os_type, try(group.vm_config.os_type, var.default_os_type))
          os_version = try(node.vm_config.os_version, try(group.vm_config.os_version, null))
        }
        if try(node.vm_config.os_version, null) != null || try(group.vm_config.os_version, null) != null
      ]
      if try(group.type, "") == "vm"
    ])
  ))

  # Filter out any entries that don't have a valid os_version
  requested_images = [
    for img in local.raw_requested_images : img
    if img.os_version != null
  ]

  # Map OS configurations using a composite key: "os_type-os_version"
  os_images_map = {
    for img in local.requested_images : "${img.os_type}-${img.os_version}" => {
      os_type    = img.os_type
      os_version = img.os_version
    }
  }

  # OS Registry containing configuration variables and pattern formats for building target URLs.
  # Right now we focus on Ubuntu but scaffold the structure for others.
  os_registry = {
    ubuntu = {
      base_url          = "https://cloud-images.ubuntu.com/releases/server"
      filename_pattern  = "ubuntu-%s-server-cloudimg-amd64.img"
      checksum_url      = "https://cloud-images.ubuntu.com/releases/server/%s/release/SHA256SUMS"
      checksum_regex    = "(?m)^([a-f0-9]{64})\\s+\\*?%s$"
      agent_package     = "qemu-guest-agent"
      dependencies      = ["liburing2"]
      customize_script  = "customize_ubuntu.sh.tftpl"
    }
  }

  # Compile full configurations dynamically
  os_images = {
    for key, val in local.os_images_map : key => {
      os_type           = val.os_type
      os_version        = val.os_version
      base_url          = "${local.os_registry[val.os_type].base_url}/${val.os_version}/release"
      upstream_filename = format(local.os_registry[val.os_type].filename_pattern, val.os_version)
      checksum_url      = format(local.os_registry[val.os_type].checksum_url, val.os_version)
      checksum_regex    = format(local.os_registry[val.os_type].checksum_regex, format(local.os_registry[val.os_type].filename_pattern, val.os_version))
      agent_package     = local.os_registry[val.os_type].agent_package
      dependencies      = local.os_registry[val.os_type].dependencies
      customize_script  = local.os_registry[val.os_type].customize_script
    }
  }

  # Parse storage contents from the data lookup. Handles empty/null storage data gracefully.
  proxmox_storage_content   = jsondecode(data.http.proxmox_storage_content.response_body)
  existing_files_on_proxmox = [
    for item in (lookup(local.proxmox_storage_content, "data", null) != null ? local.proxmox_storage_content.data : []) :
    regex(".*/(.*)", item.volid)[0]
    if try(item.volid, null) != null
  ]

  # Parse SHA256 checksums from downloaded manifests
  image_state = {
    for key, config in local.os_images : key => {
      upstream_hash = regex(config.checksum_regex, data.http.checksums[key].response_body)[0]
    }
  }

  # Final target image definitions
  final_image_defs = {
    for key, config in local.os_images : key => {
      os_type           = config.os_type
      os_version        = config.os_version
      upstream_filename = config.upstream_filename
      base_url          = config.base_url
      upstream_hash     = local.image_state[key].upstream_hash
      target_filename   = "${config.os_type}-${config.os_version}-amd64-cloudinit-${substr(local.image_state[key].upstream_hash, 0, 8)}.qcow2"
      target_path       = "${var.local_cache_dir}/${config.os_type}-${config.os_version}-amd64-cloudinit-${substr(local.image_state[key].upstream_hash, 0, 8)}.qcow2"
      agent_package     = config.agent_package
      dependencies      = config.dependencies
      customize_script  = config.customize_script
    }
  }

  # Decide if we need to run local-exec image builder
  build_decisions = {
    for key, def in local.final_image_defs : key => contains(local.existing_files_on_proxmox, def.target_filename) ? 0 : 1
  }

  # Output image paths for modules consuming this output
  image_paths = {
    for key, def in local.final_image_defs : key => "${var.target_datastore}:import/${def.target_filename}"
  }
}
