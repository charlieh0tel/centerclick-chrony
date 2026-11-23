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
| `fetch` | `build/dl/` | pinned downloads, SHA-256 checked (`sources.sh`), all at once; `uboot` and `kernel` fetch their own too |
| `uboot` | `build/u-boot-rockchip.bin` | `rock-pi-s-rk3308_defconfig` + `u-boot.config` (no EFI loader: boots extlinux only), `patches/u-boot/`, rkbin DDR init v1.26 and BL31 |
| `kernel` | `build/deb/linux-image-KREL_KREL_arm64.deb` | arm64 `defconfig` + `kernel.config`, `patches/linux/`; DTB from `dts/rk3308-ntp250.dts`; KREL `LINUX_VERSION` + `LINUX_LOCALVERSION` (`sources.sh`, e.g. `6.18.60-ntp250.1`); fails unless `LINUX_INPUTS_SHA256` matches the inputs (bump `LINUX_LOCALVERSION` on a change); skipped when that package exists |
| `config` | `build/deb/ntp250-config_VERSION_all.deb`, `build/ntp250-config.deb` (link) | `package/build-ntp250-config.sh` (`package/README.md`) |
| `rootfs` | `build/rootfs.tar` | `mmdebstrap` unshare mode; `rootfs-setup.sh`; installs `build/linux-image.deb` and `build/ntp250-config.deb` |
| `image` | `out/ntp250.img`, `out/ntp250.img.sha256` | GPT, U-Boot at sector 64 in partition 3, ext4 root at 16 MiB, ext4 data after root |

Runs unprivileged.  Host packages (Ubuntu): `gcc-aarch64-linux-gnu`,
`bison`, `flex`, `swig`, `python3-pyelftools`, `libgnutls28-dev`,
`mmdebstrap`, `debian-archive-keyring`, `qemu-user`,
`qemu-user-binfmt`, `gdisk`, e2fsprogs 1.47.1 or later (`mkfs.ext4 -d`
from a tarball).  On an arm64 host: native `gcc`, no qemu.

## Write a card

```
sudo image/flash.sh -k ~/.ssh/id_ed25519.pub /dev/sdX chronos   # image, site/chronos, SSH key
sudo image/flash.sh /dev/sdX                                     # image as built
```

A release's image instead: `ntp250.img.xz` and `ntp250.img.sha256` from
the GitHub release, `unxz` into `out/`.

Checks `out/ntp250.img.sha256`; refuses a device that is not a whole,
removable, unmounted disk.  Confirm DEVICE with
`lsblk -o NAME,SIZE,MODEL,SERIAL` first.  A site overlay is a tree
rooted at `/`, copied onto the root partition owned by root.  `-k
KEYFILE` installs `/root/.ssh/authorized_keys`; no default.  The image
has no SSH key: without `-k`, root logs in on the serial consoles only.

