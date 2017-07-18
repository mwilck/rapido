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
_rt_require_lib "libkeyutils.so.1"
_rt_require_multipath

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs \
		   $LIBS_INSTALL_LIST" \
	--include "$RAPIDO_DIR/nvme_mpath_local_autorun.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--include "$RAPIDO_DIR/lib/zram.sh" /usr/lib/rapido/zram.sh \
	--include "$RAPIDO_DIR/lib/nvme.sh" /usr/lib/rapido/nvme.sh \
	--add-drivers "nvme-core nvme-fabrics nvme-loop nvmet zram lzo" \
	--modules "bash base multipath" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT

_rt_xattr_vm_networkless_set "$DRACUT_OUT"
