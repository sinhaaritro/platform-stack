# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION - ANSIBLE INVENTORY GENERATION
# -----------------------------------------------------------------------------

locals {
  # --- STEP 6.A: Create a Flattened List of All Host-to-Group Mappings ---
  # This is the first phase of the render. It creates a simple list of objects,
  # where each object represents one VM belonging to one group. We create a
  # mapping for every tag the VM has. This logic only uses data known at
  # 'plan' time (names and tags).
  host_group_mappings = flatten([
    # Loop through each of our final, fully resolved VM objects...
    for vm in var.vm_list : [
      # 1. Create a single list containing all possible group names for this VM.
      #    - The VM's tags (e.g., "web", "ubuntu")
      #    - The VM's application key (e.g., "web_server")
      #    - The VM's Proxmox node name (e.g., "moo-moo")
      # 2. Use 'distinct()' to ensure there are no duplicate group names.
      for group_name in distinct(concat(
        try(vm.tags, []),
        [try(vm.app_key, null)],
        [try(vm.node_name, null)],
        [try(vm.type, null)],
        keys(try(vm.ansible_groups, {}))
        )) : {

        # 3. Create the simple mapping object for each group.
        group = replace(group_name, "-", "_")
        host  = vm.name
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
}

# --- STEP 6.C: Create the Ansible Inventory File Directly ---
resource "local_file" "ansible_inventory" {
  # The 'content' is rendered from our template file.
  content = templatefile("${path.module}/templates/ansible_inventory.yml.tftpl", {

    # This is the second phase of the render. This expression is evaluated
    # during the 'apply' phase, after the VMs have been created.
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
              ansible_host = try([for addr in flatten(var.vm_outputs[host].ipv4_addresses) : addr if addr != "127.0.0.1"][0], "IP_PENDING")
              ansible_user = var.vm_list[host].user_account_username
            },
            # Merge in the variables for this specific group from the host's definition
            try(var.vm_list[host].ansible_groups[group_name], {})
          )
        }
      }
    }
  })

  # The 'filename' specifies where to save the file.
  filename = "${var.inventory_dir}/${var.stack_name}.yml"
}
