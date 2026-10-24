#!/bin/sh
# Fast 64 KB WF_PHY register scanner for OpenWrt (mt7996e / MT7995AV) using native ucode
ucode -e '
import * as fs from "fs";
let Z = "0x00000000";
function rr(hi, lo) {
    fs.writefile("/sys/kernel/debug/ieee80211/phy0/mt76/regidx", sprintf("0x%04x%04x\n", hi, lo));
    return trim(fs.readfile("/sys/kernel/debug/ieee80211/phy0/mt76/regval"));
}
for (let win in [0x00, 0x08, 0x0a]) {
    printf("=== SCANNING WINDOW +0x%02x0000 (0x0000..0xfffc) ===\n", win);
    let h0 = 0x8300 + win;
    let h1 = 0x8310 + win;
    let h2 = 0x8320 + win;
    for (let ofs = 0; ofs < 0x10000; ofs += 4) {
        let b0 = rr(h0, ofs);
        let b1 = rr(h1, ofs);
        let b2 = rr(h2, ofs);
        if ((b0 != Z && b2 != Z && b1 == Z) || (b0 == Z && b2 == Z && b1 != Z)) {
            printf("  +0x%04x: B0=%s | B1=%s | B2=%s\n", ofs, b0, b1, b2);
        }
    }
}
'
