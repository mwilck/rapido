#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2017, all rights reserved.
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
. /usr/lib/rapido/zram.sh
. /usr/lib/rapido/nvme.sh

set -x

#### start udevd
ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| /usr/lib/systemd/systemd-udevd --daemon

cat /proc/mounts | grep debugfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t debugfs debugfs /sys/kernel/debug/
fi

modprobe configfs
cat /proc/mounts | grep configfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t configfs configfs /sys/kernel/config/
fi

modprobe nvme-core
modprobe nvme-fabrics
modprobe nvme-loop
modprobe nvmet

for i in $DYN_DEBUG_MODULES; do
	echo "module $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done
for i in $DYN_DEBUG_FILES; do
	echo "file $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done

export_blockdev=$(_zram_hot_add "1G")
[ -b "$export_blockdev" ] || _fatal "$export_blockdev device not available"

SUBSYS=nfmf-test
#UUID=28732221-723c-4900-b794-73919f984fc8

_nvmet_create_loop_port 1

_nvmet_add_subsys ${SUBSYS}
_nvmet_add_namespace ${SUBSYS} 1 ${export_blockdev} ${UUID}
_nvmet_link_subsys_to_port ${SUBSYS} 1

echo "transport=loop,nqn=${SUBSYS}" > /dev/nvme-fabrics || _fatal

N=10
while [[ ! -b /dev/nvme0n1 && $((N--)) -gt 0 ]]; do
    sleep 1
done
[[ -b /dev/nvme0n1 ]] || _fatal "/dev/nvme0n1 did not appear"

set +x

echo "$export_blockdev mapped via NVMe loopback:"
ls /dev/nvme[0-9]*n[0-9]*
