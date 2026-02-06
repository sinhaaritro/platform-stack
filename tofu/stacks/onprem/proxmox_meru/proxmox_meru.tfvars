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

# Target Proxmox Environment
target_node      = "moo-moo"
target_datastore = "data-storage"

# Resource Definations
# This map defines all the VMs to be created by this stack. The map key is
# used as the default name for the VM.
resources = {
  "kind" = {
    enabled     = false
    type        = "vm"
    node_name   = "moo-moo"
    description = "Kubernetes servers. Ubuntu 24.04."
    tags        = ["kind", "ansible", "ubuntu", "kind"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Etc/GMT"
        "user_locale"   = "en_US.UTF-8"
      }
    }

    vm_config = {
      cpu_cores         = 2
      memory_size       = 2048
      disk_datastore_id = "local-thin"
      os_version        = "24.04"
      disk_size         = 16
    }

    nodes = {
      "kind-01" = {
        vm_id           = 700
        cloud_init_user = "dev"
        vm_config = {
          disk_datastore_id = "data-storage"
          ipv4_address      = "192.168.0.70/24"
        }
      }
    }
  },
  "ruth" = {
    enabled     = true
    type        = "vm"
    node_name   = "moo-moo"
    description = "Kubernets servers. Ubuntu 24.04."
    tags        = ["ruth", "ansible", "ubuntu", "kubeadm", "k_management"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Asia/Kolkata"
        "user_locale"   = "en_US.UTF-8"
      },
      "kubeadm" = {
        "kubeadm_bootstrap_node" : "ruth-01"
      },
      "k_management" = {
        "argocd_managed_fleets" : "arr"
      }
    }

    vm_config = {
      cpu_cores         = 3
      memory_size       = 6144
      disk_datastore_id = "local-thin"
      os_version        = "24.04"
      disk_size         = 24
    }

    nodes = {
      "ruth-01" = {
        vm_id           = 1020
        tags            = ["k_control"]
        cloud_init_user = "dev"
        vm_config = {
          cpu_cores    = 4
          memory_size  = 6144
          ipv4_address = "192.168.0.20/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "data-storage"
              size         = 32
              ssd          = true
            }
          ]
        }
      },
      "ruth-02" = {
        vm_id           = 1021
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.21/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "data-storage"
              size         = 32
              ssd          = true
            }
          ]
        }
      },
      "ruth-03" = {
        vm_id           = 1022
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.22/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "data-storage"
              size         = 32
              ssd          = true
            }
          ]
        }
      }
    }
  },
  "arr" = {
    enabled     = false
    type        = "vm"
    node_name   = "moo-moo"
    description = "Kubernets servers. Ubuntu 24.04."
    tags        = ["arr", "ansible", "ubuntu", "kubeadm", "k_fleet_local", "k_arr"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Asia/Kolkata"
        "user_locale"   = "en_US.UTF-8"
      },
      "kubeadm" = {
        kubeadm_bootstrap_node : "arr-01"
      }
    }

    vm_config = {
      cpu_cores         = 2
      memory_size       = 4096
      disk_datastore_id = "local-thin"
      os_version        = "24.04"
      disk_size         = 16
    }

    nodes = {
      "arr-01" = {
        vm_id           = 1025
        tags            = ["k_control"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.25/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "data-storage"
              size         = 10
              ssd          = true
            }
          ]
        }
      },
      "arr-02" = {
        vm_id           = 1026
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.26/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "data-storage"
              size         = 20
              ssd          = true
            }
          ]
        }
      },
      "arr-03" = {
        vm_id           = 1027
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.27/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "data-storage"
              size         = 20
              ssd          = true
            }
          ]
        }
      }
    }
  },

  "web_server" = {
    enabled     = false
    type        = "vm"
    node_name   = "moo-moo"
    description = "Web servers. Ubuntu 24.04."
    tags        = ["server", "ansible"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "GMT"
        "user_locale"   = "en_US.UTF-8"
      }
    }

    vm_config = {
      disk_datastore_id = "local-thin"
      os_version        = "24.04"
    }

    nodes = {
      "web-server-01" = {
        vm_id           = 700
        tags            = ["server", "ubuntu"]
        cloud_init_user = "web_admins"
        ansible_groups = {
          "timezone" = {
            "user_timezone" = "Asia/Kolkata"
            "user_locale"   = "en_US.UTF-8"
          }
        }
        vm_config = {
          disk_datastore_id = "data-storage"
          ipv4_address      = "192.168.0.96/24"
        }
      },
      "web-server-02" = {
        vm_id           = 701
        tags            = ["server", "ubuntu"]
        cloud_init_user = "web_admins"
        vm_config = {
          disk_datastore_id = "data-storage"
          ipv4_address      = "192.168.0.97/24"
        }
      }
    }
  },

  "db_server" = {
    enabled         = false
    type            = "vm"
    node_name       = "moo-moo"
    description     = "Primary database servers. Ubuntu 24.04."
    tags            = ["db", "ansible"]
    cloud_init_user = "db_admins"

    vm_config = {
      os_version = "25.04"
    }

    nodes = {
      "db-server-01" = {
        vm_id = 600
        tags  = ["mongo"]
        vm_config = {
          ipv4_address = "192.168.0.98/24"
        }
      },
      "db-server-02" = {
        vm_id       = 601
        description = "Primary database servers, for postgress. Ubuntu 24.04."
        tags        = ["postgres"]
        vm_config = {
          disk_size    = 16
          ipv4_address = "192.168.0.99/24"
        }
      },
    }
  },

  "support_servers" = {
    enabled         = false
    type            = "lxc"
    node_name       = "moo-moo"
    description     = "Primary database servers. Ubuntu 24.04."
    tags            = ["db", "ansible"]
    cloud_init_user = "dev"

    lxc_config = {
      template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
      os_type          = "debian"
    }

    nodes = {
      "support-servers-01" = {
        vm_id = 800
        tags  = ["mongo"]
        lxc_config = {
          hostname     = "support-servers-01"
          ipv4_address = "192.168.0.105/24"
        }
      },
      "support-servers-02" = {
        vm_id       = 801
        description = "Primary database servers, for postgress. Ubuntu 24.04."
        tags        = ["postgres"]
        lxc_config = {
          hostname     = "support-servers-02"
          disk_size    = 16
          ipv4_address = "192.168.0.106/24"
        }
      },
    }
  },
}
