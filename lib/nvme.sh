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

_NVMET_CFS="/sys/kernel/config/nvmet/"

function _nvmet_add_subsys() {
	local subsys=$1
	mkdir -p ${_NVMET_CFS}/subsystems/${subsys} || {
	    echo "failed to create nvmet subsys $subsys" >&2
	    return 1
	}
	echo 1 > ${_NVMET_CFS}/subsystems/${subsys}/attr_allow_any_host || {
	    echo "failed to set allow_any_host for $subsys" >&2
	    return 1
	}
}

function _nvmet_add_namespace() {
	local subsys=$1
	local nsid=$2
	local blockdev=$3
	local uuid=$4
	[[ -d ${_NVMET_CFS}/subsystems/${subsys} ]] || {
	    echo "subsys $subsys does not exist" >&2
	    return 1
	}
	mkdir -p ${_NVMET_CFS}/subsystems/${subsys}/namespaces/${nsid} || {
	    echo "failed to create namespace $nsid for $subsys" >&2
	    return 1
	}
	echo -n $blockdev > \
	     ${_NVMET_CFS}/subsystems/${subsys}/namespaces/${nsid}/device_path || {
	    echo "failed to set device path for $subsys:$nsid" >&2
	    return 1
	}
	[ -z "$uuid" ] \
	    || echo -n "$uuid" > \
		    ${_NVMET_CFS}/subsystems/${subsys}/namespaces/${nsid}/device_nguid \
	    || {
		echo "failed to set uuid for $subsys:$nsid" >&2
		return 1
	    }
	echo -n 1 \
	     > ${_NVMET_CFS}/subsystems/${subsys}/namespaces/${nsid}/enable \
	    || {
	    echo "failed to enable $subsys:$nsid" >&2
	    return 1
	}
	return 0
}

function _nvmet_create_loop_port() {
	local port=$1
	mkdir ${_NVMET_CFS}/ports/${port} \
	    || _fatal "failed to create nvmet port $port"
	echo loop >${_NVMET_CFS}/ports/${port}/addr_trtype \
	    || _fatal "failed to set addr_trtype=loop for port $port"
}

function _nvmet_link_subsys_to_port() {
	local subsys=$1
	local port=$2
	[ -e ${_NVMET_CFS}/ports/${port}/subsystems/${subsys} ] || \
	    ln -s ${_NVMET_CFS}/subsystems/${subsys} \
	       ${_NVMET_CFS}/ports/${port}/subsystems/${subsys} || {
		echo "failed to link subsys $subsys to port $port" >&2
		return 1
	    }
	return 0
}
