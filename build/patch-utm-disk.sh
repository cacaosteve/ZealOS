#!/bin/sh
# Restore ZealOS UTM qcow2 and sync selected source files (USB work only).
set -e

UTM_BUNDLE="${UTM_BUNDLE:-$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/ZealOS.utm}"
UTM_DIR="${UTM_DIR:-$UTM_BUNDLE/Data}"
IMAGE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Drive:0:ImageName" "$UTM_BUNDLE/config.plist" 2>/dev/null || true)
[ -n "$IMAGE_NAME" ] || IMAGE_NAME="9B0F9544-DD68-41D3-ACC3-96A486D80F73-2.qcow2"
DISK="${DISK:-$UTM_DIR/$IMAGE_NAME}"
RESTORE_FROM="${RESTORE_FROM:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SRC_DIR="$(cd "$(dirname "$0")/../src" && pwd -P)"
STAMP=$(date +%Y%m%d-%H%M%S)

PART1_OFF=32256
PART2_OFF=542900736

export MTOOLS_SKIP_CHECK=1

SYNC_FILES="
Home/HomeSys.ZC
Home/Once.ZC
Kernel/KGlobals.ZC
Kernel/KConfig.ZC
Kernel/KMain.ZC
Kernel/Kernel.PRJ
Kernel/KernelA.HH
Kernel/KDebug.ZC
Kernel/PCI.ZC
Kernel/BlkDev/DiskAddDev.ZC
Kernel/SerialDev/MakeSerialDev.ZC
Kernel/SerialDev/Mouse.ZC
Kernel/SerialDev/USB.ZC
Kernel/SerialDev/USBUHCI.ZC
Kernel/SerialDev/USBEHCI.ZC
Kernel/SerialDev/USBXHCI.ZC
Kernel/SerialDev/USBControl.ZC
Kernel/SerialDev/USBKbd.ZC
Kernel/SerialDev/USBMouse.ZC
Kernel/SerialDev/USBBoot.ZC
Doc/Requirements.DD
Doc/Strategy.DD
Doc/WhyNotMore.DD
Doc/USBBoot.DD
Doc/Install.DD
Doc/InstallMacMini.DD
Demo/USBInput.ZC
Demo/MacMiniProbe.ZC
Doc/Tips.DD
Doc/Start.DD
Home/BootInsAuto.DD
Home/BootInsAuto.ZC
Home/BootKernelOnly.ZC
Home/BootKernelFull.ZC
System/Boot/BootDVD.ZC
System/Boot/BootDVDIns.ZC
System/Boot/BootHD.ZC
System/Boot/BootHDIns.ZC
System/Boot/BootMHD.ZC
System/Boot/BootMHD2.ZC
System/Boot/BootMHDIns.ZC
System/Boot/LimineMHDIns.ZC
System/Boot/LimineESPIns.ZC
System/Boot/BootRAM.ZC
System/Boot/DiskISO9660.ZC
System/Boot/DiskISORedSea.ZC
System/Boot/MakeBoot.ZC
StartOS.ZC
Compiler/Compiler.PRJ
Compiler/BackLib.ZC
System/Math/Conversion.ZC
System/Math/F32.ZC
System/Math/MakeMath.ZC
System/Math/Math.ZC
System/Math/MathODE.ZC
System/Math/Mat4.ZC
System/Math/NDArray.ZC
System/Math/Types.ZC
System/Math/Vec3.ZC
System/Math/Vec4.ZC
Kernel/FontAux.ZC
Kernel/FontStd.ZC
Kernel/KMathB.ZC
Kernel/StrPrint.ZC
Kernel/StrScan.ZC
System/Gr/Gr.HH
System/Gr/GrAsm.ZC
System/Gr/GrBitMap.ZC
System/Gr/GrComposites.ZC
System/Gr/GrDC.ZC
System/Gr/GrEnd.ZC
System/Gr/GrExterns.ZC
System/Gr/GrGlobals.ZC
System/Gr/GrInitA.ZC
System/Gr/GrInitB.ZC
System/Gr/GrMath.ZC
System/Gr/GrPalette.ZC
System/Gr/GrPrimatives.ZC
System/Gr/GrScreen.ZC
System/Gr/GrSpritePlot.ZC
System/Gr/GrTextBase.ZC
System/Gr/MakeGr.ZC
System/Gr/ScreenCast.ZC
System/Gr/SpriteBitMap.ZC
System/Gr/SpriteCode.ZC
System/Gr/SpriteEd.ZC
System/Gr/SpriteMain.ZC
System/Gr/SpriteMesh.ZC
System/Gr/SpriteNew.ZC
System/Gr/SpriteSideBar.ZC
System/Ctrls/CtrlsA.ZC
System/ZSplash.ZC
System/BlkDev/DiskCheck.ZC
System/BlkDev/DiskPart.ZC
System/BlkDev/FileMgr.ZC
System/BlkDev/MakeZBlkDev.ZC
System/BlkDev/Mount.ZC
System/BlkDev/ZDiskA.ZC
System/BlkDev/ZDiskB.ZC
System/DolDoc/DocGr.ZC
System/Utils/ToTXT.ZC
System/WinMgr.ZC
Misc/OSInstall.ZC
"

