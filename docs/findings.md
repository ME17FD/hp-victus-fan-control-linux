# Findings: fan control on board 8C2E

Machine: Victus by HP Gaming Laptop 15-fa1xxx, board `8C2E`, kernel 7.0.0-38.

## Symptom

`/sys/devices/platform/hp-wmi/hwmon/hwmon*/` had `fan1_input`, `fan2_input`
and `pwm1_enable`, but no `pwm1`. hpfand's support check
(`ls .../pwm1`) therefore failed.

## Cause 1: board not in the driver's list

`pwm1` (`hwmon_pwm_input`) is only made visible when
`is_victus_s_thermal_profile()` is true, i.e. the DMI board name matches an
entry in `victus_s_thermal_profile_boards`. `8C2E` was missing. The firmware
already implements the needed WMI commands.

## What the firmware (DSDT `WMID`, WMI GUID `5FB7F034-...`) implements

Commands `0x20008`, by type:

| Type | Behavior (from the disassembled DSDT) |
|---|---|
| `0x26` | Read EC field `FFFS` (max/manual fan flag) |
| `0x27` | Write EC field `FFFS` |
| `0x2D` | Read fan RPM from EC `RPM1..RPM4` (units of 100 RPM) |
| `0x2E` | Write fan speed targets to EC `SRP1` / `SRP2` |
| `0x2F` | Fan table: **hardcoded stub** (see below) |

These match the commands the upstream Victus S code already uses
(`HPWMI_VICTUS_S_FAN_SPEED_GET_QUERY = 0x2D`, `..._SET_QUERY = 0x2E`).

## Cause 2: stub fan table

The driver derives `max_rpm` from the last entry of the fan table (`0x2F`).
On this board the table is a static buffer that is effectively empty past the
first bytes, so `max_rpm == 0`. With that, `pwm1` read 0 in automatic mode and
any write was converted to a 0 RPM target; fans did not respond.

Fix: when `max_rpm == 0`, use limits measured on the machine. With
`pwm1_enable=0` (full speed) the fans reached 4900 / 4800 RPM, so
`max_rpm = 49` (units of 100 RPM), `min_rpm = 20`, `gpu_delta = 0`.

## Reproducing the analysis

```sh
sudo apt install acpica-tools        # or: sudo pacman -S acpica
mkdir dump && cd dump
sudo acpidump -b && sudo chown $USER: *
iasl -d dsdt.dat
grep -n "for WMI 20008h command" dsdt.dsl
```


## Not verified

- Behavior under sustained load with the manual curve (thermals).
- Other 15-fa1xxx board revisions; only `8C2E` was tested.
- The measured 4900 RPM may be below the true hardware maximum if the fans
  had not fully ramped after the 10 s sample.
