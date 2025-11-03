# -----------------------------------------------------------------------------
# STACK CONFIGURATION FOR 'proxmox_meru'
# -----------------------------------------------------------------------------
# This file provides all the non-secret data for this specific stack.
# -----------------------------------------------------------------------------
# Run commands for this file: 
# ```bash
# tofu -chdir="tofu/stacks/onprem/proxmox_meru" apply \
#   -var-file="proxmox_meru.tfvars" \
#   -var-file=<(ansible-vault view --vault-password-file <(echo "$ANSIBLE_VAULT_PASSWORD") tofu/stacks/onprem/proxmox_meru/proxmox_meru.secret.tfvars)
# ```

# --- Target Proxmox Environment ---
target_node      = "moo-moo"
target_datastore = "data-storage"

# --- Resource Definations ---
# This map defines all the VMs to be created by this stack. The map key is
# used as the default name for the VM.
resources = {
  "web_server" = {
    enabled = true
    type    = "vm"
    tags    = ["web", "Ansible"]

    node_name = "moo-moo"
    # description       = "Primary web server, managed by OpenTofu. Ubuntu 24.04."
    disk_datastore_id = "local-thin"


    nodes = {
      "web-server-01" = {
        vm_id                 = 700
        tags                  = ["web", "ubuntu"]
        disk_datastore_id     = "data-storage"
        cloud_init_secret_key = "web_admins"
        ipv4_address          = "192.168.0.101/24"
      },
      "web-server-02" = {
        vm_id                 = 701
        tags                  = ["web", "ubuntu"]
        disk_datastore_id     = "data-storage"
        cloud_init_secret_key = "dev"
        ipv4_address          = "192.168.0.102/24"
      }
    }
  },
  "db_server" = {
    enabled = true
    type    = "vm"
    tags    = ["db", "Ansible"]

    node_name             = "moo-moo"
    description           = "Primary database servers. Ubuntu 24.04."
    cloud_init_secret_key = "dev"

    nodes = {
      "db-server-01" = {
        vm_id        = 600
        tags         = ["mongo"]
        ipv4_address = "192.168.0.103/24"
      },
      "db-server-02" = {
        vm_id        = 601
        description  = "Primary database servers, for postgress. Ubuntu 24.04."
        tags         = ["pg"]
        disk_size    = 16
        ipv4_address = "192.168.0.104/24"
      },
    }
  },
}
