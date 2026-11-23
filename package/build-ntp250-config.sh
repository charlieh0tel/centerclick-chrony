#!/bin/bash
# Build ntp250-config_VERSION_all.deb: package/ntp250-config/root as
# the file tree, package/ntp250-config/ for control and maintainer scripts.
# Usage: package/build-ntp250-config.sh OUTDIR [VERSION]
# VERSION defaults to the latest v* tag (v1.2.0 -> 1.2.0; commits after
# it -> 1.2.0+N.gHASH; no tag -> 0.0.0+N.gHASH).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly root
readonly meta=$root/package/ntp250-config
readonly tree=$meta/root
readonly name=ntp250-config
# The kernel this package depends on (image/sources.sh).
# shellcheck source=../image/sources.sh
source "$root/image/sources.sh"
readonly krel=$LINUX_VERSION$LINUX_LOCALVERSION

# git_version: Debian version from git describe.
git_version() {
    local d
    if d=$(git -C "$root" describe --tags --long --match 'v[0-9]*' 2>/dev/null); then
        local tag=${d%-*-g*} rest=${d#"${d%-*-g*}"-}
        local n=${rest%%-*} hash=${rest#*-}
        if [[ $n == 0 ]]; then echo "${tag#v}"; else echo "${tag#v}+$n.$hash"; fi
    else
        echo "0.0.0+$(git -C "$root" rev-list --count HEAD).g$(git -C "$root" rev-parse --short HEAD)"
    fi
}

[[ $# -ge 1 && $# -le 2 ]] || { echo "usage: $0 OUTDIR [VERSION]" >&2; exit 2; }
out=$1
version=${2:-$(git_version)}
mkdir -p "$out"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

cp -r "$tree/." "$stage/"
doc=$stage/usr/share/doc/$name
mkdir -p "$doc"
cat >"$doc/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $name
Source: https://github.com/charlieh0tel/centerclick-chrony

Files: *
Copyright: 2026 Christopher Hoover
License: GPL-2
 This program is free software; you can redistribute it and/or modify it
 under the terms of version 2 of the GNU General Public License as
 published by the Free Software Foundation.
 .
 On Debian systems, the full text of the GNU General Public License
 version 2 can be found in /usr/share/common-licenses/GPL-2.
COPYRIGHT

epoch=${SOURCE_DATE_EPOCH:-$(git -C "$root" log -1 --format=%ct)}
cat >"$doc/changelog" <<CHANGELOG
$name ($version) unstable; urgency=medium

  * Built from centerclick-chrony $(git -C "$root" rev-parse --short HEAD).

 -- Christopher Hoover <ch@murgatroid.com>  $(date -u -R -d "@$epoch")
CHANGELOG
gzip -9n "$doc/changelog"

# Modes from the tree's intent, not the checkout's umask: scripts 755,
# other files 644, directories 755.
find "$stage" -type d -exec chmod 755 {} +
find "$stage" -type f -exec chmod 644 {} +
chmod 755 "$stage"/usr/sbin/* "$stage"/usr/share/kernel/*/*

mkdir "$stage/DEBIAN"
sed -e "s/@VERSION@/$version/" -e "s/@KREL@/$krel/" "$meta/control" >"$stage/DEBIAN/control"
install -m 755 "$meta/preinst" "$meta/postinst" "$meta/prerm" "$meta/postrm" "$stage/DEBIAN/"
# Every file under /etc is a conffile; md5sums covers the rest.
(cd "$stage" && find etc -type f | sort | sed 's|^|/|') >"$stage/DEBIAN/conffiles"
(cd "$stage" && find . -path ./DEBIAN -prune -o -path ./etc -prune -o -type f -printf '%P\n' \
    | sort | xargs md5sum) >"$stage/DEBIAN/md5sums"

# Reproducible: every mtime at the last commit.
find "$stage" -exec touch -h -d "@$epoch" {} +

deb=$out/${name}_${version}_all.deb
SOURCE_DATE_EPOCH=$epoch dpkg-deb --root-owner-group -Zxz --build "$stage" "$deb" >/dev/null
echo "$deb"
