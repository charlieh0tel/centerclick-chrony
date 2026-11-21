#!/usr/bin/env bash
# Build out/ntp250.img for the NTP250: mainline U-Boot and Linux, Debian
# arm64 root filesystem.  Runs unprivileged (mmdebstrap unshare mode,
# mkfs.ext4 -d).
#
# Usage: image/build.sh [STAGE...]
#   STAGE is fetch, uboot, kernel, rootfs or image; default: all, in order.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT
# shellcheck source=sources.sh
source "$ROOT/image/sources.sh"

readonly BUILD=$ROOT/build
readonly DL=$BUILD/dl
readonly OUT=$ROOT/out
readonly IMAGE=$OUT/ntp250.img
readonly CROSS=aarch64-linux-gnu-
JOBS=$(nproc)
readonly JOBS
readonly AUTHORIZED_KEYS=${NTP250_AUTHORIZED_KEYS:-$HOME/.ssh/id_ed25519.pub}

# Card layout in 512-byte sectors.  The RK3308 boot ROM loads U-Boot
# (idbloader + FIT) from sector 64, inside partition 3 (uboot), so tools
# that treat unpartitioned space as free (systemd-repart discards it) leave
# it alone; the root partition starts at 16 MiB, as on the stock card.  The data partition follows root; systemd-repart
# grows it to the end of the card on first boot.
readonly UBOOT_SECTOR=64
readonly ROOT_START_SECTOR=32768
readonly ROOT_SIZE_MIB=2048
readonly DATA_SIZE_MIB=512
# Room for the backup GPT at the end of the image.
readonly GPT_TAIL_MIB=1
# Fixed so extlinux.conf and fstab can name the root partition.
readonly ROOT_PARTUUID=33f4c7e9-0436-473f-9913-48d960e86116
readonly ROOT_FS_UUID=54bad6a8-164c-4ba7-9e9d-a63bf9872bd4
readonly DATA_PARTUUID=21a10599-5390-427c-8790-0a84a983ba3c
readonly DATA_FS_UUID=b83d83f4-2dd3-473c-8405-dbd96c7191d1
# Trees that live on the data partition, bind-mounted from /data.
readonly DATA_TREES=(var/lib var/log)

# Debian archive signing keys (Ubuntu package debian-archive-keyring).
readonly DEBIAN_KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg

readonly HOSTNAME=ntp250
readonly DTB=rockchip/rk3308-ntp250.dtb
# Kernel console: uart2 (carrier micro-USB), from the first message.  Only
# one ttyS port can be a kernel console; uart0 (module header 1) gets a
# login only.
readonly KERNEL_CONSOLE="console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xff0c0000"

# Debian packages on top of the minbase variant.
readonly PACKAGES=(
    # base system
    systemd-sysv systemd-resolved systemd-repart udev dbus kmod util-linux-extra
    ca-certificates less nano procps psmisc lsof
    # network
    iproute2 iputils-ping openssh-server ethtool lldpd nftables
    bind9-dnsutils traceroute netcat-openbsd tcpdump
    # time and GPS
    chrony gpsd gpsd-tools python3-gps python3-serial pps-tools
    # monitoring, from image/apt/charlieh0tel.sources
    chronymon
    # hardware
    gpiod i2c-tools
)

# Host commands the stages need.
readonly TOOLS=(
    curl sha256sum tar patch make bison flex swig "${CROSS}gcc"
    mmdebstrap qemu-aarch64 mkfs.ext4 sgdisk dd truncate
)

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

check_tools() {
    local tool
    for tool in "${TOOLS[@]}"; do
        command -v "$tool" >/dev/null || die "missing host tool: $tool"
    done
}

# fetch URL SHA256: download URL into $DL once; verify it every time.
fetch() {
    local url=$1 sha=$2
    local file=$DL/${url##*/}
    if [[ ! -f $file ]]; then
        log "fetch $url"
        curl -fsSL --retry 3 -o "$file.part" "$url"
        mv "$file.part" "$file"
    fi
    echo "$sha  $file" | sha256sum --check --quiet \
        || die "checksum mismatch: $file"
}

# unpack TARBALL DIR: replace DIR with a fresh tree from TARBALL.
unpack() {
    rm -rf "$2"
    mkdir -p "$2"
    tar -xf "$1" -C "$2" --strip-components=1
}

# apply_patches NAME DIR: apply image/patches/NAME/*.patch to DIR, in order.
apply_patches() {
    local patch
    for patch in "$ROOT/image/patches/$1"/*.patch; do
        [[ -e $patch ]] || continue
        log "patch $1: ${patch##*/}"
        patch -d "$2" -p1 --quiet --forward <"$patch"
    done
}

