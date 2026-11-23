# Pinned build inputs, sourced by image/build.sh.  Each download is
# checked against its SHA-256 before use.

LINUX_VERSION=6.18.60
LINUX_URL=https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VERSION}.tar.xz
LINUX_SHA256=3c2f44ef6acc021a7ad444d9a2e6ec1ef488ff09368793d0004a6080f69d621e
# Kernel release LINUX_VERSION + LINUX_LOCALVERSION names the package
# (linux-image-6.18.60-ntp250.1), so each build installs beside the last.
# Bump the counter when the kernel inputs change, reset it to 1 with a new
# LINUX_VERSION; image/build.sh kernel checks LINUX_INPUTS_SHA256 against
# the inputs and prints the new value.
LINUX_LOCALVERSION=-ntp250.2
LINUX_INPUTS_SHA256=108315c036ae3a33df77ccc6fcb9b8a346124bbc3210299f56580d7473310d28

UBOOT_VERSION=2026.07
# The GitHub mirror's tag archive: GitHub runners cannot reach
# ftp.denx.de.  Same tree as denx's u-boot-2026.07.tar.bz2.
UBOOT_URL=https://github.com/u-boot/u-boot/archive/refs/tags/v${UBOOT_VERSION}.tar.gz
UBOOT_SHA256=21463d6d4498768d01fa192f6027468c04480d0daa99cd546f9a75a4d9ec353c
UBOOT_DEFCONFIG=rock-pi-s-rk3308_defconfig

# Rockchip binaries (no open-source equivalent for RK3308).
RKBIN_BASE=https://raw.githubusercontent.com/rockchip-linux/rkbin
# DDR init: v1.x for the RK3308(A); v2.x supports only the RK3308B/S
# ("RK3308A is not supported by this DDR bin version!").  v1.26 with
# debug UART uart0_m0, as on the stock card; it leaves uart0 on the
# 24 MHz oscillator, which U-Boot assumes.
RKBIN_DDR_COMMIT=491dafd997ed996270d2d91b3a9ce2c345b3353c
RKBIN_DDR=rk3308_ddr_589MHz_uart0_m0_v1.26.bin
RKBIN_DDR_SHA256=d9f339b8bb6604cc3e2c9f3b7764495954c07bcba55f31d545189a776d579721
RKBIN_BL31_COMMIT=3e288fe814e059dd06833495f845cab04ac20a5c
RKBIN_BL31=rk3308_bl31_v2.28.elf
RKBIN_BL31_SHA256=fb4daee17fb3732f7ec04d92e480d0ed00b951e3e1e28ff5efe01c8794d9841c

DEBIAN_SUITE=trixie
DEBIAN_MIRROR=http://deb.debian.org/debian
DEBIAN_SECURITY_MIRROR=http://security.debian.org/debian-security
