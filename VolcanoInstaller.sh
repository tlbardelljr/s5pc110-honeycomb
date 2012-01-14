#!/bin/sh
# feel free to use, modify, improve, etc

LOG_FILE="/mnt/mmc/log.txt"
> $LOG_FILE # clear log file

# echo message to screen and log file
echo_msg() {
  echo "$@" | tee -a $LOG_FILE > /dev/tty0
  sync
}

# spinner progress
spinner() {
  rm /tmp/kill_spinner
  while [ ! -e /tmp/kill_spinner ]; do
    for i in / - \\ \| ; do
      echo -ne "$i" > /dev/tty0
      sleep 0.05
    done
  done
  echo "done" > /dev/tty0
}

# write new line to log file
newline() {
  echo "" >> $LOG_FILE
  sync
}

kill_spinner() {
  p="$1"
  touch /tmp/kill_spinner
  wait $p
}

if [ -r /mnt/mmc/ROM.inf ]; then
  dos2unix /mnt/mmc/ROM.inf
  . /mnt/mmc/ROM.inf 2>>$LOG_FILE
fi

# Use default values if not set:
SIZE_CACHE=${SIZE_CACHE:-128} # cache partition size
SIZE_DATA=${SIZE_DATA:-1536} # data partition size
SIZE_ROOTFS=${SIZE_ROOTFS:-256} # rootfs partition size
WIPE_DATA="${WIPE_DATA:-true}" # wipe data partition (removes apps)

echo_msg "*********************"
echo_msg "* Volcano Installer *"
echo_msg "*********************"
echo_msg ""

# wait for rcS to exit
sleep 2

cd /

SIZE_128M=134217728
SIZE_256M=268435456
SIZE_2G=2147483648
if [ -e /sys/block/mtdblock4 ]; then
  MTD_SIZE=$(cat /sys/block/mtdblock4/device/size)
  if [ $MTD_SIZE -lt $SIZE_128M ]; then
    NAND_SIZE=128
  elif [ $MTD_SIZE -lt $SIZE_256M ]; then
    NAND_SIZE=256
  elif [ $MTD_SIZE -lt $SIZE_2G ]; then
    NAND_SIZE=2048
  else
    NAND_SIZE=4096
  fi
  echo_msg "NAND size: $NAND_SIZE MB"
else
  echo_msg "No NAND detected"
  NAND_SIZE=0
fi

SIZE_4G=8388608
SIZE_8G=16777216
SIZE_16G=33554432
if [ -e /sys/block/mmcblk0 ]; then
  MMC_SIZE=$(cat /sys/block/mmcblk0/size)
  if [ $MMC_SIZE -lt $SIZE_4G ]; then
    SD_SIZE=4
  elif [ $MMC_SIZE -lt $SIZE_8G ]; then
    SD_SIZE=8
  elif [ $MMC_SIZE -lt $SIZE_16G ]; then
    SD_SIZE=16
  else
    SD_SIZE=32
  fi
  echo_msg "Internal SD size: $SD_SIZE GB"
else
  echo_msg "No internal SD detected. Aborting installation!"
  sleep 5
  reboot -f
fi

if [ -e /sys/block/mtdblock5 ]; then
  mkdir /mnt/param
  mount -t yaffs2 /dev/mtdblock5 /mnt/param 2>>$LOG_FILE
  
  if [ -r /mnt/mmc/mac.txt ]; then
    # Update softmac
    MAC_ADDRESS="$(cat /mnt/mmc/mac.txt)"
    case $MAC_ADDRESS in 
      ??:??:??:??:??:??)
        # Valid softmac
        umount /mnt/param 2>>$LOG_FILE
        flash_eraseall /dev/mtd5 2>>$LOG_FILE
        mount -t yaffs2 /dev/mtdblock5 /mnt/param 2>>$LOG_FILE
        echo "$MAC_ADDRESS" > /mnt/param/softmac 2>>$LOG_FILE
        sync
      ;;
      *)
        echo_msg "Invalid softmac in mac.txt"
      ;;
    esac
  fi

  [ -r /mnt/param/softmac ] && echo_msg "MAC address: $(cat /mnt/param/softmac)"
fi

if [ -e /sys/block/mmcblk1 ]; then
  echo_msg "Dual SD found"
  FW_ROOT="/mnt/mmc"
