# [mt7996e] BPI-R4 Pro 8X + BPI-R4-NIC-BE14 (MT7995AV 2-3-3): 5 GHz Band 1 has ~70 dB RF attenuation (-95 dBm RX) while 2.4 GHz & 6 GHz work normally

### Hardware & Software Environment
- **Host Board**: Banana Pi **BPI-R4 Pro 8X** (`bananapi,bpi-r4-pro-8x`, MediaTek MT7988A Filogic 880)
- **Wi-Fi 7 Module**: SinoVoip **BPI-R4-NIC-BE14** (`MT7995AV` `0x7990`, dual PCIe `0000:01:00.0` + `0001:01:00.0`, 2-3-3 configuration with internal FEMs `2i5i6i`: `ADIE 0 = MT7976CN 0x7976` for 2.4G+5G, `ADIE 1 = 0x0000`, `ADIE 2 = MT7977IAN 0x7977` for 6G)
- **OS / Kernel**: OpenWrt SNAPSHOT `r36304-0f8cceb469`, kernel `6.18.44`
- **WM Firmware**: `20250909121549` (`mt7996_wm.bin`)

---

### Problem Summary
On the **BPI-R4 Pro 8X** with the **BPI-R4-NIC-BE14** module:
- **Band 0 (2.4 GHz, `phy0.0-ap0`, `ADIE 0` chains 0..1)** works normally on both TX and RX (`-28 dBm` RSSI at 1m).
- **Band 2 (6 GHz, `phy0.2-ap0`, `ADIE 2` `MT7977IAN` chains 0..2)** works normally on both TX and RX (`EHT320` on Ch 37 `6135 MHz`, clients connect and pass traffic).
- **Band 1 (5 GHz, `phy0.1-ap0`, `ADIE 0` `MT7976CN` chains 2..4)** comes up cleanly in `hostapd` (`ENABLE_DONE`), completes `NormalTRx` calibration, and increments `tx_mpdu_cnt` / `ch_time_tx` / `ch_time_busy`, **but experiences ~70 dB of physical RF attenuation on both RX and TX**:
  - No 5 GHz beacons are visible over the air even 50 cm from the antennas (`iw dev scan freq 5220 flush`).
  - When a laptop (`+22 dBm` TX on Channel 44 `5220 MHz HE80`) is placed 50 cm from the router antennas (`-19 dBm` incident field), the 5 GHz baseband correlates preambles (`0x83181010` increments by `+280` during a 4s ping flood, `ch_time_busy` jumps from `28 ms` on idle Ch 149 to `7883 ms` on busy Ch 44), but with `MT_WF_RFCR` (`0x820f5000`) set to `0x00000000` (`monitor fcsfail otherbss control`), captured frames in `tcpdump` arrive at **`-95 dBm signal`** (right at the thermal noise floor, ~70 dB below expected `-20..-25 dBm`).

---

### Deep Hardware & Register Diagnosis Already Performed

#### 1. eFuse vs EEPROM & `0x0198` Radar/ZWDFS Calibration Fix
1. The card's internal eFuse is blank except for `0x0000 = 0x7990`. Under default OpenWrt fallback (`mt7996_eeprom_233_2i5i6i.bin`), we tested both standard fallback and `FLASH_MODE = 2` with the card's native calibration dump (`be14_native.bin`).
2. In `be14_native.bin`, byte `0x0198` had bit 7 set (`0x80`) while `ADIE 1` (`0x1f000000`) is not populated (`0x00000000`), which caused the WM MCU to spam every second:
   `WM: (792.201614:00:RDM-E) [rdmDoRunTmAlgoInFw] in one sec after fail == 30, 30!`
   and shortened `NormalTRx` calibration on `ePhyIdx[1]` (5 GHz) to `62 ms`.
3. Clearing `0x0198 = 0x00` and `0x01af = 0x00` (with `background_radar = 0`) **completely eliminated `[rdmDoRunTmAlgoInFw] fail == 30`** (`fail == 0, 0!`), restored full **`503.75 ms` `NormalTRx` calibration** on `ePhyIdx[1]` (`20.016205 -> 20.519959`), and cleared `0x83180000` from `0x01010000` to `0x00000000`.
4. However, even with `fail == 0, 0!` and a full `503.75 ms` `NormalTRx` calibration, the ~70 dB RF attenuation on 5 GHz remains.

