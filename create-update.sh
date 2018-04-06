#!/bin/sh

checkfile() {
    if [ -f $1 ]; then
		printf "\x1B[1;37m%-20s\t\E[1;32mOK\E[0m\n" $(basename $1)
    else
		printf "\x1B[1;37m%-20s\t\E[1;32mnot found\E[0m\n" $(basename $1)
    fi
}

UPDATEFILE=update.tar
ROOTFS_PKG=rootfs.tar.gz
KERNEL_PKG=kernel.tar.gz
UBOOT_PKG=uboot.tar.gz
APP_PKG=app.tar.gz
KERNEL_BINARIES=kernel/binaries
UBOOT_BINARIES=u-boot/binaries

UBOOT_VERSION=0508-013
SPL_VERSION=$UBOOT_VERSION
KERNEL_VERSION=0508-010
ROOTFS_VERSION=2.2
ROOTFSLIVE_VERSION=0508-008
APP_VERSION=5

YOCTO_IMAGE=0508consolecptimx6qdl-$ROOTFS_VERSION

skippartitioning=1
skipuboot=0
skipspl=0
skipkernel=0
skiprootfs=0
skipapp=0

usage() { echo "Usage: $0 [--no-uboot | --no-spl | --no-kernel | --no-rootfs | --no-app | --makepartition | --help]" 1>&2; exit 1; }

TEMP=$(getopt -o 1 -l no-uboot,no-spl,no-kernel,no-rootfs,no-app,makepartition,help -- "$@")
eval set -- "$TEMP"

while true
do
    case "$1" in
        --no-uboot )  skipuboot=1; shift;;
        --no-spl )    skipspl=1; shift;;
        --no-kernel ) skipkernel=1; shift;;
        --no-rootfs ) skiprootfs=1; shift;;
        --no-app )    skipapp=1; shift;;
        --makepartition ) skippartitioning=0; shift;;
        --help )      usage; shift;;
	    -- ) shift; break;;
		* ) break;
    esac
done

#create dirs
[ ! -d update-app ] && mkdir update-app
[ ! -d update-kernel ] && mkdir update-kernel
[ ! -d update-uboot ] && mkdir update-uboot
[ ! -d update-rootfs ] && mkdir update-rootfs
[ ! -d usb-key ] && mkdir usb-key
[ ! -d liveimage ] && mkdir liveimage

#cleanup
rm ./*.bgr 1>/dev/null 2>&1
rm ./*.tar 1>/dev/null 2>&1
rm ./*.gz 1>/dev/null 2>&1
rm ./update-kernel/* 1>/dev/null 2>&1
rm ./update-uboot/* 1>/dev/null 2>&1
rm ./update-rootfs/* 1>/dev/null 2>&1
rm ./usb-key/* 1>/dev/null 2>&1
rm ./update-key/* 1>/dev/null 2>&1
rm ./liveimage/* 1>/dev/null 2>&1

#graphics
echo Building graphics
convert logo-itema-updating.bmp update-splash.bgr
gzip < update-splash.bgr > update-splash.gz

convert logo-itema-update-terminated.bmp update-terminated.bgr
gzip < update-terminated.bgr > update-terminated.gz

#build app update
#----------------
if [ $skipapp = 0 ]; then
echo Building application update
cd update-app
if [ -f app-$APP_VERSION.tar.gz ]; then
  cp app-$APP_VERSION.tar.gz ../$APP_PKG
  checkfile ../$APP_PKG
else
  echo Application update not found: app-$APP_VERSION.tar.gz
fi
cd ..
fi

#build u-boot+SPL update
#-------------------
cd update-uboot
rm ./* 1>/dev/null 2>&1

if [ $skipuboot = 0 ]; then
echo Building u-boot update
#update u-boot
cp ../../$UBOOT_BINARIES/u-boot.img-$UBOOT_VERSION ./u-boot.img
cp ../../$UBOOT_BINARIES/u-boot-silent.img-$UBOOT_VERSION ./u-boot-silent.img
checkfile ./u-boot.img
checkfile ./u-boot-silent.img
fi

if [ $skipspl = 0 ]; then
cp ../../$UBOOT_BINARIES/SPL-$SPL_VERSION ./spl.img
cp ../../$UBOOT_BINARIES/SPL-silent-$SPL_VERSION ./spl-silent.img
checkfile ./spl.img
checkfile ./spl-silent.img
fi

if [[ $skipspl = 0 || $skipuboot = 0 ]]; then
tar czvf ../$UBOOT_PKG *
fi
cd ..


#build kernel update
#-------------------
if [ $skipkernel = 0 ]; then
echo Building kernel update
cd update-kernel
[ -f $KERNEL_PKG ] && rm $KERNEL_PKG
#update kernel
cp ../../$KERNEL_BINARIES/$KERNEL_VERSION/* .
checkfile ./zImage
#copy uboot logo
cp ../logo-itema-loading.bmp ./logo-itema.bmp
tar czvf ../$KERNEL_PKG *
cd ..
fi

#build rootfs update
#-------------------
if [ $skiprootfs = 0 ]; then
cd update-rootfs
echo Building rootfs update
rm ./* 1>/dev/null 2>&1
#update rootfs
cp /data2/developer/yocto_rootfs/$YOCTO_IMAGE.tar.bz2 .
if [ -f $YOCTO_IMAGE.tar.bz2 ]; then
    echo converting yocto rootfs into gzip...
	bunzip2 $YOCTO_IMAGE.tar.bz2
	gzip $YOCTO_IMAGE.tar
	mv $YOCTO_IMAGE.tar.gz ../$ROOTFS_PKG
else
	tar czvf ../$ROOTFS_PKG *
fi
cd ..
fi

cp template-setup.sh setup.sh

#force make partition
if [ $skippartitioning = 0 ]; then
	sed -i 's/mkfs=0/mkfs=1/g' setup.sh
fi

[ -f silent.boot ] && rm silent.boot 
#touch silent.boot 


#build update file
echo Packaging files
tar cvf $UPDATEFILE installPackage.sh setup.sh
tar uvf $UPDATEFILE update-splash.gz
tar uvf $UPDATEFILE update-terminated.gz
[ -f kernel.tar.gz ] && tar uvf $UPDATEFILE kernel.tar.gz
[ -f uboot.tar.gz ] && tar uvf $UPDATEFILE uboot.tar.gz
[ -f app.tar.gz ] && tar uvf $UPDATEFILE app.tar.gz
[ -f rootfs.tar.gz ] && tar uvf $UPDATEFILE rootfs.tar.gz
[ -f silent.boot ] && tar uvf $UPDATEFILE silent.boot

#copy update package
cp $UPDATEFILE ./usb-key/

#copy live image
cp ../$KERNEL_BINARIES/$ROOTFSLIVE_VERSION-live/* ./usb-key/

#cleanup
rm ./*.bgr

echo
echo -e  '\E[1;37mUpdate package is stored in ./usb-key path'
echo -e '\E[1;33mPackages: '
[ $skipuboot = 0 ]  && echo 'U-Boot ' $UBOOT_VERSION
[ $skipspl = 0 ]    && echo 'SPL    ' $SPL_VERSION
[ $skipkernel = 0 ] && echo 'Kernel ' $KERNEL_VERSION
[ $skiprootfs = 0 ] && echo 'Rootfs ' $ROOTFS_VERSION
[ $skipapp = 0 ]    && echo 'App    ' $APP_VERSION
echo
[ $skippartitioning = 0 ] && echo -e '\E[1;32m!!! Partitions will be recreated !!!'; echo;