| Site | Contents |
|---|---|
| `site/chronos` | hostname `chronos`; `end0` 10.0.0.239/16, gateway 10.0.0.254, DNS 10.0.0.240, domain `murgatroid.com`, mDNS (`05-site.network`, ahead of the image's DHCP); chrony `log tracking measurements statistics refclocks tempcomp` |

## Image

| Item | Value |
|---|---|
| U-Boot | sector 64 (`u-boot-rockchip.bin`: idbloader + FIT), in GPT partition 3 `uboot`, type Linux reserved, sectors 64-32767, PARTUUID `e659fba8-1c8f-4466-ba63-24033337a2cb`, so `systemd-repart` does not discard it as free space; `bootcmd` `sysboot` of `/boot/extlinux/extlinux.conf` on mmc 1:1, then `reset` (set by `preboot`, `u-boot.config`) |
| U-Boot environment | two copies at card offsets 0xF00000 and 0xF10000, 32 KiB each, in partition 3 (`u-boot.config`; `build.sh` checks the layout against `/etc/fw_env.config`); `fw_printenv`, `fw_setenv` (`libubootenv-tool`); U-Boot saves the built-in one on a new card's first boot (`preboot`: `env info -d -q`), so `fw_setenv` edits a complete environment (with none saved, it refuses: no `/etc/u-boot-initial-env`); otherwise written only while a kernel is on trial; a saved environment replaces the built-in one whole; a card write zeroes it; after writing a new U-Boot alone, the saved `preboot` stays: `fw_setenv preboot` or zero the environment |
| Kernel trial | a new default kernel other than the running one (`ntp250-extlinux`) sets `upgrade_available=1`, `bootcount=0`; U-Boot counts each boot (`BOOTCOUNT_ENV`); past `bootlimit` 3, `altbootcmd` boots `/boot/extlinux/fallback.conf`; a failed boot resets: panic (`panic=10`), hang (U-Boot starts the watchdog, 21.5 s), boot error (`reset`); `ntp250-boot-ok.service`: on the default kernel, `end0` online within 5 min ends the trial, else reboot; on the fallback kernel the trial stays, so every boot takes the fallback until another kernel is installed |
| Root partition | GPT partition 1, type root-arm64, sector 32768, 2048 MiB, PARTUUID `33f4c7e9-0436-473f-9913-48d960e86116`, legacy BIOS bootable; `/var/lib`, `/var/log` empty mount points |
| Data partition | GPT partition 2 `data`, type linux-generic, after root, 512 MiB in the image, PARTUUID `21a10599-5390-427c-8790-0a84a983ba3c`; mounted on `/data`; `/data/var/lib` and `/data/var/log` bind-mounted on `/var/lib`, `/var/log`; no `nofail` |
| First boot | `systemd-repart` (`/usr/lib/repart.d/`) grows `data` to the end of the card, root fixed; `x-systemd.growfs` grows its ext4 |
| Kernel | package `linux-image-KREL`: `/boot/vmlinuz-KREL`, `/boot/config-KREL`, `/usr/lib/linux-image-KREL/rockchip/rk3308-ntp250.dtb`, `/usr/lib/modules/KREL/`; runs the `/etc/kernel/*.d` and `/usr/share/kernel/*.d` hooks; each KREL a separate package, marked automatically installed (`build.sh`; `ntp250-config` depends on it); unattended-upgrades removes unused ones (apt autoremove: keeps the running kernel, the newest and the next newest), running the hooks |
| Boot config | `ntp250-extlinux` (kernel hooks, `ntp250-config` postinst) writes `/boot/extlinux/extlinux.conf` (newest installed kernel, `sort -V`) and `/boot/extlinux/fallback.conf` (the running kernel if older, else the next newest); kernel arguments from `/etc/kernel/cmdline` (`rootfs-setup.sh`, with `panic=10`) |
| Boot target | `multi-user.target`; no `getty@tty1` (no display) |
| Carrier console | `ttyS2` (uart2, carrier micro-USB CH340N), 1500000 8N1: U-Boot from the autoboot prompt on, kernel (`earlycon` from the first message), root autologin |
| Module console | `ttyS0` (uart0, module header 1 pins 8 TX, 10 RX, 6 GND), 1500000 8N1: DDR init, SPL, U-Boot, root autologin; no kernel log |
| Config layout | package `ntp250-config` (`package/README.md`): units, drop-ins, networkd, resolved, journald, dnssd, repart, env files and the ruleset under `/usr/lib` (`/usr/lib/ntp250/`), scripts in `/usr/sbin`; `/etc` only where the program reads nothing else (`/etc/chrony/conf.d/ntp250.conf`, `/etc/apt/apt.conf.d/52ntp250-unattended-upgrades`); site and local overrides go in `/etc` |
| Network | `systemd-networkd`, DHCP on Ethernet (`/usr/lib/systemd/network/10-ethernet.network`), `MulticastDNS=yes` |
| Name resolution | `systemd-resolved` (`resolved.conf.d/ntp250.conf`): LLMNR off; mDNS answers `HOSTNAME.local` and publishes `/usr/lib/systemd/dnssd/`: `ntp.dnssd` (`_ntp._udp`, port 123) |
| SSH | root by key only; host keys generated on first boot |
| Firewall | `nftables.service`, `/usr/lib/ntp250/nftables.conf` (drop-in `nftables.service.d/ntp250.conf`; the package's `/etc/nftables.conf` is unused): input drop except loopback, replies, ICMP/ICMPv6, NTP (UDP 123), SSH, chronymon-web (TCP 8323), mDNS (UDP 5353), DHCP from port 67, DHCPv6 from `fe80::/10` port 547, chain `site`; the rest counted (`dropped by policy`) and dropped; UDP 123 not connection tracked (stock NOTRACK); output and forward: accept, drop; site rules in `/etc/nftables.d/*.nft`, added to chain `inet filter site`; kernel `NF_TABLES`, `NF_TABLES_INET`, `NFT_CT`, `NF_CONNTRACK` built in |
| Hostname | `ntp250` |
| Locale | `LANG=C.UTF-8` (`/etc/locale.conf`, written by `rootfs-setup.sh`; Debian tmpfiles links `/etc/default/locale` to it; built into glibc, no `locales` package) |
| Carrier GPIOs | named lines (`gpioinfo`); `ntp250-gpio-init.service` sets `gps-nreset`=1, `gps-reset`=0, `hdr-ppsout-en`=0 at boot |
| Front panel | `ntp250-panel.service`: system and NTP LEDs and button SW1 with the stock rules (`NOTES.md` "Stock LEDs and button"), chrony in place of ntpd (NTP on: synced to PPS with PPS std dev <= 0.1 ms; blink: higher, or another source at stratum < 8; off: not synced); hold SW1 > 3 s: power off (halts; BL31 `rockchip_soc_system_off: Not supported!`, power stays on until unplugged), > 8 s: reboot; > 14 s: nothing (stock factory reset); DTS default triggers: system `timer`, SD `mmc1`, NTP off |
| GPS reset | `ntp250-gps-reset` (0.5 s pulse, as stock `cc_resetgps`) |
| GPS config | `ntp250-gps-config.service` at every boot: factory reset, 115200, GPS+Galileo (no GLONASS/BeiDou), stationary, NMEA GGA/RMC/ZDA; see `NOTES.md` "GPS configuration" |
| GPS daemon | `gpsd -n -b -s 115200 /dev/ttyS1` (`/usr/lib/ntp250/gpsd.env`), after `ntp250-gps-config` |
| chrony | `/etc/chrony/conf.d/ntp250.conf`: SHM 0 `NMEA` (noselect, offset 0.043), `/dev/pps0` `PPS` locked to NMEA, preferred; Debian pool as sanity sources; serves NTP to all, `ratelimit` with chrony defaults (average interval 8 s, burst 8); `tempcomp`; `-s` (`/usr/lib/ntp250/chrony.env`): at start, clock set from the drift file mtime if later than the clock and RTC (RTC not backed) |
| Monitoring | chronymon from `https://charlieh0tel.github.io/apt-repo` (`image/apt/charlieh0tel.sources`, key embedded, fingerprint A913 FC70 9FC0 4F20 2A4E ECF4 77CD 3854 7561 F4EC); `chronymond`: PPS `/dev/pps0`, gpsd `localhost`, commit every 120 s (`/usr/lib/ntp250/chronymond.env`); `chronymon-web` on `0.0.0.0:8323`, mDNS advert `HOSTNAME chronymon` `_http._tcp` (`chronymon-web.dnssd`); database `/var/lib/chronymon/` |
| Temperature | chrony `tempcomp` reads `thermal_zone0` (SoC logic TSADC); coefficients zero; see `NOTES.md` "Temperature" |
| APT sources | `trixie`, `trixie-updates`, `trixie-security` main (`/etc/apt/sources.list`, from `DEBIAN_MIRROR` and `DEBIAN_SECURITY_MIRROR` in `sources.sh`) |
| Updates | `unattended-upgrades`, daily (`apt-daily*.timer`): Debian stable, point releases, `-updates`, `-security`, charlieh0tel (`52ntp250-unattended-upgrades`); keeps changed conffiles (`--force-confold`); never reboots; log `/var/log/unattended-upgrades/` |
| Journal | volatile, `/run/log/journal`, at most 32 MiB (`journald.conf.d/ntp250.conf`) |
| Watchdog | `dw_wdt` `/dev/watchdog0`, started by U-Boot (21.5 s), fed by the kernel until systemd takes it: `RuntimeWatchdogSec=30s` (`system.conf.d/ntp250.conf`) |
| Disabled | eMMC (not fitted), Wi-Fi (SDIO), Bluetooth (uart4) |
| Timing tweaks | `ntp250-tuning.service`: cpuidle state1 off, governor `performance`, `end0` IRQ on CPU3, `rx-usecs 82`; see `NOTES.md` "Timing tweaks" |

## Write to a card

Confirm the device first (`lsblk -o NAME,SIZE,MODEL,SERIAL`), then:

```
sudo dd if=out/ntp250.img of=/dev/sdX bs=4M conv=fsync status=progress
```

No site overlay, no SSH key: root logs in on the serial consoles only.