else
  echo_msg "Single SD found"
  echo_msg ""

  echo_msg -n "Copying installation files into RAM... " ; spinner &
  newline
  mkdir /ramdisk
  mount -t tmpfs -o size=90% tmpfs /ramdisk
  cp -f $LOG_FILE /ramdisk/log.txt ; sync
  LOG_FILE="/ramdisk/log.txt"
  [ -d /mnt/mmc/firmware ] && cp -rf /mnt/mmc/firmware /ramdisk/ 2>>$LOG_FILE
  [ -d /mnt/mmc/patches ] && cp -rf /mnt/mmc/patches /ramdisk/ 2>>$LOG_FILE
  [ -d /mnt/mmc/customer ] && cp -rf /mnt/mmc/customer /ramdisk/ 2>>$LOG_FILE
  [ -d /mnt/mmc/utmodules ] && cp -rf /mnt/mmc/utmodules /ramdisk/ 2>>$LOG_FILE
  [ -d /mnt/mmc/fat ] && cp -rf /mnt/mmc/fat /ramdisk/ 2>>$LOG_FILE
  [ -r /mnt/mmc/fixperms.sh ] && cp -f /mnt/mmc/fixperms.sh /ramdisk/ 2>>$LOG_FILE
  [ -r /mnt/mmc/bootanimation.zip ] && cp -f /mnt/mmc/bootanimation.zip /ramdisk/ 2>>$LOG_FILE
  [ -r /mnt/mmc/pic.gif ] && cp -f /mnt/mmc/pic.gif /ramdisk/ 2>>$LOG_FILE
  [ -r /mnt/mmc/tune2fs.static ] && cp -f /mnt/mmc/tune2fs.static /ramdisk/ 2>>$LOG_FILE
  FW_ROOT="/ramdisk"  
  umount /mnt/mmc 2>>$LOG_FILE
  sync
  kill_spinner $!
fi

echo_msg ""

if [ $NAND_SIZE -gt 0 ]; then
  echo_msg -n "Formatting NAND... " ; spinner &
  newline

  ubidetach /dev/ubi_ctrl -m 4
  ubidetach /dev/ubi_ctrl -m 3
  flash_eraseall /dev/mtd4 2>>$LOG_FILE
  ubiattach /dev/ubi_ctrl -m 4 -d 0 2>>$LOG_FILE

  if [ $NAND_SIZE -eq 4096 ]; then
    ubimkvol /dev/ubi0 -n 0 -N rootfs -s 256MiB 2>>$LOG_FILE
    ubimkvol /dev/ubi0 -n 1 -N userdata -s 1536MiB 2>>$LOG_FILE
    ubimkvol /dev/ubi0 -n 2 -N cache -s 128MiB 2>>$LOG_FILE
    ubimkvol /dev/ubi0 -n 3 -N flash -m 2>>$LOG_FILE
  elif [ $NAND_SIZE -eq 2048 ]; then
    ubimkvol /dev/ubi0 -n 0 -N rootfs -s 256MiB 2>>$LOG_FILE
    ubimkvol /dev/ubi0 -n 1 -N userdata -s 512MiB 2>>$LOG_FILE
    ubimkvol /dev/ubi0 -n 2 -N cache -s 128MiB 2>>$LOG_FILE
    ubimkvol /dev/ubi0 -n 3 -N flash -m 2>>$LOG_FILE
  else
    ubimkvol /dev/ubi0 -n 0 -N rootfs -m 2>>$LOG_FILE
  fi

  kill_spinner $!
fi

echo_msg -n "Formatting internal SD... " ; spinner &
newline

if [ "$WIPE_DATA" = "true" ]; then
  # Erase MBR
  #dd if=/dev/zero of=/dev/mmcblk0 bs=512 count=1 2>>$LOG_FILE
  
  sd_fdisk /dev/mmcblk0 2>>$LOG_FILE
  dd if=sd_mbr.dat of=/dev/mmcblk0 2>>$LOG_FILE
  sync

  # starting cylinders
  START_CACHE=35 # leave some space at the beginning to be used as an embedding area on sd-only systems
  START_DATA=$(($START_CACHE + $SIZE_CACHE + 1))
  START_ROOTFS=$(($START_DATA + $SIZE_DATA + 1))
  START_SDCARD=$(($START_ROOTFS + $SIZE_ROOTFS + 1))

  # Repartition internal SD
  fdisk -H 64 -S 32 /dev/mmcblk0 <<EOF 2>>$LOG_FILE
