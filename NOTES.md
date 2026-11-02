# NOTES

Findings log. Each entry cites its source.

## Unit
- NTP250, HW rev 10, SN 203, stock software 2.26.4 [7a7171e]. Source: web UI System Info.
- Stock card: Gigastone HE 8 GB (7431 MiB). Source: web UI.

## Compute module (photos in `photos/`)
- Radxa ROCK Pi S V1.3, silkscreen date 20190910.
- SoC: Rockchip RK3308 (marking HAAKT35005 2052).
- RAM: TMTC TN4G16D3CSEP-EK (4 Gb DDR3 = 512 MiB).
- Realtek Wi-Fi/BT QFN with IPEX connector, unused.
- Plugs into the base board; removable.

## Base board "CHRONOS V10" (photos in `photos/`)
- U3: u-blox MAX-M8Q-0-10.
- U2: NXP PCF8563 RTC (stock DTB uses compatible `haoyu,hym8563`), Y1 32.768 kHz, C15 supercap backup.
- U4: CH340N, micro-USB "Console", 115200 8N1.
- Header "UART0" (TX/RX/GND) near R25/R26. Presumed wired to ROCK Pi S
  header pins 8/10 (UART0, kernel console); unverified.
- J6: 26-pin socket for the ROCK Pi S. J5, J7: 4-pin sockets picking up other module pins.
- J4: DC / VIN / G / 5V / 3V3 / G / Pu to the PSU board.
- SW1: front button. D10: LEDs.
- PSU board: DC barrel (7-14 V marking) + PoE daughter board.

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
| Compute module | Radxa ROCK Pi S V1.3 (`radxa,rockpis`) | DTB, silkscreen (`photos/`) |
| Board model string | "Radxa ROCK Pi S On Chronos Carrier" | same DTB |
| SoC | RK3308 (not RK3308B) | DTB, package marking (`photos/`) |
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

Sources: `stock/ntp250.dts` (decompiled from
`boot/rk3308-rock-pi-s-chronos.dtb`, the DTB `boot.scr` loads; no
overlays are applied); module header pins from Radxa
`docs.radxa.com/en/rockpi/rockpis/hardware/pin-gpio` (header 1 is pins
1-26, header 2 is pins 27-52).  GPIO phandles: `0x19` = gpio0,
`0x85` = gpio2.  Pin index n maps to `GPIOb_` + `ABCD`[n / 8] + n % 8.

| Function | RK3308 pin / bus | Module pin | Flags | DTS line |
|---|---|---|---|---|
| GPS UART (`ttyS1`, uart1 `ff0b0000`) | GPIO1_D0 RX, GPIO1_D1 TX | 23, 24 | pull up | 555, 1970 |
| PPS (`pps-gpio`) | GPIO2_B6 | 30 | active high, pull none | 2834, 2621 |
| Kernel console (`ttyS0`, uart0 `ff0a0000`) | GPIO2_A0 RX, GPIO2_A1 TX | 10, 8 | pull up | 539, 1947 |
| Admin CLI / CH340N (`ttyS2`, uart2m0 `ff0c0000`) | GPIO1_C6 RX, GPIO1_C7 TX | 21, 19 | pull up | 571, 1988 |
| RTC | I2C1 (`ff050000`) 0x51, SDA GPIO0_B3, SCL GPIO0_B4 | 3, 5 | | 427, 441 |
| RTC IRQ | GPIO0_C1 | 15 | level low | 2613 |
| EEPROM `st,24c64` | I2C1 0x54 in the DTB; not on the bus on this carrier (`i2cdetect -y -r 1`: 0x42, 0x51 only) | 3, 5 | | 455 |
| GPS I2C (u-blox DDC) | I2C1 0x42 (`i2cdetect`); no DTB node; I2C1 at 400 kHz in stock | 3, 5 | | 438 |
| LED `green:power` (module) | GPIO0_A6 | on module | trigger heartbeat | 2798 |
| LED `blue:sd` (module) | GPIO0_A5 | on module | trigger mmc0 | 2805 |
| LED `green:system` | GPIO2_A7 | 22 | trigger timer | 2812 |
| LED `green:sd` | GPIO2_A5 | 12 | trigger mmc0 | 2819 |
| LED `green:ntp` | GPIO2_B5 | 28 | trigger none | 2826 |
| Button SW1 `fp-button-1` | GPIO2_B1 | 18 | gpio-export input, flag 0 (active high); measured: high while pressed, SoC pull-down when idle | 2760 |
| `hdr-ppsout-en` | GPIO2_A4 | 7 | gpio-export output, low | 2765 |
| `gps-nreset` | GPIO2_B7 | 32 | gpio-export output, high; `cc_resetgps` drives 0 for 0.5 s with `gps-reset` 1 | 2776 |
| `gps-reset` | GPIO2_C0 | 34 | gpio-export output, low | 2782 |
| `poe-sense` | GPIO2_B2 | 16 | gpio-export input; 1 = PoE power good (`cc_monitor`) | 2788 |
| `barrel-mech` | GPIO0_B7 | 11 | gpio-export input; 0 = DC plug out (`cc_monitor`) | 2771 |
| Ethernet (`ff4e0000`) | RMII, MAC clock output, PHY reset GPIO0_A7 active low | on module | | 1294 |

