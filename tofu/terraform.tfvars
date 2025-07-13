# # Proxmox Connection Details - REPLACE WITH YOUR VALUES
# proxmox_url = "https://192.168.0.2:8006/api2/json"

# # Proxmox Credentials
# # YES I KNOW WE SHOULD NOT PUT SENSITIVE INFORMATION HERE.
# # BUT THIS USER IS DISABLED BY DEFAULT
# proxmox_user     = "vmprovisioner@pve"
# proxmox_password = "vmprovisioner"

# # VM Configuration
# template_name  = "ubuntu-cloud-init"
# target_node    = "moo-moo"


# # SSH Public Key for Login
# ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwC01G8nJScuxp7Cga8uUsnHUW2IpXXiiTw1gzhEL4P RyzenWindows"

# # Cloud-Init User Configuration Object
# cloud_init_user = {
#   username = "dev"
#   password = "dev"
#   ssh_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwC01G8nJScuxp7Cga8uUsnHUW2IpXXiiTw1gzhEL4P RyzenWindows"
#   upgrade = true
# }

# # The list of VMs to create
# laboon_cluster_enabled = true
# laboon_vms = {
#   "laboon-1" = {
#     vmid = 1002
#     ip   = "192.168.0.4"
#   }
#   "laboon-2" = {
#     vmid = 1003
#     ip   = "192.168.0.5"
#   }
#   "laboon-3" = {
#     vmid = 1004
#     ip   = "192.168.0.6"
#   }
# }

# # VM Properties
# vm_cores = 2
# vm_memory = 2048
# storage_pool = "local-lvm"
# vm_disk_size = "16G"

# network_bridge = "vmbr0"
# gateway_ip     = "192.168.0.1"