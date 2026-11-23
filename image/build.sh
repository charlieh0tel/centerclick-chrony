#!/usr/bin/env bash
# Build out/ntp250.img for the NTP250: mainline U-Boot and Linux, Debian
# arm64 root filesystem.  Runs unprivileged (mmdebstrap unshare mode,
# mkfs.ext4 -d).
#
# Usage: image/build.sh [STAGE...]
#   STAGE is fetch, uboot, kernel, config, rootfs or image; default: all,
#   in order.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT
# shellcheck source=sources.sh
source "$ROOT/image/sources.sh"

readonly BUILD=$ROOT/build
readonly DL=$BUILD/dl
readonly OUT=$ROOT/out
readonly IMAGE=$OUT/ntp250.img
# Cross compiler prefix; none on an arm64 host.
if [[ $(uname -m) == aarch64 ]]; then
    readonly CROSS=
else
    readonly CROSS=aarch64-linux-gnu-
fi
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
# Fixed so /etc/fw_env.config can name the U-Boot environment's partition.
readonly UBOOT_PARTUUID=e659fba8-1c8f-4466-ba63-24033337a2cb
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
    # updates; U-Boot environment (boot count)
    unattended-upgrades libubootenv-tool
    # monitoring, from image/apt/charlieh0tel.sources
    chronymon
    # hardware
    gpiod i2c-tools
)

# Host commands each stage needs.
declare -rA TOOLS=(
    [fetch]="curl sha256sum"
    [uboot]="tar patch make bison flex swig ${CROSS}gcc"
    [kernel]="sha256sum tar patch make bison flex ${CROSS}gcc dpkg-deb"
    [config]="dpkg-deb"
    [rootfs]="mmdebstrap qemu-aarch64"
    [image]="tar mkfs.ext4 sgdisk dd truncate sha256sum"
)

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# check_tools STAGE...: fail unless every tool the STAGEs need is present.
check_tools() {
    local stage tool
    for stage in "$@"; do
        for tool in ${TOOLS[$stage]}; do
            command -v "$tool" >/dev/null || die "missing host tool: $tool"
        done
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
    check_uboot_env "$src"
    cp "$src/u-boot-rockchip.bin" "$BUILD/"
}

# check_uboot_env SRC: the environment copies of the U-Boot built in SRC
# lie after U-Boot, inside partition 3, and match /etc/fw_env.config
# (offsets from the partition start).
check_uboot_env() {
    local src=$1 conf=$ROOT/package/ntp250-config/root/etc/fw_env.config
    local size offset redund part=$(( UBOOT_SECTOR * 512 ))
    size=$(sed -n 's/^CONFIG_ENV_SIZE=//p' "$src/.config")
    offset=$(sed -n 's/^CONFIG_ENV_OFFSET=//p' "$src/.config")
    redund=$(sed -n 's/^CONFIG_ENV_OFFSET_REDUND=//p' "$src/.config")
    (( UBOOT_SECTOR * 512 + $(stat -c %s "$src/u-boot-rockchip.bin") <= offset )) \
        || die "U-Boot overlaps its environment"
    (( offset + size <= redund && redund + size <= ROOT_START_SECTOR * 512 )) \
        || die "U-Boot environment outside partition 3"
    diff <(grep -v '^#' "$conf" | awk '{ print $1, $2, $3 }') - <<EOF \
        || die "$conf does not match the U-Boot environment"
/dev/disk/by-partuuid/$UBOOT_PARTUUID $(printf '0x%x 0x%x' $(( offset - part )) $(( size )))
/dev/disk/by-partuuid/$UBOOT_PARTUUID $(printf '0x%x 0x%x' $(( redund - part )) $(( size )))
EOF
}

readonly KREL=$LINUX_VERSION$LINUX_LOCALVERSION
readonly KERNEL_DEB=$BUILD/deb/linux-image-${KREL}_${KREL}_arm64.deb

