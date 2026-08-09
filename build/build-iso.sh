#!/bin/sh

set -e

# Build OS using AUTO.ISO minimal auto-install as bootstrap to merge codebase, recompile system, attempt build limine UEFI hybrid ISO

# make sure we are in the correct directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SCRIPT_NAME="$(basename "$0")"
EXPECTED_DIR="$(pwd -P)"

if test "${EXPECTED_DIR}" != "${SCRIPT_DIR}"
then
	( cd "$SCRIPT_DIR" || exit ; "./$SCRIPT_NAME" "$@" );
	exit
fi

[ "$1" = "--headless" ] && QEMU_HEADLESS='-display none'
# SSH / no GUI: GTK display fails with "gtk initialization failed" and leaves an empty disk.
if [ -z "${QEMU_HEADLESS:-}" ] && { [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; }; then
	echo "No DISPLAY/WAYLAND_DISPLAY; using QEMU -display none (pass --headless explicitly to silence this)."
	QEMU_HEADLESS='-display none'
fi

KVM=''
(lsmod | grep -q kvm) && KVM=' -accel kvm'
# Attach USB HID devices only when testing the completed ISO.  The two
# noninteractive builder VMs must not exercise the in-progress USB stack.
QEMU_USB_INPUT='-device qemu-xhci,id=xhci -device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0 -device usb-mouse,bus=xhci.0'

# Set this true if you want to test ISOs in QEMU after building.
TESTING=false

# Change this if your default QEMU version does not work and you have installed a different version elsewhere.
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
	echo "ERROR: qemu-system-x86_64 not found. On Fedora: sudo dnf install -y qemu-system-x86 qemu-img qemu-kvm xorriso" >&2
	exit 1
fi
QEMU_BIN_PATH="$(dirname "$(command -v qemu-system-x86_64)")"
for need in qemu-img qemu-nbd; do
	if [ ! -x "$QEMU_BIN_PATH/$need" ] && ! command -v "$need" >/dev/null 2>&1; then
		echo "ERROR: $need not found next to qemu-system-x86_64 ($QEMU_BIN_PATH). Install qemu-img / qemu-kvm." >&2
		exit 1
	fi
done

TMPDIR="$(mktemp -d)"
TMPISODIR="$TMPDIR/iso"
TMPDISK="$TMPDIR/ZealOS.raw"
TMPMOUNT="$TMPDIR/mnt"

fail_build() {
	echo "ERROR: $*" >&2
	false
}

require_ascii_file() {
	if LC_ALL=C tr -d '\11\12\15\40-\176' < "$1" | grep -q .; then
		fail_build "non-ASCII byte(s) found in automatic build script: $1"
	fi
}

require_file() {
	[ -f "$1" ] || fail_build "missing required file: $1"
}

require_nonempty_file() {
	[ -s "$1" ] || fail_build "missing or empty required file: $1"
}

require_same_file() {
	if ! cmp -s "$1" "$2"; then
		fail_build "staged file differs from source: $2"
	fi
}

require_line() {
	if ! grep -Fqx "$2" "$1"; then
		fail_build "missing required line '$2' in $1"
	fi
}

require_text() {
	if ! grep -Fq "$2" "$1"; then
		fail_build "missing required text '$2' in $1"
	fi
}

require_kernel_symbol() {
	if ! strings "$1" | grep -q "$2"; then
		fail_build "kernel image missing symbol/text '$2': $1"
	fi
}

verify_live_redsea_image() {
	image="$1"
	redsea_block=88
	redsea_offset=$((redsea_block * 512))
	image_size="$(wc -c < "$image" | tr -d '[:space:]')"
	echo "Verifying RedSea filesystem at block $redsea_block in $image ..."
	[ "$image_size" -ge $((redsea_offset + 512)) ] ||
		fail_build "live image is too small for RedSea block $redsea_block: $image"
	redsea_type="$(od -An -tu1 -j $((redsea_offset + 3)) -N 1 "$image" | tr -d '[:space:]')"
	redsea_signature="$(od -An -tx1 -j $((redsea_offset + 510)) -N 2 "$image" | tr -d '[:space:]')"
	[ "$redsea_type" = "136" ] ||
		fail_build "live image has no RedSea type byte at block $redsea_block: $image"
	[ "$redsea_signature" = "55aa" ] ||
		fail_build "live image has no RedSea signature at block $redsea_block: $image"
}

verify_live_hook_generator() {
	generator="../src/Misc/Auto/AutoFullDistro5.ZC"
	echo "Verifying generated live ISO startup hook in $generator ..."
	require_text "$generator" 'CHashFun *tmpf;\n'
	require_text "$generator" 'HashFind(\"UsbBootInit\", Fs->hash_table, HTT_FUN)'
	require_text "$generator" 'ExePrint(\"UsbBootInit;\");\n'
	require_text "$generator" 'FileWrite("/Distro/Home/StartOSAfterSystem.ZC", start_os_after_system'
}

verify_current_usb_tree() {
	root="$1"
	tree_kind="${2:-source}"
	echo "Verifying staged USB input tree in $root ..."
	require_same_file "../src/HomeSys.ZC" "$root/HomeSys.ZC"
	require_same_file "../src/Misc/OSInstall.ZC" "$root/Misc/OSInstall.ZC"
	require_same_file "../src/Once.ZC" "$root/Once.ZC"
	require_same_file "../src/StartOS.ZC" "$root/StartOS.ZC"
	require_same_file "../src/System/BlkDev/ZDiskA.ZC" "$root/System/BlkDev/ZDiskA.ZC"
	for stage in ../src/Misc/Auto/AutoFullDistro*.ZC; do
		stage_name="$(basename "$stage")"
		require_same_file "$stage" "$root/Misc/Auto/$stage_name"
	done
	case "$tree_kind" in
		source)
			require_same_file "../src/Home/StartOSAfterSystem.ZC" "$root/Home/StartOSAfterSystem.ZC"
			;;
		container)
			# This is the outer Limine filesystem. AutoFullDistro5 writes the
			# generated live hook inside the nested RedSea Boot/Live.ISO.C image.
			require_file "$root/Home/StartOSAfterSystem.ZC"
			;;
		*)
			fail_build "unknown staged USB tree kind: $tree_kind"
			;;
	esac
	require_same_file "../src/System/Boot/BootHDIns.ZC" "$root/System/Boot/BootHDIns.ZC"
	require_same_file "../src/System/Boot/LimineMHDIns.ZC" "$root/System/Boot/LimineMHDIns.ZC"
	require_same_file "../src/System/Boot/LimineESPIns.ZC" "$root/System/Boot/LimineESPIns.ZC"
	require_same_file "../src/System/Boot/MakeBoot.ZC" "$root/System/Boot/MakeBoot.ZC"
	require_same_file "../src/Doc/InstallMacMini.DD" "$root/Doc/InstallMacMini.DD"
	require_file "$root/Demo/MacMiniProbe.ZC"
	require_same_file "../src/Kernel/BlkDev/DiskAHCI.ZC" "$root/Kernel/BlkDev/DiskAHCI.ZC"
	require_same_file "../src/Kernel/BlkDev/DiskATAId.ZC" "$root/Kernel/BlkDev/DiskATAId.ZC"
	require_same_file "../src/Kernel/KMain.ZC" "$root/Kernel/KMain.ZC"
	require_same_file "../src/Kernel/KStart16.ZC" "$root/Kernel/KStart16.ZC"
	require_same_file "../src/Kernel/KernelA.HH" "$root/Kernel/KernelA.HH"
	require_same_file "../src/Kernel/KernelB.HH" "$root/Kernel/KernelB.HH"
	require_file "$root/Kernel/Usb/MakeKUsb.ZC"
	require_same_file "../src/Kernel/SerialDev/Keyboard.ZC" "$root/Kernel/SerialDev/Keyboard.ZC"
	require_same_file "../src/Kernel/SerialDev/MakeSerialDev.ZC" "$root/Kernel/SerialDev/MakeSerialDev.ZC"
	require_same_file "../src/Kernel/SerialDev/Mouse.ZC" "$root/Kernel/SerialDev/Mouse.ZC"
	require_same_file "../src/Kernel/SerialDev/USB.ZC" "$root/Kernel/SerialDev/USB.ZC"
	require_same_file "../src/Kernel/SerialDev/USBBoot.ZC" "$root/Kernel/SerialDev/USBBoot.ZC"
	require_same_file "../src/Kernel/SerialDev/USBEHCI.ZC" "$root/Kernel/SerialDev/USBEHCI.ZC"
	require_same_file "../src/Kernel/SerialDev/USBControl.ZC" "$root/Kernel/SerialDev/USBControl.ZC"
	require_same_file "../src/Kernel/SerialDev/USBKbd.ZC" "$root/Kernel/SerialDev/USBKbd.ZC"
	require_same_file "../src/Kernel/SerialDev/USBMouse.ZC" "$root/Kernel/SerialDev/USBMouse.ZC"
	require_same_file "../src/Kernel/SerialDev/USBUHCI.ZC" "$root/Kernel/SerialDev/USBUHCI.ZC"
	require_same_file "../src/Kernel/SerialDev/USBXHCI.ZC" "$root/Kernel/SerialDev/USBXHCI.ZC"
	require_same_file "../src/Doc/USBBoot.DD" "$root/Doc/USBBoot.DD"
	require_file "$root/Demo/USBInput.ZC"
}

