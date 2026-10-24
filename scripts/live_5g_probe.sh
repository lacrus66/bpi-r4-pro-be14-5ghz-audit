#!/bin/sh
# Read live 5 GHz (Band 1) OFDM/HE preamble and valid header counters on MT7995AV
DBG=/sys/kernel/debug/ieee80211/phy0/mt76
echo 0x83181010 > $DBG/regidx; c10=$(cat $DBG/regval)
echo 0x83181018 > $DBG/regidx; c18=$(cat $DBG/regval)
echo 0x83181024 > $DBG/regidx; c24=$(cat $DBG/regval)
echo 0x83181028 > $DBG/regidx; c28=$(cat $DBG/regval)
echo "5G PHY Counters: 1010(preambles)=$c10 | 1018(valid_hdr)=$c18 | 1024(valid_pkt)=$c24 | 1028(lsig_err)=$c28"
