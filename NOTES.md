# NOTES: NTP250 findings

## Stock image

| File | What | Source |
|---|---|---|
| `stock/centerclick-ntp250.dd` | ext4 partition image, 4 GiB, last mounted on `/data`; not a whole-card image | `file`, `dumpe2fs -h` |
| `stock/SHA256SUMS` | checksum of the above | `sha256sum` |
| `stock/extracted/` | copy of `/backup2` from the image (gitignored) | `debugfs -c -R 'rdump /backup2 ...'` |
| `stock/extracted/rootfs/` | unpacked `rootfs.squashfs` (gitignored) | `unsquashfs` |
| `stock/ntp250.dts` | decompiled `boot/rk3308-rock-pi-s-chronos.dtb` | `dtc -I dtb -O dts` |
| `stock/chronos-overlay.dts` | decompiled `boot/rockchip/overlays/chronos.dtbo` | `dtc -I dtb -O dts` |

- `/backup` and `/backup2` hold identical `idbloader.img`, `uboot.img`,
  `trust.img`; `/backup2` also holds `rootfs.squashfs`.
- Filesystem state: "needs journal recovery"; last write time
  2026-11-01 18:06, two minutes before the image file was written.

## Platform

| Item | Value | Source |
|---|---|---|
| Compute module | Radxa ROCK Pi S (`radxa,rockpis`) | `boot/rk3308-rock-pi-s-chronos.dtb` |
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
