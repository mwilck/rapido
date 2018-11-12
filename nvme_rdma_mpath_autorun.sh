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
. /usr/lib/rapido/vlan.sh
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

ip link set eth0 mtu ${BR_MTU:-9000}
#sleep 5 # give the network stack some time

# Module crc32 is ambiguous on some kernels (kernel/lib and kernel/crypto)
# MUST load the crypto/crc32 module like this, all else fails.
##insmod /lib/modules/*/kernel/crypto/crc32.ko
modprobe ib_core
modprobe ib_uverbs
modprobe rdma_ucm
modprobe rdma-rxe
modprobe nvme-core  #multipath=0
modprobe nvme-fabrics
modprobe nvme-rdma
modprobe nvmet-rdma
modprobe nvmet
modprobe zram num_devices="0"
modprobe dm-multipath

for i in $DYN_DEBUG_MODULES; do
	echo "module $i +pf" > /sys/kernel/debug/dynamic_debug/control
done
for i in $DYN_DEBUG_FILES; do
	echo "file $i +pf" > /sys/kernel/debug/dynamic_debug/control
done
# echo 8 >/proc/sys/kernel/printk

# These flood the log with state machine messages
#for i in rxe_comp.c rxe_resp.c; do
#	echo "file $i format \"state = %s\" -pf" > /sys/kernel/debug/dynamic_debug/control
#done


nvmet_cfs="/sys/kernel/config/nvmet"
SUBSYS="rapnv"
#UUID=28732221-723c-4900-b794-73919f984fc8

mkdir -p /var/lib/dhcp

cat >/etc/multipath.conf <<EOF
defaults {
	 find_multipaths greedy
}
EOF

echo eth0 > /sys/module/rdma_rxe/parameters/add

nvl=0
while [[ $nvl -lt ${#VLANS[@]} ]]; do
	_add_vlan eth0 $nvl
	# echo eth0.$nvl > /sys/module/rdma_rxe/parameters/add
	: $((nvl++))
done

ip link show eth0 | grep $MAC_ADDR1
if [ $? -eq 0 ]; then
	BLKDEV=$(_zram_hot_add "1G")
	[ -b "$BLKDEV" ] || \
		_fatal "$BLKDEV device not available"
	_nvmet_add_subsys ${SUBSYS} || \
		_fatal
	_nvmet_add_namespace ${SUBSYS} 1 ${BLKDEV}

	np=1
	for vl in ${VLANS[@]}; do
		_nvmet_create_rdma_port $np ${vl}${IP_ADDR1#$SUBNET}
		_nvmet_link_subsys_to_port ${SUBSYS} $np
		: $((np++))
	done
	#rping -a 192.168.201.101 -s -d -S 128 &
fi

ip link show eth0 | grep $MAC_ADDR2
if [ $? -eq 0 ]; then
    #rping -c -a 192.168.201.101 -C 10 -S 128 -d
	for vl in ${VLANS[@]}; do
	    nvme discover -t rdma -a ${vl}${IP_ADDR1#$SUBNET} -s 4420
	    nvme connect -t rdma -a ${vl}${IP_ADDR1#$SUBNET} -s 4420 -n ${SUBSYS} # || _fatal
	done
	udevadm settle
#	nvmedev=$(ls /dev/ | grep -Eo 'nvme[0-9]n[0-9]')
#	echo nvmedev=$nvmedev#
	multipathd -d -v2 &>/tmp/mp.log &
	sleep 2
	multipath -ll
	multipathd show maps
#	multipathd show paths
#	cat /tmp/mp.log
#	rxe_cfg add eth0
#	rxe_cfg status
#	rdma_client -s ${IP_ADDR1}
#	rdma_client -s ${VLANS[0]}${IP_ADDR1#$SUBNET}
	dd if=/dev/zero of=/dev/nvme0n1 bs=4M count=32 oflag=direct
fi

#modprobe ib700wdt timeout=15 nowayout=1
#echo >/dev/watchdog
#set +x
#N=0
#while true; do echo $((++N)); sleep 1; done

