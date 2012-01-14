#!/system/bin/sh

for MODULE in `find /system/modules/ -name "*.ko"`
do
    insmod $MODULE
done