# kernel_inputs_sha: SHA-256 over everything that goes into the kernel
# package; a change needs a new LINUX_LOCALVERSION (image/sources.sh).
kernel_inputs_sha() {
    {
        echo "$LINUX_VERSION $LINUX_SHA256 $DTB"
        cat "$ROOT/image/kernel.config" "$ROOT/dts/rk3308-ntp250.dts" \
            "$ROOT"/image/patches/linux/*.patch "$ROOT"/package/linux-image/*
        # The two functions' source, the same under any bash.
        sed -n '/^kernel_deb() {$/,/^}$/p; /^stage_kernel() {$/,/^}$/p' "$ROOT/image/build.sh"
    } | sha256sum | cut -d' ' -f1
}

# kernel_deb SRC MAKE...: package the kernel built in SRC as $KERNEL_DEB;
# MAKE runs make in SRC.
kernel_deb() {
    local src=$1 stage=$BUILD/kernel-deb script
    local kmake=("${@:2}")
    local doc=$stage/usr/share/doc/linux-image-$KREL
    rm -rf "$stage"
    mkdir -p "$stage/boot" "$stage/usr/lib/linux-image-$KREL/${DTB%/*}" "$doc" "$stage/DEBIAN"
    cp "$src/arch/arm64/boot/Image" "$stage/boot/vmlinuz-$KREL"
    cp "$src/.config" "$stage/boot/config-$KREL"
    cp "$src/arch/arm64/boot/dts/$DTB" "$stage/usr/lib/linux-image-$KREL/$DTB"
    # Debian has merged /usr: modules go under /usr/lib/modules.
    "${kmake[@]}" modules_install INSTALL_MOD_PATH="$stage/usr" INSTALL_MOD_STRIP=1
    # build and source point into this host's tree; no headers on target.
    rm -f "$stage/usr/lib/modules/$KREL/build" "$stage/usr/lib/modules/$KREL/source"
    printf '%s\n' \
        "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/" \
        "Upstream-Name: linux" \
        "Source: $LINUX_URL" \
        "" \
        "Files: *" \
        "Copyright: Linus Torvalds and others" \
        "License: GPL-2" \
        " On Debian systems, the full text of the GNU General Public License" \
        " version 2 can be found in /usr/share/common-licenses/GPL-2." \
        >"$doc/copyright"
    printf '%s\n' \
        "linux-image-$KREL ($KREL) unstable; urgency=medium" "" \
        "  * Linux $LINUX_VERSION for the NTP250." "" \
        " -- Christopher Hoover <ch@murgatroid.com>  $(date -u -R -r "$src/arch/arm64/boot/Image")" \
        | gzip -9n >"$doc/changelog.Debian.gz"
    find "$stage" -type d -exec chmod 755 {} +
    find "$stage" -type f -exec chmod 644 {} +
    printf '%s\n' \
        "Package: linux-image-$KREL" \
        "Version: $KREL" \
        "Architecture: arm64" \
        "Maintainer: Christopher Hoover <ch@murgatroid.com>" \
        "Section: kernel" \
        "Priority: optional" \
        "Provides: linux-image" \
        "Homepage: https://github.com/charlieh0tel/centerclick-chrony" \
        "Description: Linux $KREL for the CenterClick NTP250" \
        " Mainline Linux $LINUX_VERSION with image/kernel.config," \
        " image/patches/linux and the rk3308-ntp250 device tree." \
        >"$stage/DEBIAN/control"
    for script in preinst postinst prerm postrm; do
        sed "s/@KREL@/$KREL/g" "$ROOT/package/linux-image/$script" >"$stage/DEBIAN/$script"
        chmod 755 "$stage/DEBIAN/$script"
    done
    (cd "$stage" && find boot usr -type f | sort | xargs md5sum) >"$stage/DEBIAN/md5sums"
    mkdir -p "${KERNEL_DEB%/*}"
    dpkg-deb --root-owner-group -Zxz --build "$stage" "$KERNEL_DEB" >/dev/null
}

stage_kernel() {
    local src=$BUILD/linux sha
    local kmake=(make -C "$src" ARCH=arm64 CROSS_COMPILE="$CROSS" -j"$JOBS"
        LOCALVERSION="$LINUX_LOCALVERSION" KBUILD_BUILD_USER=ntp250
        KBUILD_BUILD_HOST=centerclick-chrony)
    sha=$(kernel_inputs_sha)
    [[ $sha == "$LINUX_INPUTS_SHA256" ]] \
        || die "kernel inputs changed: in image/sources.sh, bump LINUX_LOCALVERSION ($LINUX_LOCALVERSION) and set LINUX_INPUTS_SHA256=$sha"
    if [[ -f $KERNEL_DEB ]]; then
        log "linux $KREL: built already"
    else
        log "linux $KREL"
        unpack "$DL/${LINUX_URL##*/}" "$src"
        apply_patches linux "$src"
        cp "$ROOT/dts/rk3308-ntp250.dts" "$src/arch/arm64/boot/dts/rockchip/"
        # shellcheck disable=SC2016 # Make syntax, written literally.
        echo 'dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3308-ntp250.dtb' \
            >>"$src/arch/arm64/boot/dts/rockchip/Makefile"
        "${kmake[@]}" defconfig
        merge_config "$src" "$ROOT/image/kernel.config" "${kmake[@]}"
        [[ $("${kmake[@]}" -s kernelrelease) == "$KREL" ]] || die "kernel release is not $KREL"
        "${kmake[@]}" Image modules dtbs
        kernel_deb "$src" "${kmake[@]}"
    fi
    ln -sf "${KERNEL_DEB#"$BUILD"/}" "$BUILD/linux-image.deb"
}