mount_tempdisk() {
	sudo modprobe nbd
	sudo "$QEMU_BIN_PATH/qemu-nbd" -c /dev/nbd0 -f raw "$TMPDISK"
	# Give the kernel a moment; partprobe alone is flaky right after nbd connect.
	sleep 1
	sudo partprobe /dev/nbd0 || true
	sleep 1
	if [ ! -b /dev/nbd0p1 ]; then
		fail_build "no /dev/nbd0p1 after auto-install (QEMU likely failed — use --headless over SSH, check AUTO.ISO ran)"
	fi
	sudo mount /dev/nbd0p1 "$TMPMOUNT"
}

umount_tempdisk() {
	sync
	sudo umount "$TMPMOUNT"
	sudo "$QEMU_BIN_PATH/qemu-nbd" -d /dev/nbd0
}

script_cleanup() {
    sync

    sudo umount "$TMPMOUNT" >/dev/null 2>&1 || true
    sudo "$QEMU_BIN_PATH/qemu-nbd" -d /dev/nbd0 >/dev/null 2>&1 || true

    echo "Deleting temp folder ..."
    sudo rm -rf "$TMPDIR"
    sudo rm -rf "$TMPISODIR"
}

trap 'script_cleanup' EXIT

mkdir -p "$TMPMOUNT"
mkdir -p "$TMPISODIR"