[ -f "$DISK" ] || { echo "Missing VM disk: $DISK"; exit 1; }
if [ -n "$RESTORE_FROM" ] && [ ! -f "$RESTORE_FROM" ]; then
	echo "Missing restore backup: $RESTORE_FROM"
	exit 1
fi

echo "Checking ZealC kernel compile traps..."
"$SCRIPT_DIR/check-zealc-kernel-traps.sh" "${ZEALC_TRAP_SCOPE:-Kernel/SerialDev}" || exit 1

if lsof "$DISK" >/dev/null 2>&1; then
	echo "ERROR: $DISK is in use. Shut down the ZealOS UTM VM first."
	lsof "$DISK" 2>/dev/null || true
	exit 1
fi

TMPDIR=$(mktemp -d)
RAW="$TMPDIR/disk.raw"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo "Backing up current disk -> ${DISK}.before-sync-${STAMP}"
cp -p "$DISK" "${DISK}.before-sync-${STAMP}"

if [ -n "$RESTORE_FROM" ]; then
	echo "Restoring from $RESTORE_FROM"
	cp -p "$RESTORE_FROM" "$DISK"
fi

echo "Converting qcow2 to raw..."
qemu-img convert -f qcow2 -O raw "$DISK" "$RAW"

fat_path() {
	# Map repo path to FAT LFN path used on ZealOS volumes.
	echo "$1" | sed 's|^|::/|'
}

local_path() {
	rel=$1
	if [ "$rel" = "Home/HomeSys.ZC" ]; then
		echo "$SRC_DIR/HomeSys.ZC"
	elif [ "$rel" = "Home/Once.ZC" ]; then
		echo "$SRC_DIR/Once.ZC"
	else
		echo "$SRC_DIR/$rel"
	fi
}

echo "Checking ZealOS CP437 encoding..."
ENCODING_FILES=""
for rel in $SYNC_FILES; do
	local=$(local_path "$rel")
	case "$local" in
		*.ZC|*.HH|*.DD|*.IN|*.PRJ) ENCODING_FILES="$ENCODING_FILES $local" ;;
	esac
done
if [ -n "$SYNC_HOME_KEY_PLUGINS" ]; then
	ENCODING_FILES="$ENCODING_FILES $SRC_DIR/HomeKeyPlugIns.ZC"
fi
"$SCRIPT_DIR/check-zealc-encoding.sh" $ENCODING_FILES || exit 1

sync_partition() {
	off=$1
	label=$2
	echo "Patching partition $label..."
	mattrib -i "$RAW@@${off}" -r -/ ::/ >/dev/null 2>&1 || true
	for rel in $SYNC_FILES; do
		local=$(local_path "$rel")
		[ -f "$local" ] || { echo "Missing local file: $local"; exit 1; }
		dest=$(fat_path "$rel")
		echo "  $rel"
		mcopy -o -i "$RAW@@${off}" "$local" "$dest"
	done
}

sync_partition "$PART1_OFF" "1"
sync_partition "$PART2_OFF" "2"

sync_home_key_plugins() {
	off=$1
	label=$2
	if [ -n "$SYNC_HOME_KEY_PLUGINS" ]; then
		tmp="$TMPDIR/HomeKeyPlugIns.$label"
		if mcopy -i "$RAW@@${off}" -n ::/Home/HomeKeyPlugIns.ZC "$tmp" 2>/dev/null; then
			echo "Skipping root HomeKeyPlugIns.ZC on partition $label; ::/Home/HomeKeyPlugIns.ZC override exists."
		else
			echo "Patching root ::/HomeKeyPlugIns.ZC on partition $label..."
			mcopy -o -i "$RAW@@${off}" "$SRC_DIR/HomeKeyPlugIns.ZC" ::/HomeKeyPlugIns.ZC
		fi
		rm -f "$tmp"
	fi
}
sync_home_key_plugins "$PART1_OFF" "1"
sync_home_key_plugins "$PART2_OFF" "2"

