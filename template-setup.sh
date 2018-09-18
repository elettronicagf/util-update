PASSWORD=""
UPDATE_UBOOT="false"
UPDATE_KERNEL="false"
UPDATE_ROOTFS="false"
UPDATE_APP="false"
UPDATE_MBUGRF_FW="false"
WBS_APP=""
MBU_FW=""
MOUNT_POINT_APP=/run/media/mmcblk2p3

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
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 errorUpdating.gz | zcat > /dev/fb0
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
kernel_dt_file=imx6-egf-"$wid".dtb
kernel_image_file=zImage
UPDATE_TAR_OFFSET="16777253"

UPDATE_PATH=$1
message "Update path is $UPDATE_PATH"

if [ $type = emmc ]; then
	message "Updating EMMC"
	dest_dev=mmcblk2
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
	dest_app_partition=/run/media/$dest_dev'p3'
	dest_app_dir=''
fi


tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 validatingUpgrade.gz | zcat > /dev/fb0

message "Check update compatibility"
tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar xm --occurrence=1 -C / supported_devices
BOARD_FAMILY=$(strings -n 20 $mtd_spl | grep "^U-Boot.*(" | awk -F "-" '{ print $3 }')
grep $BOARD_FAMILY /supported_devices > /dev/null

if [ $? -ne 0 ]; then
  error_handler "Unsupported board $BOARD_FAMILY"
fi

message "Update compatibility validated"

#---------------------------------------------------------------------------------------------------------------
# Show Initial Page with countdown
#---------------------------------------------------------------------------------------------------------------
if [ "$UPDATE_MBUGRF_FW" = "true" ] || [ "$UPDATE_APP" = "true" ]; then

	echo 1 > /sys/class/leds/LED-1/brightness

	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 app.tar.gz | tar -xmz --occurrence=1 -C / version.ini

	SD_ONBOARD_VER=$(cat $MOUNT_POINT_APP/version.ini | grep SDRel | awk -F'=' '{print $2}')
	SD_UPDATE_VER=$(cat /version.ini | grep -i SDRel | awk -F'=' '{print $2}')
	echo "SD ONBOARD: " $SD_ONBOARD_VER
	echo "UPDATE: " $SD_UPDATE_VER
	if [ -z "$SD_ONBOARD_VER" ]; then
		SD_ONBOARD_VER="NONE"
	fi
	if [ -z "$SD_UPDATE_VER" ]; then
		SD_UPDATE_VER="NONE"
	fi

	message "Extracting mbugrf fw update"
    mkdir /mbufw
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar xm --occurrence=1 -C /mbufw mbufw.tar.gz 
	if [ $? -ne 0 ]; then
		error_handler "Error while unpacking mbugrf fw update from update package"
	fi
	
	#unpack u-boot update
	tar xmf /mbufw/mbufw.tar.gz -C /mbufw 
	if [ $? -ne 0 ]; then
		error_handler "Error while extracting mbugrf fw update files"
	fi


	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 firstPage.gz | zcat > /dev/fb0

	/mbufw/$WBS_APP /dev/ttymxc1  /mbufw/$MBU_FW "$SD_ONBOARD_VER" "$SD_UPDATE_VER "
	
fi

tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 startUpdating.gz | zcat > /dev/fb0

#---------------------------------------------------------------------------------------------------------------
# Partitioning
#---------------------------------------------------------------------------------------------------------------
if [ $type!=nand ]; then
#----------------------
#eMMC partitioning:
#Disk /dev/mmcblk2: 3.7 GiB, 3909091328 bytes, 7634944 sectors
#Units: sectors of 1 * 512 = 512 bytes
#Sector size (logical/physical): 512 bytes / 512 bytes
#I/O size (minimum/optimal): 512 bytes / 512 bytes
#Disklabel type: dos
#Disk identifier: 0x273f9840

#Device         Boot   Start     End Sectors  Size Id Type
#/dev/mmcblk2p1         2048   43007   40960   20M  c W95 FAT32 (LBA)
#/dev/mmcblk2p2        43008 1091583 1048576  512M 83 Linux
#/dev/mmcblk2p3      1091584 7634943 6543360  3.1G 83 Linux

