# PLAN: Replace CenterClick NTP250 firmware with Linux + chrony

## Goal

Boot a self-built Linux image from microSD on the CenterClick NTP250 and run chrony as a Stratum 1 server, disciplined by the onboard GPS (NMEA + PPS). Keep the original card intact so the appliance can be restored.

## Known hardware facts

| Item | Value |
|---|---|
| Model / HW rev / SN | NTP250, rev 10, SN 203 |
| Stock software | 2.26.4 [7a7171e] |
| SoC | Rockchip RK3308 on a Radxa ROCK Pi S compute module (see NOTES.md) |
| RAM | 512 MiB |
| Boot media | microSD, stock card is a Gigastone 8 GB |
| GPS | u-blox MAX-M8Q, active 3.3 V antenna; GPS I2C also wired to the CPU |
| Console | micro-USB via CH340N; stock kernel console is `ttyS0` at 1500000 8N1 (CH340N wiring unconfirmed) |
| Ethernet | 10/100 |
| Power | PoE (in use) or 7-11 V DC on this rev |
| RTC + GPS backup | Supercap, about 3 h holdover |
| PPS output terminal | **None** (added in rev 15); PPS goes only to a SoC GPIO |

## Unknowns to resolve (Phase 1)

- Exact SoC and compute-module part (read the silkscreen)
- GPS UART controller and pins
- PPS GPIO
- RTC part and I2C bus
- LED and button GPIOs
- Bootloader layout: U-Boot location, partition table, extlinux vs. FIT vs. raw
- Whether the stock rootfs is readable or encrypted

## Machines and roles

- **Workstation**: the Linux box with the microSD reader, where Claude Code runs. All build, inspection and imaging happens here.
- **NTP250**: the target. Reach it via its USB console (from the workstation, e.g. `/dev/ttyUSB0`) and via SSH once our image boots.
- **Human-only steps** (Claude Code must stop and ask): powering the unit off and on, opening the case, moving the microSD card, and reading the silkscreen.

## Safety rules

1. Never write to the stock card. Before any `dd` of output, ask the human to confirm the target device by model and size from `lsblk -o NAME,SIZE,MODEL,SERIAL`.
2. Create the stock backup image first, before anything else. Keep it read-only and record its checksum (`sha256sum`).
3. Use a separate blank card for our image.
4. Mount stock partitions read-only (`-o ro`).

## Repo layout

```
centerclick-chrony/
  PLAN.md
  NOTES.md            # findings log: pin map, part numbers, decisions
  stock/              # backup image (gitignored), extracted dts, file listings
  dts/                # our device tree (+ overlays)
  image/              # image build scripts
  rootfs/overlay/     # config files copied into the image
  validate/           # test scripts
```

## Phase 0: Back up the stock card (workstation)

Human: shut down the NTP250, open the case, remove the microSD and insert it into the workstation reader.

1. Identify the device with `lsblk -o NAME,SIZE,MODEL,SERIAL`, then confirm it with the human.
2. Image it: `sudo dd if=/dev/sdX of=stock/centerclick-ntp250.dd bs=4M status=progress conv=fsync`
3. Record the checksum: `sha256sum stock/centerclick-ntp250.dd > stock/SHA256SUMS`
4. `chmod a-w stock/centerclick-ntp250.dd`

**Done when:** the image exists, its checksum is recorded, and its size matches the card.

## Phase 1: Reverse-engineer the stock image (workstation, image file only)

Work only on the image file. The physical card is no longer needed and can go back into the unit.

1. Partition table: `fdisk -l` and `sgdisk -p` on the image. Note any raw gaps before the first partition, since Rockchip idbloader/U-Boot usually sits at sector 64 / 16384.
2. Loop-mount every partition read-only: `sudo losetup -Pr --show -f img`, then mount each one `-o ro`.
3. Find the boot artifacts: kernel, DTB, initramfs, `extlinux.conf`, `boot.scr`, FIT images. Use `dumpimage -l`, `binwalk` and `file` as needed.
4. Extract and decompile the DTB to `stock/ntp250.dts` with `dtc -I dtb -O dts`.
5. Record in NOTES.md:
   - compatible strings (these identify the SoC and board)
   - every enabled UART, I2C, SPI, GPIO-LED, gpio-keys and PPS node
   - RTC compatible string
   - Ethernet PHY node
6. Inspect the rootfs if readable. Look for:
   - time daemon and its config (ntpd/chrony/gpsd)
   - GPS device path and baud rate
   - u-blox init commands
   - any `/sys/class/pps` usage
   - kernel version (`strings` on the kernel image)
7. Extract U-Boot version strings from the raw area.
8. Human: report the compute-module silkscreen and any part markings near the GPS and RTC.