patch_limine_conf() {
	off=$1
	label=$2
	tmp="$TMPDIR/Limine.CONF"
	if mcopy -i "$RAW@@${off}" -n ::/Boot/Limine.CONF "$tmp" 2>/dev/null; then
		sed 's/1024x768/640x480/g' "$tmp" > "$tmp.new"
		mcopy -o -i "$RAW@@${off}" "$tmp.new" ::/Boot/Limine.CONF
		echo "  Boot/Limine.CONF -> 640x480 on $label"
	fi
}
patch_limine_conf "$PART1_OFF" "1"
patch_limine_conf "$PART2_OFF" "2"

remove_boot_ins_pending() {
	off=$1
	label=$2
	if [ -n "$REMOVE_BOOT_INS_PENDING" ]; then
		echo "Removing ::/Home/BootInsPending.DD on partition $label (skip auto kernel rebuild)..."
		mdel -i "$RAW@@${off}" ::/Home/BootInsPending.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/.boot_ins_pending 2>/dev/null || true
	fi
}
remove_boot_ins_pending "$PART1_OFF" "1"
remove_boot_ins_pending "$PART2_OFF" "2"

set_normal_rebuild_pending() {
	off=$1
	label=$2
	if [ -n "$AUTO_NORMAL_REBUILD" ]; then
		echo "Creating ::/Home/NormalRebuildKernel.DD on partition $label (normal boot rebuild after system server starts)..."
		mdel -i "$RAW@@${off}" ::/Home/BootInsPending.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/.boot_ins_pending 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/BootInsStage.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/BootInsErrs.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/BootCompileLog.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/UsbBootLast.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/OnceRebuildKernel.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/.once_rebuild_kernel 2>/dev/null || true
		printf '1' | mcopy -o -i "$RAW@@${off}" - ::/Home/NormalRebuildKernel.DD
		printf '1' | mcopy -o -i "$RAW@@${off}" - ::/Home/.normal_rebuild_kernel
	fi
}
set_normal_rebuild_pending "$PART1_OFF" "1"
set_normal_rebuild_pending "$PART2_OFF" "2"

set_usb_only_input() {
	off=$1
	label=$2
	if [ "${USB_ONLY_INPUT:-1}" = 1 ]; then
		echo "Creating ::/Home/UsbOnlyInput.DD on partition $label (skip PS/2 fallback)..."
		printf '1' | mcopy -o -i "$RAW@@${off}" - ::/Home/UsbOnlyInput.DD
		printf '1' | mcopy -o -i "$RAW@@${off}" - ::/Home/.usb_only_input
	else
		echo "Removing ::/Home/UsbOnlyInput.DD on partition $label (allow PS/2 fallback)..."
		mdel -i "$RAW@@${off}" ::/Home/UsbOnlyInput.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/.usb_only_input 2>/dev/null || true
	fi
}
set_usb_only_input "$PART1_OFF" "1"
set_usb_only_input "$PART2_OFF" "2"

set_boot_ins_pending() {
	off=$1
	label=$2
	if [ -n "$AUTO_BOOT_INS" ] && [ -z "$AUTO_NORMAL_REBUILD" ]; then
		mdel -i "$RAW@@${off}" ::/Home/OnceRebuildKernel.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/.once_rebuild_kernel 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/BootInsStage.DD 2>/dev/null || true
		mdel -i "$RAW@@${off}" ::/Home/BootInsErrs.DD 2>/dev/null || true
		echo "Creating ::/Home/BootInsPending.DD on partition $label (auto kernel rebuild next boot)..."
		printf '1' | mcopy -o -i "$RAW@@${off}" - ::/Home/BootInsPending.DD
		echo "Creating legacy ::/Home/.boot_ins_pending on partition $label..."
		printf '1' | mcopy -o -i "$RAW@@${off}" - ::/Home/.boot_ins_pending
	fi
}
set_boot_ins_pending "$PART1_OFF" "1"
set_boot_ins_pending "$PART2_OFF" "2"

verify_one() {
	rel=$1
	local=$(local_path "$rel")
	dest=$(fat_path "$rel")
	local_sum=$(shasum -a 256 "$local" | awk '{print $1}')
	p1="$TMPDIR/p1"
	p2="$TMPDIR/p2"
	rm -f "$p1" "$p2"
	mcopy -i "$RAW@@${PART1_OFF}" "$dest" "$p1"
	mcopy -i "$RAW@@${PART2_OFF}" "$dest" "$p2"
	p1_sum=$(shasum -a 256 "$p1" | awk '{print $1}')
	p2_sum=$(shasum -a 256 "$p2" | awk '{print $1}')
	if [ "$local_sum" = "$p1_sum" ] && [ "$local_sum" = "$p2_sum" ]; then
		echo "  OK $rel"
	else
		echo "  MISMATCH $rel"
		echo "    local=$local_sum part1=$p1_sum part2=$p2_sum"
		exit 1
	fi
}

