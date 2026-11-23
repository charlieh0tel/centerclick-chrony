#!/bin/sh
# Runs inside the arm64 root filesystem (mmdebstrap customize hook).
# Usage: rootfs-setup.sh HOSTNAME ROOT_PARTUUID DATA_PARTUUID KERNEL_CONSOLE
# KERNEL_CONSOLE is the console and earlycon kernel arguments.
set -eu

hostname=$1
root_partuuid=$2
data_partuuid=$3
kernel_console=$4

echo "$hostname" >/etc/hostname
# C.UTF-8 is built into glibc; no locales package.
echo LANG=C.UTF-8 >/etc/locale.conf
cat >/etc/hosts <<EOF
127.0.0.1	localhost
127.0.1.1	$hostname
::1		localhost ip6-localhost ip6-loopback
EOF

# /var/lib and /var/log live on the data partition (image/build.sh
# DATA_TREES); no nofail, so a missing data partition stops the boot.
# systemd-repart grows the partition first; x-systemd.growfs then grows
# the file system.
mkdir -p /data
cat >/etc/fstab <<EOF
PARTUUID=$root_partuuid / ext4 defaults,noatime 0 1
PARTUUID=$data_partuuid /data ext4 defaults,noatime,x-systemd.growfs,x-systemd.after=systemd-repart.service 0 2
/data/var/lib /var/lib none bind,x-systemd.requires-mounts-for=/data 0 0
/data/var/log /var/log none bind,x-systemd.requires-mounts-for=/data 0 0
EOF

# Kernel arguments; ntp250-extlinux (ntp250-config) writes the boot menus
# from them when the kernel is installed.  panic=10: a panic reboots, so
# U-Boot counts a failed boot of a kernel on trial.
mkdir -p /etc/kernel
echo "root=PARTUUID=$root_partuuid rootwait rw $kernel_console panic=10" >/etc/kernel/cmdline

# Host keys are generated on first boot (ntp250-ssh-hostkeys.service),
# so no two cards share them.
rm -f /etc/ssh/ssh_host_*

# Site firewall rules (/usr/lib/ntp250/nftables.conf includes them).
mkdir -p /etc/nftables.d

# The ntp250-* units: enabled by ntp250-config's postinst.
systemctl enable systemd-networkd systemd-resolved gpsd.service \
    nftables.service serial-getty@ttyS0.service serial-getty@ttyS2.service

# No display: boot to multi-user, no login on the VT.
systemctl set-default multi-user.target
systemctl disable getty@tty1.service
