# -----------------------------------------------------------------------------
# ANSIBLE DYNAMIC INVENTORY GENERATION
#
# This file uses the 'local_file' resource with the 'templatefile' function
# to directly create the Ansible inventory file. This is the most robust
# pattern for generating complex text files, as it gives us full control
# over the output format and avoids unexpected quoting issues.
# -----------------------------------------------------------------------------

locals {
  # --- Create a Flattened List of All Host-to-Group Mappings ---
  # This is the core logic. It creates a simple list of objects, where each
  # object represents one hostname belonging to one group.
  host_group_mappings = flatten([
    # Loop through each enabled resource group from our main variables file...
    for group_name, group_data in var.resource_groups : [
      # ...then loop through each node defined within that group.
      for hostname, node_data in group_data.nodes : [
        # For each tag and the resource type associated with this host...
        for group_name in toset(concat(group_data.tags, [group_data.type])) : {
          # ...create a simple mapping object.
          group    = group_name
          hostname = hostname
        }
      ]
    ] if group_data.enabled # Only process enabled groups
  ])

  # --- Transform the Flat List into the Grouped Inventory Map ---
  # This just groups hostnames by their tag/type.
  inventory_groups_with_hosts = {
    for mapping in local.host_group_mappings :
    mapping.group => mapping.hostname...
  }

  # --- Create a Master Map of All Node Details ---
  # This local combines the outputs from both modules into a single,
  # easy-to-query map of all created nodes.
  all_created_nodes = merge(
    # First, create a single flat map of all QEMU nodes from the module outputs.
    merge([
      for group_key, module_instance in module.qemu_groups : module_instance.vm_details
    ]...),

    # Second, do the same for all LXC containers.
    merge([
      for group_key, module_instance in module.lxc_groups : module_instance.container_details
    ]...)
  )
}

# --- Create the Ansible Inventory File Directly ---
resource "local_file" "ansible_inventory" {
  # The 'content' is now rendered from our template file.
  content = templatefile("${path.module}/templates/ansible_inventory.yml.tftpl", {
    # We pass our calculated data into the template as variables.
    inventory_groups = {
      for group_name, hostnames in local.inventory_groups_with_hosts :
      group_name => {
        for host in hostnames :
        host => local.all_created_nodes[host].ip_address
      }
    }
    ansible_user     = var.user_profile.username
  })

  # The 'filename' specifies where to save the file.
  filename = "${path.root}/../ansible/inventory.yml"
}