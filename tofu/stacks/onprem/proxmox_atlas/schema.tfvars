# -----------------------------------------------------------------------------
# STACK CONFIGURATION
# -----------------------------------------------------------------------------
# This file provides all the non-secret data for this specific stack.
# -----------------------------------------------------------------------------
# Run commands for this file: 
# ```bash
# tofu -chdir="tofu/stacks/onprem/proxmox_atlas" apply \
#   -var-file="schema.tfvars" \
#   -var-file=<(ansible-vault view --vault-password-file <(echo "$ANSIBLE_VAULT_PASSWORD") tofu/stacks/onprem/proxmox_meru/schema.secret.tfvars)
#
# Alternatively using task:
# task tofu:apply:approve STACK_NAME=proxmox_atlas
# ```

enable_debug = false

# Target Proxmox Environment
target_node      = "atlas"
target_datastore = "local-lvm"
image_datastore  = "local"

# Resource Definations
# This map defines all the VMs to be created by this stack. The map key is
# used as the default name for the VM.
resources = {
  "kind" = {
    enabled     = false
    type        = "vm"
    node_name   = "atlas"
    description = "Kubernetes servers. Ubuntu 26.04."
    tags        = ["kind", "ansible", "ubuntu", "kind"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Etc/GMT"
        "user_locale"   = "en_US.UTF-8"
      }
      "kind" = {
        "kind_version" = "v0.26.0"
      }
      "helm" = {
        "helm_version" = "v3.16.2"
      }
      "k8s_repo" = {
        "k8s_repo_version" = "v1.36"
      }
    }

    vm_config = {
      cpu_cores         = 2
      memory_size       = 2048
      disk_datastore_id = "local-lvm"
      os_version        = "26.04"
      disk_size         = 16
    }

    nodes = {
      "kind-01" = {
        vm_id           = 1080
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.80/24"
        }
      }
    }
  },
  "hyperion" = {
    enabled     = true
    type        = "vm"
    node_name   = "atlas"
    on_boot     = true
    description = "Kubernets servers. Ubuntu 26.04."
    tags        = ["hyperion", "ansible", "ubuntu", "k3s", "k_management"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Asia/Kolkata"
        "user_locale"   = "en_US.UTF-8"
      },
      "k3s" = {
        "k3s_bootstrap_node" : "hyperion-01"
        "sealed_secrets_master_key_url" : "https://github.com/sinhaaritro/platform-stack.git"
        "sealed_secrets_master_key_path" : "kubernetes/clusters/hyperion/sealed-secrets/master.secret.yaml"
        "sealed_secrets_master_key_revision" : "HEAD"
        "k3s_version" : "v1.36.2+k3s1"
      },
      "k_management" = {
        "argocd_managed_fleets" : "quanta"
        "argocd_chart_version" : "10.1.3"
      }
    }

    vm_config = {
      cpu_cores         = 4
      memory_size       = 8192
      disk_datastore_id = "local-lvm"
      os_version        = "26.04"
      disk_size         = 24
    }

    nodes = {
      "hyperion-01" = {
        vm_id           = 1050
        tags            = ["k_control"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.50/24"
          cpu_cores    = 12
          memory_size  = 16384
          disk_size    = 32
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "WD4TB"
              size         = 250
              ssd          = true
            }
          ]
        }
      },
      "hyperion-02" = {
        vm_id           = 1051
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.51/24"
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
      "hyperion-03" = {
        enabled         = false
        vm_id           = 1052
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.52/24"
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
  "quanta" = {
    enabled     = false
    type        = "vm"
    node_name   = "atlas"
    on_boot     = true
    description = "Kubernets servers. Ubuntu 26.04."
    tags        = ["quanta", "ansible", "ubuntu", "k3s", "k_fleet_local", "k_quanta"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Asia/Kolkata"
        "user_locale"   = "en_US.UTF-8"
      },
      "k3s" = {
        k3s_bootstrap_node : "quanta-01"
        "k3s_version" : "v1.36.2+k3s1"
      }
    }

    vm_config = {
      cpu_cores         = 2
      memory_size       = 4096
      disk_datastore_id = "local-lvm"
      os_version        = "26.04"
      disk_size         = 16
    }

    nodes = {
      "quanta-01" = {
        vm_id           = 1060
        tags            = ["k_control"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.60/24"
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
      "quanta-02" = {
        enabled         = false
        vm_id           = 1061
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.61/24"
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
      "quanta-03" = {
        enabled         = false
        vm_id           = 1062
        tags            = ["k_worker"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.62/24"
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
  "elysia" = {
    enabled     = false
    type        = "vm"
    node_name   = "atlas"
    on_boot     = true
    description = "Kubernets servers. Ubuntu 26.04."
    tags        = ["elysia", "ansible", "ubuntu", "k3s", "k_management"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Asia/Kolkata"
        "user_locale"   = "en_US.UTF-8"
      },
      "k3s" = {
        "k3s_bootstrap_node" : "elysia-01"
        "sealed_secrets_master_key_url" : "https://github.com/sinhaaritro/platform-stack.git"
        "sealed_secrets_master_key_path" : "kubernetes/clusters/elysia/sealed-secrets/master.secret.yaml"
        "sealed_secrets_master_key_revision" : "HEAD"
        "k3s_version" : "v1.36.2+k3s1"
      },
      "argocd" = {
        "argocd_git_repo_path" : "kubernetes/bootstrap/elysia"
        "argocd_chart_version" : "10.1.3"
      }
    }

    vm_config = {
      cpu_cores         = 4
      memory_size       = 8192
      disk_datastore_id = "local-lvm"
      os_version        = "26.04"
      disk_size         = 24
    }

    nodes = {
      "elysia-01" = {
        vm_id           = 1070
        tags            = ["k_control"]
        cloud_init_user = "dev"
        vm_config = {
          ipv4_address = "192.168.0.70/24"
          cpu_cores    = 12
          memory_size  = 16384
          disk_size    = 32
          additional_disks = [
            {
              interface    = "scsi1"
              datastore_id = "WD4TB"
              size         = 10
              ssd          = true
            }
          ]
        }
      }
    }
  },


  "agora" = {
    enabled     = true
    type        = "vm"
    node_name   = "atlas"
    description = "Merch store dev environment. Ubuntu 26.04."
    tags        = ["agora", "ansible", "ubuntu", "dev", "docker"]
    ansible_groups = {
      "timezone" = {
        "user_timezone" = "Asia/Kolkata"
        "user_locale"   = "en_US.UTF-8"
      }
      "dev"    = {}
      "docker" = {}
    }

    vm_config = {
      cpu_cores         = 4
      memory_size       = 8096
      disk_datastore_id = "local-lvm"
      os_version        = "26.04"
      disk_size         = 16
    }

    nodes = {
      "agora-01" = {
        vm_id           = 1040
        tags            = ["node", "python", "bun", "git"]
        cloud_init_user = "dev"
        ansible_groups = {
          "node" = {
            "node_version" = "26"
          }
          "bun" = {
            "bun_version" = "latest"
          }
          "python" = {}
          "git" = {
            "git_user_name"  = "sinhaaritro"
            "git_user_email" = "sinhaaritro@gmail.com"
          }
        }
        vm_config = {
          ipv4_address = "192.168.0.40/24"
        }
      }
    }
  },

  "web_server" = {
    enabled     = false
    type        = "vm"
    node_name   = "atlas"
    description = "Web servers. Ubuntu 26.04."
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
      disk_datastore_id = "local-lvm"
      os_version        = "26.04"
      disk_size         = 16
    }

    nodes = {
      "web-server-01" = {
        vm_id           = 1041
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
          ipv4_address      = "192.168.0.41/24"
        }
      },
      "web-server-02" = {
        enabled         = false
        vm_id           = 1042
        tags            = ["server", "ubuntu"]
        cloud_init_user = "web_admins"
        vm_config = {
          disk_datastore_id = "WD4TB"
          ipv4_address      = "192.168.0.42/24"
        }
      }
    }
  },

  "db_server" = {
    enabled         = false
    type            = "vm"
    node_name       = "atlas"
    description     = "Primary database servers. Ubuntu 26.04."
    tags            = ["db", "ansible"]
    cloud_init_user = "db_admins"

    vm_config = {
      os_version = "26.04"
    }

    nodes = {
      "db-server-01" = {
        vm_id = 1045
        tags  = ["mongo"]
        vm_config = {
          ipv4_address = "192.168.0.45/24"
        }
      },
      "db-server-02" = {
        vm_id       = 1046
        description = "Primary database servers, for postgress. Ubuntu 26.04."
        tags        = ["postgres"]
        vm_config = {
          disk_size    = 16
          ipv4_address = "192.168.0.46/24"
        }
      },
    }
  },

  "support_servers" = {
    enabled         = false
    type            = "lxc"
    node_name       = "atlas"
    description     = "Primary database servers. Ubuntu 26.04."
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
          ipv4_address = "192.168.0.33/24"
        }
      },
      "support-servers-02" = {
        vm_id       = 1034
        description = "Primary database servers, for postgress. Ubuntu 26.04."
        tags        = ["postgres"]
        lxc_config = {
          disk_size    = 16
          ipv4_address = "192.168.0.34/24"
        }
      },
    }
  },

  "oceanus" = {
    enabled         = true
    type            = "vm"
    node_name       = "atlas"
    description     = "NAS NFS client (mounts host export /WD4TB/shared/v1). Ubuntu 26.04."
    tags            = ["ansible", "storage", "nfs", "vm"]
    on_boot         = true
    cloud_init_user = "dev"
    ansible_groups = {
      # NAS CLIENT config lives with the consumer. Mounts reference a share by
      # (provider node + share id) and choose their own versioned `subpath`
      # (v1/v2/…); the nas_client role resolves server+remote at runtime.
      "nas" = {
        nas_mounts = [
          { provider = "atlas", share = "WD4TB", subpath = "v1", path = "/export/data", options = "hard,noatime,actimeo=2" }
        ]
      }
    }

    vm_config = {
      os_type           = "ubuntu"
      os_version        = "26.04"
      disk_datastore_id = "local-lvm"
      disk_size         = 8
      cpu_cores         = 1
      memory_size       = 1024
    }

    nodes = {
      "oceanus.olympus.strawslabs.com" = {
        vm_id = 1047
        vm_config = {
          ipv4_address = "192.168.0.47/24"
        }
      }
    }
  },

  "adguard" = {
    enabled         = true
    type            = "lxc"
    node_name       = "atlas"
    description     = "AdGuard Home DNS server. Alpine."
    tags            = ["ansible", "adguard", "dns", "lxc"]
    ansible_groups  = {}
    on_boot         = true
    cloud_init_user = "adguard"
    ansible_groups = {
      "adguard" = {
        "adguard_version" = "v0.107.78"
      }
    }

    lxc_config = {
      template_datastore_id       = "local"
      template_url                = "http://download.proxmox.com/images/system/alpine-3.24-default_20260714_amd64.tar.xz"
      template_checksum           = "9877b74de4c4878b70450502618f7b02952e792afdbc91f146f6cba507432dae516674d0bb3a306484d58edc722ff63db1ed3c4e5b0954fb2a2773ec8d8f33bd"
      template_checksum_algorithm = "sha512"
      os_type                     = "alpine"
      cpu_cores                   = 1
      memory_size                 = 256
      disk_size                   = 1
      unprivileged                = true
    }

    nodes = {
      "aegis.olympus.strawslabs.com" = {
        vm_id = 1020
        lxc_config = {
          ipv4_address = "192.168.0.20/24"
        }
      }
    }
  },

  "netbird" = {
    enabled         = true
    type            = "lxc"
    node_name       = "atlas"
    description     = "Netbird VPN server/client LXC container. Alpine."
    tags            = ["ansible", "netbird", "vpn", "lxc"]
    on_boot         = true
    cloud_init_user = "dev"
    ansible_groups = {
      "netbird" = {}
    }

    lxc_config = {
      template_datastore_id       = "local"
      template_url                = "http://download.proxmox.com/images/system/alpine-3.24-default_20260714_amd64.tar.xz"
      template_checksum           = "9877b74de4c4878b70450502618f7b02952e792afdbc91f146f6cba507432dae516674d0bb3a306484d58edc722ff63db1ed3c4e5b0954fb2a2773ec8d8f33bd"
      template_checksum_algorithm = "sha512"
      os_type                     = "alpine"
      cpu_cores                   = 1
      memory_size                 = 512
      disk_size                   = 4
      unprivileged                = true
      nesting                     = true
    }

    nodes = {
      "hermes.olympus.strawslabs.com" = {
        vm_id = 1021
        lxc_config = {
          ipv4_address = "192.168.0.21/24"
        }
      }
    }
  },

  "cloudflared" = {
    enabled         = true
    type            = "lxc"
    node_name       = "atlas"
    description     = "Cloudflare Tunnel connector LXC container. Alpine."
    tags            = ["ansible", "cloudflared", "tunnel", "lxc"]
    on_boot         = true
    cloud_init_user = "dev"
    ansible_groups = {
      "cloudflared" = {}
    }

    lxc_config = {
      template_datastore_id       = "local"
      template_url                = "http://download.proxmox.com/images/system/alpine-3.24-default_20260714_amd64.tar.xz"
      template_checksum           = "9877b74de4c4878b70450502618f7b02952e792afdbc91f146f6cba507432dae516674d0bb3a306484d58edc722ff63db1ed3c4e5b0954fb2a2773ec8d8f33bd"
      template_checksum_algorithm = "sha512"
      os_type                     = "alpine"
      cpu_cores                   = 1
      memory_size                 = 256
      disk_size                   = 2
      unprivileged                = true
    }

    nodes = {
      "iris.olympus.strawslabs.com" = {
        vm_id = 1022
        lxc_config = {
          ipv4_address = "192.168.0.22/24"
        }
      }
    }
  },
}

# -----------------------------------------------------------------------------
# TOPOLOGY — physical hosts, clusters, and the NAS contract
# -----------------------------------------------------------------------------
# The single source of truth for the physical layer. OpenTofu does NOT create
# or destroy these hosts — it normalizes them and emits them into the Ansible
# inventory (connection details, groups, cluster role, per-concern config).
#
# SCOPE MODEL:
#   clusters.<c>.*  → CLUSTER-scoped concerns, applied by `primary` ONLY and
#                     inherited by the other members via the Proxmox cluster
#                     API / /etc/pve (SDN VLANs, shared storage definitions,
#                     firewall, replication).
#   nodes.<n>.*     → NODE-local concerns, applied on that node itself (its own
#                     disks, ZFS pools, mounts, exports, Samba, and future
#                     per-node vlan/firewall/replication overrides).
#
# Adding a host, pool, share, or VLAN is a DATA change.
# -----------------------------------------------------------------------------
topology = {
  # ── Clusters ───────────────────────────────────────────────────────────────
  # `primary` applies the cluster-scoped concern keys below. `members` lists the
  # nodes in the cluster. Scaffold: concern keys are present-but-unset until we
  # implement each one. atlas is standalone for now; prometheus/godzilla later.
  clusters = {
    asgard = {
      primary = "atlas"
      members = ["atlas"]

      # ── cluster-scoped concern scaffolds (applied by `primary` only) ──
      # vlan        = { zones = {...}, vnets = {...} }   # Proxmox SDN → /etc/pve/sdn
      # firewall    = {...}                              # cluster firewall rules
      # replication = {...}                              # ZFS replication jobs
      # (no cluster-level storage — storage is node-local, under nodes.<n>.storage)
    }
  }

  # ── Nodes ──────────────────────────────────────────────────────────────────
  # Each node carries one key per concern. `storage` holds the full, node-local
  # storage config (pools, data disks, exports, Samba, Proxmox datastores,
  # backup). Further concerns (vlan / firewall / replication) slot in as extra
  # keys as they are implemented.
  nodes = {
    atlas = {
      cluster      = "asgard"
      ipv4_address = "192.168.0.2"
      ansible_user = "root"
      # No explicit `groups`: physical hosts are identified by the generated
      # `proxmox_node` group, and the cluster primary by `proxmox_primary`.
      # (Optional `groups = [...]` can still add extra membership per node.)

      # ── node-local concern: storage ──
      # Tofu's job here = make the pool and give access. No directory tree
      # (tenants/PVCs) is declared — apps create their own dirs.
      storage = {
        backend = "proxmox"
        owner = {
          uid       = 1000
          gid       = 1000
          dir_mode  = "0775"
          file_mode = "0664"
        }
        pools = [
          {
            name  = "WD4TB"
            vdev  = "single"
            disks = ["/dev/disk/by-id/ata-ST4000NM000B-2TF100_WX11QNR8"]
            # NOTE: `recordsize` omitted — it is ZFS's default (128K). If you set
            # it, use BYTES (e.g. 131072 / 1048576): ZFS reports recordsize in
            # bytes, so "128K" would look like a perpetual (no-op) change.
            props = { ashift = 12, compression = "on", xattr = "sa", acltype = "posixacl" }
            datasets = [
              { name = "shared", mountpoint = "/WD4TB/shared" }
            ]
          }
        ]
        # `by_id` names the FILESYSTEM device: the whole disk for a fresh,
        # unpartitioned disk; the partition when it already carries one (WD1TB's
        # ext4 lives on sdb1, per `lsblk -f`). NEVER point this at a whole disk
        # that still has partitions.
        data_disks = [
          {
            interface = "sdb"
            by_id     = "/dev/disk/by-id/ata-WDC_WD10EZRX-00L4HB0_WD-WCC4J2501696-part1"
            fstype    = "ext4"
            path      = "/mnt/pve/WD1TB"
          }
        ]
        # Access, keyed by share id. The share defines only the exported base
        # path; the versioned segment (v1/v2/…) is a CLIENT concern — each app
        # picks its own, so the server never manages the directory tree.
        exports = {
          WD4TB = {
            pool    = "WD4TB"
            path    = "/WD4TB/shared"
            clients = "192.168.0.0/24"
            options = "rw,sync,no_subtree_check,no_root_squash"
          }
          WD1TB = {
            pool    = "WD1TB"
            path    = "/mnt/pve/WD1TB/shared"
            clients = "192.168.0.0/24"
            options = "rw,sync,no_subtree_check,no_root_squash"
          }
        }
        smb_user = { name = "smbuser", uid = 1000, gid = 1000 }
        smb_shares = {
          WD4TB = { path = "/WD4TB/shared" }
          WD1TB = { path = "/mnt/pve/WD1TB/shared" }
        }
        proxmox_storages = [
          { id = "WD4TB", type = "zfspool", pool = "WD4TB", content = "rootdir,images", nodes = ["atlas"] },
          { id = "WD1TB", type = "dir", path = "/mnt/pve/WD1TB", is_mountpoint = 1, content = "rootdir,vztmpl,import,iso,images" }
        ]
        backup = {
          snapshots = { enabled = false, schedule = "daily", keep = 7 }
          scrub     = { enabled = false }
          smart     = { enabled = true, selftests = false }
          rclone = {
            enabled          = true
            remote           = "vault"
            storage_class    = "DEEP_ARCHIVE"
            healthchecks_url = ""
            jobs = [
              { name = "immich", mode = "sync", source = "/WD4TB/shared/v1/personal/immich", target = "v1/personal/immich", schedule = "monthly", max_delete = 100, storage_class = "DEEP_ARCHIVE", excludes = ["/thumbs/**", "/encoded-video/**"] },
              { name = "obsidian", mode = "sync", source = "/WD4TB/shared/v1/personal/obsidian", target = "v1/personal/obsidian", schedule = "weekly", max_delete = 50, storage_class = "GLACIER_IR" },
              # { name = "docs",     mode = "sync", source = "/WD4TB/shared/v1/personal/docs",     target = "v1/personal/docs",     schedule = "weekly",  max_delete = 50, storage_class = "GLACIER_IR" },
              # { name = "projects", mode = "sync", source = "/WD4TB/shared/v1/personal/projects", target = "v1/personal/projects", schedule = "weekly",  max_delete = 50, storage_class = "DEEP_ARCHIVE" },
              # { name = "media",    mode = "copy", source = "/WD4TB/shared/v1/personal/media",    target = "v1/personal/media",    schedule = "monthly", storage_class = "DEEP_ARCHIVE" }
            ]
          }
        }
      }

      # ── other node-local concern scaffolds ──
      # vlan        = {...}
      # firewall    = {...}
      # replication = {...}
    }

    # prometheus / godzilla slot in here later with their own `storage` blocks.
  }
}
