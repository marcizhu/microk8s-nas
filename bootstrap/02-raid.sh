#!/bin/bash
set -euo pipefail

# =============================================================
# NAS RAID / Storage Setup (optional)
#
# Walks you through:
#   1. Reusing an existing MD array, creating a new RAID 5 array,
#      or using a single disk.
#   2. Formatting (only if empty) and mounting the device, with a
#      persistent /etc/fstab entry.
#   3. Optionally exposing it over NFS with macOS-friendly UID/GID
#      squashing.
#
# Safe to skip entirely if your storage is already set up.
# =============================================================

COLOR_BLUE='\033[1;34m'
COLOR_WHITE='\033[1;37m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m'

echo "███╗░░░███╗██╗░█████╗░██████╗░░█████╗░██╗░░██╗░█████╗░░██████╗  ███╗░░██╗░█████╗░░██████╗"
echo "████╗░████║██║██╔══██╗██╔══██╗██╔══██╗██║░██╔╝██╔══██╗██╔════╝  ████╗░██║██╔══██╗██╔════╝"
echo "██╔████╔██║██║██║░░╚═╝██████╔╝██║░░██║█████═╝░╚█████╔╝╚█████╗░  ██╔██╗██║███████║╚█████╗░"
echo "██║╚██╔╝██║██║██║░░██╗██╔══██╗██║░░██║██╔═██╗░██╔══██╗░╚═══██╗  ██║╚████║██╔══██║░╚═══██╗"
echo "██║░╚═╝░██║██║╚█████╔╝██║░░██║╚█████╔╝██║░╚██╗╚█████╔╝██████╔╝  ██║░╚███║██║░░██║██████╔╝"
echo "╚═╝░░░░░╚═╝╚═╝░╚════╝░╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝░╚════╝░╚═════╝░  ╚═╝░░╚══╝╚═╝░╚═╝╚═════╝░"
echo
echo -e "${COLOR_WHITE}=== NAS RAID / Storage Setup ===${COLOR_RESET}"
echo "Answer 'n' or leave blank to skip any step."
echo

# Confirm before doing anything destructive
confirm_destructive() {
    local msg=$1
    local reply
    echo -e "${COLOR_YELLOW}${msg}${COLOR_RESET}"
    read -r -p "Type 'yes' to confirm: " reply
    if [ "$reply" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
}

# -------------------------------------------------------------
# 1. Pick / create the data block device
# -------------------------------------------------------------
BLOCK_DEV=""

if command -v mdadm >/dev/null 2>&1; then
    EXISTING_MD="$(sudo mdadm --detail --scan 2>/dev/null | awk '{print $1}' | head -n1 || true)"
    if [ -n "$EXISTING_MD" ]; then
        echo -e "${COLOR_BLUE}Found existing MD array: ${EXISTING_MD}${COLOR_RESET}"
        read -r -p "Use it as the data device? [Y/n] " ans
        [[ "$ans" =~ ^[Nn] ]] || BLOCK_DEV="$EXISTING_MD"
    fi
fi

if [ -z "$BLOCK_DEV" ]; then
    read -r -p "Create a new RAID 5 array now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy] ]]; then
        read -r -p "Member disks (space separated) [/dev/sdb /dev/sdc /dev/sdd]: " members
        members="${members:-/dev/sdb /dev/sdc /dev/sdd}"
        read -r -p "Target MD device [/dev/md0]: " target
        target="${target:-/dev/md0}"
        dev_count="$(echo $members | wc -w | tr -d ' ')"

        echo
        confirm_destructive "WARNING: creating the array DESTROYS all data on: ${members}"
        [ "$dev_count" -ge 2 ] || { echo "RAID 5 needs at least 2 disks." >&2; exit 1; }

        sudo apt-get install -y mdadm
        # shellcheck disable=SC2086
        sudo mdadm --create "$target" --level=5 --raid-devices="$dev_count" $members
        sudo mdadm --detail "$target"
        BLOCK_DEV="$target"
    else
        read -r -p "Use an existing single disk instead? (e.g. /dev/sdb1) [n]: " single
        if [[ "$single" =~ ^[Nn]$ ]] || [ -z "$single" ]; then
            echo
            echo "No data device selected — skipping storage/NFS setup."
            exit 0
        fi
        BLOCK_DEV="$single"
    fi
fi

echo -e "${COLOR_BLUE}Using data device: ${BLOCK_DEV}${COLOR_RESET}"
echo

# -------------------------------------------------------------
# 2. Filesystem (only if the device is empty)
# -------------------------------------------------------------
if ! sudo blkid "$BLOCK_DEV" >/dev/null 2>&1; then
    read -r -p "No filesystem detected on ${BLOCK_DEV}. Format as ext4? [y/N] " ans
    if [[ "$ans" =~ ^[Yy] ]]; then
        confirm_destructive "WARNING: formatting DESTROYS all data on ${BLOCK_DEV}"
        sudo mkfs.ext4 "$BLOCK_DEV"
    else
        echo "Aborting — no usable filesystem on ${BLOCK_DEV}." >&2
        exit 1
    fi
fi

# -------------------------------------------------------------
# 3. Mount point + /etc/fstab
# -------------------------------------------------------------
read -r -p "Mount point [/mnt/nas]: " mountpoint
mountpoint="${mountpoint:-/mnt/nas}"

sudo mkdir -p "$mountpoint"

if ! mountpoint -q "$mountpoint"; then
    sudo mount "$BLOCK_DEV" "$mountpoint"
fi

if ! grep -qsF "$BLOCK_DEV" /etc/fstab; then
    echo "${BLOCK_DEV} ${mountpoint} ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
    echo "Added a persistent entry to /etc/fstab."
fi
echo "Mounted ${BLOCK_DEV} at ${mountpoint}."
echo

# -------------------------------------------------------------
# 4. NFS (optional, with macOS UID/GID squashing)
# -------------------------------------------------------------
read -r -p "Expose ${mountpoint} over NFS? [y/N] " ans
if [[ "$ans" =~ ^[Yy] ]]; then
    sudo apt-get install -y nfs-kernel-server

    read -r -p "Subnet to allow (e.g. 192.168.1.0/24) [192.168.1.0/24]: " subnet
    subnet="${subnet:-192.168.1.0/24}"
    read -r -p "Force UID for macOS clients [1000]: " anonuid
    anonuid="${anonuid:-1000}"
    read -r -p "Force GID for macOS clients [1000]: " anongid
    anongid="${anongid:-1000}"

    export_line="${mountpoint} ${subnet}(rw,sync,no_subtree_check,all_squash,anonuid=${anonuid},anongid=${anongid})"

    # Replace any existing export for this path, then append the new one.
    sudo sed -i "\|^${mountpoint}[[:space:]]|d" /etc/exports 2>/dev/null || true
    echo "$export_line" | sudo tee -a /etc/exports
    sudo exportfs -ra
    echo "NFS export configured."
fi

# -------------------------------------------------------------
# 5. Done
# -------------------------------------------------------------
echo
echo -e "${COLOR_WHITE}Storage setup complete.${COLOR_RESET}"
echo "Reminder: make sure the app PVCs in apps/ (transmission, jellyfin, etc.)"
echo "point their hostPath at ${mountpoint}."
