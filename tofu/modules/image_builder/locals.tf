# -----------------------------------------------------------------------------
# LOCAL VARIABLES - IMAGE BUILDER MODULE
# -----------------------------------------------------------------------------

locals {
  # OS Registry containing configuration variables and pattern formats for building target URLs.
  os_registry = {
    ubuntu = {
      base_url          = "https://cloud-images.ubuntu.com/releases/server"
      filename_pattern  = "ubuntu-%s-server-cloudimg-amd64.img"
      checksum_url      = "https://cloud-images.ubuntu.com/releases/server/%s/release/SHA256SUMS"
      checksum_regex    = "(?m)^([a-f0-9]{64})\\s+\\*?%s$"
      agent_package     = "qemu-guest-agent"
      dependencies      = ["liburing2", "ubuntu-virt", "ubuntu-helper-virt-hwe"]
      customize_script  = "customize_ubuntu.sh.tftpl"
    }
  }

  # Compile full configurations dynamically
  os_images = {
    for key, val in var.requested_images : key => {
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

  # Decide if we need to run local-exec image builder.
  # Skip building if the file is already uploaded to the destination datastore, 
  # or if the customized file is already present in the local cache.
  build_decisions = {
    for key, def in local.final_image_defs : key => (contains(var.existing_images, def.target_filename) || fileexists(def.target_path)) ? 0 : 1
  }
}
