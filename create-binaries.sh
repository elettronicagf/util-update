mkdir binaries
cd binaries

mkdir rootfs
mkdir app
mkdir mbu-fw

ln -s ../../kernel/binaries/ kernel
ln -s ../../u-boot/binaries/ u-boot

cd rootfs
ln -s /data2/developer/yocto_rootfs/0510mbugrfimx6-full-*.tar.bz2 .
