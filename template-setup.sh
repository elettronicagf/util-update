set -x
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
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 update-error.gz | zcat > /dev/fb0
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
fi

if [ $type = emmc ]; then
	mtd_spl=/dev/mtd0
	mtd_uboot=/dev/mtd1
	dest_boot_partition=/run/media/$dest_dev'p1'
	dest_rootfs_partition=/run/media/$dest_dev'p2'
	dest_app_partition=/run/media/$dest_dev'p3'
	dest_app_dir=/home/root
fi

tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 update-splash.gz | zcat > /dev/fb0

message "Check update compatibility"
tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar xm --occurrence=1 -C / supported_devices
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
#eMMC partitioning:
#Disk /dev/mmcblk2: , 3909091328 bytes
#4 heads, 16 sectors/track, 119296 cylinders
#Units = cylinders of 64 * 512 = 32768 bytes
#
#   Device Boot      Start         End      Blocks   Id  System
#/dev/mmcblk2p1             16     39103   19544   c W95 FAT32 (LBA)
#/dev/mmcblk2p2          39104   1015743  488320  83 Linux
#/dev/mmcblk2p3        1015744   7070463 3027360  83 Linux
#/dev/mmcblk2p4        7070464   7733247  331392  83 Linux
#----------------------
if [ $mkfs = 1 ]; then
	message "Partitioning $dest_dev..."
	umount /dev/$dest_dev'p'*
	
	sleep 6
	
    echo -e "d\n4\nd\n3\nd\n2\nd\n1\nn\np\n1\n\n+20M\nt\n0c\nn\np\n2\n\n+500M\nn\np\n3\n\n+3100M\nn\np\n4\n\n\nw\n" | fdisk /dev/$dest_dev

	message "Formatting '$dest_dev'p1..."
	mkfs.vfat /dev/$dest_dev'p1'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p1'
        mkfs.vfat /dev/$dest_dev'p1'
    fi
    
    message "Formatting '$dest_dev'p2..."
	mkfs.ext4 /dev/$dest_dev'p2'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p2'
        mkfs.ext4 /dev/$dest_dev'p2'
    fi
    
    message "Formatting '$dest_dev'p3..."
	mkfs.ext4 /dev/$dest_dev'p3'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p3'
        mkfs.ext4 /dev/$dest_dev'p3'
    fi
    
    message "Formatting '$dest_dev'p4..."
	mkfs.ext4 /dev/$dest_dev'p4'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p4'
        mkfs.ext4 /dev/$dest_dev'p4'
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
    #echo 90 > /sys/class/gpio/export
    #echo out > /sys/class/gpio/gpio90/direction
    #echo 1 > /sys/class/gpio/gpio90/value

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
	#echo 0 > /sys/class/gpio/gpio90/value
	rm -r /uboot
fi


#---------------------------------------------------------------------------------------------------------------
# Kernel
#---------------------------------------------------------------------------------------------------------------

if [ "$UPDATE_KERNEL" = "true" ]; then
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

	#eMMC
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

	message "Successfully updated kernel and dtbs"
fi

#---------------------------------------------------------------------------------------------------------------
# Rootfs
#---------------------------------------------------------------------------------------------------------------

if [ "$UPDATE_ROOTFS" = "true" ]; then
	#eMMC
	message "Extracting and writing rootfs. This may take several minutes..."
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 rootfs.tar.bz2 | tar -xmj -C $dest_rootfs_partition		
	if [ $? -ne 0 ]; then
		error_handler "Failed extracting and writing rootfs"
	fi
	#umount $dest_rootfs_partition
	message "Rootfs written successfully..."
fi

#---------------------------------------------------------------------------------------------------------------
# App and Modules
#---------------------------------------------------------------------------------------------------------------

if [ "$UPDATE_APP" = "true" ]; then
	message "Installing application -> $dest_app_partition"

	#eMMC
	umount "$dest_app_partition"
	app_dev=${dest_app_partition#/run/media/}
	mount /dev/$app_dev "$dest_rootfs_partition"/home/root/
	
	#app_dev=${dest_app_partition#/run/media/}
	#mount /dev/$app_dev $dest_app_partition
	app_dir="$dest_rootfs_partition"
	if [ ! -e "$app_dir" ]; then
		error_handler "Failed extracting and writing app data, unable to find $dest_rootfs_partition directory in rootfs"
	fi
	message "Extracting and writing app data. This may take several minutes..."
	tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 app.tar.gz | tar -xmz -C "$app_dir"
	if [ $? -ne 0 ]; then
		error_handler "Failed extracting and writing app data"
	fi
	umount /dev/$app_dev
	message "Application written successfully..."
fi

#only emmc
umount $dest_rootfs_partition

# Show "update terminated" splash screen
tail -c +$UPDATE_TAR_OFFSET $UPDATE_PATH | openssl enc -aes-256-cbc -d -pass pass:$PASSWORD 2> /dev/null | tar -xm -O --occurrence=1 update-terminated.gz | zcat > /dev/fb0

umount /dev/mmcblk*
umount /dev/sd*

exit 0


