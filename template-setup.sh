source=$(dirname $0)
destination=/run/media/mmcblk2
apphome=/
mkfs=0

cd $source

#show splash screen
zcat update-splash.gz > /dev/fb0

#----------------------
# partizionamento emmc:
#Disk /dev/mmcblk2: 3909 MB, 3909091328 bytes
#4 heads, 16 sectors/track, 119296 cylinders
#Units = cylinders of 64 * 512 = 32768 bytes
#
#        Device Boot      Start         End      Blocks  Id System
#/dev/mmcblk2p1               1         611       19544   c Win95 FAT32 (LBA)
#/dev/mmcblk2p2             612      119296     3797920  83 Linux
#----------------------
if [ $mkfs = 1 ]; then
	[ -d /run/media/mmcblk2p1 ] && umount /run/media/mmcblk2p1
	[ -d /run/media/mmcblk2p2 ] && umount /run/media/mmcblk2p2
	[ -d /run/media/mmcblk2p3 ] && umount /run/media/mmcblk2p3
	echo -e "d\n4\nd\n3\nd\n2\nd\n1\nn\np\n1\n\n+20M\nt\n0c\nn\np\n2\n\n\nw\n" | fdisk /dev/mmcblk2
	mkfs.vfat /dev/mmcblk2p1
	mkfs.ext3 /dev/mmcblk2p2
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
#per ora l'app è installata nella partizione p2 e non p3!
echo Installing application update...
mkdir -p "$destination"p2/$apphome
./installPackage.sh $source/app.tar.gz "$destination"p2/$apphome

zcat update-terminated.gz > /dev/fb0

sync

umount /dev/sda1
umount /dev/sda2
umount /dev/mmcblk2p1
umount /dev/mmcblk2p2