# merge_config SRC FRAGMENT MAKE...: merge FRAGMENT over SRC/.config,
# resolve dependencies with MAKE, and fail if any FRAGMENT line did not
# survive.
merge_config() {
    local src=$1 fragment=$2 line
    shift 2
    (cd "$src" && scripts/kconfig/merge_config.sh -m .config "$fragment")
    "$@" olddefconfig
    while read -r line; do
        [[ $line == CONFIG_* ]] || continue
        grep -qxF "$line" "$src/.config" || die "$src/.config lacks $line"
    done <"$fragment"
}

stage_fetch() {
    mkdir -p "$DL"
    fetch "$LINUX_URL" "$LINUX_SHA256"
    fetch "$UBOOT_URL" "$UBOOT_SHA256"
    fetch "$RKBIN_BASE/$RKBIN_DDR_COMMIT/bin/rk33/$RKBIN_DDR" "$RKBIN_DDR_SHA256"
    fetch "$RKBIN_BASE/$RKBIN_BL31_COMMIT/bin/rk33/$RKBIN_BL31" "$RKBIN_BL31_SHA256"
}

stage_uboot() {
    local src=$BUILD/u-boot
    local umake=(make -C "$src" CROSS_COMPILE="$CROSS" -j"$JOBS")
    log "u-boot $UBOOT_VERSION"
    unpack "$DL/${UBOOT_URL##*/}" "$src"
    apply_patches u-boot "$src"
    "${umake[@]}" "$UBOOT_DEFCONFIG"
    merge_config "$src" "$ROOT/image/u-boot.config" "${umake[@]}"
    "${umake[@]}" BL31="$DL/$RKBIN_BL31" ROCKCHIP_TPL="$DL/$RKBIN_DDR"
    cp "$src/u-boot-rockchip.bin" "$BUILD/"
}

stage_kernel() {
    local src=$BUILD/linux staging=$BUILD/kernel-staging
    local kmake=(make -C "$src" ARCH=arm64 CROSS_COMPILE="$CROSS" -j"$JOBS")
    log "linux $LINUX_VERSION"
    unpack "$DL/${LINUX_URL##*/}" "$src"
    apply_patches linux "$src"
    cp "$ROOT/dts/rk3308-ntp250.dts" "$src/arch/arm64/boot/dts/rockchip/"
    # shellcheck disable=SC2016 # Make syntax, written literally.
    echo 'dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3308-ntp250.dtb' \
        >>"$src/arch/arm64/boot/dts/rockchip/Makefile"
    "${kmake[@]}" defconfig
    merge_config "$src" "$ROOT/image/kernel.config" "${kmake[@]}"
    "${kmake[@]}" Image modules dtbs
    rm -rf "$staging"
    mkdir -p "$staging/boot/dtbs/rockchip"
    cp "$src/arch/arm64/boot/Image" "$staging/boot/"
    cp "$src/arch/arm64/boot/dts/$DTB" "$staging/boot/dtbs/rockchip/"
    # Debian has merged /usr: modules go under /usr/lib/modules.
    "${kmake[@]}" modules_install INSTALL_MOD_PATH="$staging/usr" \
        INSTALL_MOD_STRIP=1
    # build and source point into this host's tree; no headers on target.
    rm -f "$staging"/usr/lib/modules/*/build "$staging"/usr/lib/modules/*/source
    tar -C "$staging" --owner=0 --group=0 --mode=go-w -cf "$BUILD/kernel.tar" boot usr
}

stage_rootfs() {
    [[ -r $DEBIAN_KEYRING ]] || die "missing $DEBIAN_KEYRING (debian-archive-keyring)"
    [[ -r $AUTHORIZED_KEYS ]] \
        || die "no SSH public key at $AUTHORIZED_KEYS (set NTP250_AUTHORIZED_KEYS)"
    log "rootfs debian $DEBIAN_SUITE"
    local include
    include=$(IFS=,; echo "${PACKAGES[*]}")
    tar -C "$ROOT/rootfs/overlay" --owner=0 --group=0 --mode=go-w \
        -cf "$BUILD/overlay.tar" etc usr
    # shellcheck disable=SC2016 # mmdebstrap expands $1 in hooks.
    mmdebstrap --mode=unshare --variant=minbase --architectures=arm64 \
        --keyring="$DEBIAN_KEYRING" --include="$include" \
        --setup-hook='mkdir -p "$1/etc/apt/sources.list.d"' \
        --setup-hook="upload '$ROOT/image/apt/charlieh0tel.sources' /etc/apt/sources.list.d/charlieh0tel.sources" \
        --customize-hook="tar-in '$BUILD/overlay.tar' /" \
        --customize-hook="tar-in '$BUILD/kernel.tar' /" \
        --customize-hook="upload '$AUTHORIZED_KEYS' /root/.ssh/authorized_keys" \
        --customize-hook="upload '$ROOT/image/rootfs-setup.sh' /tmp/rootfs-setup.sh" \
        --customize-hook="chroot \"\$1\" sh /tmp/rootfs-setup.sh '$HOSTNAME' '$ROOT_PARTUUID' '$DATA_PARTUUID' '$KERNEL_CONSOLE' '$DTB'" \
        --customize-hook='rm "$1/tmp/rootfs-setup.sh"' \
        "$DEBIAN_SUITE" "$BUILD/rootfs.tar" "$DEBIAN_MIRROR"
}

