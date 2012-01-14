#!/bin/sh
# Workaround to allow unmounting of /mnt/mmc (needed when installing from internal SD)
#
# This script is called by rcS, which is keeping this folder open, so we'll fork to the background to allow it to exit.

cp -f VolcanoInstaller.sh /tmp/
chmod 0755 /tmp/VolcanoInstaller.sh

exec /tmp/VolcanoInstaller.sh &
