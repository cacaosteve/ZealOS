#!/usr/bin/env python3
"""Read-only post-build gate for the hardware5 IRQ EOI addressing change.

Usage: python3 utils/check_irq_eoi.py path/to/Boot/Kernel.ZXE
This checks emitted x86 code, not native APIC operation or initialization timing.
"""
from pathlib import Path
import struct
import sys


def kernel_parts(data):
    if len(data) < 32 or data[4:8] != b"ZXE\0":
        raise ValueError("not a ZXE module")
    patch, size = struct.unpack_from("<QQ", data, 16)
    if size != len(data) or not 32 <= patch < size:
        raise ValueError("invalid ZXE file size/patch offset")
    symbols = {}
    pos = patch
    while pos < size:
        kind = data[pos]
        pos += 1
        if not kind:
            return data[32:patch], symbols
        if pos + 4 > size:
            raise ValueError("truncated patch record")
        value = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        end = data.find(b"\0", pos)
        if end < 0:
            raise ValueError("unterminated patch symbol")
        name = data[pos:end].decode("ascii")
        pos = end + 1
        if kind == 16:  # IET_REL32_EXPORT, relative to module body
            symbols[name] = value
        elif kind == 20:
            pos += 4 * value
        elif kind in (21, 22):
            pos += 4 + 4 * value
        elif kind in (23, 24):
            pos += 8 + 4 * value
        elif kind not in (*range(2, 12), 17, 18, 19, 25):
            raise ValueError(f"unsupported patch record {kind}")
        if pos > size:
            raise ValueError("truncated patch payload")
    raise ValueError("missing patch-table terminator")


def check_eoi(body, symbols):
    required = ("INT_LAPIC_EOI_ADDR", "INT_WAKE", "IRQ_TIMER", "INT_FAULT")
    for name in required:
        if name not in symbols:
            raise ValueError(f"missing {name}; kernel does not contain the hardware5 EOI fix")
    slot, wake, timer, fault = (symbols[name] for name in required)
    if not (0 <= slot <= len(body) - 8 and slot + 8 <= wake < timer < fault <= len(body)):
        raise ValueError("invalid EOI slot/handler boundaries")
    # MOV RAX,[RIP+disp32]; MOV DWORD [RAX],0. No absolute &dev immediate.
    stores = []
    for name, start, end in (("INT_WAKE", wake, timer), ("IRQ_TIMER", timer, fault)):
        matches = []
        for pos in range(start, end - 12):
            if body[pos:pos+3] == b"\x48\x8b\x05" and body[pos+7:pos+13] == b"\xc7\x00\0\0\0\0":
                disp = struct.unpack_from("<i", body, pos + 3)[0]
                if pos + 7 + disp == slot:
                    matches.append(pos)
        if len(matches) != 1:
            raise ValueError(f"{name}: expected exactly one RIP-relative EOI-slot load/store")
        stores.append(matches[0])
    if body[wake:stores[0]] != b"\x50" or body[stores[0]+13:stores[0]+16] != b"\x58\x48\xcf":
        raise ValueError("INT_WAKE must preserve RAX and return with IRETQ")
    return stores


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    try:
        body, symbols = kernel_parts(Path(sys.argv[1]).read_bytes())
        stores = check_eoi(body, symbols)
    except (ValueError, OSError) as error:
        raise SystemExit(f"FAIL: {error}")
    print("PASS: both IRQ handlers use the runtime EOI slot through RIP-relative loads "
          f"at {', '.join(hex(p) for p in stores)}. Native SMP testing is still required.")


if __name__ == "__main__":
    main()
