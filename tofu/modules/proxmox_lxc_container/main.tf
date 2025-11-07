resource "proxmox_virtual_environment_container" "example_lxc" {
  # --- General Settings ---
  node_name     = "moo-moo"
  vm_id         = 800
  description   = "Example LXC"
  start_on_boot = true
  started       = true
  unprivileged  = true
  features {
    nesting = true
  }

  # --- OS Template ---
  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
    type             = "debian"
  }

  # --- Disk Configuration ---
  disk {
    datastore_id = "local-thin"
    size         = 8
  }

  # --- Hardware Resources ---
  cpu {
    cores = 1
  }
  memory {
    dedicated = 512
  }

  # --- Network Configuration ---
  network_interface {
    name    = "net0"
    bridge  = "vmbr0"
    vlan_id = 1
  }

  # --- THIS IS THE CORRECT INITIALIZATION BLOCK ---
  initialization {
    hostname = "example-lxc-01"
    ip_config {
      ipv4 {
        address = "192.168.0.101/24"
      }
    }

    user_account {
      password = "A-Secure-Password-You-Will-Change"
      keys     = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwC01G8nJScuxp7Cga8uUsnHUW2IpXXiiTw1gzhEL4P RyzenWindows"]
    }
  }
  # ----------------------------------------------

  # --- Lifecycle Management ---
  lifecycle {
    prevent_destroy = true
  }
}
