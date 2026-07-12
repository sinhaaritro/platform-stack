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
target_node      = "atlas"
target_datastore = "WD1TB"

# Resource Definations
# This map defines all the VMs to be created by this stack. The map key is
# used as the default name for the VM.
resources = {
  "kind" = {
    enabled     = false
    type        = "vm"
    node_name   = "atlas"
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
      disk_datastore_id = "WD1TB"
      os_version        = "24.04"
      disk_size         = 16
    }

    nodes = {
      "kind-01" = {
        vm_id           = 700
        cloud_init_user = "dev"
        vm_config = {
          disk_datastore_id = "WD4TB"
          ipv4_address      = "192.168.0.70/24"
        }
      }
    }
  },
  "ruth" = {
    enabled     = true
    type        = "vm"
    node_name   = "atlas"
    description = "Kubernets servers. Ubuntu 24.04."
    tags        = ["ruth", "ansible", "ubuntu", "k3s", "k_management"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Asia/Kolkata"
        "user_locale"   = "en_US.UTF-8"
      },
      "k3s" = {
        "k3s_bootstrap_node" : "ruth-01"
        "sealed_secrets_master_key_url" : "https://github.com/sinhaaritro/platform-stack.git"
        "sealed_secrets_master_key_path" : "kubernetes/clusters/ruth/sealed-secrets/master.secret.yaml"
        "sealed_secrets_master_key_revision" : "HEAD"
      },
      # "k_management" = {
      #   "argocd_managed_fleets" : "arr"
      # }
    }

    vm_config = {
      cpu_cores         = 4
      memory_size       = 8192
      disk_datastore_id = "WD1TB"
      os_version        = "24.04"
      disk_size         = 24
    }

    nodes = {
      "ruth-01" = {
        vm_id           = 1040
        tags            = ["k_control"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.40/24"
          cpu_cores    = 12
          memory_size  = 16384
          disk_size    = 32
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "WD4TB"
              size         = 150
              ssd          = true
            }
          ]
        }
      },
      "ruth-02" = {
        enabled         = false
        vm_id           = 1041
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.41/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "WD4TB"
              size         = 64
              ssd          = true
            }
          ]
        }
      },
      "ruth-03" = {
        enabled         = false
        vm_id           = 1042
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.42/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "WD4TB"
              size         = 64
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
    node_name   = "atlas"
    description = "Kubernets servers. Ubuntu 24.04."
    tags        = ["arr", "ansible", "ubuntu", "k3s", "k_fleet_local", "k_arr"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Asia/Kolkata"
        "user_locale"   = "en_US.UTF-8"
      },
      "k3s" = {
        k3s_bootstrap_node : "arr-01"
      }
    }

    vm_config = {
      cpu_cores         = 2
      memory_size       = 4096
      disk_datastore_id = "WD1TB"
      os_version        = "24.04"
      disk_size         = 16
    }

    nodes = {
      "arr-01" = {
        vm_id           = 1045
        tags            = ["k_control"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.45/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "WD4TB"
              size         = 10
              ssd          = true
            }
          ]
        }
      },
      "arr-02" = {
        vm_id           = 1046
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.46/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "WD4TB"
              size         = 20
              ssd          = true
            }
          ]
        }
      },
      "arr-03" = {
        vm_id           = 1047
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.47/24"
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "WD4TB"
              size         = 20
              ssd          = true
            }
          ]
        }
      }
    }
  },

  "web_server" = {
    enabled     = true
    type        = "vm"
    node_name   = "atlas"
    description = "Web servers. Ubuntu 24.04."
    tags        = ["server", "ansible"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Asia/Kolkata"
        "user_locale"   = "en_US.UTF-8"
      }
    }

    vm_config = {
      cpu_cores         = 2
      memory_size       = 2048
      disk_datastore_id = "WD1TB"
      os_version        = "25.04"
      disk_size         = 16
    }

    nodes = {
      "web-server-01" = {
        vm_id           = 1031
        tags            = ["server", "ubuntu"]
        cloud_init_user = "dev"
        ansible_groups = {
          "timezone" = {
            "user_timezone" = "Asia/Kolkata"
            "user_locale"   = "en_US.UTF-8"
          }
        }
        vm_config = {
          disk_datastore_id = "WD4TB"
          ipv4_address      = "192.168.0.31/24"
        }
      },
      "web-server-02" = {
        enabled         = false
        vm_id           = 1032
        tags            = ["server", "ubuntu"]
        cloud_init_user = "web_admins"
        vm_config = {
          disk_datastore_id = "WD4TB"
          ipv4_address      = "192.168.0.32/24"
        }
      }
    }
  },

  "db_server" = {
    enabled         = false
    type            = "vm"
    node_name       = "atlas"
    description     = "Primary database servers. Ubuntu 24.04."
    tags            = ["db", "ansible"]
    cloud_init_user = "db_admins"

    vm_config = {
      os_version = "25.04"
    }

    nodes = {
      "db-server-01" = {
        vm_id = 1035
        tags  = ["mongo"]
        vm_config = {
          ipv4_address = "192.168.0.35/24"
        }
      },
      "db-server-02" = {
        vm_id       = 1036
        description = "Primary database servers, for postgress. Ubuntu 24.04."
        tags        = ["postgres"]
        vm_config = {
          disk_size    = 16
          ipv4_address = "192.168.0.36/24"
        }
      },
    }
  },

  "support_servers" = {
    enabled         = false
    type            = "lxc"
    node_name       = "atlas"
    description     = "Primary database servers. Ubuntu 24.04."
    tags            = ["db", "ansible"]
    cloud_init_user = "dev"

    lxc_config = {
      template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
      os_type          = "debian"
    }

    nodes = {
      "support-servers-01" = {
        vm_id = 1033
        tags  = ["mongo"]
        lxc_config = {
          hostname     = "support-servers-01"
          ipv4_address = "192.168.0.33/24"
        }
      },
      "support-servers-02" = {
        vm_id       = 1034
        description = "Primary database servers, for postgress. Ubuntu 24.04."
        tags        = ["postgres"]
        lxc_config = {
          hostname     = "support-servers-02"
          disk_size    = 16
          ipv4_address = "192.168.0.34/24"
        }
      },
    }
  },
}
