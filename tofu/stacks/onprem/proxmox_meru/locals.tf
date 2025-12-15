# -----------------------------------------------------------------------------
# LOCAL VARIABLES
# -----------------------------------------------------------------------------
# This file centralizes all internal calculations and name definitions for the
# 'proxmox_meru' stack. These are not user-configurable inputs; they are used
# to simplify the code and reduce repetition in other files.
# -----------------------------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # STEP 1: Gathering information
  # This section contains all the configurable details for the master cloud
  # image. To upgrade to a new Ubuntu version, you only need to change the
  # values in this section. These values are derived from the 
  # URL: https://cloud-images.ubuntu.com/releases/server/xx.xx/release/
  # ---------------------------------------------------------------------------

  # 1a. OS Configuration

  # The architecture of the image to use.
  architecture = "amd64"

  # Infer OS versions from usage:
  # Scan the 'var.resources' map to find all unique 'os_version' values requested
  # by the user (either at group level or node level).
  requested_versions = distinct(concat(
    # Scan Groups
    [
      for group in var.resources : group.vm_config.os_version
      if group.type == "vm" && try(group.vm_config.os_version, null) != null
    ],
    # Scan Nodes (nested)
    flatten([
      for group in var.resources : [
        for node in group.nodes : node.vm_config.os_version
        if try(node.vm_config.os_version, null) != null
      ]
    ])
  ))

  # Generate OS Image Configurations:
  # Build a map where each key is a version (e.g. "24.04") and the value is its config.
  os_images = {
    for ver in local.requested_versions : ver => {
      version  = ver
      base_url = "https://cloud-images.ubuntu.com/releases/server/${ver}/release"
      # Constructed filename for download
      upstream_filename = "ubuntu-${ver}-server-cloudimg-${local.architecture}.img"
      # URL to the checksums file
      checksum_url = "https://cloud-images.ubuntu.com/releases/server/${ver}/release/SHA256SUMS"
    }
  }

  # 1b. Proxmox Datastore Configuration

  # First, parse the JSON response from the Proxmox API call in 'data.tf'.
  proxmox_storage_content = jsondecode(data.http.proxmox_storage_content.response_body)

  # Next, create a clean list of just the filenames. The Proxmox API returns a
  # in the format 'datastore:content/filename'. We use a for-loop with a regex
  # to extract only the filename part from each item in the list.
  existing_files_on_proxmox = [for item in local.proxmox_storage_content.data : regex(".*/(.*)", item.volid)[0]]

  # ---------------------------------------------------------------------------
  # STEP 2: DEFINE DESIRED STATE AND MAKE BUILD DECISION
  # This section processes the data gathered in 'data.tf' to determine the
  # final state we want and to decide if the image needs to be built.
  # -----------------------------------------------------------------------------

  # 2a: Image Hashes
  # Calculate unique hash for EACH version
  image_state = {
    for ver, config in local.os_images : ver => {
      # 1. Get Hash from Data Source (using the version as key)
      upstream_hash = regex("(?m)^([a-f0-9]{64})\\s+\\*?${config.upstream_filename}$", data.http.ubuntu_checksums[ver].response_body)[0]
    }
  }

  # 2b: Target Image Definitions
  # Define a temporary directory for all downloaded artifacts.
  temp_artifacts_path = "/var/tmp/tofu-artifacts/"

  # Combine config with hash to create final target definitions
  # Construct the unique, node-agnostic, and versioned filename we want to
  # exist on the Proxmox datastore. Using the first 8 characters of the hash
  # makes the filename unique to this specific version of the Ubuntu image.
  # Format: OS-Version-Arch-cloudinit-ShortHash.qcow2
  final_image_defs = {
    for ver, config in local.os_images : ver => {
      upstream_filename = config.upstream_filename
      base_url          = config.base_url
      upstream_hash     = local.image_state[ver].upstream_hash

      # Unique target filename
      target_filename = "ubuntu-${ver}-${local.architecture}-cloudinit-${substr(local.image_state[ver].upstream_hash, 0, 8)}.qcow2"

      # Full local path
      target_path = "${local.temp_artifacts_path}/ubuntu-${ver}-${local.architecture}-cloudinit-${substr(local.image_state[ver].upstream_hash, 0, 8)}.qcow2"
    }
  }

  # 2c: Make Build Decision
  # Determine build necessity for EACH version
  build_decisions = {
    for ver, def in local.final_image_defs : ver => contains(local.existing_files_on_proxmox, def.target_filename) ? 0 : 1
  }

  # This map allows the module to look up the final Proxmox ID by version
  final_image_paths = {
    for ver, def in local.final_image_defs : ver => "${var.target_datastore}:import/${def.target_filename}"
  }

  # ---------------------------------------------------------------------------
  # STEP 3: OFFLINE PACKAGE DEFINITIONS
  # This section defines the agent software and its dependencies that will be
  # downloaded and installed offline into the image.
  # ---------------------------------------------------------------------------

  # 3a. The name of the main package to install.
  agent_package = "qemu-guest-agent"

  # 3b. A list of any dependency packages required by the main package.
  agent_dependencies = ["liburing2"]
}
