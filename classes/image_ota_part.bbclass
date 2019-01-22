inherit image_types

IMAGE_BOOTLOADER ?= "u-boot"

# Handle u-boot suffixes
#UBOOT_SUFFIX ?= "bin"
#UBOOT_SUFFIX_SDCARD ?= "${UBOOT_SUFFIX}"

#IMAGE_LINK_NAME_linux.sb = ""
#IMAGE_CMD_linux.sb () {
#	kernel_bin="`readlink ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${MACHINE}.bin`"
#	kernel_dtb="`readlink ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${MACHINE}.dtb || true`"
#	linux_bd_file=imx-bootlets-linux.bd-${MACHINE}
#	if [ `basename $kernel_bin .bin` = `basename $kernel_dtb .dtb` ]; then
#		# When using device tree we build a zImage with the dtb
#		# appended on the end of the image
#		linux_bd_file=imx-bootlets-linux.bd-dtb-${MACHINE}
#		cat $kernel_bin $kernel_dtb \
#		    > $kernel_bin-dtb
#		rm -f ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${MACHINE}.bin-dtb
#		ln -s $kernel_bin-dtb ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${MACHINE}.bin-dtb
#	fi
#
#	# Ensure the file is generated
#	rm -f ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.linux.sb
#	(cd ${DEPLOY_DIR_IMAGE}; elftosb -z -c $linux_bd_file -o ${IMAGE_NAME}.linux.sb)
#
#	# Remove the appended file as it is only used here
#	rm -f ${DEPLOY_DIR_IMAGE}/$kernel_bin-dtb
#}


# Boot partition volume id
BOOTDD_VOLUME_ID ?= "Boot ${MACHINE}"

# Boot partition size [in KiB]
BOOT_SPACE ?= "8192"

# Set alignment to 4MB [in KiB]
IMAGE_ROOTFS_ALIGNMENT = "4096"

do_image_ota_sdcard[depends] = "parted-native:do_populate_sysroot \
                        dosfstools-native:do_populate_sysroot \
                        mtools-native:do_populate_sysroot \
                        virtual/kernel:do_deploy \
                        ${@d.getVar('IMAGE_BOOTLOADER', True) and d.getVar('IMAGE_BOOTLOADER', True) + ':do_deploy' or ''}"

SDCARD = "${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.sdcard"
SDCARD_GENERATION_COMMAND_ota = "generate_ota_sdcard"


#
# Generate the boot image with the boot scripts and required Device Tree
# files
_generate_boot_image() {
	local boot_part=$1

	# Create boot partition image
	BOOT_BLOCKS=$(LC_ALL=C parted -s ${SDCARD} unit b print \
	                  | awk "/ $boot_part / { print substr(\$4, 1, length(\$4 -1)) / 1024 }")

	# mkdosfs will sometimes use FAT16 when it is not appropriate,
	# resulting in a boot failure from SYSLINUX. Use FAT32 for
	# images larger than 512MB, otherwise let mkdosfs decide.
	if [ $(expr $BOOT_BLOCKS / 1024) -gt 512 ]; then
		FATSIZE="-F 32"
	fi

	rm -f ${WORKDIR}/boot.img
	mkfs.vfat -n "${BOOTDD_VOLUME_ID}" -S 512 ${FATSIZE} -C ${WORKDIR}/boot.img $BOOT_BLOCKS

	mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${MACHINE}.bin ::/${KERNEL_IMAGETYPE}

	# Copy boot scripts
	for item in ${BOOT_SCRIPTS}; do
		src=`echo $item | awk -F':' '{ print $1 }'`
		dst=`echo $item | awk -F':' '{ print $2 }'`

		mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/$src ::/$dst
	done

	# Copy device tree file
	if test -n "${KERNEL_DEVICETREE}"; then
		for DTS_FILE in ${KERNEL_DEVICETREE}; do
			DTS_BASE_NAME=`basename ${DTS_FILE} | awk -F "." '{print $1}'`
			if [ -e "${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${DTS_BASE_NAME}.dtb" ]; then
				kernel_bin="`readlink ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${MACHINE}.bin`"
				kernel_bin_for_dtb="`readlink ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${DTS_BASE_NAME}.dtb | sed "s,$DTS_BASE_NAME,${MACHINE},g;s,\.dtb$,.bin,g"`"
				if [ $kernel_bin = $kernel_bin_for_dtb ]; then
					mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${DTS_BASE_NAME}.dtb ::/${DTS_BASE_NAME}.dtb
				fi
			else
				bbfatal "${DTS_FILE} does not exist."
			fi
		done
	fi
}
prepare_sdcard () {
	if [ -z "${SDCARD_ROOTFS}" ]; then
		bberror "SDCARD_ROOTFS is undefined. To use sdcard OTA image SDCARD_ROOTFS must be defined."
		exit 1
	fi

	# Align boot partition and calculate total SD card image size
	BOOT_SPACE_ALIGNED=$(expr ${BOOT_SPACE} + ${IMAGE_ROOTFS_ALIGNMENT} - 1)
	BOOT_SPACE_ALIGNED=$(expr ${BOOT_SPACE_ALIGNED} - ${BOOT_SPACE_ALIGNED} % ${IMAGE_ROOTFS_ALIGNMENT})
	SDCARD_SIZE=$(expr ${IMAGE_ROOTFS_ALIGNMENT} + ${BOOT_SPACE_ALIGNED} + $ROOTFS_SIZE + ${IMAGE_ROOTFS_ALIGNMENT})

	# Initialize a sparse file

	dd if=/dev/zero of=${SDCARD} bs=1 count=0 seek=$(expr 1024 \* ${SDCARD_TOTAL_SIZE})
	${SDCARD_GENERATION_COMMAND}
}




