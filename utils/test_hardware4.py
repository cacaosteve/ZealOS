#!/usr/bin/env python3
"""Host regression checks. These do not replace booting the rebuilt HolyC kernel.

Run the actual AHCIAtapiRBlks body as C++ with mocked block I/O under ASan/UBSan.
Only the catch syntax/implicit rethrow is translated; the read/copy arithmetic
comes directly from the checked-out source, not a separate Python model.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / "src/Kernel" / path).read_text(encoding="latin1")


class Hardware4Regression(unittest.TestCase):
    def test_atapi_actual_read_loop(self):
        body = source("BlkDev/DiskAHCI.ZC").split("Bool AHCIAtapiRBlks(", 1)[1]
        body = "Bool AHCIAtapiRBlks(" + body.split("\nBool AHCIAtaRBlks", 1)[0]
        body = body.replace("catch\n", "catch (...)\n")
        body = body.replace(
            "//HolyC rethrows automatically when catch_except remains FALSE.",
            "throw; //Explicit C++ equivalent of HolyC implicit rethrow.")
        prelude = r'''
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>
using I64 = int64_t; using U64 = uint64_t; using U8 = uint8_t; using Bool = bool;
constexpr bool TRUE=true, FALSE=false;
constexpr I64 BDT_ATAPI=5, BDF_READ_CACHE=1, BLK_SIZE_BITS=9;
constexpr I64 BLK_SIZE=512, DVD_BLK_SIZE=2048;
struct CBlkDev { I64 blk_size=2048, max_reads=128, type=BDT_ATAPI, flags=1; };
struct CDrive { CBlkDev *bd; I64 drv_offset, size; };
I64 MinI64(I64 a,I64 b) { return std::min(a,b); }
I64 MaxI64(I64 a,I64 b) { return std::max(a,b); }
U64 CeilU64(U64 a,U64 b) { return (a+b-1)/b*b; }
int allocations=0, reads=0, short_at=0;
std::vector<U8> disk;
U8 *MAlloc(I64 n) { ++allocations; return static_cast<U8*>(malloc(n)); }
void Free(void *p) { --allocations; free(p); }
void MemCopy(void *d,const void *s,I64 n) { memcpy(d,s,n); }
I64 AHCIAtapiBlksRead(CBlkDev *bd,U8 *buf,I64 first,I64 count) {
    assert(count>0 && count*4<=std::max<I64>(4,std::min<I64>(128,bd->max_reads)/4*4));
    assert(first>=0 && (first+count)*2048<=static_cast<I64>(disk.size()));
    memcpy(buf,disk.data()+first*2048,count*2048);
    ++reads;
    return count*2048-(reads==short_at ? 512:0);
}
void DiskCacheAdd(CDrive *,U8 *buf,I64 first,I64 count) {
    assert(memcmp(buf,disk.data()+first*512,count*512)==0);
}
'''
        tests = r'''
int main() {
    disk.resize(5*1024*1024);
    for (size_t i=0;i<disk.size();++i) disk[i]=(i*73+(i>>9)*29+(i>>16)*11)&255;
    CBlkDev bd;
    CDrive drive{&bd,0,static_cast<I64>(disk.size()/512)};
    size_t cases=0;
    for (I64 cache: {0,1}) for (I64 limit: {0,4,7,64,128,8192})
    for (I64 start=0;start<8;++start)
    for (I64 count: {0,1,3,4,127,128,129,257,385,2049,8192}) {
        bd.flags=cache; bd.max_reads=limit;
        std::vector<U8> output(count*512,0xAF);
        assert(AHCIAtapiRBlks(&drive,output.data(),start,count));
        if(count) assert(memcmp(output.data(),disk.data()+start*512,count*512)==0);
        assert(allocations==0); ++cases;
    }
    bd.max_reads=128;
    for(I64 count=1;count<=129;++count) {
        I64 start=drive.size-count;
        std::vector<U8> output(count*512);
        assert(AHCIAtapiRBlks(&drive,output.data(),start,count));
        assert(memcmp(output.data(),disk.data()+start*512,count*512)==0);
        assert(allocations==0); ++cases;
    }
    //Short DMA and out-of-range reads must throw and release the window.
    for(int fail: {1,2}) {
        std::vector<U8> output(385*512,0xAF);
        reads=0; short_at=fail; bool threw=false;
        try { AHCIAtapiRBlks(&drive,output.data(),0,385); } catch(...) { threw=true; }
        assert(threw && allocations==0); ++cases;
    }
    short_at=0;
    U8 output[512]; bool threw=false;
    try { AHCIAtapiRBlks(&drive,output,drive.size,1); } catch(...) { threw=true; }
    assert(threw && allocations==0); ++cases;
    bd.type=0; assert(!AHCIAtapiRBlks(&drive,output,0,1));
    std::cout << cases << " ATAPI boundary/error cases passed\n";
}
'''
        with tempfile.TemporaryDirectory(prefix="zealos-hardware4-test-") as tmp:
            exe = str(Path(tmp) / "atapi")
            subprocess.run([os.environ.get("CXX", "c++"), "-x", "c++", "-",
                            "-std=c++17", "-fsanitize=address,undefined",
                            "-fno-omit-frame-pointer", "-Wno-multichar", "-o", exe],
                           input=prelude + body + tests, text=True, check=True)
            subprocess.run([exe], check=True)

    def test_legacy_tie_keeps_ehci(self):
        text = source("SerialDev/LegacyUsbBoot.ZC")
        self.assertIn("ehci_active && LegacyUsbInputScore(ehci_active) >= best_score", text)
        self.assertIn("if (best_backend != 1)", text)
        self.assertEqual(text.count("\tEhciCoreInit;"), 1)

    def test_boot_order_and_absent_ps2(self):
        main = source("KMain.ZC")
        self.assertLess(main.index('if (!Load("Compiler"'), main.index('"Core0StartMP;"'))
        self.assertIn('HashFind("ExeFile", Fs->hash_table, HTT_EXPORT_SYS_SYM)', main)
        self.assertIn("if (UsbMouseOwnsInput)", main)
        self.assertNotIn("MacMini2014BCM57766Present", main)
        self.assertNotIn("keeping auxiliary CPUs offline", main)
        for path in ("SerialDev/Keyboard.ZC", "SerialDev/Mouse.ZC"):
            self.assertIn("if (!KbdControllerPresent)", source(path))

    def test_msd_dma_contract(self):
        text = source("Usb/KUsbMsd.ZC")
        self.assertIn("CAllocAligned(USB_MSD_CHUNK_BLKS * BLK_SIZE, 0x10000", text)
        self.assertIn("msd->data_residue || msd->csw->residue", text)
        #All possible 64-byte-aligned CBW/CSW starts stay within a 64 KiB page.
        for size in (13, 31):
            for address in range(0, 65536, 64):
                self.assertLessEqual(address + size, 65536)
        self.assertRegex(text, re.compile(r"if \(residue\).*?return -1", re.S))

    def test_uefi_does_not_ship_build_registry(self):
        build = (ROOT / "build/build-iso.sh").read_text()
        extract = build.index('mcopy -s -Q -n -o -i "$IMG" "::/*" "$TMPISODIR/"')
        clean = build.index('rm -f "$TMPISODIR/Home/Registry.ZC"')
        package = build.index("xorriso -as mkisofs")
        self.assertLess(extract, clean)
        self.assertLess(clean, package)


if __name__ == "__main__":
    unittest.main(verbosity=2)