#----------------------
if [ $mkfs = 1 ]; then

	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 formattingEMMC.gz | zcat > /dev/fb0

	message "Partitioning $dest_dev..."
	umount /dev/$dest_dev'p'*
	
	sleep 6
	
	echo -e "d\n3\nd\n2\nd\nn\np\n1\n\n+20M\nt\n0c\nn\np\n2\n\n+512M\nn\np\n3\n\n\nw\n" | fdisk /dev/$dest_dev

	message "Formatting '$dest_dev'p1..."
	mkfs.vfat /dev/$dest_dev'p1'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p1'
        mkfs.vfat /dev/$dest_dev'p1'
    fi
    
    message "Formatting '$dest_dev'p2..."
	mkfs.ext4 -F /dev/$dest_dev'p2'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p2'
        mkfs.ext4 -F /dev/$dest_dev'p2'
    fi
    
    message "Formatting '$dest_dev'p3..."
	mkfs.ext4 -F /dev/$dest_dev'p3'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p3'
        mkfs.ext4 -F /dev/$dest_dev'p3'
    fi
    
	udevadm trigger --action=add
	udevadm settle --timeout=10
fi
fi #type!=nand

#---------------------------------------------------------------------------------------------------------------
# Bootloader
#---------------------------------------------------------------------------------------------------------------
if [ "$UPDATE_UBOOT" = "true" ]; then
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 updatingBootloader.gz | zcat > /dev/fb0
	message "Extracting bootloader update"
    #extracting bootloader update from update package
    mkdir /uboot
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar xm --occurrence=1 -C /uboot uboot.tar.gz 
	if [ $? -ne 0 ]; then
		error_handler "Error while unpacking bootloader update from update package"
	fi
	
	#unpack u-boot update
	tar xmf /uboot/uboot.tar.gz -C /uboot 
	if [ $? -ne 0 ]; then
		error_handler "Error while extracting bootloader update files"
	fi
	
    message "Check u-boot and SPL current versions"
    
    UBOOT_VERSION_STRING=$(strings -n 20 $mtd_uboot | grep "^U-Boot.*(" | awk -F "-" '{ print $4 }' | awk '{ print $1}')
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
		UPD_UBOOT_VERSION_STRING=$(strings -n 20 /uboot/u-boot.img | grep "^U-Boot.*(" | awk -F "-" '{ print $4 }' | awk '{ print $1}')
		UPD_UBOOT_VERSION=$(expr $UPD_UBOOT_VERSION_STRING + 0);
		UPD_UBOOT_BOARD_FAMILY=$(strings -n 20 /uboot/u-boot.img | grep "^U-Boot.*(" | awk -F "-" '{ print $3 }')
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
    echo 90 > /sys/class/gpio/export
    echo out > /sys/class/gpio/gpio90/direction
    echo 1 > /sys/class/gpio/gpio90/value

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
	echo 0 > /sys/class/gpio/gpio90/value
	rm -r /uboot
fi


#---------------------------------------------------------------------------------------------------------------
# Kernel
#---------------------------------------------------------------------------------------------------------------

