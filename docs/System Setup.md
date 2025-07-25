# System Setup

The commands will install all the necessary software directly onto a system. 

---

### Phase 1: Install System-Level Packages with `apt`

This step installs all the base dependencies that are managed by the operating system's package manager.

```bash
# 1. Update the package list to ensure you get the latest versions.
sudo apt-get update

# 2. Install all common dependencies from both containers.
#    - git, curl, openssh-client: Core command-line utilities.
#    - python3-pip, python3-venv: Required to manage Python packages and create isolated environments.
sudo apt-get install -y git curl openssh-client python3-pip python3-venv
```

---

### Phase 2: Install OpenTofu

OpenTofu is not in the default Ubuntu repositories, so we must add its official repository, just like in the container.

```bash
# 1. Installing tooling
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

# 2. Ensure the directory for GPG keys exists.
sudo install -m 0755 -d /etc/apt/keyrings

# 3. Download and install the official OpenTofu GPG signing key.
#    This allows 'apt' to verify the authenticity of the OpenTofu package.
curl -fsSL https://get.opentofu.org/opentofu.gpg | sudo tee /etc/apt/keyrings/opentofu.gpg >/dev/null
curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | sudo gpg --no-tty --batch --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg >/dev/null
sudo chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg

# 4. Add the OpenTofu package repository to your system's sources.
#    This tells 'apt' where to look for the 'tofu' package.
echo \
  "deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
deb-src [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" | \
  sudo tee /etc/apt/sources.list.d/opentofu.list > /dev/null
sudo chmod a+r /etc/apt/sources.list.d/opentofu.list

# 5. Update the package list again to include the new OpenTofu repository.
sudo apt-get update

# 6. Install the OpenTofu package.
sudo apt-get install -y tofu

# 7. Verify the installation.
which tofu
tofu --version
```

---

### Phase 3: Install Ansible

We will install everything using Ubuntu's native package manager. So that `ansible` to be a system-wide command, just like `git` or `curl`, without needing to manage a virtual environment.

```bash
# 1. Update the Package List
sudo apt-get update

# 2. Install Ansible's Official PPA
#    Ubuntu's default repositories can have an old version of Ansible. Using 
#    the official Ansible PPA (Personal Package Archive) ensures you get a 
#    modern, supported version.
sudo apt-get install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible

# 3. Install Ansible and its dependencies
#    - ansible: The automation engine.
#    - ansible-lint: The tool VSCodium will use for code quality checks.
#    - proxmoxer: The Python library that the Proxmox modules depend on.
sudo apt-get install -y ansible ansible-lint
# Not installed
sudo apt-get install -y python3-proxmoxer

# 4. Verify
ansible --version
```

---

### Phase 4: Kuberneties

```bash
```


After saving this and **reloading VSCodium** (`F1` -> `Developer: Reload Window`), the extension will now be perfectly integrated with your new, simpler, system-wide Ansible installation.