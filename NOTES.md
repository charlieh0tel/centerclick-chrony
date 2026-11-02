# NOTES: NTP250 findings

## Stock image

| File | What | Source |
|---|---|---|
| `stock/centerclick-ntp250.dd` | whole stock card, 7791968256 bytes (gitignored) | `dd if=/dev/sdc` |
| `stock/SHA256SUMS` | checksum of the above | `sha256sum` |
| `stock/extracted/` | copy of `/backup2` from partition 4 (gitignored) | `debugfs -c -R 'rdump /backup2 ...'` |
| `stock/extracted/rootfs/` | unpacked `rootfs.squashfs` (gitignored) | `unsquashfs` |
| `stock/ntp250.dts` | decompiled `boot/rk3308-rock-pi-s-chronos.dtb` | `dtc -I dtb -O dts` |
| `stock/chronos-overlay.dts` | decompiled `boot/rockchip/overlays/chronos.dtbo` | `dtc -I dtb -O dts` |

## Card layout

Source: `gdisk -l`, `file`, and `sha256sum` against `/meta.sums` on
partition 1.  GPT; 512-byte sectors.

| Start sector | Size | Content | Matches |
|---|---|---|---|
| 64 | 130048 B | `idbloader.img` (Rockchip, encrypted header) | `meta.sums` |
| 16384 | 1 MiB | `uboot.img` (`LOADER` header) | `meta.sums` |
| 24576 | 1 MiB | `trust.img` (`BL3X` header) | `meta.sums` |
| 32768 (p1, `boot`, EF00) | 112 MiB | ext4: `Image.gz`, `boot.scr`, DTB, `rootdev.txt`, `meta.size`, `meta.sums` | `meta.sums` |
| 262144 (p2) | 448 MiB | rootfs squashfs, slot A | `meta.sums` |
| 1179648 (p3) | 448 MiB | rootfs squashfs, slot B, identical to p2 | `meta.sums` |
| 2097152 (p4) | 4 GiB | ext4 `/data`: config, `/backup`, `/backup2` | |

- `rootdev.txt`: `rootdev=/dev/mmcblk0p2`.
- `meta.sums` hashes `rootfs.squashfs` padded to 42991616 bytes.
- `/backup` and `/backup2` on p4 hold the same `idbloader.img`,
  `uboot.img`, `trust.img`; `/backup2` also holds `rootfs.squashfs`.
  All match `meta.sums`.
- p4 state: clean, last write 2020-01-01 16:00:02 (unit time before
  sync).

## Platform

| Item | Value | Source |
|---|---|---|
| Compute module | Radxa ROCK Pi S (`radxa,rockpis`), stock board by visual inspection | `boot/rk3308-rock-pi-s-chronos.dtb`, human |
| Board model string | "Radxa ROCK Pi S On Chronos Carrier" | same DTB |
| SoC | RK3308 | DTB name, `boot.scr` |
| U-Boot | 2017.09 (Rockchip vendor) | `strings uboot.img` |
| Kernel | 4.4.247 (Rockchip vendor), Buildroot 2023.02.11 toolchain | `zcat boot/Image.gz \| strings` |
| Rootfs | Buildroot 2023.02.11, squashfs, gzip | `rootfs/etc/os-release` |

## Boot

Source: `boot/boot.scr`.

- Reads `rootdev.txt` from the boot partition for `rootdev`.
- Loads `Image.gz` and `rk3308-rock-pi-s-chronos.dtb` by `ext4load` from
  `${distro_bootpart}`.
- bootargs: `root=${rootdev} console=ttyS0,1500000n8 ro
  rootfstype=squashfs rootwait swiotlb=1024 net.ifnames=0`.
- Overlays present in `boot/rockchip/overlays/`: `chronos.dtbo`,
  `i2c1-hym8563.dtbo`, `rk3308-i2c1.dtbo`, `rk3308-uart{0,1,2}.dtbo`.

## Pin map

Source: `stock/ntp250.dts` (decompiled from
`boot/rk3308-rock-pi-s-chronos.dtb`, the DTB `boot.scr` loads; no
overlays are applied).  GPIO phandles: `0x19` = gpio0, `0x85` = gpio2.
Pin index n maps to `GPIOb_` + `ABCD`[n / 8] + n % 8.

