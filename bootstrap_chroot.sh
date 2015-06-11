#!/bin/bash -x
set -o errexit
set -o nounset

# This script runs inside the chroot environment
BOOT_DEV=$1

# apt wont ask you questions now, you are welcome
export DEBIAN_FRONTEND=noninteractive

# gen locale to prevent wierd unicode crap
locale-gen en_US.UTF-8

# Set hostname
echo server01 > /etc/hostname

# stop any services from starting (we remove this later)
cat << EOF > /usr/sbin/policy-rc.d
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d

apt-get update
apt-get upgrade -y
# adjust any packages you want to install here, software-properties-common and
# the kernel/kernel headers are required (but they dont have to be vivid)
# vivid is 3.19, I recommend using it
apt-get install -y linux-firmware linux-headers-generic-lts-vivid htop tmux \
                   linux-image-generic-lts-vivid intel-microcode bridge-utils \
                   vim ifenslave sudo vlan openssh-server cryptsetup \
                   software-properties-common

# zfs me!
add-apt-repository -y ppa:zfs-native/stable
apt-get update
apt-get install -y ubuntu-zfs zfs-initramfs grub2

patch /usr/share/initramfs-tools/hooks/cryptroot < /cryptroot.patch

# disable quiet to see additional startup information, enable boot from zfs
sed -i 's|quiet splash|boot=zfs|' /etc/default/grub

# regen the initramfs to include zfs, install grub, update the grub config
update-initramfs -u -k all
grub-install $BOOT_DEV
update-grub

# Add a user and set the password to 'a'
useradd -m -s /bin/bash sam
echo -e 'a\na' | passwd sam

# Add a user to sudoers (dont require user to enter password to 'sudo')
echo "sam ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/sam

# Enable pageup and pagedown to scroll through matching history
sed -i 's/.*history-search-backward.*/"\\e[5~": history-search-backward/' /etc/inputrc
sed -i 's/.*history-search-forward.*/"\\e[6~": history-search-forward/' /etc/inputrc

# cleanup
rm /usr/sbin/policy-rc.d
