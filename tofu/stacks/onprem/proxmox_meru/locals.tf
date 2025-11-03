# -----------------------------------------------------------------------------
# LOCAL VARIABLES
# -----------------------------------------------------------------------------
# This file centralizes all internal calculations and name definitions for the
# 'proxmox_meru' stack. These are not user-configurable inputs; they are used
# to simplify the code and reduce repetition in other files.
# -----------------------------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # STEP 1: DEFINE BASE IMAGE PARAMETERS
  # This section contains all the configurable details for the master cloud
  # image. To upgrade to a new Ubuntu version, you only need to change the
  # values in this section. These values are derived from the 
  # URL: https://cloud-images.ubuntu.com/releases/server/xx.xx/release/
  # ---------------------------------------------------------------------------

  # The version number of the Ubuntu release to use.
  ubuntu_version = "25.04"

  #   # The architecture of the image to use.
  architecture = "amd64"

  # The base URL for the Ubuntu cloud image repository, constructed from the version.
  base_url = "https://cloud-images.ubuntu.com/releases/server/${local.ubuntu_version}/release"

  # The full filename of the official image to be downloaded from the repository.
  upstream_image_filename = "ubuntu-${local.ubuntu_version}-server-cloudimg-${local.architecture}.img"

  # The full URL to the file containing the official SHA256 hashes for verification.
  checksum_url = "${local.base_url}/SHA256SUMS"

  # ---------------------------------------------------------------------------
  # OFFLINE PACKAGE DEFINITIONS
  # This section defines the agent software and its dependencies that will be
  # downloaded and installed offline into the image.
  # ---------------------------------------------------------------------------

  # The name of the main package to install.
  agent_package = "qemu-guest-agent"

  # A list of any dependency packages required by the main package.
  agent_dependencies = ["liburing2"]

  # ---------------------------------------------------------------------------
  # STEP 2: DEFINE DESIRED STATE AND MAKE BUILD DECISION
  # This section processes the data gathered in 'data.tf' to determine the
  # final state we want and to decide if the image needs to be built.
  # ---------------------------------------------------------------------------

  # -- 2.a: Construct Target Filename --

  # First, extract the hash from the upstream manifest file. This hash represents
  # the specific version of the upstream image we want to use.
  upstream_image_hash = regex("(?m)^([a-f0-9]{64})\\s+\\*?${local.upstream_image_filename}$", data.http.ubuntu_checksums.response_body)[0]

  # Define a temporary directory for all downloaded artifacts.
  temp_artifacts_path = "/var/tmp/tofu-artifacts/"

  # Now, construct the unique, node-agnostic, and versioned filename we want to
  # exist on the Proxmox datastore. Using the first 8 characters of the hash
  # makes the filename unique to this specific version of the Ubuntu image.
  # Format: OS-Version-Arch-cloudinit-ShortHash.qcow2
  target_image_filename = "ubuntu-${local.ubuntu_version}-${local.architecture}-cloudinit-${substr(local.upstream_image_hash, 0, 8)}.qcow2"

  # The full path to the artifact in the shared cache.
  target_image_path = "${local.temp_artifacts_path}/${local.target_image_filename}"

  # -- 2.b: Make Build Decision --

  # First, parse the JSON response from the Proxmox API call in 'data.tf'.
  proxmox_storage_content = jsondecode(data.http.proxmox_storage_content.response_body)

  # Next, create a clean list of just the filenames. The Proxmox API returns a
  # 'volid' in the format 'datastore:content/filename'. We use a for-loop with a
  # regex to extract only the filename part from each item in the list.
  existing_files_on_proxmox = [for item in local.proxmox_storage_content.data : regex(".*/(.*)", item.volid)[0]]

  # Finally, check if our target filename exists in the list of files on Proxmox.
  # The contains() function returns 'true' if the element is found, 'false' otherwise.
  image_already_exists_on_proxmox = contains(local.existing_files_on_proxmox, local.target_image_filename)

  # Convert the boolean result into a number (0 or 1). This is necessary because
  # the 'count' meta-argument in a resource requires a number, not a boolean.
  # If the image exists, we build 0. If it doesn't, we build 1.
  image_needs_to_be_built = local.image_already_exists_on_proxmox ? 0 : 1

  # --- 5a. Determine Final Image Path ---
  # This local variable constructs the full, predictable path (or "Volume ID")
  # for the master image on the Proxmox datastore. This is the path that the
  # module will use for the 'import_from' instruction.
  final_image_path = "${var.target_datastore}:import/${local.target_image_filename}"
}
