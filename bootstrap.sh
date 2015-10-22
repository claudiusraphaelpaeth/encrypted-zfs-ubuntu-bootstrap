#!/bin/bash -x
# We will exit on any non-zero exit code and break on variables that are unset
set -o errexit

# uncomment for crypto support
crypt=yes

# Assumption is you are running from an Ubuntu host with the zfs modules 
# modules and cryptroot installed already. This can be a livecd as well.
#
# Commands ending it " # luks_commands" can be ignored if not using luks
#
# USAGE: ./bootstrap.sh
# its expected you run it exactly as the usage. Things will break otherwise

### WARNING WARNING WARNING ###
# This is really destructive, so whatever disk you have here will get
# repartitioned and formated. You've been warned
BOOT_DEV=/dev/sda
ZFS_DEV1=/dev/sda2

echo "WARNING: I am about to wipe '${BOOT_DEV}' completely, now is the time to exit"
sleep 5

# Formatting is happening
parted ${BOOT_DEV} -s -- mklabel msdos mkpart pri 1 1G mkpart pri 1G 40G set 1 boot on
wipefs -a ${BOOT_DEV}1
mkfs.ext4 ${BOOT_DEV}1

if [[ "${!crypt[@]}" ]]; then
    CRYPT_DEV1="${ZFS_DEV1}"
    ZFS_DEV1=/dev/mapper/zfs01
fi

if [[ "${!crypt[@]}" ]]; then
    # setuping up cryptdevices
    cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha512 ${CRYPT_DEV1} # luks_commands
    cryptsetup luksOpen ${CRYPT_DEV1} zfs01 # luks_commands
fi

# creating the zpool: -o is zpool properties, -O is zfs properties
# DO NOT ADJUST ashift=12 UNLESS YOU KNOW WHY YOU ARE DOING IT
# /dev/mapper/zfs01 is a LUKS volume, you can put /dev/sd? here
# This creates a mirror set
zpool create -f -o ashift=12 -o cachefile=/tmp/zpool.cache -O compression=lz4 -O atime=off -O dedup=off -O sync=disabled -m none -R /mnt rpool ${ZFS_DEV1}
zfs create -o mountpoint=none rpool/ROOT
zfs create -o mountpoint=/ rpool/ROOT/ubuntu
zfs create -o mountpoint=/home rpool/HOME
zfs create -o mountpoint=/root rpool/HOME/root
zpool set bootfs=rpool/ROOT/ubuntu rpool

debootstrap vivid /mnt/ http://192.168.31.11:3142/ubuntu

mount -t proc none /mnt/proc
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount ${BOOT_DEV}1 /mnt/boot


if [[ "${!crypt[@]}" ]]; then
    ln -sf ${ZFS_DEV1} /dev/zfs01 # luks_commands
fi

# Copy bootstrap script to be run inside the chroot
cp bootstrap_chroot.sh /mnt/bootstrap_chroot.sh

# This writes the interfaces file out
# bond physical interfaces and add the bond to a bridge, apply ip stuff to bridge
cp interfaces /mnt/etc/network/interfaces

# Writes out the sources.list
# I recommend not changing this since some packages come from the non-free repo
cp sources.list /mnt/etc/apt/sources.list

# UUID=<BOOT_DEV>, this is the only fstab entry needed (unless you use swap)
echo "UUID="$(blkid ${BOOT_DEV}1 | awk -F\" '{print $2}')" /boot ext4 rw,data=ordered 0 2" > /mnt/etc/fstab

if [[ "${!crypt[@]}" ]]; then
    echo "${ZFS_DEV1} / zfs defaults 0 0" >> /mnt/etc/fstab # luks_commands
    echo 'ENV{DM_NAME}=="zfs01", SYMLINK+="zfs01"' > /mnt/etc/udev/rules.d/99-zfs.rules # luks_commands
    echo -e "zfs01 UUID="$(blkid ${CRYPT_DEV1} | awk -F\" '{print $2}')" none luks,discard" > /mnt/etc/crypttab # luks_commands
fi

# execute script in chroot
chroot /mnt /bootstrap_chroot.sh ${BOOT_DEV} ${crypt}

# cp in zpool cache file
cp /tmp/zpool.cache /mnt/etc/zfs/
cp bootstrap.sh /mnt/bootstrap.sh

# turn sync back on (set it to default of 'standard')
zfs inherit sync rpool

./cleanup.sh ${crypt}
