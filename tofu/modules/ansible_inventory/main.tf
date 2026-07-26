# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION - ANSIBLE INVENTORY GENERATION
# -----------------------------------------------------------------------------

locals {
  # --- STEP 6.A: Create a Flattened List of All Host-to-Group Mappings ---
  # This is the first phase of the render. It creates a simple list of objects,
  # where each object represents one host belonging to one group. We create a
  # mapping for every tag the host has. This logic only uses data known at
  # 'plan' time (names and tags).
  host_group_mappings = flatten([
    for host in var.host_list : [
      for group_name in distinct(concat(
        try(host.tags, []),
        [try(host.app_key, null)],
        [try(host.node_name, null)],
        [try(host.type, null)],
        keys(try(host.ansible_groups, {}))
        )) : {
        group = replace(group_name, "-", "_")
        host  = host.name
      } if group_name != null
    ]
  ])

  # --- STEP 6.B: Transform the Flat List into a Grouped Map ---
  # This takes the flat list from the previous step and groups the hostnames
  # by their group name (tag). The result is a map where the key is the group
  # and the value is a list of hostnames.
  inventory_groups_with_hosts = {
    for mapping in local.host_group_mappings :
    mapping.group => mapping.host...
  }

  # Index host_list by name for quick lookup during inventory generation
  host_index = { for host in var.host_list : host.name => host }
}

# --- STEP 6.C: Create the Ansible Inventory File Directly ---
resource "local_file" "ansible_inventory" {
  # The 'content' is rendered from our template file.
  content = templatefile("${path.module}/templates/ansible_inventory.yml.tftpl", {

    # This is the second phase of the render. This expression is evaluated
    # during the 'apply' phase, after the hosts have been created.
    inventory_data = {
      for group_name, hostnames in local.inventory_groups_with_hosts :
      group_name => {
        # 1. GENERATE GROUP VARIABLES
        # We do not generate group-level variables from the individual host definitions
        # to prevent conflicts and overwrites. Instead, we push these down as host-level variables.
        vars = {}

        # 2. GENERATE HOSTS, USER AND IPs
        hosts = {
          for host in hostnames :
          host => merge(
            {
              ansible_host     = try(local.host_index[host].ipv4_address, "IP_PENDING")
              ansible_user     = try(local.host_index[host].user_account_username, "root")
              ansible_password = try(local.host_index[host].ansible_password, null)
            },
            # Merge in the variables for this specific group from the host's definition
            try(local.host_index[host].ansible_groups[group_name], {})
          )
        }
      }
    }
  })

  # The 'filename' specifies where to save the file.
  filename = "${var.inventory_dir}/${var.stack_name}.yml"
}
