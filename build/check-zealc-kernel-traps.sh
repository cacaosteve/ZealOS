#!/bin/sh
# Scan ZealOS kernel .ZC for HolyC patterns that fail Comp("/Kernel/Kernel").
# Not a full compiler; catches documented traps from ::/Doc/USBBoot.DD.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SRC_DIR="${SRC_DIR:-$SCRIPT_DIR/../src}"
SCOPE="${1:-Kernel/SerialDev}"

if [ ! -d "$SRC_DIR/$SCOPE" ]; then
	echo "ERROR: $SRC_DIR/$SCOPE not found" >&2
	exit 1
fi

FAIL=0
ISSUES=0

scan_pattern() {
	pattern=$1
	shift
	if command -v rg >/dev/null 2>&1; then
		rg -n "$pattern" "$@" 2>/dev/null || true
		return
	fi

	glob="*"
	paths=""
	while [ $# -gt 0 ]; do
		if [ "$1" = "--glob" ]; then
			shift
			glob=$1
		else
			paths="$paths
$1"
		fi
		shift
	done
	printf '%s\n' "$paths" | while IFS= read -r path; do
		[ -n "$path" ] || continue
		if [ -d "$path" ]; then
			find "$path" -type f -name "$glob" -exec perl -ne '
				BEGIN { $pat = $ENV{"ZEALC_TRAP_PATTERN"}; }
				if (/$pat/) { print "$ARGV:$.:$_"; }
			' {} \;
		elif [ -f "$path" ]; then
			perl -ne '
				BEGIN { $pat = $ENV{"ZEALC_TRAP_PATTERN"}; }
				if (/$pat/) { print "$ARGV:$.:$_"; }
			' "$path"
		fi
	done
}

check() {
	name=$1
	pattern=$2
	shift 2
	matches=$(ZEALC_TRAP_PATTERN="$pattern" scan_pattern "$pattern" "$@")
	if [ -n "$matches" ]; then
		echo "FAIL: $name"
		printf '%s\n' "$matches"
		echo
		FAIL=1
		ISSUES=$((ISSUES + 1))
	fi
}

echo "ZealC kernel trap scan: $SRC_DIR/$SCOPE"
echo

# continue (ZealC has no continue; use goto)
check "continue statement" '\bcontinue\s*;' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# compound assign on postfix-cast lvalue: *(x)(U32 *) |= ...
check "compound assign on postfix cast" '\)\(U[0-9]+ \*\)\s*[|&]=' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# *ptr = !*ptr
check "pointer ! toggle (*x = !*x)" '\*\w+\s*=\s*!\*' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# member/global self ! toggle (usb.x = !usb.x)
check "self ! toggle (member = !member)" '\.\w+\s*=\s*!\w+\.' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'
check "self ! toggle (global = !global)" '^\s*\w+\.\w+\s*=\s*!\w+\.\w+' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# trb->field &= or |= (often needs temp; &= ~ is the common trap)
check "trb->field compound assign" '->\w+\s*[|&]=' \
	"$SRC_DIR/$SCOPE" --glob 'USB*.ZC'

# postfix ++/-- on dereference
check "postfix inc/dec on deref" '\(\*\w+\)\+\+|--\(\*\w+\)|\(\*\w+\)--|\+\+\(\*\w+\)' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# C-style casts are intentionally not checked here. A simple regex cannot
# distinguish invalid "(U32 *)expr" from valid ZealC postfix casts "expr(U32 *)".

# C-style ternary conditionals are not accepted by the ZealC kernel compiler.
check "C ternary operator (? :)" '\?.*:' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# DevCtx(slot,0)[0]; use temp pointer
check "DevCtx(...)[subscript]" 'DevCtx\([^)]+\)\[' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# t = Spawn( in kernel (Invalid lval at Spawn)
check "Spawn assignment in kernel" '=\s*Spawn\(' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# Spawn from kernel sources can parse/compile differently than StartOS/System code.
check "Spawn call in kernel" '\bSpawn\(' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# #exe { if (HashFind(...)) } in headers → Invalid lval at HashFind (StartOS JIT).
# Prefer #ifaot/_extern + #ifjit stubs, or runtime HashFind outside #exe.
# (rg needs -U for #exe ... HashFind across lines.)
check_exe_hashfind() {
	name=$1
	shift
	matches=""
	if command -v rg >/dev/null 2>&1; then
		matches=$(rg -n -U --glob '*.HH' --glob '*.ZC' '#exe[\s\S]{0,500}?HashFind' "$@" 2>/dev/null || true)
	fi
	if [ -n "$matches" ]; then
		echo "FAIL: $name"
		printf '%s\n' "$matches"
		echo
		FAIL=1
		ISSUES=$((ISSUES + 1))
	fi
}
check_exe_hashfind "HashFind inside #exe (Invalid lval)" \
	"$SRC_DIR/Kernel" "$SRC_DIR/$SCOPE"

check "if (HashFind(...)) in headers" 'if\s*\(\s*HashFind\s*\(' \
	"$SRC_DIR/Kernel" --glob '*.HH'

# SerialDev is included before BlkDev/MakeBlkDev in Kernel.PRJ.  Do not call
# block-device helpers that are only defined later in the kernel build.
if [ -d "$SRC_DIR/Kernel/SerialDev" ]; then
	check "DriveIsWritable before BlkDev include" '\bDriveIsWritable\b' \
		"$SRC_DIR/Kernel/SerialDev" --glob '*.ZC'
fi

# KbdMouseHandler already owns poll-mode USB after startup. A second task races
# the same UHCI/EHCI transfer state and can replay raw HID bytes as input.
check "duplicate USB background poller" 'Spawn\s*\(&UsbPollBgTask' \
	"$SRC_DIR/StartOS.ZC" \
	"$SRC_DIR/Home/StartOSAfterSystem.ZC" \
	"$SRC_DIR/Misc/Auto/AutoFullDistro5.ZC"

# BootHDIns is noninteractive. Text-driven XTalkWait can either execute legacy
# answers as HolyC or remain blocked on terminal UI state after compilation.
check "text-driven BootHDIns installer job" 'XTalkWait.*BootHDIns' \
	"$SRC_DIR/Misc/OSInstall.ZC" \
	"$SRC_DIR/Misc/Auto/AutoInstall.ZC"

# The full-distro stages rebuild the kernel across reboots. Queued keystrokes
# are timing-sensitive and can stop at a prompt or execute as HolyC commands.
check "queued input in automatic distro stage" '\bIn\s*\(' \
	"$SRC_DIR/Misc/Auto/AutoFullDistro1.ZC" \
	"$SRC_DIR/Misc/Auto/AutoFullDistro2.ZC" \
	"$SRC_DIR/Misc/Auto/AutoFullDistro3.ZC"

# StrCmp (use StrCompare)
check "StrCmp (use StrCompare)" '\bStrCmp\b' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# reg is a keyword-like storage/register annotation; as a local variable it
# can produce "Missing expression" at ordinary assignments.
check "reserved local name reg" '^\s*(I64|U64|I32|U32|I16|U16|I8|U8)\s+[^;]*\breg\b' \
	"$SRC_DIR/$SCOPE" --glob '*.ZC'

# Risky USB* compound names in SerialDev (HolyC may split USB.Mouse).
if [ -d "$SRC_DIR/$SCOPE/SerialDev" ]; then
	USB_SCOPE="$SRC_DIR/$SCOPE/SerialDev"
else
	USB_SCOPE="$SRC_DIR/$SCOPE"
fi
usb_warn=$(ZEALC_TRAP_PATTERN='\bUSB[A-Z][a-zA-Z0-9_]+\s*\(' scan_pattern '\bUSB[A-Z][a-zA-Z0-9_]+\s*\(' "$USB_SCOPE" --glob 'USB*.ZC')
if [ -n "$usb_warn" ]; then
	echo "WARN: USB* compound function names in SerialDev (review for USB.X parsing):"
	printf '%s\n' "$usb_warn"
	echo "(warnings do not fail the scan)"
	echo
fi

# KConfig: interactive prompt code is still parsed even if hidden below returns.
if [ -f "$SRC_DIR/Kernel/KConfig.ZC" ]; then
	kconfig_hits=$(ZEALC_TRAP_PATTERN="CharGet|StrGet|I64Get" scan_pattern "CharGet|StrGet|I64Get" "$SRC_DIR/Kernel/KConfig.ZC")
	if [ -n "$kconfig_hits" ]; then
		echo "FAIL: KConfig still contains interactive prompt code"
		printf '%s\n' "$kconfig_hits"
		echo
		FAIL=1
		ISSUES=$((ISSUES + 1))
	fi
fi

if [ "$FAIL" -eq 0 ]; then
	echo "OK: no documented ZealC kernel traps found in $SCOPE"
	exit 0
fi

echo "$ISSUES trap category(ies) matched; fix before BootHDInsAuto / auto-rebuild."
echo "See ZealOS/src/Doc/USBBoot.DD (ZealC Kernel Compile Traps)."
exit 1
