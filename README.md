# hp-wmi fan control for HP Victus 15-fa1xxx (board 8C2E)

The upstream Linux `hp-wmi` driver supports manual fan control on some
HP Victus / Omen boards (it exposes `pwm1`), but only for boards on a hardcoded
list. **Board `8C2E` (Victus by HP Gaming Laptop 15-fa1xxx) is not on it**, so
on stock kernels you only get read-only `fan*_input` and a bare `pwm1_enable`.

The firmware does support manual fan control on this board. This repo packages
a small patch to `hp-wmi.c` as a DKMS module that enables it, so that
[hpfand](https://github.com/emomaxd/hpfand) (or anything else using
`hwmon` `pwm1`) works.

> [!CAUTION]
> **Use at your own risk.** This project overrides the firmware's thermal
> management on your laptop and loads an unofficial, unsigned kernel module.
> Setting fans too low, or leaving them in manual mode under heavy load, can
> cause overheating, throttling, thermal shutdown, data loss or hardware damage.
> It was developed and tested on a single machine (board 8C2E, idle and
> fixed-speed tests only) and comes with **no warranty** (see [LICENSE](LICENSE)).
>
> - Test with the machine under observation and watch temperatures.
> - Keep `pwm1_enable=2` (automatic, firmware-controlled) as your fallback;
>   `sudo ./uninstall.sh` and a reboot restore the stock driver.
> - Not affiliated with or endorsed by HP.

## What the patch does

[`patches/0001-hp-wmi-add-8C2E-fan-control.patch`](patches/0001-hp-wmi-add-8C2E-fan-control.patch)
(against upstream Linux v7.0 `drivers/platform/x86/hp/hp-wmi.c`):

1. Adds `8C2E` to `victus_s_thermal_profile_boards`.
2. Falls back to measured fan limits when the firmware's fan table is a stub
   (this board returns `max_rpm == 0`, which would make every PWM value map to
   0 RPM). Limits used: min 2000 RPM, max 4900 RPM, no GPU offset.

Details of how this was found: [docs/findings.md](docs/findings.md).

## Requirements

- Board name `8C2E` (`cat /sys/class/dmi/id/board_name`)
- A kernel whose `hp-wmi` already has the Victus S fan support (the
  patch is based on v7.0 source and was only built against 7.0.0-38; older or newer kernels may not build)
- `dkms` and headers for your running kernel
- Secure Boot disabled, or sign the module yourself (DKMS modules are unsigned
  unless you configure MOK signing)

## Install

```sh
git clone <this repo> && cd hp-victus-fan-control-linux
sudo ./install.sh
sudo rmmod hp_wmi && sudo modprobe hp_wmi     # or reboot
ls /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1
```

`install.sh` installs `dkms` and headers with `apt` (Debian/Ubuntu) or
`pacman` (Arch; picks `linux-headers`, `linux-lts-headers`, `linux-zen-headers`
or `linux-hardened-headers` from your running kernel). On other distros install
those yourself first. DKMS rebuilds the module on every kernel update.

Arch note: the in-tree `hp-wmi` is shipped compressed (`.ko.zst`); DKMS installs
the patched module under `updates/dkms`, which `depmod` prefers. Verified on
Ubuntu only; the Arch path uses the standard DKMS flow but has not been tested
by the author. Reports welcome.

Uninstall: `sudo ./uninstall.sh`.

## Verify

```sh
H=$(echo /sys/devices/platform/hp-wmi/hwmon/hwmon*)
cat $H/pwm1_enable $H/pwm1 $H/fan1_input $H/fan2_input
echo 1   | sudo tee $H/pwm1_enable     # manual
echo 100 | sudo tee $H/pwm1; sleep 10; cat $H/fan1_input $H/fan2_input   # ~1900 RPM
echo 200 | sudo tee $H/pwm1; sleep 10; cat $H/fan1_input $H/fan2_input   # ~3600 RPM
echo 2   | sudo tee $H/pwm1_enable     # back to automatic
```

Results on the reference machine: `pwm1=100` gave 1900/1800 RPM, `pwm1=200`
gave 3600/3600 RPM, `pwm1_enable=0` (max) gave 4900/4800 RPM.

`pwm1_enable`: `0` = full speed, `1` = manual, `2` = automatic (firmware).
The driver re-sends the manual speed every 90 s because the firmware resets it
after about 120 s.

## Fan curves with hpfand

With `pwm1` present, install [hpfand](https://github.com/emomaxd/hpfand)
(Bash daemon + `hpf` CLI, systemd, GPL-2.0), which follows your
`platform_profile` and applies a CPU/GPU temperature curve:

```sh
git clone https://github.com/emomaxd/hpfand && cd hpfand && sudo ./install.sh
hpf status
```

It works on Arch (needs `systemd`, `udev`, `util-linux`).

## Upstreaming

This should go to the kernel, not stay out-of-tree. Send to
`platform-driver-x86@vger.kernel.org` (see `scripts/get_maintainer.pl`). A
maintainer will likely prefer per-board limits over a magic fallback; treat the
fallback here as a pragmatic stopgap.

## Layout

| Path | Contents |
|---|---|
| `dkms/` | `hp-wmi.c` (patched, v7.0 base), `Makefile`, `dkms.conf` |
| `patches/` | The change as a unified diff against upstream |
| `docs/findings.md` | Reverse-engineering notes (DSDT / WMI) |
| `install.sh`, `uninstall.sh` | DKMS install helpers (apt / pacman) |
| `scripts/fan-test.sh` | Hold a fixed fan speed for N seconds, log RPM/temps, restore auto |

## License

GPL-2.0, same as the Linux kernel driver this is derived from
(`hp-wmi.c`: GPL-2.0-or-later, see its header for original authors).
