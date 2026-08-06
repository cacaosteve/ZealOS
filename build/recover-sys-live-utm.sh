#!/bin/sh
# Fix UTM boot panic: Expecting system symbol at "SYS_LIVE_ADDR"
#
# Cause: C:/Kernel/KernelB.HH declares _extern SYS_LIVE_ADDR but the running
# /Boot/Kernel.ZXE was built before that export existed. StartOS JIT-includes
# KernelB and panics before BootInsPending can rebuild.
#
# Shut down the ZealOS UTM VM first, then:
#   ./build/recover-sys-live-utm.sh
#
# Next boot: recovery StartOS Compiles Kernel (with KStart16 SYS_LIVE_*),
# restores normal StartOS.ZC, reboots. One more cold boot should reach desktop.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
export RECOVER_SYS_LIVE=1
export AUTO_NORMAL_REBUILD=
export AUTO_BOOT_INS=
export USB_ONLY_INPUT="${USB_ONLY_INPUT:-0}"
export ZEALC_TRAP_SCOPE="${ZEALC_TRAP_SCOPE:-Kernel/SerialDev}"
exec "$SCRIPT_DIR/patch-utm-disk.sh"
