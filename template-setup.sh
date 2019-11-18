#set -x

PASSWORD=""
UPDATE_UBOOT="false"
UPDATE_KERNEL="false"
UPDATE_ROOTFS="false"
UPDATE_APP="false"


message() {
	echo "##### $1 #####"
	if [ "$LOG_FILE_PATH" != " " ]; then
		echo "$1" >> $LOG_FILE_PATH
		sync
	fi
}

error_handler() {
	message "##### Error: $1 #####"
	# Show "update error" splash screen
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 logo-update-error$res.gz | zcat > /dev/fb0
	exit 1;
}

get_wid_from_cmdline() {
	local CMDLINE=$(cat /proc/cmdline)
	local WID=" "
	for i in $CMDLINE; do
		if [ "${i:0:3}" = "WID" ]; then
			WID=$i
			break;
		fi
	done;
	echo $WID;
}

get_cpu_from_cmdline() {
	local CMDLINE=$(cat /proc/cmdline)
	local CPU=" "
	for i in $CMDLINE; do
		if [ "${i:0:7}" = "imx_cpu" ]; then
			CPU=${i#imx_cpu=}
			break;
		fi
	done;
	echo $CPU;
}

get_display() {
	local CMDLINE=$(cat /proc/cmdline)
	local DISPLAY=" "
	for i in $CMDLINE; do
		if [ "${i:0:5}" = "panel" ]; then
			DISPLAY=${i#panel=}
			break;
		fi
	done;
	echo $DISPLAY;	
}

# Write file to NAND Flash and verify
# $1 is destination partition, eg /dev/mtd0
# $2 is the path of the file to write
write_file_to_nand_and_verify() {
	local ret=0
	FILE_SIZE=$(stat -c "%s" $2)
	flash_erase $1 0 0
	nandwrite -p $1 $2
	dd if=$1 of=temp.bak bs=$FILE_SIZE count=1 &>/dev/null
	cmp temp.bak $2
	ret=$?
	rm temp.bak
	return $ret
}

if [ "$#" -ne 1 ]; then
  error_handler "Usage ./template-setup.py <update file path>"
fi;

if  [ ! -e $1 ]; then
	error_handler "Update package not found"
fi;

type=emmc
mkfs=0
wid=$(get_wid_from_cmdline)
kernel_dt_file=egf-sbc-"$wid".dtb
kernel_image_file=zImage
UPDATE_TAR_OFFSET="16777253"

UPDATE_PATH=$1
message "Update path is $UPDATE_PATH"

if [ $type = emmc ]; then
	message "Updating EMMC"
	dest_dev=mmcblk0
elif [ $type = sdcard ]; then
	message "Updating SDCARD"
	dest_dev=mmcblk0
elif [ $type = nand ]; then
	message "Updating NAND"
fi

if [ $type = nand ]; then
	mtd_spl=/dev/mtd4
	mtd_uboot=/dev/mtd5
	dest_kernel_partition=/dev/mtd0
	dest_dtb_partition=/dev/mtd1
	dest_rootfs_partition=/dev/mtd2
	dest_app_partition=/dev/mtd3
else
	mtd_spl=/dev/mtd0
	mtd_uboot=/dev/mtd1
	dest_boot_partition=/run/media/$dest_dev'p1'
	dest_rootfs_partition=/run/media/$dest_dev'p2'
	dest_app_partition=/run/media/$dest_dev'p2'
	dest_app_dir=/home/root
fi

#get display resolution
display=$(get_display)
case "$display" in
	EGF_BLC1177)
		res="800x480"
		;;

	EGF_BLC1182)
		res="1280x800"
		;;
	
	*)
		echo "display type [$display] not recognized"
		res="800x480"
esac	
res="-$res"


# Show "updating" splash screen
tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 logo-updating$res.gz | zcat > /dev/fb0

message "Check update compatibility"
tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar xm --occurrence=1 -C / supported_devices
BOARD_FAMILY=$(strings -n 20 $mtd_spl | grep "^U-Boot.*(" | awk -F "-" '{ print $3 }')
grep $BOARD_FAMILY /supported_devices > /dev/null

if [ $? -ne 0 ]; then
  error_handler "Unsupported board $BOARD_FAMILY" 
fi

message "Update compatibility validated"

