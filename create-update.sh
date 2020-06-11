#!/bin/bash
#set -x
PASSWORD='47382e)9[xh?'
SUPPORTED_DEVICES='0508'

UBOOT_VERSION=0508-017
SPL_VERSION=$UBOOT_VERSION
KERNEL_VERSION=0508-014
ROOTFS_VERSION=2.2
ROOTFSLIVE_VERSION=0508-011

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
APP_PKG=app.tar.gz.disabled
APP_BINARIES=$HOME/binaries/app

MODULES_FILE=modules_$KERNEL_VERSION.tgz

YOCTO_IMAGE=0508consolecptimx6qdl-$ROOTFS_VERSION

skippartitioning=1
skipuboot=0
skipspl=0
skipkernel=0
skiprootfs=0

# ./create-update.sh --makepartition
usage() { echo "Usage: $0 [--no-uboot | --no-spl | --no-kernel | --no-rootfs | --makepartition | --help]" 1>&2; exit 1; }

message() {
	echo -e '\E[1;33m'$1'\E[0m'	
}

error() {
	echo -e '\E[1;31m'$1'\E[0m'
	echo " "	
}

bmp2rgb() {
	$CONV  -i $IMAGES/$1.bmp -vcodec rawvideo -f rawvideo -pix_fmt bgr24 tmp/$1.bmp.bin 1>/dev/null 2>&1
	gzip < tmp/$1.bmp.bin > $OUTPUT/$2.gz	
}

#setup image conversion utility
VTMP=$(which avconv)
if [ -z $VTMP ]; then
  VTMP=$(which ffmpeg)
  [ ! -z $VTMP ] && CONV=ffmpeg
else
  CONV=avconv
fi
  
if [ -z $CONV ]; then
  error "Image converter not found, install either avconv or ffmpeg"
  exit
fi

TEMP=$(getopt -o 1 -l no-uboot,no-spl,no-kernel,no-rootfs,makepartition,help -- "$@")
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
        --help )          usage; shift;;
	    -- )              shift; break;;
		* )               break;
    esac
done

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
bmp2rgb logo-itema-updating           update-splash
bmp2rgb logo-itema-update-terminated  update-terminated
bmp2rgb logo-itema-update-error       update-error

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
	else
		[ -e $APP_BINARIES/$APP_PKG ] && cp $APP_BINARIES/$APP_PKG $OUTPUT/$APP_PKG
	fi
	
	#update kernel
	cd $KERNEL_BINARIES
	
	#add boot logo
	cp $IMAGES/logo-itema-loading.bmp ./logo-itema.bmp
	
	tar czvf $OUTPUT/$KERNEL_PKG zImage *.dtb logo-itema.bmp
	cd $HOME
else
	#no kernel update, move application package to output
	[ -e $APP_BINARIES/$APP_PKG ] && cp $APP_BINARIES/$APP_PKG $OUTPUT/$APP_PKG
fi

#build rootfs update
#-------------------
if [ $skiprootfs = 0 ]; then
	message "Adding rootfs"
	#update rootfs
	if [ -f $ROOTFS_BINARIES/$YOCTO_IMAGE.tar.bz2 ]; then
		cp $ROOTFS_BINARIES/$YOCTO_IMAGE.tar.bz2 $OUTPUT/$ROOTFS_PKG
    else
		message "rootfs not found"
	fi
fi

cd $HOME

cd $OUTPUT

#force make partition
if [ $skippartitioning = 0 ]; then
	sed -i 's/mkfs=0/mkfs=1/g' setup.sh
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
cp $IMAGES/logo-itema-updating.bmp mnt/logo.bmp
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
  echo "Application found.."
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

cat update.tar | openssl enc -aes-256-cbc -md md5 -pass pass:$PASSWORD > update.tar.enc
rm update.tar
cat fat.bin update.tar.enc > payload
SUM=$(md5sum payload | awk '{print $1;}')
echo -n eGF1$SUM > header
cat header payload > update.eup
cp update.eup $DEST/update.eup
cd ..

cp $IMAGES/logo-itema-updating.bmp $DEST/logo.bmp

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
[ -e $APP_BINARIES/$APP_PKG ] && echo 'Application package included'
echo
[ $skippartitioning = 0 ] && echo -e '\E[1;32m!!! Partitions will be formatted !!!'; echo;
