#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016, all rights reserved.
#
# This library is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation; either version 2.1 of the License, or
# (at your option) version 3.
#
# This library is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.

if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

set -x

lio_cfgfs="/sys/kernel/config/target/"
fabric_uuid=$(uuidgen |sed "s#.*-##g")
nexus_uuid=$(uuidgen |sed "s#-##g")
nexus_wwn="naa.${nexus_uuid}"
lu_uuid=$(uuidgen |sed "s#.*-##g")
lu_num=0
lu_name="tcmu_rbd_lu"

tcmu_dev_conf="rbd/${CEPH_RBD_POOL}/${CEPH_RBD_IMAGE}"
tcmu_dev_size="$(( $CEPH_RBD_IMAGE_MB * 1024 * 1024 ))"

ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| /usr/lib/systemd/systemd-udevd --daemon

cat /proc/mounts | grep debugfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t debugfs debugfs /sys/kernel/debug/
fi

cat /proc/mounts | grep configfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t configfs configfs /sys/kernel/config/
fi

modprobe target_core_user || _fatal "failed to load LIO kernel module"
modprobe tcm_loop || _fatal "failed to load LIO kernel module"

for i in $DYN_DEBUG_MODULES; do
	echo "module $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done
for i in $DYN_DEBUG_FILES; do
	echo "file $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done

ln -s /lib64/librbd.so /lib64/librbd.so.1
ln -s /lib64/librados.so /lib64/librados.so.2

sed -i "s#keyring = .*#keyring = /etc/ceph/keyring#g; \
	s#admin socket = .*##g; \
	s#run dir = .*#run dir = /var/run/#g; \
	s#log file = .*#log file = /var/log/\$name.\$pid.log#g" \
	/etc/ceph/ceph.conf

/bin/tcmu-runner -d --handler-path /lib64/ &

[ -d $lio_cfgfs ] \
	|| _fatal "$lio_cfgfs not present - LIO kernel modules not loaded?"
mkdir -p ${lio_cfgfs}/core/user_0/${lu_name} \
	||  _fatal "failed to create tcmu backstore"
echo "dev_config=${tcmu_dev_conf},dev_size=${tcmu_dev_size}" \
			> ${lio_cfgfs}/core/user_0/${lu_name}/control \
			|| _fatal "LIO control file I/O failed"
echo 1 > ${lio_cfgfs}/core/user_0/${lu_name}/enable

# loopback fabric
mkdir -p ${lio_cfgfs}/loopback/naa.${fabric_uuid}/tpgt_0/lun/lun_${lu_num} \
	||  _fatal "failed to create LUN for tcmu backstore"
echo ${nexus_wwn} > ${lio_cfgfs}/loopback/naa.${fabric_uuid}/tpgt_0/nexus
ln -s ${lio_cfgfs}/core/user_0/${lu_name}/ \
  ${lio_cfgfs}/loopback/naa.${fabric_uuid}/tpgt_0/lun/lun_${lu_num}/${lu_uuid} \
	|| _fatal "failed to create LUN symlink"

set +x