stage_config() {
    log "ntp250-config"
    local deb
    deb=$("$ROOT/package/build-ntp250-config.sh" "$BUILD/deb")
    ln -sf "${deb#"$BUILD"/}" "$BUILD/ntp250-config.deb"
}

stage_rootfs() {
    [[ -r $DEBIAN_KEYRING ]] || die "missing $DEBIAN_KEYRING (debian-archive-keyring)"
    [[ -r $AUTHORIZED_KEYS ]] \
        || die "no SSH public key at $AUTHORIZED_KEYS (set NTP250_AUTHORIZED_KEYS)"
    [[ -r $BUILD/ntp250-config.deb ]] || die "no $BUILD/ntp250-config.deb (stage config)"
    [[ -r $BUILD/linux-image.deb ]] || die "no $BUILD/linux-image.deb (stage kernel)"
    log "rootfs debian $DEBIAN_SUITE"
    local include
    include=$(IFS=,; echo "${PACKAGES[*]}")
    # shellcheck disable=SC2016 # mmdebstrap expands $1 in hooks.
    mmdebstrap --mode=unshare --variant=minbase --architectures=arm64 \
        --keyring="$DEBIAN_KEYRING" --include="$include" \
        --setup-hook='mkdir -p "$1/etc/apt/sources.list.d"' \
        --setup-hook="upload '$ROOT/image/apt/charlieh0tel.sources' /etc/apt/sources.list.d/charlieh0tel.sources" \
        --customize-hook="upload '$AUTHORIZED_KEYS' /root/.ssh/authorized_keys" \
        --customize-hook="upload '$ROOT/image/rootfs-setup.sh' /tmp/rootfs-setup.sh" \
        --customize-hook="chroot \"\$1\" sh /tmp/rootfs-setup.sh '$HOSTNAME' '$ROOT_PARTUUID' '$DATA_PARTUUID' '$KERNEL_CONSOLE'" \
        --customize-hook='rm "$1/tmp/rootfs-setup.sh"' \
        --customize-hook="upload '$(realpath "$BUILD/linux-image.deb")' /tmp/linux-image.deb" \
        --customize-hook="upload '$(realpath "$BUILD/ntp250-config.deb")' /tmp/ntp250-config.deb" \
        --customize-hook='chroot "$1" env DEBIAN_FRONTEND=noninteractive apt-get install -y -q /tmp/linux-image.deb /tmp/ntp250-config.deb' \
        --customize-hook='rm "$1/tmp/linux-image.deb" "$1/tmp/ntp250-config.deb"' \
        "$DEBIAN_SUITE" "$BUILD/rootfs.tar" \
        "deb $DEBIAN_MIRROR $DEBIAN_SUITE main" \
        "deb $DEBIAN_MIRROR $DEBIAN_SUITE-updates main" \
        "deb $DEBIAN_SECURITY_MIRROR $DEBIAN_SUITE-security main"
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
        --partition-guid=3:"$UBOOT_PARTUUID" \
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
    (( ${#stages[@]} )) || stages=(fetch uboot kernel config rootfs image)
    for stage in "${stages[@]}"; do
        [[ -v TOOLS[$stage] ]] || die "unknown stage: $stage"
    done
    check_tools "${stages[@]}"
    for stage in "${stages[@]}"; do
        "stage_$stage"
    done
}

main "$@"
