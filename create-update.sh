#!/bin/sh
#set -x
PASSWORD='12kjh8dfs[324'
SUPPORTED_DEVICES='MBUGRFiMX6'

UBOOT_VERSION=MBUGRFiMX6-001
SPL_VERSION=$UBOOT_VERSION
KERNEL_VERSION=MBUGRFiMX6-001
ROOTFS_VERSION=1.0
ROOTFSLIVE_VERSION=MBUGRFiMX6-001

HOME=$(pwd)
OUTPUT=$HOME/output
IMAGES=$HOME/images
DEST=$HOME/usb-key
ROOTFS_PKG=rootfs.tar.bz2
KERNEL_PKG=kernel.tar.gz
UBOOT_PKG=uboot.tar.gz
KERNEL_BINARIES=$HOME/binaries/kernel/$KERNEL_VERSION
KERNEL_LIVE_BINARIES=$HOME/binaries/kernel/$ROOTFSLIVE_VERSION-live
UBOOT_BINARIES=$HOME/binaries/u-boot
ROOTFS_BINARIES=$HOME/binaries/rootfs
APP_PKG=app.tar.gz
APP_BINARIES=$HOME/binaries/app

MODULES_FILE=modules_$KERNEL_VERSION.tgz

YOCTO_IMAGE=0510mbugrfimx6-$ROOTFS_VERSION

skippartitioning=1
skipuboot=0
skipspl=0
skipkernel=0
skiprootfs=0
update_nand=0

# ./create-update.sh --makepartition --nand 
usage() { echo "Usage: $0 [--no-uboot | --no-spl | --no-kernel | --no-rootfs | --makepartition | --nand | --help]" 1>&2; exit 1; }

message() {
	echo -e '\E[1;33m'$1'\E[0m'	
}

error() {
	echo -e '\E[1;31m'$1'\E[0m'
	echo " "	
}

TEMP=$(getopt -o 1 -l no-uboot,no-spl,no-kernel,no-rootfs,makepartition,nand,dt:,cpu:,help -- "$@")
[ $? -eq 1 ] && exit

eval set -- "$TEMP"

while true
do
    case "$1" in
        --no-uboot )      skipuboot=1; shift;;
        --no-spl )        skipspl=1; shift;;
        --no-kernel )     skipkernel=1; shift;;
        --no-rootfs )     skiprootfs=1; shift;;
        --makepartition ) skippartitioning=0; shift;;
        --nand )          update_nand=1; shift;;
        --help )          usage; shift;;
	    -- )              shift; break;;
		* )               break;
    esac
done

if [ $update_nand = 1 ]; then
	if [ $skippartitioning = 0 ]; then
		error "Error: option 'makepartition' is incompatible with option 'nand'"
		exit
	fi
fi	

#create dirs
rm -rf $DEST
rm -rf $OUTPUT
rm -rf tmp

mkdir -p $DEST
mkdir -p $OUTPUT
mkdir tmp