o
n
p
2
$START_CACHE
+$SIZE_CACHE
n
p
3
$START_DATA
+$SIZE_DATA
n
p
4
$START_ROOTFS
+$SIZE_ROOTFS
n
p
$START_SDCARD

t
1
c
w
EOF

  mkfs.ext4 -m 1 /dev/mmcblk0p3 #data
fi

# Format partitions:
mkdosfs -n sdcard /dev/mmcblk0p1 #sdcard
mkfs.ext4 -m 1 /dev/mmcblk0p2 #cache
mkfs.ext4 /dev/mmcblk0p4 # system

if [ -r $FW_ROOT/tune2fs.static ]; then
  cp -f $FW_ROOT/tune2fs.static /sbin/tune2fs
  chmod 0755 /sbin/tune2fs 
  # writeback mode gives better performance and reduces writes to the sdcard, at a slight cost of reliability:
  tune2fs -o journal_data_writeback /dev/mmcblk0p2
  tune2fs -o journal_data_writeback /dev/mmcblk0p3
  tune2fs -o journal_data_writeback /dev/mmcblk0p4
fi

kill_spinner $!

# mount partitions:

mkdir /mnt/root
if [ $NAND_SIZE -gt 0 ]; then
  mount -t ubifs ubi0:rootfs /mnt/root 2>>$LOG_FILE
  
  if [ $NAND_SIZE -eq 128 ]; then
    # 128MB NAND is too small, move /system to sdcard)
    mkdir -p /mnt/root/system
    mount -t ext4 /dev/mmcblk0p4 /mnt/root/system 2>>$LOG_FILE
  fi

else
  mount -t ext4 /dev/mmcblk0p4 /mnt/root 2>>$LOG_FILE
fi

mkdir /mnt/data
if [ $NAND_SIZE -gt 256 ]; then
  # mount nand data partition
  mount -t ubifs ubi0:userdata /mnt/data 2>>$LOG_FILE
else
  # mount sd data partition
  mount -t ext4 /dev/mmcblk0p3 /mnt/data 2>>$LOG_FILE
fi

rm -r /mnt/data/dalvik-cache 2> /dev/null # clear dalvik-cache

mkdir /mnt/sdcard
mount -t vfat /dev/mmcblk0p1 /mnt/sdcard 2>>$LOG_FILE

echo_msg ""

echo_msg "Updating firmware:"

