# environments/calm-belt.secrets.tfvars (decrypted view)

# --- Proxmox Connection ---
# Defines the API endpoint and credentials for the Calm Belt Proxmox server.
# IMPORTANT: Replace these values with your actual sandbox credentials.

proxmox_connection = {
  url          = "https://192.168.0.202:8006/api2/json"
  insecure_tls = true
  auth_method  = "password"
  password_auth = {
    user     = "vmprovisioner@pve"
    password = "vmprovisioner"
  }
}

# --- Default User Configuration ---
# Defines the non-secret user information.
user_profile = {
  username        = "dev"
  package_upgrade = true
}

# Defines the secret user information.
user_credentials = {
  password        = "devdevdev"
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwC01G8nJScuxp7Cga8uUsnHUW2IpXXiiTw1gzhEL4P RyzenWindows"]
}
