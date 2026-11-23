#!/usr/bin/env bash
# Write the image to a card, then copy a site overlay (a tree rooted at /,
# e.g. site/chronos) onto its root partition and install root's SSH key.
# Run as root.
#
# Usage: sudo image/flash.sh [-i IMAGE] [-k KEYFILE] DEVICE [SITE]
#   IMAGE: ntp250.img or ntp250.img.xz (a release's), checked against
#   ntp250.img.sha256 beside it; default out/ntp250.img.
#   KEYFILE: SSH public keys for root (/root/.ssh/authorized_keys); none:
#   console login only.
#   DEVICE is the whole card (e.g. /dev/sdc): removable, nothing mounted.
#   SITE is a directory under site/, or a path; none: the image as built.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT
# The root partition's GPT number (image/build.sh).
readonly ROOT_PARTN=1

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage="usage: image/flash.sh [-i IMAGE] [-k KEYFILE] DEVICE [SITE]"
image=$ROOT/out/ntp250.img
keys=
while getopts i:k: opt; do
    case $opt in
        i) image=$OPTARG ;;
        k) keys=$OPTARG ;;
        *) die "$usage" ;;
    esac
done
shift $((OPTIND - 1))
(( $# == 1 || $# == 2 )) || die "$usage"
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
if [[ -n $keys ]]; then
    ssh-keygen -l -f "$keys" >&2 || die "$keys: not SSH public keys"
fi
# read_image: the uncompressed image on stdout.
read_image() {
    case $image in
        *.xz) xz -dc "$image" ;;
        *) cat "$image" ;;
    esac
}
sums=${image%.xz}.sha256
[[ -r $image && -r $sums ]] || die "need $image and $sums"
log "check $image"
[[ $(read_image | sha256sum | cut -d' ' -f1) == "$(cut -d' ' -f1 "$sums")" ]] \
    || die "$image: checksum mismatch ($sums)"

lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,PARTLABEL "$dev" >&2
log "write $image to $dev"
read_image | dd of="$dev" bs=4M iflag=fullblock conv=fsync status=progress
blockdev --rereadpt "$dev"
udevadm settle

[[ -n $site || -n $keys ]] || { log "done: $dev (no site overlay, no SSH key)"; exit 0; }
part=$(lsblk -lnpo NAME,PARTN "$dev" | awk -v n="$ROOT_PARTN" '$2 == n { print $1 }')
[[ -b $part ]] || die "no partition $ROOT_PARTN on $dev"
mnt=$(mktemp -d)
mount "$part" "$mnt"
trap 'umount "$mnt" && rmdir "$mnt"' EXIT
if [[ -n $site ]]; then
    log "site overlay $site"
    # Files land owned by root with the overlay's modes.
    cp -rT --no-preserve=ownership "$site" "$mnt"
    find "$site" -mindepth 1 -printf '%P\n' >&2
fi
if [[ -n $keys ]]; then
    log "SSH key $keys"
    install -d -m 700 "$mnt/root/.ssh"
    install -m 600 "$keys" "$mnt/root/.ssh/authorized_keys"
fi
log "done: $dev"
