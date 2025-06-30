
# Homelab Naming Convention

> This document is the single source of truth for all naming conventions within this homelab. All infrastructure, from physical nodes to ephemeral containers, must adhere to these rules. Adherence ensures clarity, scalability, and logical segmentation.

## 1. Core Philosophy

The naming scheme is built on two pillars:

1.  **Thematic Cohesion:** All names are derived from the **Cthulhu Mythos** by H.P. Lovecraft and associated authors. This provides a vast, hierarchical, and expandable pool of names.
2.  **Structural Clarity:** Names are not merely thematic but follow a strict `hostname.subdomain.domain.tld` structure that instantly communicates the device's purpose, location, and security context.

## 2. Fully Qualified Domain Name (FQDN) Structure

All devices will be addressable by a Fully Qualified Domain Name (FQDN) with the following structure:

`hostname.subdomain.domain.tld`

*   **`hostname`**: The unique name of the machine or service, based on a Mythos entity. See Section 4 for details.
*   **`subdomain`**: The **Security and Purpose Group**. This is the most important organizational component. See Section 3 for the list of approved subdomains.
*   **`domain.tld`**: The base domain for the lab.
    *   **Production:** `eldritch.works` (or your purchased domain)
    *   **Pre-production/Testing:** A `.test` TLD, e.g., `arkham.test`.

## 3. Subdomain Groups

Each subdomain represents a distinct security zone and purpose. Assigning a resource to a subdomain defines its firewall rules, access level, and role in the lab.

| Group          | Subdomain      | Purpose                                                                                           | Thematic Concept                                  | Example FQDN                                     |
| :------------- | :------------- | :------------------------------------------------------------------------------------------------ | :------------------------------------------------ | :----------------------------------------------- |
| **Maintenance**| `sentinel`     | Core infrastructure: Hypervisors, DNS, monitoring, automation tools. The lab's backbone.            | The watchers and foundational mechanics.          | `azathoth.sentinel.eldritch.works`               |
| **Data**       | `yuggoth`      | Storage servers, NAS, and backup destinations (on-site and off-site).                             | Alien worlds used for storage and archives.       | `nas-prime.yuggoth.eldritch.works`               |
| **Private**    | `kadath`       | Highest security services. **No internet access.** Password managers, private docs, core secrets.   | The hidden, unreachable sanctum of the gods.      | `yithian-vaultwarden.kadath.eldritch.works`      |
| **Internal**   | `arkham`       | Services for personal use, accessible over the internet but requiring strong authentication.        | A city of secrets, known but hard to access.      | `dashboard.arkham.eldritch.works`                |
| **Guest**      | `innsmouth`    | Services for trusted friends/family, accessible over the internet with authentication.              | A strange town that welcomes (or ensnares) outsiders. | `dagon-jellyfin.innsmouth.eldritch.works`        |
| **Public**     | `miskatonic`   | Public-facing services with anonymous access. Wiki, public file shares, link shorteners.         | The university, a place of public knowledge.      | `wiki.miskatonic.eldritch.works`                 |
| **Testing**    | `ritual`       | Unstable, no-backup environment for development and testing new applications.                     | A place of chaotic and dangerous experiments.     | `test-nextcloud.ritual.eldritch.works`           |

## 4. Hostname Naming Convention

The `hostname` itself provides specific identity.

**The Hierarchy:**

*   **Outer Gods:** The most powerful, reality-defining beings. Perfect for your most fundamental hardware.
*   **Great Old Ones:** Immensely powerful, ancient beings, often trapped or sleeping. Ideal for major clusters or critical servers.
*   **Mythical Places & Artifacts:** Locations of power, knowledge, or madness. Excellent for networks, storage, and repositories.
*   **Lesser Races & Monsters:** The numerous creatures that serve the gods. Perfect for the endless supply of VMs and containers.

**Why This Scheme Works Well:**

*   **Highly Expandable:** The Cthulhu Mythos has a massive number of entities, creatures, places, and books. You will not run out of names.
*   **Clear Hierarchy:** The power levels are well-defined, allowing you to map them logically from your physical hardware down to your ephemeral containers.
*   **Evocative:** It sets a strong, consistent, and fun theme for your entire lab. Managing `nyarlathotep-shoggoth-docker` feels more epic than managing `server01-docker-vm`.
*   **Unique Personality:** It gives your homelab a distinct character that is both classic and geeky.

