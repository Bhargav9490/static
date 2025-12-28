# setup.sh — Static IPv4 in seconds (Ubuntu 16.04 → 24.04)

When you deploy VMs/instances into certain environments (Isolated Setup, SOC UAT/Labs, IOT/OT networks, private VLANs, customer networks, etc.), **DHCP may be disabled or unreliable**, and **only static IP addressing works**.

Manually configuring static IP on Ubuntu can be slow and error-prone because modern Ubuntu may involve:
- Netplan YAML files
- cloud-init rewriting networking at boot
- NetworkManager/systemd-networkd conflicting with changes

This script automates the full conversion and configuration in **seconds**, making it a “game changer” for scenarios where you need to **quickly assign a correct static IP** to a VM/instance without spending time debugging network stack conflicts.

---

## Problem Statement

In static-only networks, a VM/instance must be configured with a static IP immediately to be reachable.  
Doing this manually is painful because:
- Different Ubuntu versions use different systems (Netplan vs ifupdown).
- cloud-init may revert your manual configuration on reboot.
- Multiple network managers can fight each other (NetworkManager, systemd-networkd, wait-online).
- In fast deployments (cloning many VMs, templates, lab rollouts), you need a repeatable method to set static IP **consistently and quickly**.

✅ **Goal:** Configure static IPv4 in seconds, consistently, and prevent other services from undoing it.

---

## What this script does (How it works)

When executed with `--apply`, the script:
1. **Backs up** existing configs into `/root/static-net-backup/`
2. **Disables conflicting services** (NetworkManager, systemd-networkd, wait-online) if they exist
3. **Disables cloud-init networking** (prevents it from overwriting your settings)
4. **Removes Netplan YAMLs** (`/etc/netplan/*.yaml`)
5. **Installs classic `ifupdown`**
6. **Writes `/etc/network/interfaces`** with your static IP, gateway, and DNS
7. **Applies networking immediately** (flushes IP, ifdown/ifup)
8. **Enables persistence** so the config survives reboot

By default it prints a plan and does nothing unless you pass `--apply`.

---

## Requirements
- Ubuntu 16.04 to 24.04
- Must run with `sudo` / root
- Know your correct:
  - interface name (ex: `enp0s3`, `ens18`)
  - static IP
  - netmask
  - gateway
  - DNS

---

## How to run
## 0) Clone the repo
```bash
git clone https://github.com/Bhargav9490/static.git
cd static 
```

## 1) Download and make executable
```bash
chmod +x setup.sh
```

## 2) Check your network interface name (important)
```bash
ip -o link show
```

## 3) Check your network interface name (important)
```bash
ip -o link show
```

## 4) Dry run (recommended) 
Shows what will change, but does not modify anything.
```bash
sudo ./setup.sh \
  --if enp0s3 \
  --ip 10.0.9.215 \
  --nm 255.0.0.0 \
  --gw 10.0.0.254 \
  --dns "8.8.8.8,1.1.1.1" \
  --dry-run
```

## 5) Apply (real execution)
IP address, Subnet and Gateway can be changed as per your infrastructure 
```bash
sudo ./setup.sh \
  --if enp0s3 \
  --ip 10.0.9.215 \
  --nm 255.0.0.0 \
  --gw 10.0.0.254 \
  --dns "8.8.8.8,1.1.1.1" \
  --apply
```

## 6) Verify
```bash
ip -4 addr show dev enp0s3
```

```bash
ip route
```

```bash
cat /etc/network/interfaces
```