- RX/TX roles: Radxa pin table (UART0, UART1, UART2_M0).
- `gpio-export` is a Rockchip vendor binding; mainline has none.
- `boot/rockchip/overlays/chronos.dtbo` (`stock/chronos-overlay.dts`)
  names LEDs `chronos:green:{system,ntp,disk}`; `boot.scr` does not
  load it.

## GPS module

Source: u-blox boot banner on `ttyS1` after `ntp250-gps-reset`.

- UBX-M8030, ROM CORE 3.01, firmware SPG 3.01, protocol 18.00.
- NMEA at 9600 baud by default; GNSS OTP GPS and GLONASS.
- Antenna supervisor: `ANTSUPERV=AC SD PDoS SR`.

## GPS configuration

Applied at every boot by `ntp250-gps-config.service`
(`rootfs/overlay/usr/local/sbin/ntp250-gps-config`), after
`ntp250-gpio-init` and before gpsd.  The MAX-M8Q has no flash; `SAVE`
reaches battery-backed RAM only (supercap, about 3 h).  Each setting must
return `UBX-ACK-ACK`, or the service fails.

| Setting | Value | ubxtool | Reason |
|---|---|---|---|
| Start state | factory defaults | `-p RESET` at 115200 and at 9600 | No leftovers (gpsd without `-b` had disabled RMC/GGA and saved it) |
| UART1 speed | 115200 | `-s 9600 -S 115200` | Lower NMEA latency; stock used 115200 |
| GNSS | GPS (with QZSS), Galileo, SBAS on; GLONASS, BeiDou off | `-e GPS -e GALILEO -d GLONASS -d BEIDOU` | Owner's choice: no GLONASS |
| Dynamic model | 2, stationary | `-p MODEL,2` | Fixed antenna |
| NMEA | GGA, RMC, ZDA at 1 Hz; GLL, GSA, GSV, VTG off | `-p CFG-MSG,0xf0,ID,RATE` | Only what gpsd needs for time; less latency |
| Timepulse (CFG-TP5) | factory: 1 Hz, 100 ms when locked, none until locked, rising edge, aligned to the second, antCableDelay 50 ns | not changed | Matches chrony `refclock PPS` (assert edge) |
| Save | BBR | `-p SAVE` | Warm start after short power loss |

Readback on 2026-11-02 (`ubxtool -p CFG-GNSS`, `CFG-NAV5`, `CFG-PRT,1`,
`CFG-TP5`): gnssId 0, 1, 2, 5 enabled; 3, 6 disabled; `dynModel 2`; UART1
115200, in/out UBX+NMEA; TP5 flags 0x77.

gpsd: `-n -b -s 115200 /dev/ttyS1` (`/etc/default/gpsd`); `-b` keeps it
from reconfiguring the receiver.

Measured: NMEA offset +161 ms at 9600 with all default sentences, +33 to
+48 ms at 115200 with GGA/RMC/ZDA (1 h median +43 ms, drifting +40 to
+48 ms; chrony `offset 0.043`, leaving about +6 ms); stratum 1 on PPS about 55 s after boot (warm
start); first fix after power-up without valid time: about 13 min.

## Timing tweaks

Applied at boot by `ntp250-tuning.service`
(`rootfs/overlay/usr/local/sbin/ntp250-tuning`), as the stock firmware
did (`stock/extracted/rootfs/usr/sbin/cc_monitor:2202-2208`).