# mkfs_tar LABEL UUID TARBALL SIZE_MIB OUT: ext4 image OUT of SIZE_MIB
# filled from TARBALL.
mkfs_tar() {
    rm -f "$5"
    mkfs.ext4 -q -F -L "$1" -U "$2" -E root_owner=0:0 -d "$3" "$5" "${4}M"
}

# split_rootfs ROOT_TAR DATA_TAR: split rootfs.tar into the root
# partition's tree (DATA_TREES left as empty mount points) and the data
# partition's (DATA_TREES only, at the same paths).  DATA_TREES are under
# var/.
split_rootfs() {
    local list=$BUILD/rootfs.list trees
    trees=$(IFS='|'; echo "${DATA_TREES[*]}")
    # Members inside a data tree; directories both partitions keep.
    local data_re="^\./($trees)/." keep_re="^\./(var/|($trees)/)?\$"
    tar -tf "$BUILD/rootfs.tar" --quoting-style=literal >"$list"
    cp "$BUILD/rootfs.tar" "$1"
    grep -E "$data_re" "$list" | tar --delete -f "$1" --no-recursion --verbatim-files-from -T -
    cp "$BUILD/rootfs.tar" "$2"
    grep -vE "$data_re|$keep_re" "$list" | tar --delete -f "$2" --no-recursion --verbatim-files-from -T -
}

stage_image() {
    local rootimg=$BUILD/root.ext4 dataimg=$BUILD/data.ext4 part=$IMAGE.part
    local roottar=$BUILD/root.tar datatar=$BUILD/data.tar
    local uboot=$BUILD/u-boot-rockchip.bin
    local uboot_max=$(( (ROOT_START_SECTOR - UBOOT_SECTOR) * 512 ))
    local data_start=$(( ROOT_START_SECTOR + ROOT_SIZE_MIB * 2048 ))
    local total_mib=$(( ROOT_START_SECTOR * 512 / 1048576 + ROOT_SIZE_MIB + DATA_SIZE_MIB + GPT_TAIL_MIB ))
    (( $(stat -c %s "$uboot") <= uboot_max )) || die "$uboot overlaps the root partition"
    log "image $IMAGE"
    split_rootfs "$roottar" "$datatar"
    mkfs_tar ntp250-root "$ROOT_FS_UUID" "$roottar" "$ROOT_SIZE_MIB" "$rootimg"
    mkfs_tar ntp250-data "$DATA_FS_UUID" "$datatar" "$DATA_SIZE_MIB" "$dataimg"
    mkdir -p "$OUT"
    rm -f "$part"
    truncate -s "${total_mib}M" "$part"
    sgdisk --clear --set-alignment=1 \
        --new=1:"$ROOT_START_SECTOR":+"${ROOT_SIZE_MIB}M" \
        --typecode=1:8305 --change-name=1:root \
        --partition-guid=1:"$ROOT_PARTUUID" --attributes=1:set:2 \
        --new=2:"$data_start":+"${DATA_SIZE_MIB}M" \
        --typecode=2:8300 --change-name=2:data \
        --partition-guid=2:"$DATA_PARTUUID" \
        --new=3:"$UBOOT_SECTOR":$(( ROOT_START_SECTOR - 1 )) \
        --typecode=3:8301 --change-name=3:uboot \
        "$part" >/dev/null
    dd if="$rootimg" of="$part" bs=512 seek="$ROOT_START_SECTOR" \
        conv=notrunc,sparse status=none
    dd if="$dataimg" of="$part" bs=512 seek="$data_start" \
        conv=notrunc,sparse status=none
    dd if="$uboot" of="$part" bs=512 seek="$UBOOT_SECTOR" \
        conv=notrunc status=none
    mv "$part" "$IMAGE"
    (cd "$OUT" && sha256sum "${IMAGE##*/}" >"${IMAGE##*/}.sha256")
    log "done: $IMAGE"
}

main() {
    local stages=("$@") stage
    (( ${#stages[@]} )) || stages=(fetch uboot kernel rootfs image)
    check_tools
    for stage in "${stages[@]}"; do
        case $stage in
            fetch | uboot | kernel | rootfs | image) "stage_$stage" ;;
            *) die "unknown stage: $stage" ;;
        esac
    done
}

main "$@"
