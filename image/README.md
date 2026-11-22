# image

Builds `out/ntp250.img`: mainline U-Boot and Linux with a Debian arm64
root filesystem, for the NTP250 (ROCK Pi S V1.3 on the CHRONOS V10
carrier).

## Build

```
image/build.sh                # all stages
image/build.sh kernel image   # selected stages, in the order given
```

| Stage | Output | Notes |
|---|---|---|
| `fetch` | `build/dl/` | pinned downloads, SHA-256 checked (`sources.sh`) |
| `uboot` | `build/u-boot-rockchip.bin` | `rock-pi-s-rk3308_defconfig`, `patches/u-boot/`, rkbin DDR init v1.26 and BL31 |
| `kernel` | `build/kernel.tar` | arm64 `defconfig` + `kernel.config`, `patches/linux/`; DTB from `dts/rk3308-ntp250.dts` |
| `rootfs` | `build/rootfs.tar` | `mmdebstrap` unshare mode; overlay `rootfs/overlay/`; `rootfs-setup.sh` |
| `image` | `out/ntp250.img`, `out/ntp250.img.sha256` | GPT, U-Boot at sector 64 in partition 3, ext4 root at 16 MiB, ext4 data after root |

Runs unprivileged.  Host packages (Ubuntu): `gcc-aarch64-linux-gnu`,
`bison`, `flex`, `swig`, `python3-pyelftools`, `libgnutls28-dev`,
`mmdebstrap`, `debian-archive-keyring`, `qemu-user`,
`qemu-user-binfmt`, `gdisk`, e2fsprogs 1.47.1 or later (`mkfs.ext4 -d`
from a tarball).

`NTP250_AUTHORIZED_KEYS` names the SSH public key installed for root
(default `~/.ssh/id_ed25519.pub`).

## Write a card

```
sudo image/flash.sh /dev/sdX chronos   # image, then site/chronos
sudo image/flash.sh /dev/sdX           # image as built
```

Checks `out/ntp250.img.sha256`; refuses a device that is not a whole,
removable, unmounted disk.  Confirm DEVICE with
`lsblk -o NAME,SIZE,MODEL,SERIAL` first.  A site overlay is a tree
rooted at `/`, copied onto the root partition owned by root.

| Site | Contents |
|---|---|
| `site/chronos` | hostname `chronos`; `end0` 10.0.0.239/16, gateway 10.0.0.254, DNS 10.0.0.240, domain `murgatroid.com` (`05-site.network`, ahead of the image's DHCP); chrony `log tracking measurements statistics rtc refclocks tempcomp` |

## Image

| Item | Value |
|---|---|
| U-Boot | sector 64 (`u-boot-rockchip.bin`: idbloader + FIT), in GPT partition 3 `uboot`, type Linux reserved, sectors 64-32767, so `systemd-repart` does not discard it as free space |
| Root partition | GPT partition 1, type root-arm64, sector 32768, 2048 MiB, PARTUUID `33f4c7e9-0436-473f-9913-48d960e86116`, legacy BIOS bootable; `/var/lib`, `/var/log` empty mount points |
| Data partition | GPT partition 2 `data`, type linux-generic, after root, 512 MiB in the image, PARTUUID `21a10599-5390-427c-8790-0a84a983ba3c`; mounted on `/data`; `/data/var/lib` and `/data/var/log` bind-mounted on `/var/lib`, `/var/log`; no `nofail` |
| First boot | `systemd-repart` (`/etc/repart.d/`) grows `data` to the end of the card, root fixed; `x-systemd.growfs` grows its ext4 |
| Boot config | `/boot/extlinux/extlinux.conf`, `/boot/Image`, `/boot/dtbs/rockchip/rk3308-ntp250.dtb` |
| Carrier console | `ttyS2` (uart2, carrier micro-USB CH340N), 1500000 8N1: U-Boot from the autoboot prompt on, kernel (`earlycon` from the first message), root autologin |
| Module console | `ttyS0` (uart0, module header 1 pins 8 TX, 10 RX, 6 GND), 1500000 8N1: DDR init, SPL, U-Boot, root autologin; no kernel log |
| Network | `systemd-networkd`, DHCP on Ethernet |
| SSH | root by key only; host keys generated on first boot |
| Hostname | `ntp250` |
| Locale | `LANG=C.UTF-8` (`/etc/locale.conf`; Debian tmpfiles links `/etc/default/locale` to it; built into glibc, no `locales` package) |
| Carrier GPIOs | named lines (`gpioinfo`); `ntp250-gpio-init.service` sets `gps-nreset`=1, `gps-reset`=0, `hdr-ppsout-en`=0 at boot |
| Front panel | `ntp250-panel.service`: system and NTP LEDs and button SW1 with the stock rules (`NOTES.md` "Stock LEDs and button"), chrony in place of ntpd (NTP on: synced to PPS with PPS std dev <= 0.1 ms; blink: higher, or another source at stratum < 8; off: not synced); hold SW1 > 3 s: power off (halts; BL31 `rockchip_soc_system_off: Not supported!`, power stays on until unplugged), > 8 s: reboot; > 14 s: nothing (stock factory reset); DTS default triggers: system `timer`, SD `mmc1`, NTP off |
| GPS reset | `ntp250-gps-reset` (0.5 s pulse, as stock `cc_resetgps`) |
| GPS config | `ntp250-gps-config.service` at every boot: factory reset, 115200, GPS+Galileo (no GLONASS/BeiDou), stationary, NMEA GGA/RMC/ZDA; see `NOTES.md` "GPS configuration" |
| GPS daemon | `gpsd -n -b -s 115200 /dev/ttyS1` (`/etc/default/gpsd`), after `ntp250-gps-config` |
| chrony | `/etc/chrony/conf.d/ntp250.conf`: SHM 0 `NMEA` (noselect, offset 0.043), `/dev/pps0` `PPS` locked to NMEA, preferred; Debian pool as sanity sources; serves NTP to all, `ratelimit` with chrony defaults (average interval 8 s, burst 8); `tempcomp` |
| Temperature | chrony `tempcomp` reads `thermal_zone0` (SoC logic TSADC); coefficients zero; see `NOTES.md` "Temperature" |
| Journal | volatile, `/run/log/journal`, at most 32 MiB (`journald.conf.d/ntp250.conf`) |
| Watchdog | `dw_wdt` `/dev/watchdog0`, systemd `RuntimeWatchdogSec=30s` (`system.conf.d/ntp250.conf`) |
| Disabled | eMMC (not fitted), Wi-Fi (SDIO), Bluetooth (uart4) |
| Timing tweaks | `ntp250-tuning.service`: cpuidle state1 off, governor `performance`, `end0` IRQ on CPU3, `rx-usecs 82`; see `NOTES.md` "Timing tweaks" |

## Write to a card

Confirm the device first (`lsblk -o NAME,SIZE,MODEL,SERIAL`), then:

```
sudo dd if=out/ntp250.img of=/dev/sdX bs=4M conv=fsync status=progress
```
