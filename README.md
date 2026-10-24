# BPI-R4-NIC-BE14 (MT7995AV 0x7990, 2-3-3 2i5i6i): 5 GHz Band 1 RF Attenuation, RFSPI (MT7976CN / MT7977IAN), WF_PHY and EEPROM Audit

## Summary & Hardware Environment

This repository contains raw register dumps, hardware measurements, and diagnostic scripts for the **SinoVoip BPI-R4-NIC-BE14** Wi-Fi 7 tri-band mini-PCIe module (**MediaTek Filogic 680 `MT7995AV`**, PCI ID `14c3:7990` + `14c3:7991`, `2-3-3` antenna layout with internal FEMs `2i5i6i`) installed in a **Banana Pi BPI-R4 Pro 8X** (`bananapi,bpi-r4-pro-8x`, **MediaTek `MT7988A`**) running **OpenWrt SNAPSHOT (Linux kernel `6.18.44`, `mt76` / `mt7996e`, WM firmware `20250909121549` / `20260311120702`)**.

- **Band 0 (2.4 GHz, `phy0.0-ap0`, `ADIE 0` `MT7976CN` chains 0..1)**: operates normally on TX and RX (`-28 dBm` RSSI at 1 m).
- **Band 2 (6 GHz, `phy0.2-ap0`, `ADIE 2` `MT7977IAN` chains 0..2)**: operates normally on TX and RX (`EHT320` on Ch 37 `6135 MHz`, clients associate and pass traffic).
- **Band 1 (5 GHz, `phy0.1-ap0`, `ADIE 0` `MT7976CN` chains 2..4)**: completes `hostapd` setup (`ENABLE_DONE`), runs `NormalTRx` calibration, and increments `tx_mpdu_cnt` / `ch_time_tx` / `ch_time_busy`, but exhibits **~70 dB of physical RF attenuation on both RX and TX** (`-95 dBm` received signal level in monitor mode when a `+22 dBm` transmitter is 50 cm away).

---

## Error Signatures & Root Causes

- **`WM: (RDM-E) [rdmDoRunTmAlgoInFw] in one sec after fail == 30, 30!`** on `MT7995AV` (`2-3-3` layout where `ADIE 1` at `0x1f000000` is unpopulated): caused by bit 7 / bits `[6:5]` in EEPROM byte `0x0198` (`0x80` or `0x60`) enabling the dedicated Background Radar / ZWDFS RX path on the absent `ADIE 1`. Clearing `0x0198 = 0x00` and `0x01af = 0x00` (with `background_radar = 0`) eliminates the error (`fail == 0, 0!`).
- **`Cal_Flow_NormalTRx: ePhyIdx[1] Band[1]Rfband[2]` aborting early (`1.68 ms` / `62 ms`)**: clearing `0x0198 = 0x00` restores the full **`503.75 ms` `NormalTRx` calibration** on `ePhyIdx[1]` (5 GHz) and clears `0x83180000` from `0x01010000` to `0x00000000`.
- **`mt7996e: eeprom load fail, use default bin` on `BPI-R4-NIC-BE14` with blank eFuse (`0x7990` only at `0x0000`)**: forcing `FLASH_MODE = 2` in `mt7996_eeprom.c` ensures the full 7680-byte (`0x1e00`) EEPROM table is pushed via `mt7996_mcu_set_eeprom()` instead of the MCU reading blank eFuse blocks during `NormalTRx`.
- **Band 1 (`phy0.1-ap0`) `rx_mpdu_cnt = 0` despite active `ch_time_busy`**: with `MT_WF_RFCR` (`0x820f5000`) set to `0x00000000` (`monitor fcsfail otherbss control`), frames from a `+22 dBm` transmitter at 50 cm (`-19 dBm` incident field) are captured in `tcpdump` at **`-95 dBm signal`**, while the PHY preamble detector `0x83181010` increments by `+280` preambles during a 4s ping flood.

---

## Register-Level Investigation (`mt7996e` / `MT7995AV`)

### 1. eFuse vs EEPROM & `0x0198` ZWDFS Calibration Fix
1. On `2-3-3` cards (`ADIE 0 = MT7976CN 0x7976`, `ADIE 1 = 0x0000`, `ADIE 2 = MT7977IAN 0x7977`), having `0x0198 = 0x80` (or `0x60` in default `mt7996_eeprom_233_2i5i6i.bin`) instructs the WM MCU to poll `ADIE 1` for background radar, producing `[rdmDoRunTmAlgoInFw] in one sec after fail == 30, 30!` every second and truncating 5 GHz `NormalTRx` calibration to `62 ms`.
2. Setting `0x0198 = 0x00` and `0x01af = 0x00` in `/lib/firmware/mediatek/mt7996/mt7996_eeprom_233_2i5i6i.bin` with `uci set wireless.radio1.background_radar='0'` results in:
   - `[rdmDoRunTmAlgoInFw] in one sec after fail == 0, 0!`
   - Full `503.75 ms` `NormalTRx` execution on `ePhyIdx[1]` (`20.016205 -> 20.519959`).
   - `0x83180000` reading `0x00000000` (matching `0x83080000` and `0x83280000`).
3. However, the ~70 dB RF attenuation on 5 GHz persists after full calibration.

