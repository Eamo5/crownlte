#!/bin/bash
set -e

# check if kernel image exists
if [ ! -f arch/arm64/boot/Image ]; then
  echo "ERROR: Kernel has not been built yet."
  exit 1
fi

# determine variables
MODEL_NAME=$(find arch/arm64/configs -type f -prune -print -quit | cut -d'-' -f2 | cut -d'_' -f1)

# fetch latest anykernel2 zip
rm -rf AnyKernel2
curl -sLO https://github.com/osm0sis/AnyKernel2/archive/master.zip
unzip -q master.zip
mv AnyKernel2-master AnyKernel2
rm -rf master.zip AnyKernel2/modules AnyKernel2/patch AnyKernel2/ramdisk

# set anykernel2 params
sed -i "s/block=.*/block=auto/" AnyKernel2/anykernel.sh
sed -i "s/is_slot_device=.*/is_slot_device=auto/" AnyKernel2/anykernel.sh
sed -i "s/device\.name1=.*/device.name1=${MODEL_NAME}/" AnyKernel2/anykernel.sh
sed -i "s/kernel\.string=.*/kernel.string=EnduranceKernel/" AnyKernel2/anykernel.sh
sed -i "/device\.name[2-5]=/d" AnyKernel2/anykernel.sh

# add additional files
cp -fR arch/arm64/boot/anykernel2/* AnyKernel2/

# remove template script
sed -i "/## AnyKernel install/,/## end install/d" AnyKernel2/anykernel.sh

# write our install script
cat <<EOF >> AnyKernel2/anykernel.sh
# dump boot.img to split_img/
dump_boot;

# switch split_img/ dir
cd ../split_img/;

# split dtb image to dtb files
../tools/split-appended-dtb boot.img-dtb && rm -f boot.img-dtb kernel;

# decompile dtb files to dts files
for f in \$(ls *.dtb); do
  ../tools/dtc -I dtb -O dts -o "\$(basename "\${f}" .dtb).dts" "\${f}" && rm -f "\${f}";
done

# apply changes needed for battery profiles
if ps | grep -i overclock | grep -v grep; then
  ui_print "Battery Profile: Overclock";
  for f in \$(ls *.dts); do
    sed -i 's/console=ram/cpu_max_c1=2002000 cpu_max_c2=2964000 console=ram/g' "\${f}";
    sed -i 's/upscale_ratio_table = < 80 1248000 90 1456000 95 >;/upscale_ratio_table = < 80 >;/g' "\${f}";
    sed -i 's/upscale_ratio_table = < 80 1261000 90 >;/upscale_ratio_table = < 80 >;/g' "\${f}";
    sed -i 's/quad_freq = <1794000>;/quad_freq = <2002000>;/g' "\${f}";
    sed -i 's/triple_freq = <1794000>;/triple_freq = <2002000>;/g' "\${f}";
    sed -i 's/dual_freq = <2314000>;/dual_freq = <2496000>;/g' "\${f}";
  done
elif ps | grep -i underclock | grep -v grep; then
  ui_print "Battery Profile: Underclock";
  for f in \$(ls *.dts); do
    sed -i 's/quad_freq = <1794000>;/quad_freq = <1586000>;/g' "\${f}";
  done
else
  ui_print "Battery Profile: Balanced";
fi

# compile dtb
for f in \$(ls *.dts); do
  ../tools/dtc -I dts -O dtb -o "\$(basename "\${f}" .dts).dtb" "\${f}" && rm -f "\${f}";
done

# concatenate dtb files
cat *.dtb > boot.img-dtb;

# switch back to previous directory
cd -;

# add init.local.rc init file
insert_line init.rc 'init.local.rc' after 'init.wifi.rc' 'import /init.local.rc';

# patch fstab to make encryption optional
patch_fstab fstab.samsungexynos9810 USERDATA ext4 options 'forceencrypt=footer' 'encryptable=footer';

# fix bootloader unlock bug
remove_line init.samsungexynos9810.rc '/dev/block/steady';
remove_line init.samsungexynos9810.rc '/dev/block/persistent';

# write boot.img
write_boot;
EOF

# copy kernel image
cp -f arch/arm64/boot/Image AnyKernel2/zImage

# compress zip
( cd AnyKernel2 ; zip -q -r9 ../AnyKernel2.zip * -x .git README.md *placeholder )

# remove anykernel2 directory
rm -rf AnyKernel2/

# write output
echo "ZIP written to $(pwd)/AnyKernel2.zip"
