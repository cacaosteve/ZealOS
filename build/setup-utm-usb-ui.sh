#!/bin/sh
# UTM "USB 3.0" UI input workflow (shut down VM first):
#   1. Sets Input USB = 3.0, PS/2 = Off, clears Additional Arguments.
#   2. Syncs USB sources and queues normal-boot kernel rebuild.
#   3. Boot VM; wait for desktop, auto compile (~5-15 min), auto reboot.
#   4. build/check-utm-usb-boot.sh — expect active=0x3 (kbd+mouse).
#
# Do NOT also set QEMU Additional Arguments (qemu-xhci etc.) — that duplicates HID.
set -e

UTM_BUNDLE="${UTM_BUNDLE:-$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/ZealOS.utm}"
CONFIG="$UTM_BUNDLE/config.plist"

if [ ! -f "$CONFIG" ]; then
	echo "ERROR: UTM bundle not found: $UTM_BUNDLE" >&2
	exit 1
fi

python3 - "$CONFIG" <<'PY'
import plistlib, shutil, sys

config_path = sys.argv[1]
backup = config_path + ".before-usb-ui"
shutil.copy2(config_path, backup)

with open(config_path, "rb") as f:
    plist = plistlib.load(f)

inp = plist.setdefault("Input", {})
inp["UsbBusSupport"] = "3.0"
inp["UsbSharing"] = False

qemu = plist.setdefault("QEMU", {})
qemu["PS2Controller"] = False
qemu["AdditionalArguments"] = []

with open(config_path, "wb") as f:
    plistlib.dump(plist, f)

print(f"Updated {config_path}")
print(f"Backup: {backup}")
print("  Input USB: 3.0, PS/2: Off, Additional Arguments: (cleared)")
print("  Cursor on uses usb-mouse; Cursor off uses usb-tablet. Pause briefly after switching.")
PY

export AUTO_NORMAL_REBUILD=1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
exec "$SCRIPT_DIR/patch-utm-disk.sh"
