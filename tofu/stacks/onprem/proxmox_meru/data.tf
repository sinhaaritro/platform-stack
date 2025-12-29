# -----------------------------------------------------------------------------
# STEP 1: GATHER INFORMATION (DATA SOURCES)
# -----------------------------------------------------------------------------
# This file is responsible for all read-only operations that gather data from
# external sources, such as public websites and the Proxmox API.
# -----------------------------------------------------------------------------


# 1a. Fetch Upstream Manifest
# Makes an API call to the Ubuntu website to download the latest SHA256SUMS
# file. This file acts as our "desired version" manifest, telling us the
# official checksum for the cloud image we want to use.
data "http" "ubuntu_checksums" {
  for_each = local.os_images

  url = each.value.checksum_url

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Error validating Ubuntu version '${each.key}'. The URL '${self.url}' returned status ${self.status_code}. Please check that '${each.key}' is a valid Ubuntu release version."
    }
  }
}


# 1b. Fetch Proxmox Datastore Manifest
# Makes an authenticated API call to the Proxmox server to get a JSON list
# of all files currently on the target datastore. This serves as our
# "current state" manifest, telling us what images already exist.
data "http" "proxmox_storage_content" {
  # The full URL to the storage content endpoint, constructed from variables.
  url = "${var.proxmox_connection.url}/nodes/${var.target_node}/storage/${var.target_datastore}/content"

  # Allow insecure (self-signed) TLS certificates, matching the provider config.
  # TODO: Make it false
  insecure = true

  # Provide the API token in the Authorization header for authentication.
  request_headers = {
    Authorization = "PVEAPIToken=${var.proxmox_connection.token_auth.id}=${var.proxmox_connection.token_auth.secret}"
  }
}