### 4.1. Physical Hardware & Core Virtual Systems

*   **Proxmox Nodes:**
	*Name these after the Outer Gods—the blind idiot gods at the center of reality.*
	*   `azathoth` (The Daemon Sultan, ruler of the Outer Gods)
	*   `nyarlathotep` (The Crawling Chaos, the messenger and soul of the Gods)
	*   `yog-sothoth` (The Key and the Gate, co-ruler with Azathoth)
	*   **Expansion:** `shub-niggurath`, `nameless-mist`, `darkness`

*   **ZFS Pool Names**
	*Name these after primordial, vast, or all-encompassing locations or concepts.*
	*   `rlyeh` (The sunken city where Cthulhu sleeps; perfect for your main data pool)
	*   `abyss` (The primeval void)
	*   `plateau-of-leng` (A strange, cold, otherworldly plateau)
	*   **Expansion:** `yaddith`, `accretion-disk` (Azathoth's "throne")

*   **VLAN Names**
	*Name these after significant, and often cursed, locations or realms.*
	*   `miskatonic` (Trusted Server VLAN - for the university, a place of knowledge)
	*   `innsmouth` (IoT / Untrusted VLAN - "something fishy about this network")
	*   `dreamlands` (Management VLAN - the separate reality only you should access)
	*   `dunwich` (Guest Network - for the "horror" of outside visitors)
	*   **Expansion:** `carcosa`, `ulthar`, `celephais`

*   **On-site Backup Server**
	*Name it after a guardian entity or a place of safekeeping.*
	*   `sentinel-hill` (The hill in Dunwich where the rites were performed)
	*   `nodens` (An Elder God, often seen as a watcher or protector against the Mythos)

*   **Off-site Backup Servers**
	*Name these after distant, alien worlds or places of exile.*
	*   `yuggoth` (The planet at the edge of the solar system, Pluto)
	*   `kadath` (The unknown, cold waste where the gods dwell)
	*   **Expansion:** `aldebaran`, `fomalhaut`

*   **Kubernetes Cluster (in a VM)**
	*Name the cluster after a collective entity or a location known for its population of horrors.*
	*   `the-cult` or `cthulhu-cult`
	*   `esoteric-order` (referencing the Esoteric Order of Dagon)
	*   `arkham-cluster` (The haunted city)
	*   **Expansion:** `kingsport-cluster`, `red-hook-cluster`

### 4.2. VMs and LXC Containers
*This is where the scheme's expandability shines. Name them after the vast bestiary of lesser races and individual monsters. Use the format `[host]-[monster]-[function]` for clarity.*

*   **Host:** `nyarlathotep`
*   **VMs on `nyarlathotep`:**
    *   `nyarlathotep-shoggoth-docker` (Shoggoths are versatile, formless blobs—perfect for Docker!)
    *   `nyarlathotep-dagon-plex` (Dagon, a marine deity)
    *   `nyarlathotep-byakhee-pihole` (Byakhee are winged servants/messengers)
    *   `nyarlathotep-cthonian-db` (Cthonians are earth-dwellers, good for "ground-level" data)
    *   `nyarlathotep-mi-go-gitea` (Mi-go are scientific, insect-like beings from Yuggoth)

**Example Scenario:** A new Docker host VM is needed on the `azathoth` Proxmox node.
1.  **Function:** It will run Docker, so the function is `docker`.
2.  **Entity:** Shoggoths are formless, versatile servants. A perfect fit. We choose `shoggoth`.
3.  **Hostname:** `shoggoth-docker`
4.  **Group:** It's core infrastructure, so it belongs in the `sentinel` group.
5.  **Final FQDN:** `shoggoth-docker.sentinel.eldritch.works`

**List of suggested entities for VMs/Containers:**
`shoggoth`, `dagon`, `hydra`, `byakhee`, `mi-go`, `deep-one`, `yithian`, `ghoul`, `night-gaunt`, `cthonian`, `loki`, `tsathoggua`, `glaaki`, `elder-thing`.

### 4.3. GitOps Repository Name
 This repository is named **`platform-stack`**.
