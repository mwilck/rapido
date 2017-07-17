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

function _zram_hot_add() {
	local zram_size="$1"

	[ -d /sys/module/zram ] \
	    || modprobe zram num_devices="0" \
	    ||  {
		echo  "failed to load zram module" >&2
		return 1
	    }

	[ -e /sys/class/zram-control/hot_add ] \
	    || {
	    echo "zram hot_add sysfs path missing (old kernel?)" >&2
	    return 1
	}

	local zram_num=$(cat /sys/class/zram-control/hot_add) \
	    || {
	    echo  "zram hot add failed" >&2
	    return 1
	}
	local zram_dev="/dev/zram${zram_num}"

	echo "$zram_size" > \
		/sys/devices/virtual/block/zram${zram_num}/disksize \
	    || {
	    echo "failed to set size for $zram_dev" >&2
	    return 1
	}
	echo "$zram_dev"
	return 0
}