if [ -r $FW_ROOT/firmware/utv210_root.tgz ]; then
  echo_msg -n "  * Installing system... " ; spinner &
  newline
  tar xvzf $FW_ROOT/firmware/utv210_root.tgz -C /mnt/root/ 2>>$LOG_FILE

  # Delete any su symlinks for now
  find /mnt/root -type l -name "su" -exec rm {} \; 2>>$LOG_FILE
  
  # Enable root access:
  if [ -r /mnt/root/system/bin/su ]; then
    # found su in bin, link in xbin
    chown 0:0 /mnt/root/system/bin/su 2>>$LOG_FILE
    chmod 6755 /mnt/root/system/bin/su 2>>$LOG_FILE
    ln -sf /system/bin/su /mnt/root/system/xbin/su 2>>$LOG_FILE
  elif [ -r /mnt/root/system/xbin/su ]; then
    # found su in xbin, link in bin
    chown 0:0 /mnt/root/system/xbin/su 2>>$LOG_FILE
    chmod 6755 /mnt/root/system/xbin/su 2>>$LOG_FILE
    ln -sf /system/xbin/su /mnt/root/system/bin/su 2>>$LOG_FILE
  fi
  
  chown 0:0 /mnt/root/system/app/?uper?ser.apk 2>>$LOG_FILE
  chmod 0644 /mnt/root/system/app/?uper?ser.apk 2>>$LOG_FILE

  [ -d $FW_ROOT/customer ] && cp -rf $FW_ROOT/customer/* /mnt/root/ 2>>$LOG_FILE
  
  [ -d $FW_ROOT/utmodules ] && cp -rf $FW_ROOT/utmodules /mnt/root/system/ 2>>$LOG_FILE

  [ -r /mnt/param/softmac ] && cp -f /mnt/param/softmac /mnt/root/system/wifi/ 2>>$LOG_FILE

  if [ -r $FW_ROOT/bootanimation.zip ]; then
    cp -f $FW_ROOT/bootanimation.zip /mnt/root/system/media/ 2>>$LOG_FILE
  elif [ -r $FW_ROOT/pic.gif ]; then
    cp -f $FW_ROOT/pic.gif /mnt/root/system/media/ 2>>$LOG_FILE
  fi

  sync
  kill_spinner $!
else
  echo_msg "  * utv210_root.tgz not found. Aborting installation!"
  sleep 5
  reboot -f
fi

if [ -r $FW_ROOT/firmware/utv210_userdata.tgz ]; then
  echo_msg -n "  * Installing userdata... " ; spinner &
  newline
  tar xvzf $FW_ROOT/firmware/utv210_userdata.tgz -C /mnt/data/ 2>>$LOG_FILE
  sync
  kill_spinner $!
fi

if [ -d $FW_ROOT/fat ]; then
  echo_msg -n "  * Copying files to mass storage... " ; spinner &
  newline
  cp -rf $FW_ROOT/fat/* /mnt/sdcard/ 2>>$LOG_FILE
  sync
  kill_spinner $!
fi

if [ -d $FW_ROOT/patches ]; then
  echo_msg -n "  * Applying patches... " ; spinner &
  newline
  for patch in $(find $FW_ROOT/patches -name "*patch.tgz") ; do
    echo "    -- $(basename $patch)" >> $LOG_FILE
    tar xvzf $patch -C /mnt/root/ 2>>$LOG_FILE
    ( cd /mnt/root
      [ -r init.rc.append ] && cat init.rc.append >> init.rc 2>>$LOG_FILE
      [ -r init.smdkv210.rc.append ] && cat init.smdkv210.rc.append >> init.smdkv210.rc 2>>$LOG_FILE
      [ -r build.prop.append ] && cat build.prop.append >> system/build.prop 2>>$LOG_FILE
      [ -r doinst.sh ] && . doinst.sh 2>>$LOG_FILE
      rm *.append doinst.sh 2> /dev/null
    )
  done
  sync
  kill_spinner $!
fi

# patch init.rc to fix mounts (if necessary):
if [ $NAND_SIZE -gt 128 -o $NAND_SIZE -eq 0 ]; then
  # no need to mount /system here
  sed -ie '/mmcblk0p4/d' /mnt/root/init.rc 2>>$LOG_FILE
fi

if [ $NAND_SIZE -gt 256 ]; then
  # fix cache mount
  sed -ie 's@ext4 /dev/block/mmcblk0p2@ubifs ubi0:cache@' /mnt/root/init.rc 2>>$LOG_FILE
  # fix userdata mount
  sed -ie 's@ext4 /dev/block/mmcblk0p3@ubifs ubi0:userdata@' /mnt/root/init.rc 2>>$LOG_FILE
fi

if [ $NAND_SIZE -ge 2048 ]; then
  echo_msg -n "Creating NandDisk... " ; spinner &
  newline
  mkdir /mnt/nanddisk
  mount -t ubifs ubi0:flash /mnt/nanddisk 2>>$LOG_FILE
  dd if=/dev/zero of=/mnt/nanddisk/vfat.img bs=1M count=0 seek=1100 2>>$LOG_FILE
  mkdosfs -n NandDisk /mnt/nanddisk/vfat.img
  umount /mnt/nanddisk
  sync
  kill_spinner $!
fi

if [ -r $FW_ROOT/fixperms.sh ]; then
  echo_msg -n "  * Fixing permissions... " ; spinner &
  newline
  . $FW_ROOT/fixperms.sh
  sync
  kill_spinner $!
fi

echo_msg ""
echo_msg "Installation finished. Shutting down."

cp -f $LOG_FILE /mnt/sdcard/log.txt

umount /mnt/root/system
umount /mnt/root
umount /mnt/data
umount /mnt/param
umount /mnt/sdcard

sync
reboot
