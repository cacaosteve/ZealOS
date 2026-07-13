#!/bin/sh
# Attach a ZealOS ISO to zeal2.utm and set UTM input for native USB HID.
# Shut down zeal2 completely before running.
#
# Usage:
#   ./setup-zeal2-iso-boot.sh [path-to-ZealOS-BSD2-UEFI-*.iso]
set -e

UTM_BUNDLE="${UTM_BUNDLE:-$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/zeal2.utm}"
CONFIG="$UTM_BUNDLE/config.plist"
DATA="$UTM_BUNDLE/Data"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

ISO="${1:-}"
if [ -z "$ISO" ]; then
	ISO="$(ls -t "$SCRIPT_DIR"/ZealOS-BSD2-UEFI-*.iso 2>/dev/null | head -1)"
fi
if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
	echo "ERROR: ISO not found. Pass path or build with ./build-iso.sh first." >&2
	exit 1
fi
ISO="$(cd "$(dirname "$ISO")" && pwd -P)/$(basename "$ISO")"

if [ ! -f "$CONFIG" ]; then
	echo "ERROR: zeal2.utm not found at $UTM_BUNDLE" >&2
	exit 1
fi

ISO_NAME="ZealOS-BSD2-UEFI.iso"
cp -f "$ISO" "$DATA/$ISO_NAME"

cp -f "$CONFIG" "$CONFIG.before-iso-boot-$(date +%Y%m%d-%H%M%S)"

python3 - "$CONFIG" "$ISO_NAME" <<'PY'
import plistlib, sys

config_path, iso_name = sys.argv[1:3]
with open(config_path, "rb") as f:
    plist = plistlib.load(f)

drives = plist.get("Drive", [])
cd_entry = None
for d in drives:
    if d.get("ImageType") == "CD":
        cd_entry = d
        break
if not cd_entry:
    cd_entry = {
        "Identifier": "CD387CA7-0A61-4026-9D67-ADAE0C124D58",
        "ImageType": "CD",
        "InterfaceVersion": 1,
    }
    drives.append(cd_entry)

cd_entry["Interface"] = "IDE"
cd_entry["ImageName"] = iso_name
cd_entry["ReadOnly"] = True
plist["Drive"] = drives

inp = plist.setdefault("Input", {})
inp["UsbBusSupport"] = "3.0"
inp["UsbSharing"] = False
inp["MaximumUsbShare"] = 1

qemu = plist.setdefault("QEMU", {})
qemu["PS2Controller"] = False
qemu["AdditionalArguments"] = []

display = plist.get("Display", [{}])
if display:
    display[0]["Hardware"] = "virtio-vga"

with open(config_path, "wb") as f:
    plistlib.dump(plist, f)

print(f"Updated {config_path}")
print(f"  CD ISO: {iso_name}")
print("  Input USB: 3.0, MaximumUsbShare: 1, PS/2: Off")
print("  Additional Arguments: (cleared)")
PY

echo
echo "Done. Quit UTM completely, reopen zeal2, and boot from the CD."
echo "After boot, expect: USB boot: active=0x3"
echo "Use UTM Cursor on/captured (usb-mouse). usb-tablet is ignored when both pointers exist."
