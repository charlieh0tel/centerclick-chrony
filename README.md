# centerclick-chrony

Mainline Linux, Debian and chrony for the CenterClick NTP250 GPS time
server, in place of the stock firmware.  The unit's microSD card is
replaced; the stock card stays untouched.

- Hardware: Radxa ROCK Pi S V1.3 (RK3308) on the CHRONOS V10 carrier,
  u-blox MAX-M8Q GPS with PPS.
- Software: mainline U-Boot and Linux, Debian trixie arm64, chrony as a
  stratum 1 server (NMEA + PPS).
- Upgrades: the `ntp250-config` and `linux-image-KREL` packages, from
  the [charlieh0tel apt repo](https://charlieh0tel.github.io/apt-repo),
  through unattended-upgrades; a new kernel boots on trial (U-Boot boot
  count, falls back after 3 failed boots).

| Path | Contents |
|---|---|
| [`image/`](image/README.md) | image build (`image/build.sh`), flashing, image contents |
| [`package/`](package/README.md) | `ntp250-config` package and release CI |
| `dts/` | device tree |
| `site/` | per-unit overlays |
| [`NOTES.md`](NOTES.md) | hardware findings, measurements |
| [`PLAN.md`](PLAN.md) | plan, open work |
| [`third_party/`](third_party/README.md) | vendor material, licenses |

Restore: put the stock card back.

License: GPL-2.0-only ([`LICENSE`](LICENSE)).
