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

RAPIDO_DIR="$(realpath -e ${0%/*})"
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args
_rt_require_nvme_cli
_rt_require_lib "libkeyutils.so.1"
_rt_require_multipath

# Pretend to dracut that root was set correctly
# (we don't want to mount root!)
HOOK=$(mktemp /tmp/nvme_rdma.XXXXXX)
[ -n "$HOOK" ] || _fatal "failed to create temp file"
cat >"$HOOK" <<\EOF
#! /bin/sh
: ${root:=NONE}
rootok=1
EOF

function get_perl_deps() {
    scandeps.pl -B "$1"  | \
	while read x rest; do
	    [[ $x ]] || continue
	    [[ a"$x" = "a'feature'" ]] && continue
	    perl -M${x//\'/} -e 'print "\t$INC{$_} " for keys %INC;'
	done
}
RXE_DEPS="ifconfig touch ibv_devinfo $(get_perl_deps $(which rxe_cfg))"

get_perl_sos () {
    for pm in "$@"; do
	case $pm in
	    *linux-thread-multi/*);;
	    *) continue;;
	esac
	bs=${pm#*linux-thread-multi/}
	dr=${pm%$bs}
	echo -n "$(ls $dr/auto/${bs%.pm}/*.so 2>/dev/null) "
    done
}
RXE_DEPS="$RXE_DEPS $(get_perl_sos $RXE_DEPS)"

rm -f $DRACUT_OUT
"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs killall insmod dhclient dhclient-script \
		   rxe_cfg $LIBS_INSTALL_LIST rdma_server rdma_client \
		   ethtool netstat \
		   /etc/libibverbs.d/rxe.driver \
		   /usr/lib64/libibverbs/librxe-rdmav16.so \
		   $RXE_DEPS
		   " \
	--include "$RAPIDO_DIR/nvme_rdma_mpath_autorun.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--include "$HOOK" "/lib/dracut/hooks/cmdline/99-fake-ok.sh" \
	--include "$RAPIDO_DIR/lib/vlan.sh" /usr/lib/rapido/vlan.sh \
	--include "$RAPIDO_DIR/lib/zram.sh" /usr/lib/rapido/zram.sh \
	--include "$RAPIDO_DIR/lib/nvme.sh" /usr/lib/rapido/nvme.sh \
	--add-drivers "nvme-core nvme-fabrics nvme-rdma nvmet nvmet-rdma \
		       rdma_rxe zram lzo ib_core ib_uverbs rdma_ucm crc32 \
		       8021q bfq cfq-iosched deadline-iosched kyber-iosched mq-deadline" \
	--modules "bash base network ifcfg multipath" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT

rm -f "$HOOK"
_rt_xattr_cmdline_set $DRACUT_OUT "log_buf_len=1M e1000.RxDescriptors=512"

_rt_xattr_qemu_args_set \
    $DRACUT_OUT \
    "-object filter-dump,id=dump0,netdev=%NETDEV%,file=/tmp/rap%VM%.pcap"