#cleanup
#rm ./images/*.bgr 1>/dev/null 2>&1
rm ./*.tar 1>/dev/null 2>&1
rm ./*.gz 1>/dev/null 2>&1
rm setup.sh 1>/dev/null 2>&1

#--------------------------------------------------------------------------------------------------------
#create your own graphics
#each image must match the screen resolution and framebuffer format (rgb,bgr,rgb565,..)
#--------------------------------------------------------------------------------------------------------
#graphics
message "Building graphics"
avconv  -i $IMAGES/logo-updating.bmp -vcodec rawvideo -f rawvideo -pix_fmt bgr24 tmp/update-splash.bin 1>/dev/null 2>&1
gzip < tmp/update-splash.bin > $OUTPUT/update-splash.gz
avconv  -i $IMAGES/logo-update-terminated.bmp -vcodec rawvideo -f rawvideo -pix_fmt bgr24 tmp/update-terminated.bin 1>/dev/null 2>&1
gzip < tmp/update-terminated.bin > $OUTPUT/update-terminated.gz
avconv  -i $IMAGES/logo-update-error.bmp -vcodec rawvideo -f rawvideo -pix_fmt bgr24 tmp/update-error.bin 1>/dev/null 2>&1
gzip < tmp/update-error.bin > $OUTPUT/update-error.gz

cp template-setup.sh $OUTPUT/setup.sh

#build u-boot+SPL update
#-------------------
cd tmp
rm ./* 1>/dev/null 2>&1

if [ $skipuboot = 0 ]; then
	message "Adding u-boot"
	cp $UBOOT_BINARIES/u-boot.img-$UBOOT_VERSION ./u-boot.img
fi

if [ $skipspl = 0 ]; then
	message "Adding SPL"
	cp $UBOOT_BINARIES/SPL-$SPL_VERSION ./spl.img
fi

if [[ $skipspl = 0 || $skipuboot = 0 ]]; then
	tar czvf $OUTPUT/$UBOOT_PKG *
fi
cd ..


#build kernel update
#-------------------
if [ $skipkernel = 0 ]; then
	message "Adding kernel"
    filename_modules=$KERNEL_BINARIES/$MODULES_FILE
    
	if [ -e $filename_modules ]; then
		message "Adding modules"
		
		cd $APP_BINARIES
		mkdir tmp
		cd tmp
		mkdir modules
		cd modules
		sudo tar xf $filename_modules .
		cd ..
		APP_TAR_NAME=${APP_PKG%.gz}
		if [ ! -e $APP_BINARIES/$APP_PKG ]; then
			touch test
			tar cvf $APP_TAR_NAME test
			tar --delete -f $APP_TAR_NAME test
		else
			gunzip -c $APP_BINARIES/$APP_PKG > $APP_TAR_NAME
		fi
		sudo chown -R root:root $APP_BINARIES/tmp/*
		tar rf $APP_TAR_NAME modules
		rm -rf modules
		gzip $APP_TAR_NAME
		cp $APP_PKG $OUTPUT/$APP_PKG
		cd ..
		rm -rf tmp
	fi
	
	#update kernel
	cd $KERNEL_BINARIES
	tar czvf $OUTPUT/$KERNEL_PKG zImage *.dtb
	cd $HOME
fi

#build rootfs update
#-------------------
if [ $skiprootfs = 0 ]; then
	message "Adding rootfs"
	#update rootfs
	if [ -f $ROOTFS_BINARIES/$YOCTO_IMAGE.ubi ]; then
		ROOTFS_PKG=rootfs.ubi
		cp $ROOTFS_BINARIES/$YOCTO_IMAGE.ubi $OUTPUT/$ROOTFS_PKG
	elif [ -f $ROOTFS_BINARIES/$YOCTO_IMAGE.tar.bz2 ]; then
		cp $ROOTFS_BINARIES/$YOCTO_IMAGE.tar.bz2 $OUTPUT/$ROOTFS_PKG
	fi
fi

cd $HOME

cd $OUTPUT

#force make partition
if [ $skippartitioning = 0 ]; then
	sed -i 's/mkfs=0/mkfs=1/g' setup.sh
fi

if [ $update_nand = 1 ]; then
	sed -i 's/type=emmc/type=nand/g' setup.sh
fi


mkdir tmp
cd tmp
rm ./* 1>/dev/null 2>&1

#Create 16MB FAT filesystem
dd if=/dev/zero of=fat.bin bs=1M count=16
echo ',,4;' | sfdisk fat.bin
mkdir mnt
FIRST_AVAILABLE_LOOP_DEV=$(losetup -f)
losetup -P $FIRST_AVAILABLE_LOOP_DEV fat.bin
mkfs.msdos $FIRST_AVAILABLE_LOOP_DEV'p1'
mount $FIRST_AVAILABLE_LOOP_DEV'p1' mnt/
#copy live image
if [ -f $KERNEL_LIVE_BINARIES/zImage ]; then
	cp $KERNEL_LIVE_BINARIES/* mnt/
else
    error "Live image not found"
fi
cp $HOME/images/logo-boot.bmp mnt/logo.bmp
umount $FIRST_AVAILABLE_LOOP_DEV'p1'
losetup -d $FIRST_AVAILABLE_LOOP_DEV
cd ..
mv tmp/fat.bin .
sync
rm -rf tmp

#update zip password
sed -i 's/PASSWORD=""/PASSWORD='"'"$PASSWORD"'"'/g' setup.sh

#configuring update
if [ -e $UBOOT_PKG ]; then
  sed -i 's/UPDATE_UBOOT="false"/UPDATE_UBOOT="true"/g' setup.sh
fi;
if [ -e $KERNEL_PKG ]; then
  sed -i 's/UPDATE_KERNEL="false"/UPDATE_KERNEL="true"/g' setup.sh
fi;
if [ -e $ROOTFS_PKG ]; then
  sed -i 's/UPDATE_ROOTFS="false"/UPDATE_ROOTFS="true"/g' setup.sh
fi;
if [ -e $APP_PKG ]; then
  sed -i 's/UPDATE_APP="false"/UPDATE_APP="true"/g' setup.sh
fi;

echo -n $SUPPORTED_DEVICES > supported_devices

#build update file
message "Packaging files"
tar cvf update.tar setup.sh supported_devices
[ -f update-splash.gz ]     && tar -rf update.tar update-splash.gz
[ -f update-terminated.gz ] && tar -rf update.tar update-terminated.gz
[ -f update-error.gz ] 		&& tar -rf update.tar update-error.gz
[ -f $KERNEL_PKG ]          && tar -rf update.tar $KERNEL_PKG
[ -f $UBOOT_PKG ]           && tar -rf update.tar $UBOOT_PKG
[ -f $ROOTFS_PKG ]          && tar -rf update.tar $ROOTFS_PKG
[ -f $APP_PKG ]             && tar -rf update.tar $APP_PKG

cat update.tar | openssl enc -aes-256-cbc -pass pass:$PASSWORD > update.tar.enc
rm update.tar
cat fat.bin update.tar.enc > payload
SUM=$(md5sum payload | awk '{print $1;}')
echo -n eGF1$SUM > header
cat header payload > update.eup
cp update.eup $DEST/update.eup
cd ..

cp $IMAGES/logo-updating.bmp $DEST/logo.bmp

#cleanup
rm -rf ./tmp
rm -rf ./output

echo
echo -e '\E[1;37mUpdate package is stored in ./usb-key path'
echo -e '\E[1;33mVersions: '
[ $skipuboot = 0 ]   && echo 'U-Boot ' $UBOOT_VERSION
[ $skipspl = 0 ]     && echo 'SPL    ' $SPL_VERSION
[ $skipkernel = 0 ]  && echo 'Kernel ' $KERNEL_VERSION
[ $skiprootfs = 0 ]  && echo 'Rootfs ' $ROOTFS_VERSION
echo
[ $skippartitioning = 0 ] && echo -e '\E[1;32m!!! Partitions will be formatted !!!'; echo;