#### 2. `ADIE 0` (`MT7976CN`) RFSPI Register State (`0x0f000000..0x0f000ffc`)
- Inside `ADIE 0` (`0x0f00002c = 0x79768a10`), all three 5 GHz RF chains (`0x01c8`, `0x01dc`, `0x0724`) are enabled identically to the two working 2.4 GHz chains (`0x01a0`, `0x01b4`):
  - Ch 44 (`5220 MHz`): `0x01c8 = 0x01dc = 0x0724 = 0xe3149186`
  - Ch 149 (`5745 MHz`): `0x01c8 = 0x01dc = 0x0724 = 0xe3349186`
  - PLL / Synthesizer (`0x0320..0x0378`, `0x0620..0x0678`) locks properly and tracks channel changes (`5220 MHz` vs `5745 MHz`).
  - Band masks `0x0f0004ac = 0x0003001c`, `0x0f0004b0 = 0x00000003` (2.4G WF0..1), `0x0f0004b4 = 0x0000001c` (5G WF2..4) are properly configured (moving `0x1c` into `0x04b0` drops 5 GHz preamble correlation `0x83181010` by 12x).
  - Per-chain antenna isolation tests (`iw phy phy0 set antenna 0xe7 / 0xeb / 0xf3`) show all three 5 GHz chains behave identically.

#### 3. Full 64 KB `WF_PHY` (`0x830xxxxx` vs `0x831xxxxx` vs `0x832xxxxx`) Diff
Scanning all 16,384 registers (`0x0000..0xfffc`) across windows `+0x000000`, `+0x080000`, and `+0x0a0000` revealed:
- In per-chain window `+0x000000`:
  - `+0x73a0` (RO): `8300=0x00000101, 8301=0x00000101 | 8310=0, 8311=0, 8312=0, 8313=0x00000d06, 8314=0 | 8320=0x07000701`
  - `+0xd0dc`: `8300=0x7, 8301=0x7 | 8310..8312=0, 8313=0x00000077 | 8320=0x4`
  - `+0x76b0..+0x76f8`, `+0xc060..+0xc248`, `+0xd24c`: populated on `8300/8301` (Band 0) and `8320` (Band 2), but `0x00000000` on `8310..8312` (Band 1).
- In common PHY window `+0x080000`:
  - `+0x0c60` (RO): `83080c60 = 0x03000000 | 83180c60 = 0x00000000 | 83280c60 = 0x03000000`
  - `+0x62cc, +0x62dc`: `8308 = 0x1, 0x78 | 8318 = 0, 0 | 8328 = 0x7e, 0x7b`

#### 4. `MT7995AV` `ANTSEL / GPIO` (`0x70005000..0x70005350`) & `BPI-R4 Pro 8X` `PCA9555` (`i2c 3-0020`)
- On `MT7995AV`:
  - `0x70005300..0x70005350`: `0x11100000`, `0x00000011`, `0x11111100`, `0x11111111`, `0x11111111`, `0x11111111` (pins `5..9` and `18..47` in `ANTSEL` mode `1`).
  - `GPIO_DIN0` (`0x70005200`) is `0xdbfd8392` when `wifi down` and `0xdbed8392` when `wifi up` (`GPIO 20` switches from `1` to `0`), while `GPIO_DIN1` (`0x70005210`) is `0x7c01f007`.
  - Overriding the `ANTSEL` pins in GPIO mode changes the 5 GHz preamble count `0x83181010` during a controlled 4s ping flood by **7x (`+187` with `ANTSEL=HIGH` vs `+28` with `ANTSEL=INVERSE`)**, proving that `ANTSEL` pins affect the 5 GHz front-end / switch state on the `BE14` module.
- On the **BPI-R4 Pro 8X** motherboard `PCA9555` (`gpiochip596` at `i2c 3-0020`):
  - Default `gpio604 = 1`, `gpio605 = 1`, while `gpio596..603` are `in lo` (Note: setting `gpio603 = 1` raises `3V3_PCIE` from `3.30V` to `3.57V` and causes `11300000.pcie` LTSSM link training to fail on warm reboot).

---

### Questions for SinoVoip / `mt76` Maintainers
1. On the **BPI-R4-NIC-BE14** (`MT7995AV` 2-3-3 `2i5i6i`) installed in the **BPI-R4 Pro 8X**, is there an external 5 GHz RF switch (`TRSW` / diplexer) or a separate 5 GHz `AVDD33` LDO enable pin controlled by a specific `MT7995AV` `ANTSEL/GPIO` pin or `BPI-R4 Pro 8X` `PCA9555` pin, or does ~70 dB attenuation across all three 5 GHz chains indicate an open `AVDD33_WF5G` power rail on the `BE14` module?
2. Why does `0x83180c60` read `0x00000000` (and `+0x73a0 = 0x00000d06` / `+0x7858..+0x7ad0` / `+0xc200 = 0x03000000` appear in `0x8313xxxx` instead of `0x8310..0x8312`) on Band 1 when `mt7996_eeprom_233_2i5i6i.bin` is used on `MT7995AV`?

### Full Register Dumps, Chronological Lab Log & Scripts
All full register dumps (`ADIE 0` `MT7976CN`, `ADIE 2` `MT7977IAN`, 64 KB `WF_PHY` scans, `GPIO/ANTSEL` truth-table tests, EEPROM diffs, and OpenWrt `ucode` scripts) are published in our open repository:
**https://github.com/lacrus66/bpi-r4-pro-be14-5ghz-audit**
