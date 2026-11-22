# package

`ntp250-config`: the NTP250 configuration as a Debian package (architecture
`all`).  The image build installs it; boards upgrade it through apt.

## Build

```
package/build-ntp250-config.sh OUTDIR [VERSION]
```

Writes `OUTDIR/ntp250-config_VERSION_all.deb` and prints its path.  Needs
`dpkg-deb` and git.  Reproducible: every mtime is the last commit's time
(`SOURCE_DATE_EPOCH` overrides).

| VERSION source | Version |
|---|---|
| tag `v1.2.0` on HEAD | `1.2.0` |
| N commits after `v1.2.0` | `1.2.0+N.gHASH` |
| no `v*` tag | `0.0.0+N.gHASH` (N commits in all) |
| argument | as given |

## Contents

| Path | Role |
|---|---|
| `ntp250-config/root/` | file tree (layout: `image/README.md` "Config layout") |
| `ntp250-config/control` | control file; `@VERSION@` substituted |
| `ntp250-config/preinst` | on upgrade: checksums of installed files to `/run/ntp250-config.sums` |
| `ntp250-config/postinst` | enables the `ntp250-*` units (`deb-systemd-helper`); on upgrade restarts only services whose files changed |
| `ntp250-config/prerm`, `postrm` | stop the panel on remove; mask on remove, purge state on purge |

Every file under `/etc` is a conffile (`/etc/chrony/conf.d/ntp250.conf`,
`/etc/apt/apt.conf.d/52ntp250-unattended-upgrades`).

## Upgrade actions

| Files changed | Action |
|---|---|
| `ntp250.conf` (chrony), `chrony.env`, chrony drop-in | `try-restart chrony` |
| `gpsd.env`, gpsd drop-in | `try-restart gpsd` |
| `chronymond.env`, `chronymon-web.env`, their drop-ins | `try-restart` that service |
| `nftables.conf`, nftables drop-in | `try-reload-or-restart nftables` |
| resolved drop-in, `*.dnssd` | `try-restart systemd-resolved` |
| `10-ethernet.network` | `networkctl reload` |
| `ntp250-panel`, `ntp250-tuning` (script or unit) | `try-restart` that unit |
| GPS setup, GPIO init, journald, systemd, repart, serial consoles | next boot |

A failed restart is logged (`ntp250-config: failed: ...`) and does not fail
the upgrade.

## Release

`.github/workflows/release.yml`: builds on every push to `main` and pull
request (artifact `ntp250-config`).  A `v*` tag creates a GitHub release with
the `.deb`, then starts the apt-repo rebuild (`APT_REPO_TOKEN`); a tag with a
hyphen is a pre-release, not published to apt.