SOURCE_REV="$(git -C .. rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
echo "Source revision: $SOURCE_REV"
for stage in ../src/Misc/Auto/AutoFullDistro*.ZC; do
	require_ascii_file "$stage"
done
for stage in 2 3 5; do
	require_line "../src/Misc/Auto/AutoFullDistro${stage}.ZC" '#include "/System/Boot/MakeBoot"'
done
require_line "../src/Misc/Auto/AutoFullDistro5.ZC" '#include "/System/Utils/LineRep"'
verify_live_hook_generator

echo "Checking ZealC kernel compile traps..."
# Default SerialDev: Spawn/etc. are normal in core Kernel but fatal in SerialDev.
# HashFind-in-#exe is always scanned under Kernel/*.HH from this script.
./check-zealc-kernel-traps.sh "${ZEALC_TRAP_SCOPE:-Kernel/SerialDev}" || exit 1

echo "Building ZealBooter..."
make -C ../zealbooter TOOLCHAIN=llvm distclean all || ( echo "ERROR: ZealBooter build failed !" && false )

echo "Making temp vdisk, running auto-install ..."
"$QEMU_BIN_PATH/qemu-img" create -f raw "$TMPDISK" 1024M
"$QEMU_BIN_PATH/qemu-system-x86_64" -machine q35 $KVM -drive format=raw,file="$TMPDISK" -m 1G -rtc base=localtime -smp 4 -cdrom AUTO.ISO -device isa-debug-exit $QEMU_HEADLESS || true

