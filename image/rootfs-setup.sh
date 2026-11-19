#!/bin/sh
# Runs inside the arm64 root filesystem (mmdebstrap customize hook).
# Usage: rootfs-setup.sh HOSTNAME ROOT_PARTUUID DATA_PARTUUID KERNEL_CONSOLE DTB
# KERNEL_CONSOLE is the console and earlycon kernel arguments.
set -eu

hostname=$1
root_partuuid=$2
data_partuuid=$3
kernel_console=$4
dtb=$5

echo "$hostname" >/etc/hostname
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

# Site firewall rules (/etc/nftables.conf includes them).
mkdir -p /etc/nftables.d

depmod -a "$(ls /usr/lib/modules)"

systemctl enable systemd-networkd systemd-resolved \
    ntp250-ssh-hostkeys.service ntp250-gpio-init.service \
    ntp250-gps-config.service gpsd.service ntp250-tuning.service \
    ntp250-panel.service nftables.service \
    serial-getty@ttyS0.service serial-getty@ttyS2.service