echo "Verifying checksums:"
verify_one "StartOS.ZC"
verify_one "Home/Once.ZC"
verify_one "Home/BootKernelFull.ZC"
verify_one "Kernel/KConfig.ZC"
verify_one "Kernel/Kernel.PRJ"
verify_one "Kernel/KernelA.HH"
verify_one "Kernel/KMain.ZC"
verify_one "Kernel/SerialDev/USBXHCI.ZC"
verify_one "System/Math/Math.ZC"
verify_one "System/Gr/GrMath.ZC"
verify_one "System/BlkDev/DiskCheck.ZC"
verify_one "System/Utils/ToTXT.ZC"
verify_one "Compiler/BackLib.ZC"
verify_one "Kernel/SerialDev/USBControl.ZC"
verify_one "Kernel/SerialDev/USBUHCI.ZC"
verify_one "Kernel/SerialDev/USBEHCI.ZC"
verify_one "Kernel/SerialDev/USBXHCI.ZC"
verify_one "Kernel/SerialDev/MakeSerialDev.ZC"
verify_one "Kernel/SerialDev/USBMouse.ZC"
verify_one "Kernel/SerialDev/USBKbd.ZC"
verify_one "Kernel/SerialDev/USBBoot.ZC"
if [ -n "$SYNC_HOME_KEY_PLUGINS" ]; then
	local_sum=$(shasum -a 256 "$SRC_DIR/HomeKeyPlugIns.ZC" | awk '{print $1}')
	if ! mcopy -i "$RAW@@${PART1_OFF}" -n ::/Home/HomeKeyPlugIns.ZC "$TMPDIR/homekey-override-p1" 2>/dev/null; then
		mcopy -i "$RAW@@${PART1_OFF}" ::/HomeKeyPlugIns.ZC "$TMPDIR/homekey-root-p1"
		p1_sum=$(shasum -a 256 "$TMPDIR/homekey-root-p1" | awk '{print $1}')
		[ "$local_sum" = "$p1_sum" ] || { echo "  MISMATCH root HomeKeyPlugIns.ZC on partition 1"; exit 1; }
		echo "  OK root HomeKeyPlugIns.ZC on partition 1"
	fi
	if ! mcopy -i "$RAW@@${PART2_OFF}" -n ::/Home/HomeKeyPlugIns.ZC "$TMPDIR/homekey-override-p2" 2>/dev/null; then
		mcopy -i "$RAW@@${PART2_OFF}" ::/HomeKeyPlugIns.ZC "$TMPDIR/homekey-root-p2"
		p2_sum=$(shasum -a 256 "$TMPDIR/homekey-root-p2" | awk '{print $1}')
		[ "$local_sum" = "$p2_sum" ] || { echo "  MISMATCH root HomeKeyPlugIns.ZC on partition 2"; exit 1; }
		echo "  OK root HomeKeyPlugIns.ZC on partition 2"
	fi
fi

echo "Writing raw back to qcow2..."
qemu-img convert -f raw -O qcow2 "$RAW" "$DISK.new"
mv "$DISK.new" "$DISK"

echo "Fresh backup -> ${DISK}.bak-after-sync-${STAMP}"
cp -p "$DISK" "${DISK}.bak-after-sync-${STAMP}"

echo
echo "Done."
if [ -n "$AUTO_NORMAL_REBUILD" ]; then
	echo "Next boot: ZealOS should reach the desktop, /Home/Once.ZC should queue"
	echo "a normal kernel rebuild after the system server starts, then reboot automatically."
	if [ "${USB_ONLY_INPUT:-1}" = 1 ]; then
		echo "UTM: keep Input USB = USB 3.0 (XHCI), PS/2 off, and no Additional Arguments."
	else
		echo "UTM recovery boot: keep Input USB = USB 3.0 (XHCI), turn PS/2 on, and no Additional Arguments."
	fi
elif [ -n "$AUTO_BOOT_INS" ]; then
	echo "Next boot: StartOS should consume /Home/BootInsPending.DD and print"
	echo "'Rebuilding kernel (USB skipped this boot for RAM)...'"
	echo "then compile (~5-15 min) and reboot automatically. No mouse or keyboard required."
	if [ "${USB_ONLY_INPUT:-1}" = 1 ]; then
		echo "UTM: keep Input USB = USB 3.0 (XHCI), PS/2 off, and no Additional Arguments."
	else
		echo "UTM recovery boot: keep Input USB = USB 3.0 (XHCI), turn PS/2 on, and no Additional Arguments."
	fi
else
	echo "Boot ZealOS, run BootHDInsAuto; then Reboot;"
fi
