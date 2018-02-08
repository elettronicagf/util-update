set -x

source=$(dirname $0)
destination=/run/media/mmcblk2
apphome=/
mkfs=0

cd $source

#show splash screen
zcat update-splash.gz > /dev/fb0

#----------------------
# partizionamento emmc:
#Disk /dev/mmcblk2: 3.7 GiB, 3959422976 bytes, 7733248 sectors
#Units: sectors of 1 * 512 = 512 bytes
#Sector size (logical/physical): 512 bytes / 512 bytes
#I/O size (minimum/optimal): 512 bytes / 512 bytes
#Disklabel type: dos
#Disk identifier: 0x00000000
#
#Device         Boot     Start       End  Blocks  Id System
#/dev/mmcblk2p1             16     39103   19544   c W95 FAT32 (LBA)
#/dev/mmcblk2p2          39104   1015743  488320  83 Linux
#/dev/mmcblk2p3        1015744   7070463 3027360  83 Linux
#/dev/mmcblk2p4        7070464   7733247  331392  83 Linux
#----------------------
if [ $mkfs = 1 ]; then
	[ -d /run/media/mmcblk2p1 ] && umount /run/media/mmcblk2p1
	[ -d /run/media/mmcblk2p2 ] && umount /run/media/mmcblk2p2
	[ -d /run/media/mmcblk2p3 ] && umount /run/media/mmcblk2p3
	[ -d /run/media/mmcblk2p3 ] && umount /run/media/mmcblk2p4
	echo -e "d\n4\nd\n3\nd\n2\nd\n1\nn\np\n1\n\n+20M\nt\n0c\nn\np\n2\n\n+500M\nn\np\n3\n\n+3100M\nn\np\n4\n\n\nw\n" | fdisk /dev/mmcblk2
	
	mkfs.vfat /dev/mmcblk2p1
	mkfs.ext4 /dev/mmcblk2p2
	mkfs.ext4 /dev/mmcblk2p3
	mkfs.ext4 /dev/mmcblk2p4
	udevadm trigger --action=add
	udevadm settle --timeout=5
fi
#--------------
# uboot
#--------------
mkdir ./uboot
./installPackage.sh $source/uboot.tar.gz ./uboot

#update u-boot
if [ -f ./uboot/u-boot.img ]; then
	echo Installing u-boot update...
	[ -f silent.boot ] && mv ./uboot/u-boot-silent.img ./uboot/u-boot.img
	flashcp ./uboot/u-boot.img  /dev/mtd1
fi

#update spl
if [ -f ./uboot/spl.img ]; then
	echo Installing spl update...
	[ -f silent.boot ] && mv ./uboot/spl-silent.img ./uboot/spl.img
	dd if=/dev/mtd0 of=spl-header.bin bs=1024 count=1
	cp spl-header.bin mtdspl.bin
	cat ./uboot/spl.img >> mtdspl.bin
	flashcp mtdspl.bin  /dev/mtd0
fi

#--------------
# kernel
#--------------
echo Installing kernel update...
./installPackage.sh $source/kernel.tar.gz "$destination"p1

#--------------
# rootfs
#--------------
echo Installing rootfs update...
./installPackage.sh $source/rootfs.tar.gz "$destination"p2 

#--------------
# Application 
#--------------
echo Installing application update...
umount "$destination"p3
mount /dev/mmcblk2p3 "$destination"p2/home/root/

#app installata in root perche' il tar.gz contiene gia' i percorsi assoluti
./installPackage.sh $source/app.tar.gz "$destination"p2

zcat update-terminated.gz > /dev/fb0

sync

umount /dev/sda1
umount /dev/sda2
umount /dev/mmcblk2p1
umount /dev/mmcblk2p3
umount /dev/mmcblk2p2
umount /dev/mmcblk2p4
