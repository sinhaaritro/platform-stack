# -----------------------------------------------------------------------------
# DATA SOURCES
# -----------------------------------------------------------------------------
# Handles API lookups and metadata collection from external sources.
# -----------------------------------------------------------------------------

data "http" "checksums" {
  for_each = local.os_images

  url = each.value.checksum_url

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Error validating OS version '${each.key}'. The URL '${self.url}' returned status ${self.status_code}. Please check if this is a valid release version."
    }
  }
}

data "http" "proxmox_storage_content" {
  url = "${var.proxmox_connection.url}/nodes/${var.target_node}/storage/${var.target_datastore}/content"

  insecure = var.proxmox_connection.insecure_tls

  request_headers = {
    Authorization = (
      var.proxmox_connection.auth_method == "token"
      ? "PVEAPIToken=${var.proxmox_connection.token_auth.id}=${var.proxmox_connection.token_auth.secret}"
      : var.proxmox_connection.auth_method == "ticket"
      ? "PVEAuthCookie=${var.proxmox_connection.ticket_auth.auth_ticket}"
      : ""
    )
  }
}
