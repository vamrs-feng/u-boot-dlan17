#!/usr/bin/env bash

if [[ ! -v ERROR_REQUIRE_FILE ]]; then
	readonly ERROR_REQUIRE_FILE=-3
fi
if [[ ! -v ERROR_ILLEGAL_PARAMETERS ]]; then
	readonly ERROR_ILLEGAL_PARAMETERS=-4
fi
if [[ ! -v ERROR_REQUIRE_TARGET ]]; then
	readonly ERROR_REQUIRE_TARGET=-5
fi

is_ufs_device() {
	local block device_path host proc_name

	[[ -b "$1" ]] || return 1
	block="$(basename "$(realpath "$1")")"
	device_path="$(realpath "/sys/class/block/$block/device")"

	if [[ "$device_path" =~ /(host[0-9]+)(/|$) ]]; then
		host="${BASH_REMATCH[1]}"
		proc_name="/sys/class/scsi_host/$host/proc_name"
		[[ -r "$proc_name" ]] && [[ "$(<"$proc_name")" == "ufshcd" ]]
	else
		return 1
	fi
}

build_spinor() {
	rm -f /tmp/spi.img /tmp/gpt.img
	truncate -s 8M /tmp/spi.img
	if [[ -f "$SCRIPT_DIR/u-boot-sunxi-with-spl.bin" ]]; then
		dd conv=notrunc,fsync if="$SCRIPT_DIR/u-boot-sunxi-with-spl.bin" of=/tmp/spi.img bs=512
	else
        echo "Missing U-Boot binary!" >&2
        return "$ERROR_REQUIRE_FILE"
	fi
}

update_bootloader() {
	local DEVICE=$1

	if [[ -f "$SCRIPT_DIR/u-boot-sunxi-with-spl.bin" ]]; then
		if is_ufs_device "$DEVICE"; then
			dd conv=notrunc,fsync if="$SCRIPT_DIR/u-boot-sunxi-with-spl.bin" of="$DEVICE" bs=512 seek=2064
		else
			dd conv=notrunc,fsync if="$SCRIPT_DIR/u-boot-sunxi-with-spl.bin" of="$DEVICE" bs=512 seek=256
		fi
	else
		echo "Missing U-Boot binary!" >&2
		return "$ERROR_REQUIRE_FILE"
	fi
	sync "$DEVICE"
}

erase_bootloader() {
	local DEVICE=$1

	dd conv=notrunc,fsync if=/dev/zero of="$DEVICE" bs=512 seek=256 count=1
	sync "$DEVICE"
}

erase_emmc_boot() {
	if [[ -f "/sys/class/block/$(basename "$1")/force_ro" ]]; then
		echo 0 >"/sys/class/block/$(basename "$1")/force_ro"
	fi
	blkdiscard -f "$@"
}

erase_spinor() {
	local DEVICE=${1:-/dev/mtd0}

	if [[ ! -e $DEVICE ]]; then
		echo "$DEVICE is missing." >&2
		return "$ERROR_REQUIRE_TARGET"
	fi

	flash_erase "$DEVICE" 0 0
}

update_spinor() {
	local DEVICE=${1:-/dev/mtd0}

	if [[ ! -e $DEVICE ]]; then
		echo "$DEVICE is missing." >&2
		return "$ERROR_REQUIRE_TARGET"
	fi

	build_spinor
	erase_spinor "$DEVICE"
	echo "Writing to $DEVICE..."
	flashcp /tmp/spi.img "$DEVICE"
	rm /tmp/spi.img
	sync
}

# https://stackoverflow.com/a/28776166
is_sourced() {
	if [ -n "$ZSH_VERSION" ]; then
		case $ZSH_EVAL_CONTEXT in
		*:file:*)
			return 0
			;;
		esac
	else # Add additional POSIX-compatible shell names here, if needed.
		case ${0##*/} in
		dash | -dash | bash | -bash | ksh | -ksh | sh | -sh)
			return 0
			;;
		esac
	fi
	return 1 # NOT sourced.
}

if ! is_sourced; then

	set -euo pipefail
	shopt -s nullglob

	SCRIPT_DIR="$(dirname "$(realpath "$0")")"

	ACTION="$1"
	shift

	if [[ $(type -t "$ACTION") == function ]]; then
		$ACTION "$@"
	else
		echo "Unsupported action: '$ACTION'" >&2
		exit "$ERROR_ILLEGAL_PARAMETERS"
	fi

fi
