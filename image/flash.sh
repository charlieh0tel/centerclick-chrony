#!/usr/bin/env bash
# Write out/ntp250.img to a card, then copy a site overlay (a tree rooted
# at /, e.g. site/chronos) onto its root partition.  Run as root.
#
# Usage: sudo image/flash.sh DEVICE [SITE]
#   DEVICE is the whole card (e.g. /dev/sdc): removable, nothing mounted.
#   SITE is a directory under site/, or a path; none: the image as built.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT
readonly IMAGE=$ROOT/out/ntp250.img
# The root partition's GPT number (image/build.sh).
readonly ROOT_PARTN=1

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

(( $# == 1 || $# == 2 )) || die "usage: image/flash.sh DEVICE [SITE]"
dev=$1
site=${2:-}
(( EUID == 0 )) || die "run as root"
[[ -b $dev && $(lsblk -dno TYPE "$dev") == disk ]] || die "$dev is not a whole disk"
[[ $(lsblk -dno RM "$dev" | tr -d ' ') == 1 ]] || die "$dev is not removable"
[[ -z $(lsblk -no MOUNTPOINTS "$dev" | tr -d ' \n') ]] || die "$dev has mounted partitions"
if [[ -n $site ]]; then
    [[ -d $site ]] || site=$ROOT/site/$site
    [[ -d $site ]] || die "no site overlay $2"
fi
(cd "${IMAGE%/*}" && sha256sum --quiet -c "${IMAGE##*/}.sha256") || die "$IMAGE checksum"

lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,PARTLABEL "$dev" >&2
log "write $IMAGE to $dev"
dd if="$IMAGE" of="$dev" bs=4M conv=fsync status=progress
blockdev --rereadpt "$dev"
udevadm settle

[[ -n $site ]] || { log "done: $dev (no site overlay)"; exit 0; }
part=$(lsblk -lnpo NAME,PARTN "$dev" | awk -v n="$ROOT_PARTN" '$2 == n { print $1 }')
[[ -b $part ]] || die "no partition $ROOT_PARTN on $dev"
mnt=$(mktemp -d)
mount "$part" "$mnt"
trap 'umount "$mnt" && rmdir "$mnt"' EXIT
log "site overlay $site"
# Files land owned by root with the overlay's modes.
cp -rT --no-preserve=ownership "$site" "$mnt"
find "$site" -mindepth 1 -printf '%P\n' >&2
log "done: $dev"