#---------------------------------------------------------------------------------------------------------------
# Partitioning
#---------------------------------------------------------------------------------------------------------------
if [ $type!=nand ]; then
#----------------------
#Disk /dev/mmcblk0: 3.7 GiB, 3909091328 bytes, 7634944 sectors
#Units: sectors of 1 * 512 = 512 bytes
#Sector size (logical/physical): 512 bytes / 512 bytes
#I/O size (minimum/optimal): 512 bytes / 512 bytes
#Disklabel type: dos
#Disk identifier: 0x00000000
#
#Device         Boot Start     End Sectors  Size Id Type
#/dev/mmcblk0p1       2048   43007   40960   20M  c W95 FAT32 (LBA)
#/dev/mmcblk0p2      43008 7634943 7591936  3.6G 83 Linux
#----------------------
if [ $mkfs = 1 ]; then
	message "Partitioning $dest_dev..."
	umount /dev/$dest_dev'p'*
	
	sleep 6
	
	echo -e "d\n3\nd\n2\nd\nn\np\n1\n\n+20M\nt\n0c\nn\np\n2\n\n\nw\n" | fdisk /dev/$dest_dev

	message "Formatting '$dest_dev'p1..."
	mkfs.vfat /dev/$dest_dev'p1'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p1'
        mkfs.vfat -F /dev/$dest_dev'p1'
    fi
    
    message "Formatting '$dest_dev'p2..."
	mkfs.ext4 -F /dev/$dest_dev'p2'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p2'
        mkfs.ext4 -F /dev/$dest_dev'p2'
    fi
    
	udevadm trigger --action=add
	udevadm settle --timeout=10
fi
fi #type!=nand

#---------------------------------------------------------------------------------------------------------------
# Bootloader
#---------------------------------------------------------------------------------------------------------------
if [ "$UPDATE_UBOOT" = "true" ]; then
	message "Extracting bootloader update"
    #extracting bootloader update from update package
    mkdir /uboot
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar xm --occurrence=1 -C /uboot uboot.tar.gz 
	if [ $? -ne 0 ]; then
		error_handler "Error whstrings -n 20 ile unpacking bootloader update from update package"
	fi
	
	#unpack u-boot update
	tar xmf /uboot/uboot.tar.gz -C /uboot 
	if [ $? -ne 0 ]; then
		error_handler "Error while extracting bootloader update files"
	fi
	
    message "Check u-boot and SPL current versions"
    
    UBOOT_VERSION_STRING=$(strings -n 20 $mtd_uboot | grep "^U-Boot 20.*(" | awk -F "-" '{ print $4 }' | awk '{ print $1}')
    UBOOT_VERSION=$(expr $UBOOT_VERSION_STRING + 0);
    SPL_VERSION_STRING=$(strings -n 20 $mtd_spl | grep "^U-Boot.*(" | awk -F "-" '{ print $4 }' | awk '{ print $1}')
    SPL_VERSION=$(expr $SPL_VERSION_STRING + 0);
    
    if [ -f /uboot/spl.img ]; then
        UPD_SPL_VERSION_STRING=$(strings -n 20 /uboot/spl.img | grep "^U-Boot.*(" | awk -F "-" '{ print $4 }' | awk '{ print $1}')
		UPD_SPL_VERSION=$(expr $UPD_SPL_VERSION_STRING + 0);
		UPD_SPL_BOARD_FAMILY=$(strings -n 20 /uboot/spl.img | grep "^U-Boot.*(" | awk -F "-" '{ print $3 }')
		
    	if [ "$UPD_SPL_BOARD_FAMILY" != "$BOARD_FAMILY" ]; then
			error_handler "Unsupported bootloader board family. Detected SPL: $UPD_SPL_BOARD_FAMILY"
		fi
		
		if [ "$SPL_VERSION" -gt "$UPD_SPL_VERSION" ]; then
			error_handler "Downgrading SPL is forbidden. SPL current version: $SPL_VERSION, update SPL version: $UPD_SPL_VERSION"
		fi
        message "Current SPL Version is: $SPL_VERSION, New SPL Version is $UPD_SPL_VERSION"
        #Backup current SPL
        message "Backup current SPL"
		dd if=$mtd_spl of=/uboot/mtdspl.bin.backup &>/dev/null
	fi
	
    if [ -f /uboot/u-boot.img ]; then	
		UPD_UBOOT_VERSION_STRING=$(strings -n 20 /uboot/u-boot.img | grep "^U-Boot 20.*(" | awk -F "-" '{ print $4 }' | awk '{ print $1}')
		UPD_UBOOT_VERSION=$(expr $UPD_UBOOT_VERSION_STRING + 0);
		UPD_UBOOT_BOARD_FAMILY=$(strings -n 20 /uboot/u-boot.img | grep "^U-Boot 20.*(" | awk -F "-" '{ print $3 }')
	    if [ "$UPD_UBOOT_BOARD_FAMILY" != "$BOARD_FAMILY" ]; then
			error_handler "Unsupported bootloader board family. Detected U-Boot: $UPD_UBOOT_BOARD_FAMILY"
		fi

		if [ "$UBOOT_VERSION" -gt "$UPD_UBOOT_VERSION" ]; then
			error_handler "Downgrading U-Boot is forbidden. U-Boot current version: $UBOOT_VERSION, update U-Boot version: $UPD_UBOOT_VERSION"
		fi
		message "Current U-Boot Version is: $UBOOT_VERSION, New U-Boot Version is $UPD_UBOOT_VERSION"
	    #Backup current u-boot
	    message "Backup current U-Boot"
		dd if=$mtd_uboot of=/uboot/u-boot.img.backup &>/dev/null
	fi

    #rw nor
    echo 131 > /sys/class/gpio/export
    echo out > /sys/class/gpio/gpio131/direction
    echo 1 > /sys/class/gpio/gpio131/value

	if [ -f /uboot/spl.img ]; then
		#Do update spl
		message "Installing SPL update"
		flash_unlock $mtd_spl
		dd if=$mtd_spl of=/uboot/spl-header.bin bs=1024 count=1 &>/dev/null
		cp /uboot/spl-header.bin /uboot/mtdspl.bin
		cat /uboot/spl.img >> /uboot/mtdspl.bin
		flashcp /uboot/mtdspl.bin  $mtd_spl
		if [ $? -ne 0 ]; then
			message "SPL installation failed. Retrying..."
			flashcp /uboot/mtdspl.bin  $mtd_spl
			if [ $? -ne 0 ]; then
				message "SPL installation failed. Recovering SPL from backup file..."
				flashcp /uboot/mtdspl.bin.backup  $mtd_spl
				if [ $? -ne 0 ]; then
					error_handler "SPL recovery from backup failed. After reboot board may not be able to boot"
				fi
			fi
		fi
		flash_lock $mtd_spl
	fi	

    if [ -f /uboot/u-boot.img ]; then	
		#Do update u-boot
		message "Installing U-Boot update"
		flash_unlock $mtd_uboot
		flashcp /uboot/u-boot.img  $mtd_uboot
		if [ $? -ne 0 ]; then
			message "U-Boot installation failed. Retrying..."
			flashcp /uboot/u-boot.img  $mtd_uboot
			if [ $? -ne 0 ]; then
				message "U-Boot installation failed. Recovering U-Boot from backup file..."
				flashcp /uboot/u-boot.img.backup  $mtd_uboot
				if [ $? -ne 0 ]; then
					error_handler "U-Boot recovery from backup failed. After reboot board may not be able to boot"
				fi
			fi
		fi
		flash_lock $mtd_uboot
	fi

	#ro nor
	echo 0 > /sys/class/gpio/gpio131/value
	rm -r /uboot
