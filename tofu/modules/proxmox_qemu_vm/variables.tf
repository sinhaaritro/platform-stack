variable "group_data" {
  type = object({
    template = string
    nodes    = map(object({ id = number, ip = string }))
    tags     = list(string)
  })
  description = "An object containing the specific data for a single group of VMs."
}

variable "hardware_profile" {
  type = object({
    cores     = number
    memory    = number
    disk_size = string
  })
  description = "The hardware profile (cores, memory, disk size) to apply to all VMs in this group."
}

# General environment settings passed down from the root
variable "target_node" { type = string }
variable "storage_pool" { type = string }
variable "network_bridge" { type = string }
variable "gateway" { type = string }
variable "cidr_mask" { type = number }

# User settings passed down from the root
variable "user_profile" { type = object({ username = string, package_upgrade = bool }) }
variable "user_credentials" { type = object({ password = string, ssh_public_keys = list(string) }) }