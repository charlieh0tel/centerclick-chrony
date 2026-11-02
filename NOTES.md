# NOTES: NTP250 findings

## Stock image

| File | What | Source |
|---|---|---|
| `stock/centerclick-ntp250.dd` | ext4 partition image, 4 GiB, last mounted on `/data`; not a whole-card image | `file`, `dumpe2fs -h` |
| `stock/SHA256SUMS` | checksum of the above | `sha256sum` |
| `stock/extracted/` | copy of `/backup2` from the image (gitignored) | `debugfs -c -R 'rdump /backup2 ...'` |

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

## Pin map (partial; GPIO numbers pending DTB decompile)

| Function | Value | Source |
|---|---|---|
| Linux console | `ttyS0`, 1500000 8N1 | `boot.scr`, `rootfs/etc/udev/rules.d/99-cc.rules` |
| GPS UART | `ttyS1` (`/dev/gps0`) | `99-cc.rules` |
| User UART | `ttyS2` | `99-cc.rules` |
| PPS | `pps-gpio` node, `pps-pins` pinctrl | DTB strings |
| RTC | `haoyu,hym8563` at I2C 0x51, bus `i2c@ff050000` (I2C1), IRQ pin `hym8563-int` | DTB strings |
| LEDs | `led-system`, `led-ntp`, `led-sd`/`led-disk` (`chronos:green:*`), `blue-led` | DTB, `chronos.dtbo` strings |
| GPS reset | `gps-reset`, `gps-nreset` (gpio-export) | DTB strings |
| PPS out enable | `hdr-ppsout-en` (gpio-export) | DTB strings |

## Stock time services

| Item | Value | Source |
|---|---|---|
| gpsd | `-n -G -s 115200 -f 8N1` on `/dev/gps0` | `rootfs/etc/default/gpsd` |
| GPS baud | 9600 default, switched to 115200 with `ubxtool -S 115200` | `rootfs/usr/sbin/cc_gpsconfig` |
| ntpd PPS | driver 22 (`127.127.22.0`), `flag3 1`, `time1 0.000010` | `rootfs/etc/ntp.conf` |
