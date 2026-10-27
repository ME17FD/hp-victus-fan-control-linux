#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Hold the fans at a fixed manual PWM for a while and log RPM/temps.
# Usage: sudo scripts/fan-test.sh [pwm 0-255, default 255] [seconds, default 180]
# Automatic mode is always restored on exit (including Ctrl-C).
set -euo pipefail

PWM=${1:-255}
DURATION=${2:-180}
[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }
[[ $PWM =~ ^[0-9]+$ && $PWM -le 255 && $DURATION =~ ^[0-9]+$ ]] || { echo "usage: $0 [pwm 0-255] [seconds]"; exit 1; }

for d in /sys/class/hwmon/hwmon*; do
    [[ "$(cat "$d/name")" == hp && -e "$d/pwm1" ]] && H=$d && break
done
[[ -n "${H:-}" ]] || { echo "error: hp hwmon with pwm1 not found (is the patched module loaded?)"; exit 1; }

temps() {
    local out="" d n t
    for d in /sys/class/hwmon/hwmon*; do
        n=$(cat "$d/name")
        [[ $n == coretemp || $n == nvme || $n == acpitz* ]] || continue
        t=$(cat "$d"/temp1_input 2>/dev/null) || continue
        out+="$n=$((t/1000))C "
    done
    command -v nvidia-smi >/dev/null && out+="gpu=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)C"
    echo "$out"
}

restore() { echo 2 > "$H/pwm1_enable"; echo "restored automatic mode (pwm1_enable=$(cat "$H/pwm1_enable"))"; }
trap restore EXIT

echo "hwmon: $H  pwm=$PWM  duration=${DURATION}s"
echo "before: fan1=$(cat "$H/fan1_input") fan2=$(cat "$H/fan2_input") $(temps)"
echo 1 > "$H/pwm1_enable"
echo "$PWM" > "$H/pwm1"

for ((t = 10; t <= DURATION; t += 10)); do
    sleep 10
    echo "t=${t}s mode=$(cat "$H/pwm1_enable") fan1=$(cat "$H/fan1_input") fan2=$(cat "$H/fan2_input") $(temps)"
done