**Done when** NOTES.md contains a complete pin map: GPS TX/RX, PPS GPIO, RTC bus and address, LEDs, button, Ethernet PHY. Each item cites the DTS line or rootfs file it came from.

**Fallback if the DTB is missing or obfuscated:** boot the stock unit and capture the full U-Boot and kernel log over the USB console, then probe with a multimeter. Ask the human before attempting either.

## Phase 2: Choose a base and build the image (workstation)

Pick a base in this order of preference:
1. Armbian or Debian support for the identified compute module, if one exists
2. Generic mainline RK3308 support (U-Boot + kernel), with our own DTS
3. Last resort: reuse the stock U-Boot and kernel with our own rootfs

Then:
1. Write `dts/ntp250.dts`. Start from the mainline DTS for the closest board and carry over the pin map from Phase 1. It must include:
   - a `pps-gpio` node (assert edge per stock config, rising by default)
   - the GPS UART enabled
   - the RTC on its I2C bus
   - LEDs and the button
2. Kernel config must enable:
   - `CONFIG_PPS`, `CONFIG_PPS_CLIENT_GPIO`
   - the RTC driver
   - Ethernet MAC/PHY drivers
   - `CONFIG_NO_HZ_IDLE`, plus high-res timers
3. Rootfs: minimal Debian (debootstrap arm64) containing:
   - chrony, gpsd, gpsd-clients, pps-tools
   - openssh-server, ubxtool (python3-gps)
4. Set up a serial getty on the console UART.
5. Add SSH keys, but no password login.
6. Write the build script `image/build.sh`. It must be reproducible and must produce `out/ntp250.img`.

**Done when** `image/build.sh` runs cleanly from a fresh clone and produces a bootable image file.

## Phase 3: Bring-up (workstation + NTP250)

1. Human: write `out/ntp250.img` to the blank card, after confirming the device per Safety rule 1.
2. Human: insert the card and power up on PoE, with the workstation console attached at 1500000 8N1.
3. Capture the boot log to `validate/boot-*.log`.
4. Check on the NTP250 (console or SSH):
   - `ip link`: Ethernet comes up at 100 Mb/s
   - `cat /dev/ttySx` (the GPS UART): NMEA is flowing
   - `ppstest /dev/pps0`: one assert per second, with no misses over 60 s
   - `hwclock -r`: the RTC reads
   - LEDs toggle via sysfs

**Done when** all five checks pass. Log any failure and its fix in NOTES.md.

## Phase 4: GPS and chrony configuration (NTP250)

1. Configure the M8Q with ubxtool:
   - stationary dynamic model
   - GPS + GLONASS + Galileo enabled
   - timepulse 1 Hz aligned to GPS or UTC
   - only the needed NMEA sentences
   - save to BBR/flash
2. gpsd: run on the GPS UART with `-n`. Make sure PPS reaches chrony exactly once, either via gpsd SHM/SOCK or directly from `/dev/pps0`, never both.
3. Write `/etc/chrony/chrony.conf` (source under `rootfs/overlay/`):
   ```
   refclock SHM 0 refid NMEA offset 0.0 delay 0.2 noselect
   refclock PPS /dev/pps0 lock NMEA refid PPS prefer poll 4
   allow <LAN prefix>
   makestep 1 3
   rtcsync
   ```
   Add 2-3 network servers as sanity sources.
4. Calibrate the NMEA offset: after 1 h, set it from `chronyc sourcestats` so that NMEA ~= PPS.
5. Support holdover and power loss: the supercap RTC should let the box boot with a sane clock before GPS lock.

**Done when:**
- `chronyc tracking` shows Stratum 1 with PPS selected
- after 24 h, the PPS offset std dev is under 1 us and system time is within 10 us of PPS
- LAN clients sync to the box

## Phase 5: Validation (workstation)

1. Wire `validate/collect.sh` to log, every 5 min for 48 h:
   - `chronyc tracking`
   - `chronyc sourcestats`
   - `chronyc sources -v`
2. Have a second LAN host poll both this box and an independent reference (another GPS-disciplined server, if available) and log the offset between them.
3. Summarize the results in NOTES.md: offset distribution, jitter, and any outliers.

## Phase 6: Polish

- LED semantics: PPS LED blinks on each assert; NTP LED is lit when chrony is synced.
- Read-only root, or overlayfs, to protect the SD card. Logs go to tmpfs.
- Unattended security updates.
- README with restore steps: insert the stock card, or `dd` the backup image onto any card of 8 GB or more.

## Out of scope

- PTP. The 10/100 MAC likely lacks hardware timestamping; revisit only if the SoC supports it.
- Modifying the base board.
