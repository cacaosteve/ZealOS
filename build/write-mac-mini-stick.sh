#!/bin/sh
# Write ZealOS BSD2-UEFI ISO to a USB stick for Mac mini Option-boot.
# Firmware reads the stick (no ZealOS USB MSC). Do not use TinkerOS .img.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
DEV="${1:-}"
ISO="${2:-}"

if [ -z "$ISO" ]; then
	ISO="$(ls -t "$SCRIPT_DIR"/ZealOS-BSD2-UEFI-*.iso 2>/dev/null | head -1 || true)"
fi
if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
	echo "ERROR: BSD2-UEFI ISO not found. Build with ./build-iso.sh first." >&2
	echo "Usage: $0 /dev/diskN [path-to-ZealOS-BSD2-UEFI-*.iso]" >&2
	exit 1
fi

if [ -z "$DEV" ]; then
	echo "Usage: $0 /dev/diskN [iso]" >&2
	echo "List disks: diskutil list   (macOS)  or  lsblk   (Linux)" >&2
	echo "Use the whole disk (e.g. /dev/disk4 or /dev/sdb), not a partition." >&2
	exit 1
fi

case "$DEV" in
	/dev/disk[0-9]*)
		if [ "$(uname -s)" = Darwin ]; then
			echo "Unmounting $DEV ..."
			diskutil unmountDisk "$DEV" || true
			RAW="/dev/r${DEV#/dev/}"
		else
			RAW="$DEV"
		fi
		;;
	/dev/sd*|/dev/nvme*|/dev/vd*|/dev/mmcblk*)
		RAW="$DEV"
		;;
	*)
		echo "ERROR: unexpected device '$DEV'" >&2
		exit 1
		;;
esac

echo "ISO: $ISO"
echo "DEV: $RAW"
echo "This ERASES $DEV. Continue? [y/N]"
read -r ans || true
case "$ans" in
	y|Y|yes|YES) ;;
	*) echo "Aborted."; exit 1 ;;
esac

if command -v sudo >/dev/null 2>&1; then
	SUDO=sudo
else
	SUDO=
fi

echo "Writing ISO (this takes a few minutes) ..."
$SUDO dd if="$ISO" of="$RAW" bs=4m status=progress conv=sync || \
	$SUDO dd if="$ISO" of="$RAW" bs=4M status=progress conv=fsync

if [ "$(uname -s)" = Darwin ]; then
	diskutil eject "$DEV" || true
else
	$SUDO sync
fi

echo
echo "Done. Plug into the Mac mini, hold Option at power-on, choose EFI Boot."
echo "Do not use a TinkerOS .img. Expect USB active=0x3 and an AHCI ATA port."
echo "See src/Doc/InstallMacMini.DD"