| Tweak | Mainline default | Set | Reason |
|---|---|---|---|
| PSCI cpuidle state1 `cpu-sleep` | enabled, wake latency 370 us | disabled on CPUs 0-3 (WFI, 1 us, stays) | Interrupt latency for PPS and NTP packets |
| `end0` IRQ affinity | CPUs 0-3 (all on CPU0) | CPU3 | Away from the PPS and GPS UART interrupts |
| `end0` RX coalescing | `rx-usecs 819` | `rx-usecs 82`, the stmmac minimum (16 RIWT units of 5.12 us; reads back 81); stock 164 | NTP request receive timestamps |

Not ported: stock conntrack NOTRACK for UDP 123 (no firewall rules yet);
ntpd's kernel PPS discipline (`flag3 1`) has no chrony equivalent.

Preliminary effect (chrony `sourcestats`, PPS): std dev 585 ns (11
samples) before, 418 ns (8 samples) 10 min after; package installs ran
during the window.  The 24 h comparison belongs to Phase 5.

Effect seen by apu-0 (GPS stratum 1 with hardware timestamps,
chronymon NTP samples of chronos, medians), 2026-11-02:

| Window (UTC) | Setting | n | Delay | Offset (sd) |
|---|---|---|---|---|
| 08:56-09:00 | defaults (cpu-sleep on, rx-usecs 819) | 15 | 444 us | +63.5 us (89.6) |
| 09:00-10:05 | tweaks, rx-usecs 164 | 73 | 190 us | +38.0 us (9.3) |
| 10:06-10:26 | tweaks, rx-usecs 81 | 19 | 187 us | +34.6 us (9.2) |

- 164 to 81 us is within noise; below 164 us coalescing no longer limits.
- stmmac accepts rx-usecs 82..1306 only; RIWT off would need a kernel
  patch (`riwt_off` is set only by the socfpga and mediatek glue in
  6.18; no DT property).  Not done.

## Temperature

| Item | Value | Source |
|---|---|---|
| Sensor | RK3308 TSADC, ch0 `logic-thermal` (`thermal_zone0`), ch1 `cpu-thermal` (`thermal_zone1`), millidegrees C | stock DTB `tsadc@ff1f0000`, `thermal-zones` |
| Stock use | `cc_monitor` reads `thermal_zone0` for display; no board thermistor on Chronos; NTPsec had no compensation | `stock/extracted/rootfs/usr/sbin/cc_monitor` |
| Mainline | no TSADC node in `rk3308.dtsi`, no `rockchip,rk3308-tsadc` match; added by `image/patches/linux/` (RK3328 data, 2 channels, as the Rockchip vendor driver) and `dts/rk3308-ntp250.dts` | Linux 6.18 |
| Shutdown | hardware TSHUT via CRU at 120 C; critical trips 115 C | stock DTB |
| Noise | 0.45 C step, 0.55 C sd per reading (90 readings at 1 s, idle) | measured 2026-11-02 |
| Averaging | `ntp250-temperature.service`: mean of both zones over 32 readings at 1 s, to `/run/ntp250/temperature` every 32 s | `rootfs/overlay/usr/local/sbin/ntp250-temperature` |
| chrony | `tempcomp /run/ntp250/temperature 32 40000 0 0 0`; coefficients zero until fitted from `tempcomp.log` against `tracking.log` frequency | `rootfs/overlay/etc/chrony/conf.d/ntp250.conf` |

## MAC address

`ce:e9:6b:89:b0:4e`, set by U-Boot from the RK3308 CPU ID
(`arch/arm/mach-rockchip/board.c` `misc_init_r()`); locally administered,
stable per SoC.  No EEPROM on this carrier, so no other source.

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
| TSADC | `rockchip_thermal.c` has no RK3308 entry; no node in `rk3308.dtsi` | Linux |
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
- `ttyS0` at 1500000 confirmed on the bare module (USB-C power, carrier
  removed): FTDI TTL-232R-3V3 on module header 1 pins 6 (GND), 8 (TX),
  10 (RX).  Kernel log plus a `serial-getty` login on `ttyS0`
  (`stock/boot-ttyS0-module.log`, starts at kernel time 0.548 s).
