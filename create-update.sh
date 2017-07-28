#!/bin/sh
#set -x
ZIP_PASSWORD='8fX589i2ed_@YT#xx++]]00$aqe34=='
#"-P password"

UBOOT_VERSION=0572-001
SPL_VERSION=$UBOOT_VERSION
KERNEL_VERSION=0572-001
ROOTFS_VERSION=1.0
ROOTFSLIVE_VERSION=0572-001

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

YOCTO_IMAGE=0572consolefulltouch-$ROOTFS_VERSION

skippartitioning=1
skipuboot=0
skipspl=0
skipkernel=0
skiprootfs=0
update_nand=0
dt_version=0

# ./create-update.sh --makepartition --nand --dt=AA01.01 --cpu=ul
usage() { echo "Usage: $0 [--no-uboot | --no-spl | --no-kernel | --no-rootfs | --makepartition | --nand | --dt=WID --help]" 1>&2; exit 1; }

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
        --dt )            dt_version=$2; shift 2;;
        --help )          usage; shift;;
	    -- )              shift; break;;
		* )               break;
    esac
done

if [ $update_nand = 1 ]; then
	if [ $dt_version = 0 ]; then
		error "Error: missing required parameter 'dt'"
		exit
	fi
	
	if [ $skippartitioning = 0 ]; then
		error "Error: option 'makepartition' is incompatible with option 'nand'"
		exit
	fi
fi	

#create dirs
rm -rf $DEST
rm -rf $OUTPUT
rm -rf tmp
sudo rm -rf $APP_BINARIES/*

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
#cp images/logo-boot.bmp $OUTPUT/logo.bmp

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
		sudo tar xf $filename_modules .
		sudo chown -R root:root $APP_BINARIES/*
		tar czf $OUTPUT/$APP_PKG -C $APP_BINARIES .
	fi
	
	#update kernel
	cd $KERNEL_BINARIES
	if [ $update_nand = 1 ]; then
		tar czvf $OUTPUT/$KERNEL_PKG zImage *$dt_version.dtb
	else
		tar czvf $OUTPUT/$KERNEL_PKG zImage *.dtb
	fi
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
cp template-setup.sh $OUTPUT/setup.sh
cd $OUTPUT

#force make partition
if [ $skippartitioning = 0 ]; then
	sed -i 's/mkfs=0/mkfs=1/g' setup.sh
fi

if [ $update_nand = 1 ]; then
	sed -i 's/type=emmc/type=nand/g' setup.sh
	sed -i 's/dt_file=XX/dt_file=imx6-egf-WID0510_'$dt_version'.dtb/g' setup.sh
fi

#update zip password
sed -i 's/ZIP_PASSWORD=""/ZIP_PASSWORD='"'"$ZIP_PASSWORD"'"'/g' setup.sh
cp setup.sh ../

#build update file
message "Packaging files"
zip -0 -P $ZIP_PASSWORD $DEST/update.bin setup.sh
[ -f update-splash.gz ]     && zip -0 -P $ZIP_PASSWORD $DEST/update.bin update-splash.gz
[ -f update-terminated.gz ] && zip -0 -P $ZIP_PASSWORD $DEST/update.bin update-terminated.gz
[ -f $KERNEL_PKG ]          && zip -0 -P $ZIP_PASSWORD $DEST/update.bin $KERNEL_PKG
[ -f $UBOOT_PKG ]           && zip -0 -P $ZIP_PASSWORD $DEST/update.bin $UBOOT_PKG
[ -f $ROOTFS_PKG ]          && zip -0 -P $ZIP_PASSWORD $DEST/update2.bin $ROOTFS_PKG
[ -f $APP_PKG ]             && zip -0 -P $ZIP_PASSWORD $DEST/update3.bin $APP_PKG
cd ..

#copy live image
if [ -f $KERNEL_LIVE_BINARIES/zImage ]; then
	cp $KERNEL_LIVE_BINARIES/* $DEST
else
    error "Live image not found"
fi

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
[ $update_nand = 1 ] && echo 'WID     WID0510_'$dt_version
echo
[ $skippartitioning = 0 ] && echo -e '\E[1;32m!!! Partitions will be formatted !!!'; echo;
