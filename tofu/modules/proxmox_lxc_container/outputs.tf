output "container_details" {
  description = "A map of details for the containers created by this module."
  value = {
    for key, container in proxmox_lxc.server :
    key => {
      hostname     = container.hostname
      vmid         = container.vmid
      ip_address   = split("/", container.network[0].ip)[0]
      tags         = container.tags
    }
  }
}