echo "Copying all src/ code into vdisk Tmp/OSBuild/ ..."
rm -f ../src/Home/Registry.ZC
rm -f ../src/Home/MakeHome.ZC
rm -f ../src/Boot/Kernel.ZXE
mount_tempdisk
sudo mkdir -p "$TMPMOUNT/Tmp/OSBuild"
sudo cp -r ../src/* "$TMPMOUNT/Tmp/OSBuild/"
sudo rm -f "$TMPMOUNT/Tmp/OSBuild/Home/UsbBootLast.DD"
# AUTO.ISO leftovers under Misc/Auto and StartOS still drive stages until
# OSBuild overlays C:/. Install current stage scripts + StartOS on the live
# tree so stage 3 does not run the stock In(ata_port) AutoFullDistro3.
sudo mkdir -p "$TMPMOUNT/Misc/Auto"
sudo cp -f ../src/Misc/Auto/AutoFullDistro*.ZC "$TMPMOUNT/Misc/Auto/"
sudo cp -f ../src/StartOS.ZC "$TMPMOUNT/StartOS.ZC"
echo "Staged AutoISO stage 2 source:"
sudo sed -n '1,14p' "$TMPMOUNT/Misc/Auto/AutoFullDistro2.ZC"
# AUTO.ISO AutoInstall only writes ".auto_iso_build"; FileFind can miss dotfiles.
# Ensure a non-dot AutoISO marker so Stage2+ never runs UsbBootInit.
sudo mkdir -p "$TMPMOUNT/Home"
echo 1 | sudo tee "$TMPMOUNT/Home/AutoISOBuild.DD" >/dev/null
# Stage0's job is OutU8 so the host can copy OSBuild. If the install left us on
# Stage0 (or no stage1 marker), the rebuild QEMU would OutU8 again and exit
# before Comp — MyDistro.ISO.C never appears. Force Stage1 for the rebuild.
sudo rm -f "$TMPMOUNT/Home/AutoISOStage0.DD"
if [ ! -f "$TMPMOUNT/Home/AutoISOStage1.DD" ] && \
   [ ! -f "$TMPMOUNT/Home/AutoISOStage2.DD" ] && \
   [ ! -f "$TMPMOUNT/Home/AutoISOStage3.DD" ] && \
   [ ! -f "$TMPMOUNT/Home/AutoISOStage4.DD" ] && \
   [ ! -f "$TMPMOUNT/Home/AutoISOStage5.DD" ]; then
	echo 1 | sudo tee "$TMPMOUNT/Home/AutoISOStage1.DD" >/dev/null
	echo "Placed AutoISOStage1.DD for rebuild QEMU."
fi
echo "AutoISO Home markers:"; sudo ls -la "$TMPMOUNT/Home"/AutoISO* "$TMPMOUNT/Home"/.auto_iso_build 2>/dev/null || true
# Do NOT copy ZDiskA onto live System yet: MakeSystem would JIT it against the
# AUTO.ISO Kernel before stage2 installs 3-arg CopySingle (Missing ')' at ",").
verify_current_usb_tree "$TMPMOUNT/Tmp/OSBuild"
# AUTO.ISO BootMHD2 blocks forever at Selection:. Patch the on-disk stage-2
# loader to return '1' (Drive C) immediately. QMP send-key is not reliable here.
if [ -f "$TMPMOUNT/Boot/BootMHD2.BIN" ]; then
	sudo python3 "$SCRIPT_DIR/patch-bootmhd2-autoselect.py" "$TMPMOUNT/Boot/BootMHD2.BIN" \
		|| fail_build "BootMHD2.BIN autoselect patch failed"
else
	fail_build "missing $TMPMOUNT/Boot/BootMHD2.BIN after auto-install"
fi
umount_tempdisk

echo "Rebuilding kernel headers, kernel, OS, and building Distro ISO ..."
# Single CPU: ZealOS heap/USB is not SMP-hardened; stage3 CopyTree has GPF'd on -smp 4.
# BootMHD2.BIN was patched above to auto-select Drive C. Keep QMP digit1 as backup.
QMP_SOCK="$TMPDIR/qmp.sock"
rm -f "$QMP_SOCK"
(
	if ! command -v python3 >/dev/null 2>&1; then
		exit 0
	fi
	python3 - "$QMP_SOCK" <<'PY' || true
import socket, sys, time
path = sys.argv[1]
deadline = time.time() + 120
sock = None
while time.time() < deadline:
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2)
        sock.connect(path)
        break
    except OSError:
        time.sleep(0.25)
else:
    sys.exit(0)
try:
    sock.recv(4096)
    sock.sendall(b'{"execute":"qmp_capabilities"}\n')
    sock.recv(4096)
except OSError:
    sys.exit(0)
key = b'{"execute":"send-key","arguments":{"keys":[{"type":"qcode","data":"digit1"}]}}\n'
while True:
    try:
        sock.sendall(key)
        try:
            sock.recv(4096)
        except socket.timeout:
            pass
        time.sleep(4)
    except OSError:
        break
sock.close()
PY
) &
QMP_SENDER_PID=$!
REBUILD_START=$(date +%s)
"$QEMU_BIN_PATH/qemu-system-x86_64" -machine q35 $KVM -drive format=raw,file="$TMPDISK" -m 1G -rtc base=localtime -smp 1 -device isa-debug-exit -qmp "unix:$QMP_SOCK,server,nowait" $QEMU_HEADLESS || true
REBUILD_END=$(date +%s)
REBUILD_SECS=$((REBUILD_END - REBUILD_START))
echo "Rebuild QEMU exited after ${REBUILD_SECS}s."
kill "$QMP_SENDER_PID" 2>/dev/null || true
wait "$QMP_SENDER_PID" 2>/dev/null || true
rm -f "$QMP_SOCK"
if [ "$REBUILD_SECS" -lt 90 ]; then
	fail_build "rebuild QEMU exited after ${REBUILD_SECS}s (need several minutes for Comp). Likely Stage0 isa-debug-exit or early crash — MyDistro was not built."
fi

LIMINE_BINARY_BRANCH="v10.x-binary"

if [ -d "limine" ]
then
	cd limine
	git remote set-branches origin $LIMINE_BINARY_BRANCH
	git fetch
	git remote set-head origin $LIMINE_BINARY_BRANCH
	git switch $LIMINE_BINARY_BRANCH
	git config --local pull.ff true
	git config --local pull.rebase true
	git pull
	rm limine

	cd ..
else
    git clone https://github.com/limine-bootloader/limine.git --branch=$LIMINE_BINARY_BRANCH --depth=1
fi
make -C limine

touch limine/Limine-BIOS-HDD.HH
echo "/*\$WW,1\$" > limine/Limine-BIOS-HDD.HH
cat limine/LICENSE >> limine/Limine-BIOS-HDD.HH
echo "*/\$WW,0\$" >> limine/Limine-BIOS-HDD.HH
cat limine/limine-bios-hdd.h >> limine/Limine-BIOS-HDD.HH
sed -i 's/const uint8_t/U8/g' limine/Limine-BIOS-HDD.HH
sed -i "s/\[\]/\[$(grep -o "0x" ./limine/limine-bios-hdd.h | wc -l)\]/g" limine/Limine-BIOS-HDD.HH

