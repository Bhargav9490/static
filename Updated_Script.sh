
---

```bash
#!/usr/bin/env bash
# setup.sh — Switch Ubuntu to classic ifupdown and set a static IPv4
# Tested on Ubuntu 16.04 → 24.04. Run with sudo.
#
# Why this exists:
# In many lab / isolated / OT networks, DHCP is disabled and only static IP works.
# Manually configuring static IP on Ubuntu can be slow due to Netplan + cloud-init +
# NetworkManager/systemd-networkd conflicts. This script automates the full process
# to set a static IPv4 in seconds and make it persistent.

set -euo pipefail

VERSION="1.1.0"

# ---- defaults (you can override with flags) ----
IF="enp0s3"
IP="10.0.9.215"
NM="255.0.0.0"
GW="10.0.0.254"
DNS1="8.8.8.8"
DNS2="1.1.1.1"

usage() {
  cat <<EOF
setup.sh v${VERSION}

Usage:
  sudo ./setup.sh [options]

Options:
  --if IFACE           Network interface (default: ${IF})
  --ip IP              Static IPv4 (default: ${IP})
  --nm NETMASK         Netmask (default: ${NM})
  --gw GATEWAY         Gateway (default: ${GW})
  --dns "D1,D2,..."    Comma-separated DNS servers (default: ${DNS1},${DNS2})

  --apply              Actually apply changes (required to proceed)
  --dry-run            Show what would change, do not modify system
  --version            Print version and exit
  -h, --help           Show help

Examples:
  sudo ./setup.sh --if enp0s3 --ip 10.0.9.215 --nm 255.0.0.0 --gw 10.0.0.254 --dns "8.8.8.8,1.1.1.1" --dry-run
  sudo ./setup.sh --if enp0s3 --ip 10.0.9.215 --nm 255.0.0.0 --gw 10.0.0.254 --dns "8.8.8.8,1.1.1.1" --apply
EOF
}

APPLY=0
DRYRUN=0
DNS="${DNS1},${DNS2}"

while (( "$#" )); do
  case "$1" in
    --if)  IF="$2"; shift 2;;
    --ip)  IP="$2"; shift 2;;
    --nm)  NM="$2"; shift 2;;
    --gw)  GW="$2"; shift 2;;
    --dns) DNS="$2"; shift 2;;
    --apply) APPLY=1; shift;;
    --dry-run) DRYRUN=1; shift;;
    --version) echo "$VERSION"; exit 0;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo/root."; exit 1
fi

# Split DNS into array
IFS=',' read -r -a DNS_ARR <<< "$DNS"

# Quick sanity checks
if ! ip link show "$IF" >/dev/null 2>&1; then
  echo "Warning: Interface '$IF' not found. Existing interfaces:"
  ip -o link show | awk -F': ' '{print "  - "$2}'
  [[ $APPLY -eq 1 ]] && { echo "Refusing to apply with a non-existent interface."; exit 1; }
fi

if [[ "$NM" == "255.0.0.0" ]]; then
  echo "Note: Netmask 255.0.0.0 is a /8. Make sure that’s really what you want."
fi

# What we will write into /etc/network/interfaces
build_interfaces() {
  echo "auto lo
iface lo inet loopback

auto ${IF}
iface ${IF} inet static
    address ${IP}
    netmask ${NM}
    gateway ${GW}
    dns-nameservers ${DNS_ARR[*]}"
}

plan() {
  echo "=== Plan ==="
  echo "Interface: $IF"
  echo "IP:        $IP"
  echo "Netmask:   $NM"
  echo "Gateway:   $GW"
  echo "DNS:       ${DNS_ARR[*]}"
  echo
  echo "Will disable waits and managers (if present):"
  echo "  - systemd-networkd-wait-online"
  echo "  - systemd-networkd"
  echo "  - NetworkManager"
  echo "Will disable cloud-init network cfg and remove netplan YAMLs."
  echo "Will install: ifupdown"
  echo "Will write /etc/network/interfaces as:"
  echo "-------------------------------------"
  build_interfaces
  echo "-------------------------------------"
  echo "Will bring ${IF} up using ifdown/ifup."
}

apply_changes() {
  echo "Creating safety backup (/root/static-net-backup)..."
  mkdir -p /root/static-net-backup
  cp -a /etc/network/interfaces "/root/static-net-backup/interfaces.$(date +%F-%H%M%S)" 2>/dev/null || true
  cp -a /etc/netplan "/root/static-net-backup/netplan.$(date +%F-%H%M%S)" 2>/dev/null || true
  cp -a /etc/cloud/cloud.cfg.d "/root/static-net-backup/cloud.$(date +%F-%H%M%S)" 2>/dev/null || true

  echo "Disabling waits / managers (ignore errors if missing)..."
  systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true
  systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true
  systemctl disable --now systemd-networkd 2>/dev/null || true
  systemctl mask systemd-networkd 2>/dev/null || true
  systemctl disable --now NetworkManager 2>/dev/null || true

  echo "Neutralizing cloud-init networking..."
  mkdir -p /etc/cloud/cloud.cfg.d
  printf 'network: {config: disabled}\n' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

  echo "Removing netplan YAMLs..."
  rm -f /etc/netplan/*.yaml 2>/dev/null || true

  echo "Installing ifupdown..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1 || true
  apt-get -y install ifupdown >/dev/null 2>&1 || true

  echo "Writing /etc/network/interfaces..."
  build_interfaces > /etc/network/interfaces

  echo "Bringing interface up now..."
  ip link set "${IF}" up || true
  ip addr flush dev "${IF}" || true
  ifdown --force "${IF}" 2>/dev/null || true
  ifup -v "${IF}" || { /etc/init.d/networking restart; ifup -v "${IF}"; }

  echo "Enabling services for persistence..."
  systemctl enable networking >/dev/null 2>&1 || true
  systemctl enable "ifup@${IF}.service" >/dev/null 2>&1 || true

  echo "Done. Current IPs on ${IF}:"
  ip -4 addr show dev "${IF}" | sed 's/^/  /'
  echo "Default route:"
  ip route | sed 's/^/  /'
}

plan

if [[ $DRYRUN -eq 1 && $APPLY -eq 0 ]]; then
  echo "Dry-run only. No changes applied."
  exit 0
fi

if [[ $APPLY -ne 1 ]]; then
  echo
  echo "Nothing applied yet. Re-run with --apply to proceed."
  exit 0
fi

# Safety warning for remote SSH sessions
if [[ -n "${SSH_CONNECTION:-}" ]]; then
  echo "WARNING: You are over SSH. If you change the IP/gateway incorrectly, you may lose connectivity."
  echo "Continuing in 5 seconds... (Ctrl+C to abort)"
  sleep 5
fi

apply_changes
