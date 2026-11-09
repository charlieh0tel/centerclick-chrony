# GPIOs

GPIO lines in our image (`dts/rk3308-ntp250.dts` on
`rk3308-rock-pi-s.dts`).  Check with `gpioinfo` and
`/sys/kernel/debug/gpio`.  Stock pin sources and module pin numbers
(header 1 is pins 1-26, header 2 is 27-52): `NOTES.md` "Pin map".

## Carrier (named, `gpio-line-names`)

| Line | Pin | Module pin | Name | Direction, owner | Idle state | Role |
|---|---|---|---|---|---|---|
| gpiochip0 15 | GPIO0_B7 | 11 | `barrel-mech` | input, free | 0 = no DC plug, 1 = DC plug in (read 1 with the plug in) | `ntp250-panel` power status |
| gpiochip0 17 | GPIO0_C1 | 15 | `rtc-int` | input, IRQ of `pcf8563`; pull-up | 1 (alarm active low) | RTC interrupt |
| gpiochip2 4 | GPIO2_A4 | 7 | `hdr-ppsout-en` | output, free | 0 (`ntp250-gpio-init`) | header PPS output enable; off |
| gpiochip2 5 | GPIO2_A5 | 12 | `led-sd` | output, LED `ntp250:green:sd` | trigger `mmc1` | SD activity |
| gpiochip2 7 | GPIO2_A7 | 22 | `led-system` | output, LED `ntp250:green:system` | on; DTS default trigger `timer` (blink) until `ntp250-panel` runs | `ntp250-panel`: on if SoC temperature, power and network good, else blink |
| gpiochip2 9 | GPIO2_B1 | 18 | `button-front` | input, free; pull-down set by `ntp250-panel` (`gpioget -b pull-down`) | 0 = released, 1 = pressed | `ntp250-panel`, sampled every 0.5 s: hold > 3 s power off, > 8 s reboot |
| gpiochip2 10 | GPIO2_B2 | 16 | `poe-sense` | input, free | 0 = no PoE, 1 = PoE power good (stock `cc_monitor`; read 0 without PoE, 1 not yet seen) | `ntp250-panel` power status |
| gpiochip2 13 | GPIO2_B5 | 28 | `led-ntp` | output, LED `ntp250:green:ntp` | on when synced to PPS; DTS default off | `ntp250-panel`: on (PPS, std dev <= 0.1 ms), blink (higher, or other source stratum < 8), off (not synced) |
| gpiochip2 14 | GPIO2_B6 | 30 | `gps-pps` | input, IRQ of `pps-gpio` (`/dev/pps0`); pull none | 0; 100 ms high each second once locked | GPS timepulse, assert edge to chrony |
| gpiochip2 15 | GPIO2_B7 | 32 | `gps-nreset` | output, free | 1 (`ntp250-gpio-init`) | GPS reset, active low: 0 for 0.5 s alone resets the receiver (u-blox boot banner, 2026-11-09); `ntp250-gps-reset` drives 0 for 0.5 s |
| gpiochip2 16 | GPIO2_C0 | 34 | `gps-reset` | output, free | 0 (`ntp250-gpio-init`) | no effect seen: 1 for 0.5 s alone, no banner, RMC uninterrupted (2026-11-09); stock drives it 1 during the pulse; `ntp250-gps-reset` too |

"Free": no driver or process holds the line; outputs keep the level
`gpioset -t 0` left.  `gpioget` on a free output makes it an input.

## Module (ROCK Pi S, unnamed)

| Line | Pin | Owner | Idle state |
|---|---|---|---|
| gpiochip0 2 | GPIO0_A2 | SDIO power sequence reset (Wi-Fi, disabled) | asserted |
| gpiochip0 5 | GPIO0_A5 | LED `rockpis:blue:user` | off |
| gpiochip0 6 | GPIO0_A6 | LED `rockpis:green:power` | on |
| gpiochip0 7 | GPIO0_A7 | Ethernet PHY reset, active low | released |
| gpiochip0 21 | GPIO0_C5 | regulator `vcc5v0-otg` | on |

Other named lines (`header1-pin*`, `header2-pin*`) are unused and free.
UART, I2C and Ethernet pins run their peripheral functions.
