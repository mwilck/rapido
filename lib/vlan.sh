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

function _add_vlan() {
	local if=$1 id=$2
	ip link add link $if name $if.$id type vlan id $id
	ip link set $if.$id up mtu ${BR_MTU:-9000}
	dhclient -4 $if.$id
}
