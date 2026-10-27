#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Check that the patched hp-wmi is the one running and that the fans really
# respond to pwm1. Run after install and after every kernel update.
#   sudo scripts/verify.sh           full check (briefly changes fan speed)
#   scripts/verify.sh --quick        read-only checks, no root needed
# Exit status 0 only if every check passed.
set -uo pipefail

QUICK=0; [[ ${1:-} == --quick ]] && QUICK=1
fail=0
ok()   { echo "ok   - $*"; }
bad()  { echo "FAIL - $*" >&2; fail=1; }

[[ $(cat /sys/class/dmi/id/board_name 2>/dev/null) == 8C2E ]] || echo "warn - board is not 8C2E; this module targets 8C2E only"

# 1. Is the DKMS build installed for the running kernel?
if command -v dkms >/dev/null 2>&1; then
    if dkms status 2>/dev/null | grep "hp-wmi-victus-8c2e" | grep -q "$(uname -r).*installed"; then
        ok "DKMS module installed for $(uname -r)"
    else
        bad "no installed DKMS build for $(uname -r) (kernel updated? try: sudo dkms autoinstall; check the build log in /var/lib/dkms/hp-wmi-victus-8c2e/)"
    fi
else
    bad "dkms not found"
fi

# 2. Is the module that modprobe would load the DKMS one, and is it what's running?
f=$(modinfo -n hp_wmi 2>/dev/null)
if [[ $f == */updates/dkms/* ]]; then ok "modprobe resolves hp_wmi to $f"
else bad "modprobe resolves hp_wmi to '${f:-nothing}', not the DKMS build"; fi

if [[ -r /sys/module/hp_wmi/srcversion && -n $f ]]; then
    disk=$(modinfo -F srcversion hp_wmi 2>/dev/null)
    live=$(cat /sys/module/hp_wmi/srcversion)
    [[ $disk == "$live" ]] && ok "loaded module matches the file on disk" \
        || bad "loaded hp_wmi (srcversion $live) differs from disk ($disk): reload with rmmod/modprobe or reboot"
else
    bad "hp_wmi is not loaded"
fi

# 3. pwm1 present?
H=
for d in /sys/class/hwmon/hwmon*; do
    [[ $(cat "$d/name" 2>/dev/null) == hp && -e $d/pwm1 ]] && H=$d && break
done
[[ -n $H ]] && ok "pwm1 present at $H" || bad "no pwm1 on the hp hwmon device"

if [[ $QUICK == 0 && -n $H ]]; then
    [[ $EUID -eq 0 ]] || { echo "error: full check needs root (or use --quick)" >&2; exit 2; }
    trap 'echo 2 > "$H/pwm1_enable"' EXIT
    rpm() { cat "$H/fan1_input"; }
    echo 1 > "$H/pwm1_enable"
    echo 90  > "$H/pwm1"; sleep 12; lo=$(rpm)
    echo 220 > "$H/pwm1"; sleep 12; hi=$(rpm)
    echo "     fan1: pwm 90 -> ${lo} RPM, pwm 220 -> ${hi} RPM"
    if (( hi - lo >= 800 )); then ok "fan speed follows pwm1"
    else bad "fan speed did not follow pwm1 (the write was accepted but the EC ignored it?)"; fi
    echo 2 > "$H/pwm1_enable"
    [[ $(cat "$H/pwm1_enable") == 2 ]] && ok "automatic mode restored" || bad "could not restore automatic mode (pwm1_enable != 2)"
    trap - EXIT
fi

(( fail )) && { echo "RESULT: FAILED" >&2; exit 1; }
echo "RESULT: all checks passed"
