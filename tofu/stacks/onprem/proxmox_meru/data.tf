# -----------------------------------------------------------------------------
# DATA SOURCES - STACK
# -----------------------------------------------------------------------------

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