- Stock U-Boot console is uart2 (`ttyS2`, uart2m0, module header 1
  pins 19 TX, 21 RX), not uart0: its embedded DTB enables only
  `serial@ff0c0000` and sets `chosen/stdout-path = "/serial@ff0c0000"`;
  env `baudrate=1500000`.  Source: DTB at offset 0x85430 in
  `uboot.img`, `strings uboot.img`.
- Kernel output on `ttyS0` begins at 0.548 s; nothing before it appears
  on uart0.
- Bare module, module header 1 pins 19/21/20 at 1500000, either wire
  order: no loader or U-Boot output seen.
- Carrier header "UART0" (TX/RX/GND): no output at 1500000 or 115200,
  either wire order.  Cause unknown (R25/R26 fitted?).

## Consoles in our image

Source: `image/u-boot.config`, `image/patches/u-boot/`, `image/build.sh`;
tested on the carrier and the bare module.

| Stage | uart0 (module pins 8/10) | uart2 (carrier micro-USB) |
|---|---|---|
| DDR init v1.26 | yes | no |
| U-Boot SPL | yes | no |
| U-Boot proper | yes | from `preboot` (autoboot prompt) on |
| Linux kernel | no | yes (`console=ttyS2`, `earlycon` at 0xff0c0000) |
| Login | root autologin | root autologin |

- Linux has one 8250 console: with `console=ttyS0 console=ttyS2`, only
  `ttyS0` registers (`/proc/consoles`).
- U-Boot on uart2 needs `CONFIG_SERIAL_PROBE_ALL` (otherwise uart2 is not
  probed and the console mux skips it) and uart2 on the 24 MHz
  oscillator (DDR init leaves it on DPLL/16; patch 0002).
- Carrier micro-USB path works at 1500000 baud.
- Carrier header "UART0": uart0 RX reaches the SoC (noise counted on
  `ttyS0` while wiring); uart0 TX does not reach the header.

## rkbin RK3308 binaries

Source: `rockchip-linux/rkbin`, `bin/rk33/`, `RKBOOT/RK3308MINIALL.ini`,
`tools/ddrbin_tool_user_guide.txt`, 2026-11-01.

- DDR init v2.x (v2.05 and later) does not run on the RK3308(A): v2.11
  contains the string "RK3308A is not supported by this DDR bin
  version!"; with it the board drops to USB maskrom (`2207:330e`).
- Last v1.x: v1.31 (commit `6bd18410a21d`, `uart2_m1`/`uart4_m0` only);
  removed in `38956aae52a2` ("update ddr bin to v2.05 to support
  RK3308B-S").  Boots this board, but leaves uart0 on DPLL/16
  (81.25 MHz); U-Boot assumes 24 MHz, so U-Boot output is garbled.
- In use: `rk3308_ddr_589MHz_uart0_m0_v1.26.bin` (commit `491dafd997ed`),
  the stock version.  Prints on uart0 and leaves uart0 at 24 MHz; full
  boot log readable (DDR3, 512 MB, 589 MHz).
- BL31 `rk3308_bl31_v2.28.elf` (`master`) runs on the RK3308(A).

## I/O voltage domains

Source: GRF `SOC_CON0` (0xff000300) read on the running board; stock
DTB `io-domains` node.

| Domain | Stock DTB | Upstream `rk3308-rock-pi-s.dts` |
|---|---|---|
| vccio0, vccio1, vccio5 | 3.3 V | 3.3 V |
| vccio2 | 1.8 V | 3.3 V |
| vccio3 | 1.8 V (`vccio_flash`) | 3.3 V |
| vccio4 | 1.8 V | 1.8 V |

- With vccio2 in 3.3 V mode, UART0 TX (module header 1 pin 8) is silent;
  setting GRF `SOC_CON0` bit 2 (1.8 V) brings it back.
- `dts/rk3308-ntp250.dts` and the U-Boot patch
  `image/patches/u-boot/0001-rock-pi-s-vccio2-vccio3-1v8.patch` set
  vccio2 and vccio3 to 1.8 V.

## Open questions

- Mainline `rk3308-rock-pi-s.dts` vccio2/vccio3 at 3.3 V: wrong for
  V1.3, or for all revisions?
- Why the carrier "UART0" header gets no uart0 TX (R25/R26? Q2/Q3?).