mount_tempdisk
echo "Extracting MyDistro ISO from vdisk ..."
require_nonempty_file "$TMPMOUNT/Tmp/MyDistro.ISO.C"
require_file "$TMPMOUNT/Tmp/DVDKernel.ZXE"
verify_current_usb_tree "$TMPMOUNT" container
require_kernel_symbol "$TMPMOUNT/Tmp/DVDKernel.ZXE" "UsbBootInit"
require_kernel_symbol "$TMPMOUNT/Tmp/DVDKernel.ZXE" "MountLiveRam"
require_kernel_symbol "$TMPMOUNT/Tmp/DVDKernel.ZXE" "SYS_LIVE_ADDR"
require_kernel_symbol "$TMPMOUNT/Tmp/DVDKernel.ZXE" "UsbKernelBusInit"
cp "$TMPMOUNT/Tmp/MyDistro.ISO.C" ./ZealOS-MyDistro.iso
# Keep a copy for the Limine RAM-live module before clearing the mount copy.
cp "$TMPMOUNT/Tmp/MyDistro.ISO.C" ./Live.ISO.C
verify_live_redsea_image ./Live.ISO.C
sudo rm -f "$TMPMOUNT/Tmp/MyDistro.ISO.C"
echo "Setting up temp ISO directory contents for use with limine xorriso command ..."
sudo cp -rf "$TMPMOUNT"/* "$TMPISODIR/"
sudo rm -f "$TMPISODIR/Boot/OldMBR.BIN"
sudo rm -f "$TMPISODIR/Boot/BootMHD2.BIN"
sudo mkdir -p "$TMPISODIR/EFI/BOOT"
sudo cp limine/Limine-BIOS-HDD.HH "$TMPISODIR/Boot/Limine-BIOS-HDD.HH"
sudo cp limine/BOOTX64.EFI "$TMPISODIR/EFI/BOOT/BOOTX64.EFI"
sudo cp limine/BOOTX64.EFI "$TMPISODIR/Boot/BOOTX64.EFI"
sudo cp limine/limine-uefi-cd.bin "$TMPISODIR/Boot/Limine-UEFI-CD.BIN"
sudo cp limine/limine-bios-cd.bin "$TMPISODIR/Boot/Limine-BIOS-CD.BIN"
sudo cp limine/limine-bios.sys "$TMPISODIR/Boot/Limine-BIOS.SYS"
sudo cp ../zealbooter/bin/kernel "$TMPISODIR/Boot/ZealBooter.ELF"
sudo cp ../zealbooter/limine.conf "$TMPISODIR/Boot/Limine.CONF"
echo "Copying DVDKernel.ZXE over ISO Boot/Kernel.ZXE ..."
sudo mv "$TMPMOUNT/Tmp/DVDKernel.ZXE" "$TMPISODIR/Boot/Kernel.ZXE"
sudo rm -f "$TMPISODIR/Tmp/DVDKernel.ZXE"
echo "Installing Limine RAM-live RedSea module Boot/Live.ISO.C ..."
sudo cp ./Live.ISO.C "$TMPISODIR/Boot/Live.ISO.C"
require_nonempty_file "$TMPISODIR/Boot/Live.ISO.C"
verify_live_redsea_image "$TMPISODIR/Boot/Live.ISO.C"
verify_current_usb_tree "$TMPISODIR" container
require_kernel_symbol "$TMPISODIR/Boot/Kernel.ZXE" "UsbBootInit"
require_kernel_symbol "$TMPISODIR/Boot/Kernel.ZXE" "MountLiveRam"
require_kernel_symbol "$TMPISODIR/Boot/Kernel.ZXE" "SYS_LIVE_ADDR"
require_kernel_symbol "$TMPISODIR/Boot/Kernel.ZXE" "UsbKernelBusInit"
umount_tempdisk

truncate -s 32K bios_boot.img

xorriso -as mkisofs -R -r -J -b Boot/Limine-BIOS-CD.BIN \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        --boot-catalog-hide \
        --efi-boot Boot/Limine-UEFI-CD.BIN \
        -efi-boot-part --efi-boot-image --protective-msdos-label \
        -append_partition 4 21686148-6449-6E6F-744E-656564454649 bios_boot.img \
        -appended_part_as_gpt \
        "$TMPISODIR" -o ZealOS-limine.iso

rm bios_boot.img

./limine/limine bios-install ZealOS-limine.iso --no-gpt-to-mbr-isohybrid-conversion

if [ "$TESTING" = true ]; then
	if [ ! -d "ovmf" ]; then
	    echo "Downloading OVMF..."
	    mkdir ovmf
	    cd ovmf
	    curl -o OVMF-X64.zip https://efi.akeo.ie/OVMF/OVMF-X64.zip
	    7z x OVMF-X64.zip
	    cd ..
	fi
	echo "Testing limine-zealbooter-xorriso isohybrid boot in UEFI mode ..."
	"$QEMU_BIN_PATH/qemu-system-x86_64" -machine q35 $KVM -m 1G -rtc base=localtime -bios ovmf/OVMF.fd -smp 4 $QEMU_USB_INPUT -cdrom ZealOS-limine.iso $QEMU_HEADLESS
	echo "Testing limine-zealbooter-xorriso isohybrid boot in BIOS mode ..."
	"$QEMU_BIN_PATH/qemu-system-x86_64" -machine q35 $KVM -m 1G -rtc base=localtime -smp 4 $QEMU_USB_INPUT -cdrom ZealOS-limine.iso $QEMU_HEADLESS
	echo "Testing native ZealC MyDistro legacy ISO in BIOS mode ..."
	"$QEMU_BIN_PATH/qemu-system-x86_64" -machine q35 $KVM -m 1G -rtc base=localtime -smp 4 $QEMU_USB_INPUT -cdrom ZealOS-MyDistro.iso $QEMU_HEADLESS
fi

# comment these 2 lines if you want lingering old Distro ISOs
rm -f ./ZealOS-PublicDomain-BIOS-*.iso
rm -f ./ZealOS-BSD2-UEFI-*.iso

BUILD_STAMP="$(date +%Y-%m-%d-%H_%M_%S)"
BIOS_ISO="ZealOS-PublicDomain-BIOS-$BUILD_STAMP.iso"
UEFI_ISO="ZealOS-BSD2-UEFI-$BUILD_STAMP.iso"

mv ./ZealOS-MyDistro.iso "./$BIOS_ISO"
mv ./ZealOS-limine.iso "./$UEFI_ISO"

# VMware builds run in a separate Fedora checkout. Export completed artifacts to
# the Mac checkout when its ZealOS shared folder is mounted.
if [ -z "${ISO_EXPORT_DIR:-}" ] && mountpoint -q /mnt/hgfs 2>/dev/null && [ -d /mnt/hgfs/ZealOS/build ]; then
	ISO_EXPORT_DIR=/mnt/hgfs/ZealOS/build
fi
if [ -n "${ISO_EXPORT_DIR:-}" ]; then
	mkdir -p "$ISO_EXPORT_DIR"
	if [ "$(cd "$ISO_EXPORT_DIR" && pwd -P)" != "$SCRIPT_DIR" ]; then
		echo "Exporting ISOs to $ISO_EXPORT_DIR ..."
		cp -f "$BIOS_ISO" "$UEFI_ISO" "$ISO_EXPORT_DIR/"
		sync
	fi
fi

echo "Finished."
echo
echo "ISOs built:"
echo "$BIOS_ISO"
echo "$UEFI_ISO"
echo