#
# Create an image that can by written onto a SD card using dd for use
# with i.MXS SoC family
#
# External variables needed:
#   ${SDCARD_ROOTFS}    - the rootfs image to incorporate
#   ${IMAGE_BOOTLOADER} - bootloader to use {imx-bootlets, u-boot}
#
IMAGE_CMD_ota_sdcard () {

	BOOTLOADER_SIZE=4096
	KERNEL_RECOVERY=$(expr ${BOOTLOADER_SIZE} + 102400)
	ROOTFS_RECOVERY=$(expr ${KERNEL_RECOVERY} + 102400)
	KERNEL_NORM=$(expr ${ROOTFS_RECOVERY} + 102400)
	ROOTFS_NORM=$(expr ${KERNEL_NORM} + ${SDCARD_TOTAL_SIZE})

	# Prepare .sdcard file
	prepare_sdcard

	# Create partition table
	# TODO : add boot partitions for every bootloader
	echo "LOOOOOO3l"
	echo $SDCARD
	parted -s ${SDCARD} mklabel msdos
	case "${IMAGE_BOOTLOADER}" in
		u-boot) # U-BOOT bootloader case
		parted -s ${SDCARD} unit B mkpart primary 512 ${BOOTLOADER_SIZE}
		parted -s ${SDCARD} unit B mkpart primary $(expr ${BOOTLOADER_SIZE} + 512)  ${KERNEL_RECOVERY}
		parted -s ${SDCARD} unit B mkpart primary $(expr ${KERNEL_RECOVERY} + 512) ${ROOTFS_RECOVERY}
		parted -s ${SDCARD} unit B mkpart extended $(expr ${ROOTFS_RECOVERY} + 512) ${SDCARD_TOTAL_SIZE}
		parted -s ${SDCARD} unit B mkpart logical $(expr ${ROOTFS_RECOVERY} + 1024)  ${KERNEL_NORM}
		parted -s ${SDCARD} unit B mkpart logical $(expr ${KERNEL_NORM} + 1024)  ${SDCARD_TOTAL_SIZE}

		dd if=${DEPLOY_DIR_IMAGE}/u-boot.bin of=${SDCARD} conv=notrunc seek=1 bs=$(expr 1024 \* 1024)

	    dd if=${DEPLOY_DIR_IMAGE}/uImage of=${SDCARD} conv=notrunc seek=2 bs=$(expr 1024 \* 1024)
		dd if=${SDCARD_ROOTFS}  of=${SDCARD} conv=notrunc seek=3 bs=$(expr 1024 \* 1024)
		dd if=${DEPLOY_DIR_IMAGE}/uImage of=${SDCARD} conv=notrunc seek=4 bs=$(expr 1024 \* 1024)
		dd if=${SDCARD_ROOTFS}  of=${SDCARD} conv=notrunc seek=5 bs=$(expr 1024 \* 1024)
		;;
		*)
		bberror "Unknown IMAGE_BOOTLOADER value"
		exit 1
		;;
	esac

	# Change partition type for ota processor family
	bbnote "Setting partition type to 0x53 as required for ota' SoC family."
	echo -n S | dd of=${SDCARD} bs=1 count=1 seek=450 conv=notrunc

	parted ${SDCARD} print

}

# The sdcard requires the rootfs filesystem to be built before using
# it so we must make this dependency explicit.
IMAGE_TYPEDEP_sdcard += "${@d.getVar('SDCARD_ROOTFS', 1).split('.')[-1]}"
