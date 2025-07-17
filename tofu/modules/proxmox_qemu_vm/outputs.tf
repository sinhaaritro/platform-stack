output "vm_details" {
  description = "A map of details for the VMs created by this module."
  value = {
    for key, vm in proxmox_vm_qemu.server :
    key => {
      hostname     = vm.name
      vmid         = vm.vmid
      # Extract just the IP address from the 'ipconfig0' string.
      ip_address   = regex("ip=([\\d\\.]+)/", vm.ipconfig0)[0]
      default_user = var.user_profile.username
      tags         = vm.tags
    }
  }
}