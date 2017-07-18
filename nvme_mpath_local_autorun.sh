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

modprobe dm-multipath
multipathd -d -v 3 &>/tmp/multipathd.log &

NGUID=f1499554-307d-46c1-b450-2ab05083a014
_nvmet_create_loop_port 1
_nvmet_add_subsys test1
_nvmet_add_namespace test1 1 ${export_blockdev} $NGUID
_nvmet_add_namespace test1 2 ${export_blockdev} $NGUID
_nvmet_add_subsys test2
_nvmet_add_namespace test2 1 ${export_blockdev} $NGUID
_nvmet_add_namespace test2 2 ${export_blockdev} $NGUID
_nvmet_link_subsys_to_port test1 1
_nvmet_link_subsys_to_port test2 1

sleep 1
udevadm monitor --env &> /tmp/udev-monitor.log &

echo "transport=loop,nqn=test1" > /dev/nvme-fabrics || _fatal
echo "transport=loop,nqn=test2" > /dev/nvme-fabrics || _fatal

set +x

sleep 4
echo "=== multipathd logs in /tmp/multipathd.log ==="
multipathd show topology