fi


#---------------------------------------------------------------------------------------------------------------
# Kernel
#---------------------------------------------------------------------------------------------------------------

if [ "$UPDATE_KERNEL" = "true" ]; then
	message "Update type is $type"
	if [ "$type" = "nand" ]; then 
		#NAND
	
		#Update Kernel
		message "Writing $kernel_image_file"
		
		flash_erase $dest_kernel_partition 0 0
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar xOm --occurrence=1 kernel.tar.gz | tar xOzm $kernel_image_file | nandwrite -p $dest_kernel_partition -
		
		if [ $? -ne 0 ]; then
			message "Kernel installation on NAND Flash failed. Retrying..."
			flash_erase $dest_kernel_partition 0 0
			tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar xOm --occurrence=1 kernel.tar.gz | tar xOzm $kernel_image_file | nandwrite -p $dest_kernel_partition -
			if [ $? -ne 0 ]; then
				error_handler "Kernel update installation on NAND Flash failed"
			fi
		fi
		
		#Update dtb
		message "Writing $kernel_dt_file"
		flash_erase $dest_dtb_partition 0 0
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar xOm --occurrence=1 kernel.tar.gz | tar xOzm $kernel_dt_file | nandwrite -p $dest_dtb_partition -

		if [ $? -ne 0 ]; then
			message "DTB installation on NAND Flash failed. Retrying..."
			flash_erase $dest_dtb_partition 0 0
			tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar xOm --occurrence=1 kernel.tar.gz | tar xOzm $kernel_dt_file | nandwrite -p $dest_dtb_partition -
			if [ $? -ne 0 ]; then
				error_handler "DTB update installation on NAND Flash failed"
			fi
		fi

	else
		#eMMC or SDCARD
		message "Installing kernel update -> $dest_boot_partition"
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar xOm --occurrence=1 kernel.tar.gz | tar -xmz --no-same-owner -C $dest_boot_partition
		if [ $? -ne 0 ]; then
			message "Kernel installation failed. Retrying..."
			tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar xOm --occurrence=1 kernel.tar.gz | tar -xmz --no-same-owner -C $dest_boot_partition
			if [ $? -ne 0 ]; then
				error_handler "Kernel update installation on eMMC/SD failed"
			fi
		fi
		umount $dest_boot_partition
	fi
	message "Successfully updated kernel and dtbs"
	rm -rf /kernel
