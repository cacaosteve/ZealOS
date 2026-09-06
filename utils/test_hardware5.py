#!/usr/bin/env python3
"""Host-side guards only; rebuild, binary gate and guest/native tests still required."""
from pathlib import Path
import struct
import unittest

from check_irq_eoi import check_eoi, kernel_parts

ROOT = Path(__file__).resolve().parents[1]


class Hardware5Regression(unittest.TestCase):
    def test_eoi_source_and_initialization_order(self):
        interrupts = (ROOT / "src/Kernel/KInterrupts.ZC").read_text()
        handlers = interrupts.split("INT_WAKE::", 1)[1].split("INT_FAULT::", 1)[0]
        self.assertNotIn("&dev", handlers)
        self.assertEqual(handlers.count("RAX, U64 [INT_LAPIC_EOI_ADDR]"), 2)
        self.assertIn("*INT_LAPIC_EOI_ADDR(U64 *) = dev.uncached_alias + LAPIC_EOI;", interrupts)
        main = (ROOT / "src/Kernel/KMain.ZC").read_text(encoding="latin1").split("U0 KMain()", 1)[1]
        self.assertLess(main.index("UncachedAliasAlloc;"), main.index("IntPICInit;"))
        self.assertLess(main.index("IntPICInit;"), main.index("IntInit2;"))
        self.assertLess(main.index("IntInit2;"), main.index("Core0StartMP;"))
        self.assertNotIn("MacMini2014BCM57766Present", main)

    def test_absent_ahci_device_throws_before_mmio_setup(self):
        body = (ROOT / "src/Kernel/BlkDev/DiskAHCI.ZC").read_text().split("U0 AHCIPortInit(", 1)[1]
        guard = body.split("bd->ahci_port = port;", 1)[0]
        self.assertIn("throw('NoAHCI');", guard)
        self.assertNotIn('Debug("AHCI Port/BlkDev error: Invalid Port Signature")', guard)
        self.assertLess(body.index("throw('NoAHCI');"), body.index("AHCIPortReset(port_num);"))

    def test_installed_mount_script_keeps_cd_optional(self):
        installer = (ROOT / "src/Misc/OSInstall.ZC").read_text()
        body = installer.split("U0 VMInstallDrive(", 1)[1].split("U0 VMInstallWiz()", 1)[0]
        self.assertNotIn('XTalkWait(task, "T%d', body)
        self.assertIn('XTalkWait(task, "C\\n%d\\n", ata_port)', body)
        self.assertIn("MountAHCIAuto\\nCT", body)

    def test_build_gates_both_kernels_before_packaging(self):
        build = (ROOT / "build/build-iso.sh").read_text()
        gate = 'python3 ../utils/check_irq_eoi.py "$TMPISODIR/Boot/Kernel.ZXE"'
        self.assertEqual(build.count(gate), 2)
        self.assertLess(build.index(gate), build.index('echo "Copying DVDKernel.ZXE'))
        self.assertLess(build.rindex(gate), build.index('xorriso -as mkisofs'))

    def fixture(self):
        body = bytearray(256)
        symbols = {"INT_LAPIC_EOI_ADDR": 0, "INT_WAKE": 16, "IRQ_TIMER": 64, "INT_FAULT": 160}
        body[16] = 0x50
        for pos in (17, 96):
            body[pos:pos+13] = b"\x48\x8b\x05" + struct.pack("<i", -pos - 7) + b"\xc7\x00\0\0\0\0"
        body[30:33] = b"\x58\x48\xcf"
        return body, symbols

    def test_binary_gate_and_relocation(self):
        body, symbols = self.fixture()
        stores = check_eoi(body, symbols)
        for base in (0, 0x7C20, 0x100000, 0x40000000):
            for pos in stores:
                disp = struct.unpack_from("<i", body, pos + 3)[0]
                self.assertEqual(base + pos + 7 + disp, base + symbols["INT_LAPIC_EOI_ADDR"])
        body[20] ^= 1
        with self.assertRaisesRegex(ValueError, "INT_WAKE"):
            check_eoi(body, symbols)
        with self.assertRaisesRegex(ValueError, "missing INT_LAPIC_EOI_ADDR"):
            check_eoi(bytes(256), {"INT_WAKE": 16})

    def test_zxe_parser_and_truncation(self):
        body, symbols = self.fixture()
        records = b"".join(b"\x10" + struct.pack("<I", value) + key.encode() + b"\0"
                           for key, value in symbols.items()) + b"\0"
        header = b"\xeb\x1e\x07\0ZXE\0" + struct.pack("<QQQ", 0x7FFFFFFFFFFFFFFF, 32 + len(body), 32 + len(body) + len(records))
        data = header + body + records
        parsed = kernel_parts(data)
        check_eoi(*parsed)
        with self.assertRaises(ValueError):
            kernel_parts(data[:-2])


if __name__ == "__main__":
    unittest.main()
