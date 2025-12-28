# setup.sh — Switch Ubuntu to classic `ifupdown` and set a static IPv4

This script converts an Ubuntu machine (tested Ubuntu **16.04 → 24.04**) from modern networking (Netplan / NetworkManager / cloud-init networking) to classic **ifupdown** and configures a **static IPv4** address on a selected network interface.

✅ Safe by default: it prints a full plan first and **does nothing unless you pass `--apply`**.

---

## What this script does

### 1) Reads inputs (with defaults)
Default configuration:
- Interface: `enp0s3`
- IP: `10.0.9.215`
- Netmask: `255.0.0.0`
- Gateway: `10.0.0.254`
- DNS: `8.8.8.8, 1.1.1.1`

You can override these using CLI flags.

---

### 2) Validates basic settings
- Ensures you run as `root` (`sudo`)
- Checks if the given interface exists:
  - If interface is missing and you try `--apply`, it **refuses to proceed**
- Warns if netmask is `255.0.0.0` (that is a `/8`)

---

### 3) Prints a plan (before applying)
The script prints:
- selected interface + IP config
- which managers/services will be disabled
- the exact `/etc/network/interfaces` content it will write

If you run with `--dry-run`, it exits after printing the plan.

---

## What happens when you run with `--apply`

### 4) Creates safety backups
Backups are stored in:
- `/root/static-net-backup`

It saves (if present), with timestamps:
- `/etc/network/interfaces`
- `/etc/netplan/`
- `/etc/cloud/cloud.cfg.d/`

---

### 5) Disables network services that can conflict
Disables/masks (if they exist):
- `systemd-networkd-wait-online`
- `systemd-networkd`
- `NetworkManager`

This prevents multiple network managers from fighting over configuration.

---

### 6) Disables cloud-init networking
Creates/overwrites:
- `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`

Content:
```yaml
network: {config: disabled}
