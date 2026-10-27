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

## What the patches do

Both apply to upstream `drivers/platform/x86/hp/hp-wmi.c` at build time:

- [`0001`](patches/0001-hp-wmi-add-8C2E-fan-control.patch) (required)
  1. Adds `8C2E` to `victus_s_thermal_profile_boards`.
  2. Falls back to measured fan limits when the firmware's fan table is a stub
     (this board returns `max_rpm == 0`, which would make every PWM value map to
     0 RPM). Limits: min 2000 RPM, max 4900 RPM, no GPU offset. The driver logs
     a `dev_warn` whenever the fallback is used.
- [`0002`](patches/0002-hp-wmi-warn-on-fan-keep-alive-failure.patch) (optional)
  Logs a warning when the periodic keep-alive write fails; upstream ignores
  that error, after which the firmware silently resets the fans after ~120 s.

Details of how this was found: [docs/findings.md](docs/findings.md).

## Requirements

- Board name `8C2E` (`cat /sys/class/dmi/id/board_name`)
- **Linux 7.0 or newer.** Fan control for Victus S boards first appears in
  `hp-wmi` in 7.0; kernels 6.17-6.19 have no such code, so there is nothing for
  this patch to enable and the build stops with a clear message.
- `dkms`, `curl`, `patch`, and headers for your running kernel
- Network access when DKMS builds (see below), except on 7.0.x
- Secure Boot disabled, or sign the module yourself (DKMS modules are unsigned
  unless you configure MOK signing)

## Supported kernels

DKMS does not ship a full driver. At build time `dkms/prebuild.sh` downloads
the `hp-wmi.c` for your kernel's upstream version (from kernel.org's stable tree,
GitHub as fallback), applies the patch, and builds it. So each kernel gets its
own driver source plus the 8C2E change, and a newer kernel keeps its upstream
`hp-wmi` fixes.

| Kernel | Result |
|---|---|
| 7.0.x | Tested (7.0.0-38, Ubuntu). Offline copy bundled, so no network needed |
| 7.1+ | Source + patch apply (checked), **not compiled or run** |
| < 7.0 | Refused: no Victus S fan control in `hp-wmi` |
| Distro kernels | Source comes from the upstream tag, not your distro's patched copy |

If the patch stops applying to a future kernel, the build fails with a message
instead of installing a wrong module. Open an issue with your `uname -r`.

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
those (and `curl`, `patch`) yourself first. DKMS rebuilds the module on every kernel update.

Arch note: the in-tree `hp-wmi` is shipped compressed (`.ko.zst`); DKMS installs
the patched module under `updates/dkms`, which `depmod` prefers. Verified on
Ubuntu only; the Arch path uses the standard DKMS flow but has not been tested
by the author. Reports welcome.

Uninstall: `sudo ./uninstall.sh`.

## Verify (run this after install and after every kernel update)

```sh
scripts/verify.sh --quick     # read-only: DKMS built for this kernel, module is the patched one, pwm1 exists
sudo scripts/verify.sh        # full: also checks the fans really follow pwm1 (changes fan speed ~25 s)
sudo scripts/fan-test.sh      # hold max fan for 3 min and log RPM/temps
```

`verify.sh` exits non-zero if anything is wrong. Reference results: `pwm1=100`
gave 1900/1800 RPM, `pwm1=200` gave 3600/3600 RPM, `pwm1_enable=0` (max) gave
4900/4800 RPM.

`pwm1_enable`: `0` = full speed, `1` = manual, `2` = automatic (firmware).
The driver re-sends the manual speed every 90 s because the firmware resets it
after about 120 s.

## Known limits (things that can still fail without an obvious error)

- **Kernel updates.** DKMS rebuilds automatically, but a failed rebuild only
  shows in your package manager's output and you boot the stock driver with no
  `pwm1`. Run `scripts/verify.sh --quick` after updating, or check
  `/var/lib/dkms/hp-wmi-victus-8c2e/`.
- **The EC can ignore a write that the WMI call reports as successful.** The
  driver does not read the speed back. This is why `verify.sh` checks RPM, not
  just the return code.
- **Build stops are loud, behavior drift is not.** Patches are applied with
  zero fuzz so a changed context fails the build, but a kernel that compiles
  cleanly with changed fan semantics would not be noticed. Only 7.0.x has been
  run on hardware.
- Fan limits (2000-4900 RPM) were measured on one unit over a 10 s sample.

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
| `dkms/` | `prebuild.sh` (fetch + patch), `hp-wmi.c.v7.0` (offline base), `Makefile`, `dkms.conf` |
| `patches/` | `0001` (8C2E support, required) and `0002` (keep-alive logging, optional) as diffs against upstream |
| `docs/findings.md` | Reverse-engineering notes (DSDT / WMI) |
| `install.sh`, `uninstall.sh` | DKMS install helpers (apt / pacman) |
| `scripts/verify.sh` | Post-install / post-kernel-update check; non-zero exit on any failure |
| `scripts/fan-test.sh` | Hold a fixed fan speed for N seconds, log RPM/temps, restore auto |

## License

GPL-2.0, same as the Linux kernel driver this is derived from
(`hp-wmi.c`: GPL-2.0-or-later, see its header for original authors).
