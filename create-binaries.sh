mkdir binaries
cd binaries

mkdir rootfs
mkdir app
mkdir mbu-fw

ln -s ../../kernel/binaries/ kernel
ln -s ../../u-boot/binaries/ u-boot

cd rootfs
ln -s /data2/developer/yocto_rootfs/0510mbugrfimx6-full-1.0.tar.bz2 .
ln -s /data2/developer/yocto_rootfs/0510mbugrfimx6-full-2.0.tar.bz2 .
ln -s /data2/developer/yocto_rootfs/0510mbugrfimx6-full-3.0.tar.bz2 .

cd ../app
ln -s ../../../app/recover/binaries/recover-1.0.tar.bz2 .
ln -s ../../../app/recover/binaries/recover-1.1.tar.bz2 .
