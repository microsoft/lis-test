if [ -e ../build.tag ]; then
	. ../build.tag
fi

if [ ! -e ../linux-image* ]; then
	sudo apt-get -y install libssl-dev

	CONFIG_FILE=.config
	yes "" | make oldconfig
	sed --in-place=.orig -e s:"# CONFIG_HYPERVISOR_GUEST is not set":"CONFIG_HYPERVISOR_GUEST=y\nCONFIG_HYPERV=y\nCONFIG_HYPERV_UTILS=y\nCONFIG_HYPERV_BALLOON=y\nCONFIG_HYPERV_STORAGE=y\nCONFIG_HYPERV_NET=y\nCONFIG_HYPERV_KEYBOARD=y\nCONFIG_FB_HYPERV=y\nCONFIG_HID_HYPERV_MOUSE=y": ${CONFIG_FILE}
	sed --in-place -e s:"CONFIG_PREEMPT_VOLUNTARY=y":"# CONFIG_PREEMPT_VOLUNTARY is not set": ${CONFIG_FILE}
	sed --in-place -e s:"# CONFIG_EXT4_FS is not set":"CONFIG_EXT4_FS=y\nCONFIG_EXT4_FS_XATTR=y\nCONFIG_EXT4_FS_POSIX_ACL=y\nCONFIG_EXT4_FS_SECURITY=y": ${CONFIG_FILE}
	sed --in-place -e s:"# CONFIG_REISERFS_FS is not set":"CONFIG_REISERFS_FS=y\nCONFIG_REISERFS_PROC_INFO=y\nCONFIG_REISERFS_FS_XATTR=y\nCONFIG_REISERFS_FS_POSIX_ACL=y\nCONFIG_REISERFS_FS_SECURITY=y": ${CONFIG_FILE}
	sed --in-place -e s:"# CONFIG_TULIP is not set":"CONFIG_TULIP=y\nCONFIG_TULIP_MMIO=y": ${CONFIG_FILE}
	yes "" | make oldconfig
	export CONCURRENCY_LEVEL=$(nproc)
	make-kpkg --append-to-version=.lisperfregression$BUILDTAG kernel-image --initrd
fi

dpkg -i ../linux-image*

#don't reboot