if [ "$UPDATE_KERNEL" = "true" ]; then
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 updatingKernel.gz | zcat > /dev/fb0
	message "Extracting kernel update"
    #extracting kernel update from update package
    mkdir /kernel
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar xm --occurrence=1 -C /kernel kernel.tar.gz
	if [ $? -ne 0 ]; then
		error_handler "Error while unpacking kernel update from update package"
	fi
	
	#unpack kernel update
	tar xmf /kernel/kernel.tar.gz -C /kernel 
	if [ $? -ne 0 ]; then
		error_handler "Error while extracting kernel update files"
	fi
	
	rm /kernel/kernel.tar.gz 
	
	if [ ! -e /kernel/$kernel_image_file ]; then
		error_handler "Invalid kernel update. Missing $kernel_image_file file!"
	fi;
	
	if [ ! -e /kernel/$kernel_dt_file ]; then
		error_handler "Invalid kernel update. Missing $kernel_dt_file dtb file!"
	fi;
	
	message "Update type is $type"
	if [ "$type" = "nand" ]; then 
		#NAND
	
		#Update Kernel
		message "Writing $kernel_image_file"
		write_file_to_nand_and_verify $dest_kernel_partition /kernel/$kernel_image_file
		if [ $? -ne 0 ]; then
			message "Kernel installation on NAND Flash failed. Retrying..."
			write_file_to_nand_and_verify $dest_kernel_partition /kernel/$kernel_image_file
			if [ $? -ne 0 ]; then
				error_handler "Kernel update installation on NAND Flash failed"
			fi
		fi
		
		#Update dtb
		message "Writing $kernel_dt_file"
		write_file_to_nand_and_verify $dest_dtb_partition /kernel/$kernel_dt_file
		if [ $? -ne 0 ]; then
			message "DTB installation on NAND Flash failed. Retrying..."
			write_file_to_nand_and_verify $dest_dtb_partition /kernel/$kernel_dt_file
			if [ $? -ne 0 ]; then
				error_handler "DTB update installation on NAND Flash failed"
			fi
		fi

	else
		#eMMC or SDCARD
		message "Installing kernel update -> $dest_boot_partition"
		cp /kernel/* $dest_boot_partition
		if [ $? -ne 0 ]; then
			message "Kernel installation failed. Retrying..."
			cp /kernel/* $dest_boot_partition
			if [ $? -ne 0 ]; then
				error_handler "Kernel update installation on eMMC/SD failed"
			fi
		fi
		umount $dest_boot_partition
	fi
	message "Successfully updated kernel and dtbs"
fi

#---------------------------------------------------------------------------------------------------------------
# Rootfs
#---------------------------------------------------------------------------------------------------------------

if [ "$UPDATE_ROOTFS" = "true" ]; then
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 updatingRootfs.gz | zcat > /dev/fb0
	if [ "$type" = "nand" ]; then 
		#NAND
		message "Installing rootfs update -> $dest_rootfs_partition"
		UBISIZE=$( tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -tv  --occurrence=1 rootfs.ubi | awk '{print $3}')
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 rootfs.ubi | ubiformat $dest_rootfs_partition -f - --yes -S$UBISIZE
		if [ $? -ne 0 ]; then
			message "Writing ubi rootfs partition failed. Retrying..."
			tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 rootfs.ubi | ubiformat $dest_rootfs_partition -f - --yes -S$UBISIZE
			if [ $? -ne 0 ]; then
				error_handler "Failed extracting and writing rootfs"
			fi
		fi
		message "Rootfs written successfully..."
	else
		#eMMC or SDCARD
		message "Extracting and writing rootfs. This may take several minutes..."
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 rootfs.tar.bz2 | tar -xmj -C $dest_rootfs_partition		
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
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 updatingApplication.gz | zcat > /dev/fb0
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
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 app.tar.gz | tar -xmz -C /run/media/home
		if [ $? -ne 0 ]; then
			error_handler "Failed extracting and writing app data"
		fi
		
		umount /run/media/home
		message "Application written successfully..."
	else
		#eMMC/SDCARD
		app_dev=${dest_app_partition#/run/media/}		
		mount /dev/$app_dev "$dest_rootfs_partition"/home/root/		
		
		app_dir="$dest_rootfs_partition"
		if [ ! -e "$app_dir" ]; then
			error_handler "Failed extracting and writing app data, unable to find app directory in rootfs"
		fi
		message "Extracting and writing app data. This may take several minutes..."
		tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 app.tar.gz | tar -xmz -C "$app_dir"
		if [ $? -ne 0 ]; then
			error_handler "Failed extracting and writing app data"
		fi

		umount /dev/$app_dev
		message "Application written successfully..."
	fi
fi

#---------------------------------------------------------------------------------------------------------------
# MBU FW
#---------------------------------------------------------------------------------------------------------------

if [ "$UPDATE_MBUGRF_FW" = "true" ]; then
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 updatingFirmware.gz | zcat > /dev/fb0
	echo 0 > /sys/class/leds/LED-1/brightness
	/mbufw/$WBS_APP /dev/ttymxc1  a /mbufw/$MBU_FW
fi

tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 upgradeCompleted.gz | zcat > /dev/fb0


umount /dev/mmcblk*
umount /dev/sd*

exit 0


