
message() {
	echo "##### $1 #####"
}

error() {
	echo "##### Error: $1 #####"
}

installPackage() {
	#----------------
	# Update package 
	#----------------
	echo 3 > /proc/sys/vm/drop_caches

	if [ ! -f "$1" ]; then
		error "Update package $1 not found, skipping..."
		return
	fi

	#test archive first
	gunzip -c $1 | tar t > /dev/null

	if [ $? -ne 0 ]; then
		error "Update package $1 corrupted! Skipping..."
		return
	fi

	if [ ! -z $3 ]; then
	if [ $3 == 'deleteAll' ]; then
		message "Erasing $2..."
		rm -rf $2/*
	fi
	fi

	#apply updated files
	tar xf $1 -C $2
	rm $1
}

#must match the one used in create-update.sh
ZIP_PASSWORD="password"
source=$(dirname $0)
#emmc | sdcard
type=emmc
mkfs=0
mtd_spl=/dev/mtd0
mtd_uboot=/dev/mtd1

if [ $type = emmc ]; then
	message "Updating EMMC"
	dest_dev=mmcblk2
elif [ $type = sdcard ]; then
	message "Updating SDCARD"
	dest_dev=mmcblk0
fi

dest_boot_partition=/run/media/$dest_dev'p1'
dest_rootfs_partition=/run/media/$dest_dev'p2'
dest_app_partition=/run/media/$dest_dev'p2'

bootmedia=/run/media/mmcblk0p1
[ ! -z "$(mount | grep sda)" ] && bootmedia=/run/media/sda
[ ! -z "$(mount | grep sda1)" ] && bootmedia=/run/media/sda1


geometry=$(fbset | grep geometry)

xres=$(echo $geometry | awk -F " " '{print $2}')
yres=$(echo $geometry | awk -F " " '{print $3}')

res=${xres}x${yres}

cd $source

#show splash screen
zcat update-splash-$res.gz > /dev/fb0

#----------------------
# partizionamento emmc:
#Disk /dev/mmcblk2: , 3909091328 bytes
#4 heads, 16 sectors/track, 119296 cylinders
#Units = cylinders of 64 * 512 = 32768 bytes
#
#   Device Boot      Start         End      Blocks   Id  System
#/dev/sdd1            2048       43007       20480    c  W95 FAT32 (LBA)
#/dev/sdd2           43008     2140159     1048576   83  Linux
#----------------------
if [ $mkfs = 1 ]; then
	message "Formatting..."
	umount /dev/$dest_dev'p'*
	
	sleep 6
	
	echo -e "d\n3\nd\n2\nd\nn\np\n1\n\n+20M\nt\n0c\nn\np\n2\n\n+1G\nn\np\n3\n\n\nw\n" | fdisk /dev/$dest_dev

	mkfs.vfat /dev/$dest_dev'p1'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p1'
        mkfs.vfat /dev/$dest_dev'p1'
    fi
    
	mkfs.ext4 /dev/$dest_dev'p2'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p2'
        mkfs.ext4 /dev/$dest_dev'p2'
    fi
    
	mkfs.ext4 /dev/$dest_dev'p3'
    if [ $? -ne 0 ]; then 
        umount /dev/$dest_dev'p3'
        mkfs.ext4 /dev/$dest_dev'p3'
    fi        
    
	udevadm trigger --action=add
	udevadm settle --timeout=10
fi

#--------------
# uboot
#--------------
if [ -f $source/uboot.tar.gz ]; then
    message "Installing u-boot update -> $mtd_spl $mtd_uboot" 
    
    #rw nor
    echo 90 > /sys/class/gpio/export
    echo out > /sys/class/gpio/gpio90/direction
    echo 1 > /sys/class/gpio/gpio90/value
    
	mkdir ./uboot
	installPackage $source/uboot.tar.gz ./uboot

	#update u-boot
	flash_unlock $mtd_uboot
	flash_erase $mtd_uboot 0 0
	[ -f ./uboot/u-boot.img ] && flashcp ./uboot/u-boot.img  $mtd_uboot
	flash_lock $mtd_uboot
	
	#update spl
	if [ -f ./uboot/spl.img ]; then
		echo Installing spl update...
		flash_unlock $mtd_spl
		dd if=$mtd_spl of=spl-header.bin bs=1024 count=1
		cp spl-header.bin mtdspl.bin
		cat ./uboot/spl.img >> mtdspl.bin
		flash_erase $mtd_spl 0 0
		flashcp mtdspl.bin  $mtd_spl
		flash_lock $mtd_spl
	fi	
	
	#ro nor
	echo 0 > /sys/class/gpio/gpio90/value
fi

#--------------
# kernel
#--------------
message "Installing kernel update -> $dest_boot_partition"
installPackage $source/kernel.tar.gz $dest_boot_partition

#--------------
# rootfs (bz2)
#--------------
if [ -f $bootmedia/update2.bin ]; then
	message "Installing rootfs update -> $dest_rootfs_partition"
	unzip -p -P $ZIP_PASSWORD $bootmedia/update2.bin | tar xjf - -C $dest_rootfs_partition
fi

#--------------
# Application 
#--------------
if [ -f $bootmedia/update3.bin ]; then
	message "Installing application update -> $dest_app_partition"
	mkdir -p $dest_app_partition
	unzip -p -P $ZIP_PASSWORD $bootmedia/update3.bin | tar xzf - -C $dest_app_partition
fi

cd /
sync

#not all devices are mounted
umount /dev/sda
umount /dev/sda1
umount /dev/sda2
umount /dev/$dest_dev'p'*

#notify update is terminated
zcat $source/update-terminated-$res.gz > /dev/fb0


