#!/bin/sh
# Runs inside the arm64 root filesystem (mmdebstrap customize hook).
# Usage: rootfs-setup.sh HOSTNAME ROOT_PARTUUID KERNEL_CONSOLE DTB
# KERNEL_CONSOLE is the console and earlycon kernel arguments.
set -eu

hostname=$1
root_partuuid=$2
kernel_console=$3
dtb=$4

echo "$hostname" >/etc/hostname
cat >/etc/hosts <<EOF
127.0.0.1	localhost
127.0.1.1	$hostname
::1		localhost ip6-localhost ip6-loopback
EOF

echo "PARTUUID=$root_partuuid / ext4 defaults,noatime 0 1" >/etc/fstab

mkdir -p /boot/extlinux
cat >/boot/extlinux/extlinux.conf <<EOF
default ntp250
timeout 10

label ntp250
	kernel /boot/Image
	fdt /boot/dtbs/$dtb
	append root=PARTUUID=$root_partuuid rootwait rw $kernel_console
EOF

chown -R root:root /root/.ssh
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

# Host keys are generated on first boot (ntp250-ssh-hostkeys.service),
# so no two cards share them.
rm -f /etc/ssh/ssh_host_*

depmod -a "$(ls /usr/lib/modules)"

systemctl enable systemd-networkd systemd-resolved \
    ntp250-ssh-hostkeys.service ntp250-gpio-init.service \
    ntp250-gps-config.service gpsd.service \
    serial-getty@ttyS0.service serial-getty@ttyS2.service
