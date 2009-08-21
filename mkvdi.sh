#!/bin/sh
VBoxManage modifyvm KFX --hda none
VBoxManage closemedium disk /Users/kennu/Git/kennu/kfx/kfx.vdi
rm -f kfx.vdi
cat bootloader.img kernel.img > kfx.img
VBoxManage convertfromraw -format VDI kfx.img kfx.vdi
uuid=`VBoxManage showhdinfo kfx.vdi|grep UUID|awk '{print $2}'`
VBoxManage openmedium disk kfx.vdi
echo "New UUID is $uuid"
VBoxManage modifyvm KFX --hda "$uuid"
