
# # -----------------------------------------------------------------------------
# # ANSIBLE DYNAMIC INVENTORY GENERATION
# # -----------------------------------------------------------------------------
# # This file processes the created VM resources and generates a dynamic
# # Ansible inventory file using a template. It correctly handles computed
# # values like IP addresses by deferring their access until the 'apply' phase.
# # -----------------------------------------------------------------------------

# locals {
#   # --- STEP 7.A: Create a Flattened List of All Host-to-Group Mappings ---
#   # This is the first phase of the render. It creates a simple list of objects,
#   # where each object represents one VM belonging to one group. We create a
#   # mapping for every tag the VM has. This logic only uses data known at
#   # 'plan' time (names and tags).
#   host_group_mappings = flatten([
#     # Loop through each of our final, fully resolved VM objects...
#     for vm in local.final_vm_list : [
#       # 1. Create a single list containing all possible group names for this VM.
#       #    - The VM's tags (e.g., "web", "ubuntu")
#       #    - The VM's application key (e.g., "web_server")
#       #    - The VM's Proxmox node name (e.g., "moo-moo")
#       # 2. Use 'distinct()' to ensure there are no duplicate group names.
#       for group_name in distinct(concat(
#         try(vm.tags, []),
#         [try(vm.app_key, null)],
#         [try(vm.node_name, null)],
#         [try(vm.type, null)]
#         )) : {

#         # 3. Create the simple mapping object for each group.
#         group = group_name
#         host  = vm.name
#       } if group_name != null
#     ]
#   ])

#   # --- STEP 7.B: Transform the Flat List into a Grouped Map ---
#   # This takes the flat list from the previous step and groups the hostnames
#   # by their group name (tag). The result is a map where the key is the group
#   # and the value is a list of hostnames.
#   inventory_groups_with_hosts = {
#     for mapping in local.host_group_mappings :
#     mapping.group => mapping.host...
#   }

#   # --- STEP 7.C: Create a Master Map of All Created Module Outputs ---
#   # This local combines the outputs from the 'proxmox_vms' module into a single,
#   # easy-to-query map, keyed by the VM's name. This will hold the final,
#   # computed data like IP addresses after the 'apply' is complete.
#   all_created_vms = {
#     for key, vm_module in module.proxmox_vms :
#     key => vm_module.vm_details
#   }
# }

# # --- STEP 7.D: Create the Ansible Inventory File Directly ---
# resource "local_file" "ansible_inventory" {
#   # The 'content' is rendered from our template file.
#   content = templatefile("${path.module}/templates/ansible_inventory.yml.tftpl", {

#     # This is the second phase of the render. This expression is evaluated
#     # during the 'apply' phase, after the VMs have been created.
#     inventory_groups = {
#       for group_name, hostnames in local.inventory_groups_with_hosts :
#       group_name => {
#         for host in hostnames :
#         # For each host, we look up its details in the master map and get its IP.
#         host => {
#           # The 'try' function provides a safe fallback in case the IP is not ready.
#           ansible_host = try([for addr in flatten(local.all_created_vms[host].ipv4_addresses) : addr if addr != "127.0.0.1"][0], "IP_PENDING")
#           # We look up the final, merged username for this specific host.
#           ansible_user = local.final_vm_list[host].user_account_username
#         }
#       }
#     }
#   })

#   # The 'filename' specifies where to save the file.
#   filename = "${path.root}/../../../../ansible/inventory.yml"

#   # This explicit dependency is good practice.
#   depends_on = [module.proxmox_vms]
# }