| Function | Pin / bus | Flags | DTS line |
|---|---|---|---|
| PPS (`pps-gpio`) | GPIO2_B6 | active high, pull none | 2834 (`pps`), 2621 (`pps-pins`) |
| GPS UART (`ttyS1`, uart1 `ff0b0000`) | GPIO1_D1, GPIO1_D0 | pull up | 555, 1970 |
| Console (`ttyS0`, uart0 `ff0a0000`) | GPIO2_A1, GPIO2_A0 | pull up | 539, 1947 |
| User UART (`ttyS2`, uart2m0 `ff0c0000`) | GPIO1_C7, GPIO1_C6 | pull up | 571, 1988 |
| RTC | `haoyu,hym8563`, I2C1 (`ff050000`) 0x51, IRQ GPIO0_C1 level low | | 441, 2613 |
| EEPROM | `st,24c64`, I2C1 0x54 | | 455 |
| LED `green:power` (module) | GPIO0_A6 | trigger heartbeat | 2798 |
| LED `blue:sd` (module) | GPIO0_A5 | trigger mmc0 | 2805 |
| LED `green:system` | GPIO2_A7 | trigger timer | 2812 |
| LED `green:sd` | GPIO2_A5 | trigger mmc0 | 2819 |
| LED `green:ntp` | GPIO2_B5 | trigger none | 2826 |
| Front-panel button `fp-button-1` | GPIO2_B1 | gpio-export input | 2760 |
| `hdr-ppsout-en` | GPIO2_A4 | gpio-export output, low | 2765 |
| `gps-nreset` | GPIO2_B7 | gpio-export output, high | 2776 |
| `gps-reset` | GPIO2_C0 | gpio-export output, low | 2782 |
| `poe-sense` | GPIO2_B2 | gpio-export input | 2788 |
| `barrel-mech` | GPIO0_B7 | gpio-export input | 2771 |
| Ethernet (`ff4e0000`) | RMII, MAC clock output, PHY reset GPIO0_A7 active low | | 1294 |

- `gpio-export` is a Rockchip vendor binding; mainline has none.
- `boot/rockchip/overlays/chronos.dtbo` (`stock/chronos-overlay.dts`)
  names LEDs `chronos:green:{system,ntp,disk}`; `boot.scr` does not
  load it.

## Stock time services

| Item | Value | Source |
|---|---|---|
| gpsd | `-n -G -s 115200 -f 8N1` on `/dev/gps0` | `rootfs/etc/default/gpsd` |
| GPS baud | 9600 default, switched to 115200 with `ubxtool -S 115200` | `rootfs/usr/sbin/cc_gpsconfig` |
| ntpd PPS | driver 22 (`127.127.22.0`), `flag3 1`, `time1 0.000010` | `rootfs/etc/ntp.conf` |

## Mainline support

Checked against Linux, U-Boot and TF-A `master` on 2026-11-01.

| Item | Mainline | Source |
|---|---|---|
| Board DTS | `rk3308-rock-pi-s.dts`, compatible `radxa,rockpis` | Linux `arch/arm64/boot/dts/rockchip/` |
| U-Boot | `rock-pi-s-rk3308_defconfig`, console uart0 at 1500000 | U-Boot `configs/` |
| DRAM init (TPL) | rkbin blob only (`rk3308_ddr_589MHz_uartX_mY_v2.07.bin`) | U-Boot `doc/board/rockchip/rockchip.rst` |
| BL31 | rkbin blob only (`rk3308_bl31_v2.26.elf`); TF-A has no rk3308 | TF-A `docs/plat/rockchip.rst` |
| Ethernet | `rockchip,rk3308-gmac` in `dwmac-rk.c`, RMII only; board DTS has RTL8201F PHY, reset GPIO0_A7 active low | Linux |
| GPS UART | `uart1` in `rk3308.dtsi`, `pinctrl-0 = <&uart1_xfer &uart1_cts &uart1_rts>`; not enabled in board DTS | Linux |
| I2C1 | enabled in board DTS | Linux |
| RTC | `rtc-hym8563.c`, compatible `haoyu,hym8563`; no node in board DTS | Linux |
| PPS | generic `pps-gpio`; no node in board DTS | Linux |
| LEDs, button | generic `gpio-leds`, `gpio-keys`; board DTS has only module LEDs GPIO0_A6, GPIO0_A5 | Linux |
| GPS reset, PPS out enable, PoE sense, barrel | no `gpio-export` binding; use `gpio-hog` or `gpio-line-names` | Linux |

Stock bootloader: Rockchip miniloader with DDR blob "DDR Version V1.26"
(`idbloader.img`), vendor BL31 (`trust.img`).

## Stock serial consoles

| UART | Use | Speed | Source |
|---|---|---|---|
| `ttyS0` (uart0) | kernel and U-Boot console | 1500000 8N1 | `boot.scr` bootargs |
| `ttyS2` (`/dev/serial/user`) | "...Booting" message, then `agetty` login to the admin CLI | 115200 | `rootfs/usr/lib/systemd/system/cc-bootmsg*.service`, `rootfs/usr/sbin/cc_console_service` |

- The micro-USB CH340N carries `ttyS2`: it shows "...Booting" and the
  admin login at 115200 (`stock/boot.log`).

## rkbin RK3308 binaries

Source: `rockchip-linux/rkbin` `master`, `RKBOOT/RK3308MINIALL.ini` and
`bin/rk33/`, 2026-11-01.

- One RK3308 set; no RK3308B-specific files.
- DDR init v2.11 at 393, 451 or 589 MHz, debug UART `uart2_m1` or
  `uart4_m0` only (this board uses uart0 for console, uart2_m0 for the
  admin CLI).
- BL31 `rk3308_bl31_v2.28.elf`.
