#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# DKMS PRE_BUILD: produce hp-wmi.c for the target kernel = upstream hp-wmi.c of
# that kernel version (from kernel.org mirror) + our 8C2E patch.
# Usage: prebuild.sh <kernelver>
set -euo pipefail

kver=${1:?usage: prebuild.sh <kernelver>}
cd "$(dirname "$0")"
PATCH=0001-hp-wmi-add-8C2E-fan-control.patch

# 7.0.0-38-generic -> 7.0 ; 6.12.7-arch1-1 -> 6.12.7 ; 6.12.arch1-1 -> 6.12
ver=$(sed -E 's/[.-](arch|lts|zen|hardened|rc)[^ ]*$//; s/-.*$//' <<<"$kver")
ver=$(sed -E 's/^([0-9]+\.[0-9]+)\.0$/\1/' <<<"$ver")
[[ $ver =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "hp-wmi-victus: cannot parse kernel version '$kver'" >&2; exit 1; }

# kernel.org stable tree has mainline and stable tags (6.12, 6.12.7, ...);
# GitHub's torvalds mirror (mainline tags only) is the fallback.
# Victus S fan control (pwm1) first appears in hp-wmi in Linux 7.0.
if [[ $(printf '%s\n7.0\n' "$ver" | sort -V | head -1) != 7.0 ]]; then
    echo "hp-wmi-victus: kernel v$ver is older than 7.0, whose hp-wmi has no Victus S fan control." >&2
    echo "  Nothing for this patch to enable; upgrade the kernel." >&2
    exit 1
fi

urls=()
for path in drivers/platform/x86/hp/hp-wmi.c drivers/platform/x86/hp-wmi.c; do
    if [[ -n ${HPWMI_URL_TEMPLATE:-} ]]; then
        urls+=("${HPWMI_URL_TEMPLATE//@VER@/$ver}/$path")
    else
        urls+=("https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/$path?h=v$ver"
               "https://raw.githubusercontent.com/torvalds/linux/v$ver/$path")
    fi
done

got=
for url in "${urls[@]}"; do
    if curl -sSfL --retry 2 --max-time 60 -o hp-wmi.c "$url" 2>/dev/null && grep -q "hp_wmi" hp-wmi.c; then
        got=$ver; break
    fi
done

if [[ -z $got ]]; then
    if [[ $ver == 7.0 || $ver == 7.0.* ]]; then
        echo "hp-wmi-victus: download failed, using bundled v7.0 source" >&2
        cp hp-wmi.c.v7.0 hp-wmi.c
    else
        echo "hp-wmi-victus: could not fetch hp-wmi.c for kernel v$ver from kernel.org" >&2
        echo "  (needs network + curl; only kernel 7.0.x has an offline copy)" >&2
        exit 1
    fi
fi

if ! patch --no-backup-if-mismatch -s hp-wmi.c < "$PATCH"; then
    echo "hp-wmi-victus: patch does not apply to kernel v$ver hp-wmi.c." >&2
    echo "  This kernel's driver differs too much; see README (Supported kernels)." >&2
    exit 1
fi
echo "hp-wmi-victus: built hp-wmi.c from upstream v$ver + 8C2E patch"