### 2. `ADIE 0` (`MT7976CN`) RFSPI Register State (`0x0f000000..0x0f000ffc`)
- Inside `ADIE 0` (`0x0f00002c = 0x79768a10`), all three 5 GHz RF chains (`0x01c8`, `0x01dc`, `0x0724`) are enabled with the same bitmasks as the two working 2.4 GHz chains (`0x01a0`, `0x01b4`):
  - Ch 44 (`5220 MHz`): `0x01c8 = 0x01dc = 0x0724 = 0xe3149186`
  - Ch 149 (`5745 MHz`): `0x01c8 = 0x01dc = 0x0724 = 0xe3349186`
- Synthesizer / PLL registers (`0x0320..0x0378`, `0x0620..0x0678`) lock and track channel frequency changes (`5220 MHz` vs `5745 MHz`).
- Band chain masks `0x0f0004ac = 0x0003001c`, `0x0f0004b0 = 0x00000003` (2.4G WF0..1), and `0x0f0004b4 = 0x0000001c` (5G WF2..4) are properly set.
- Per-chain antenna isolation tests (`iw phy phy0 set antenna 0xe7 / 0xeb / 0xf3`) confirm identical behavior across all three 5 GHz chains.

### 3. 64 KB `WF_PHY` (`0x830xxxxx` vs `0x831xxxxx` vs `0x832xxxxx`) Diff
Scanning all 16,384 registers (`0x0000..0xfffc`) across windows `+0x000000`, `+0x080000`, and `+0x0a0000` shows:
- In per-chain window `+0x000000`:
  - `+0x73a0` (RO): `8300=0x00000101, 8301=0x00000101 | 8310=0, 8311=0, 8312=0, 8313=0x00000d06, 8314=0 | 8320=0x07000701`
  - `+0xd0dc`: `8300=0x7, 8301=0x7 | 8310..8312=0, 8313=0x00000077 | 8320=0x4`
  - `+0x7858..+0x7ad0` and `+0xc200 = 0x03000000`: non-zero in `0x8313xxxx` (chain index 3) while `0x00000000` in `0x8310..0x8312` (chains 0..2).
  - `+0x76b0..+0x76f8`, `+0xc060..+0xc248`, `+0xd24c`: populated on `8300/8301` (Band 0) and `8320` (Band 2), but `0x00000000` on `8310..8312` (Band 1).
- In common PHY window `+0x080000`:
  - `+0x0c60` (RO): `83080c60 = 0x03000000 | 83180c60 = 0x00000000 | 83280c60 = 0x03000000`
  - `+0x62cc, +0x62dc`: `8308 = 0x1, 0x78 | 8318 = 0, 0 | 8328 = 0x7e, 0x7b`

### 4. `MT7995AV` `ANTSEL / GPIO` (`0x70005000..0x70005380`)
- `0x70005300..0x70005350`: `0x11100000`, `0x00000011`, `0x11111100`, `0x11111111`, `0x11111111`, `0x11111111` (pins `5..9` and `18..47` configured in `ANTSEL` mode `1`).
- `GPIO_DIN0` (`0x70005200`) reads `0xdbfd8392` when `wifi down` and `0xdbed8392` when `wifi up` (`GPIO 20` transitions `1 -> 0`), while `GPIO_DIN1` (`0x70005210`) reads `0x7c01f007`.
- With `OE = 0` and `PINMUX = 0` (input float state), `DIN0 = 0x1bfd83d2` and `DIN1 = 0x7c210000`.
- Overriding `ANTSEL` pins `30..31` from `11` to `00` reduces the 5 GHz preamble count `0x83181010` during a 4s ping flood by **6.5x (`+134 -> +21`)**, while all other tested `ANTSEL` truth-table combinations on `GPIO 18..63` either reduce `0x83181010` or leave the ~70 dB attenuation unchanged.

---

## Host Board Note (`mediatek/filogic` — Banana Pi BPI-R4 Pro 8X `PCA9555`)

Separately from `mt76`, on the **Banana Pi BPI-R4 Pro 8X** motherboard, an I2C GPIO expander `PCA9555` (`3-0020`, `gpiochip596..611`) controls mini-PCIe slot power:
- `gpio604` (`gpiochip1` `gpio-8`): Slot 0 (`11300000.pcie`) power enable (`1` = ON).
- `gpio605` (`gpiochip1` `gpio-9`): Slot 1 (`11310000.pcie`) power enable (`1` = ON).
- `gpio603` (`gpiochip1` `gpio-7`): Mini-PCIe `3V3` rail voltage select (`0` = `3.30V`, `1` = `3.57V`). Setting `gpio603 = 1` causes `11300000.pcie` LTSSM link training to fail (`detect.quiet 0x0`) on warm reboot; keep `gpio603 = 0`.

---

## Repository Contents
- [`POST_FOR_MT76_AND_BPI_FORUM.md`](./POST_FOR_MT76_AND_BPI_FORUM.md) — Issue summary for `openwrt/mt76` and Banana Pi forum.
- [`LAB_NOTES_RU.md`](./LAB_NOTES_RU.md) — Chronological lab notes and raw register measurements (in Russian).
- [`scripts/scan_wf_phy_ucode.sh`](./scripts/scan_wf_phy_ucode.sh) — OpenWrt `ucode` scanner that diffs all 16,384 registers (`0x0000..0xfffc`) of `WF_PHY` across Bands 0, 1, and 2.
- [`scripts/live_5g_probe.sh`](./scripts/live_5g_probe.sh) — Live 5 GHz preamble (`0x83181010`) and valid header (`0x83181018` / `0x83181024`) counter probe.
