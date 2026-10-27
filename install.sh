#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Install the patched hp-wmi module (HP Victus 15-fa1xxx, board 8C2E) via DKMS.
# Supports Debian/Ubuntu (apt) and Arch (pacman); other distros: install
# dkms + kernel headers yourself and re-run.
set -euo pipefail

NAME=hp-wmi-victus-8c2e
VER=1.0
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dkms"

[[ $EUID -eq 0 ]] || { echo "error: run as root (sudo $0)"; exit 1; }

board=$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)
if [[ "$board" != 8C2E && "${FORCE:-0}" != 1 ]]; then
    echo "error: this module patch targets board 8C2E, found '${board:-unknown}'."
    echo "       Set FORCE=1 to install anyway (the patch only matters on 8C2E)."
    exit 1
fi

if ! command -v dkms >/dev/null 2>&1 || [[ ! -e /lib/modules/$(uname -r)/build ]]; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y dkms "linux-headers-$(uname -r)"
    elif command -v pacman >/dev/null 2>&1; then
        # Headers package must match your kernel (linux-headers, linux-lts-headers, linux-zen-headers, ...)
        case "$(uname -r)" in
            *-lts)  hdr=linux-lts-headers ;;
            *-zen)  hdr=linux-zen-headers ;;
            *-hardened) hdr=linux-hardened-headers ;;
            *)      hdr=linux-headers ;;
        esac
        pacman -S --needed --noconfirm dkms "$hdr"
    else
        echo "error: install 'dkms' and your kernel headers, then re-run"; exit 1
    fi
fi

dkms remove "$NAME/$VER" --all 2>/dev/null || true
rm -rf "/usr/src/$NAME-$VER"
cp -r "$SRC_DIR" "/usr/src/$NAME-$VER"
dkms add "$NAME/$VER"
dkms install "$NAME/$VER"
depmod -a

echo
echo "Installed. Reload the module now, or reboot:"
echo "  sudo rmmod hp_wmi && sudo modprobe hp_wmi"
echo "Then check:  ls /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1"
