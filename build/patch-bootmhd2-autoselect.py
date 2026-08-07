#!/usr/bin/env python3
"""Patch ZealOS Boot/BootMHD2.BIN so Selection auto-picks Drive C ('1').

AUTO.ISO's BootMHD2 blocks forever on INT 0x16. QEMU QMP send-key is not
reliable for that BIOS path. In-place patch of the stage-2 loader is.
"""
from __future__ import annotations

import sys
from pathlib import Path


def patch(data: bytearray) -> int:
	n = 0
	# XOR AH,AH; INT 0x16  ?  MOV AL,'1'; RET; NOP
	for sig in (bytes([0x30, 0xE4, 0xCD, 0x16]), bytes([0x32, 0xE4, 0xCD, 0x16])):
		start = 0
		while True:
			i = data.find(sig, start)
			if i < 0:
				break
			data[i : i + 4] = bytes([0xB0, 0x31, 0xC3, 0x90])
			n += 1
			start = i + 4
	# MOV AH,0; INT 0x16
	sig = bytes([0xB4, 0x00, 0xCD, 0x16])
	start = 0
	while True:
		i = data.find(sig, start)
		if i < 0:
			break
		data[i : i + 4] = bytes([0xB0, 0x31, 0xC3, 0x90])
		n += 1
		start = i + 4
	return n


def main() -> int:
	if len(sys.argv) != 2:
		print(f"usage: {sys.argv[0]} BootMHD2.BIN", file=sys.stderr)
		return 2
	path = Path(sys.argv[1])
	data = bytearray(path.read_bytes())
	n = patch(data)
	if n <= 0:
		print(f"ERROR: no INT 0x16 getchar pattern in {path}", file=sys.stderr)
		return 1
	path.write_bytes(data)
	print(f"Patched {n} BootMHD2 getchar site(s) ? auto '1' in {path}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