fi

#---------------------------------------------------------------------------------------------------------------
# Rootfs
#---------------------------------------------------------------------------------------------------------------

if [ "$UPDATE_ROOTFS" = "true" ]; then
	if [ "$type" = "nand" ]; then 
		#NAND
		message "Installing rootfs update -> $dest_rootfs_partition"
		UBISIZE=$( tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar -tv  --occurrence=1 rootfs.ubi | awk '{print $3}')
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 rootfs.ubi | ubiformat $dest_rootfs_partition -f - --yes -S$UBISIZE
		if [ $? -ne 0 ]; then
			message "Writing ubi rootfs partition failed. Retrying..."
			tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 rootfs.ubi | ubiformat $dest_rootfs_partition -f - --yes -S$UBISIZE
			if [ $? -ne 0 ]; then
				error_handler "Failed extracting and writing rootfs"
			fi
		fi
		message "Rootfs written successfully..."
	else
		#eMMC or SDCARD
		message "Extracting and writing rootfs. This may take several minutes..."
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 rootfs.tar.bz2 | tar -xmj -C $dest_rootfs_partition		
		if [ $? -ne 0 ]; then
			error_handler "Failed extracting and writing rootfs"
		fi
		umount $dest_rootfs_partition
		message "Rootfs written successfully..."
	fi
fi

#---------------------------------------------------------------------------------------------------------------
# App and Modules
#---------------------------------------------------------------------------------------------------------------

if [ "$UPDATE_APP" = "true" ]; then
	message "Installing application -> $dest_app_partition"
	if [ "$type" = "nand" ]; then 
		#NAND
		message "Formatting ubi app partition"
		ubiformat --yes $dest_app_partition
		if [ $? -ne 0 ]; then
			message "Formatting ubi app partition failed. Retrying..."
			ubiformat $dest_app_partition
			if [ $? -ne 0 ]; then
				error_handler "Failed formatting ubi app partition"
			fi
		fi

		message "Attaching ubi app partition"
		app_part_no=${dest_app_partition#/dev/mtd}
		ubiattach /dev/ubi_ctrl -m $app_part_no -d 1
		if [ $? -ne 0 ]; then
			error_handler "Failed attaching ubi app partition"
		fi	
	
		message "Creating ubi app volume"
		ubimkvol /dev/ubi1 -N app -m
		if [ $? -ne 0 ]; then
			error_handler "Failed creating ubi app volume"
		fi

		message "Mounting ubi app volume"
		mkdir -p /run/media/home/
		mount -t ubifs ubi1:app /run/media/home/
		
		message "Extracting and writing app data. This may take several minutes..."
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 app.tar.gz | tar -xmz -C /run/media/home
		if [ $? -ne 0 ]; then
			error_handler "Failed extracting and writing app data"
		fi
		
		umount /run/media/home
		message "Application written successfully..."
	else
		#eMMC/SDCARD
		app_dev=${dest_app_partition#/run/media/}
		mount /dev/$app_dev $dest_app_partition
		app_dir="$dest_app_partition""$dest_app_dir"
		if [ ! -e "$app_dir" ]; then
			error_handler "Failed extracting and writing app data, unable to find /home/root directory in rootfs"
		fi
		message "Extracting and writing app data. This may take several minutes..."
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 app.tar.gz | tar -xmz -C "$app_dir"
		if [ $? -ne 0 ]; then
			error_handler "Failed extracting and writing app data"
		fi
		umount $dest_app_partition
		message "Application written successfully..."
	fi
fi

# Show "update terminated" splash screen
tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -md md5 -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 logo-update-terminated$res.gz | zcat > /dev/fb0

umount /dev/mmcblk*
umount /dev/sd*

exit 0


