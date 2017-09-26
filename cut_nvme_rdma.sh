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

# Pretend to dracut that root was set correctly
# (we don't want to mount root!)
HOOK=$(mktemp /tmp/nvme_rdma.XXXXXX)
[ -n "$HOOK" ] || _fatal "failed to create temp file"
cat >"$HOOK" <<\EOF
#! /bin/sh
: ${root:=NONE}
rootok=1
EOF

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs killall insmod \
		   $LIBS_INSTALL_LIST" \
	--include "$RAPIDO_DIR/nvme_rdma_autorun.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--include "$HOOK" "/lib/dracut/hooks/cmdline/99-fake-ok.sh" \
	--add-drivers "nvme-core nvme-fabrics nvme-rdma nvmet nvmet-rdma \
		       rdma_rxe zram lzo ib_core ib_uverbs rdma_ucm crc32" \
	--modules "bash base network ifcfg" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT

rm -f "$HOOK"
_rt_xattr_cmdline_set $DRACUT_OUT "log_buf_len=4M"
_rt_xattr_qemu_args_set \
    $DRACUT_OUT \
    "-object filter-dump,id=dump0,netdev=%NETDEV%,file=/tmp/rap%VM%.pcap"
