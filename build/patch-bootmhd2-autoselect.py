#!/usr/bin/env python3
"""Patch ZealOS Boot/BootMHD2.BIN so Selection auto-picks Drive C ('1').

AUTO.ISO's BootMHD2 blocks forever on INT 0x16. In-place patch of the stage-2
loader is the reliable AutoISO fix (QEMU QMP send-key is not).
"""
from __future__ import annotations

import sys
from pathlib import Path


def patch(data: bytearray) -> int:
	n = 0
	replacements = [
		# XOR AH,AH; INT 0x16
		(bytes([0x30, 0xE4, 0xCD, 0x16]), bytes([0xB0, 0x31, 0xC3, 0x90])),
		(bytes([0x32, 0xE4, 0xCD, 0x16]), bytes([0xB0, 0x31, 0xC3, 0x90])),
		# MOV AH,0; INT 0x16
		(bytes([0xB4, 0x00, 0xCD, 0x16]), bytes([0xB0, 0x31, 0xC3, 0x90])),
	]
	for sig, rep in replacements:
		start = 0
		while True:
			i = data.find(sig, start)
			if i < 0:
				break
			data[i : i + 4] = rep
			n += 1
			start = i + 4
	return n


def main() -> int:
	if len(sys.argv) != 2:
		print(f"usage: {sys.argv[0]} BootMHD2.BIN", file=sys.stderr)
		return 2
	path = Path(sys.argv[1])
	raw = path.read_bytes()
	data = bytearray(raw)
	n = patch(data)
	if n <= 0:
		# Help diagnose AUTO.ISO variants
		idx = raw.find(b"\xCD\x16")
		print(f"ERROR: no INT 0x16 getchar pattern in {path} (size={len(raw)}, first CD16@{idx})", file=sys.stderr)
		if idx >= 0:
			lo = max(0, idx - 8)
			print("context:", raw[lo : idx + 4].hex(), file=sys.stderr)
		return 1
	path.write_bytes(data)
	print(f"Patched {n} BootMHD2 getchar site(s) → auto '1' in {path}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
