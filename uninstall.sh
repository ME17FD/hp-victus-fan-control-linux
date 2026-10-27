#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "error: run as root (sudo $0)"; exit 1; }
dkms remove hp-wmi-victus-8c2e/1.1 --all || true
rm -rf /usr/src/hp-wmi-victus-8c2e-1.1
depmod -a
echo "Removed. Reboot (or rmmod hp_wmi && modprobe hp_wmi) to load the stock module."
