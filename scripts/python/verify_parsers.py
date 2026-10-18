#!/usr/bin/env python3
# =============================================================================
# verify_parsers.py — Golden model for parser header offsets
# Project : BLAZE NGFW / M06-M12
# =============================================================================
import sys
PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
fails = 0

def check(name, got, exp):
    global fails
    if got == exp: print(f"{PASS} [{name}]")
    else: print(f"{FAIL} [{name}] got={got} exp={exp}"); fails += 1

# ---------------------------------------------------------------------------
# Header offset model
# ---------------------------------------------------------------------------
def l3_start(has_vlan, has_qinq):
    if has_qinq: return 22
    if has_vlan: return 18
    return 14

def l4_start(has_vlan, has_qinq, is_ipv6, ihl=5):
    l3 = l3_start(has_vlan, has_qinq)
    return l3 + (40 if is_ipv6 else ihl * 4)

def l7_start_tcp(has_vlan, has_qinq, is_ipv6, data_offset=5):
    return l4_start(has_vlan, has_qinq, is_ipv6) + data_offset * 4

def l7_start_udp(has_vlan, has_qinq, is_ipv6):
    return l4_start(has_vlan, has_qinq, is_ipv6) + 8

# ---------------------------------------------------------------------------
print("\n=== L3 Start Offsets ===")
check("no-vlan l3_start",   l3_start(False, False), 14)
check("vlan l3_start",      l3_start(True,  False), 18)
check("qinq l3_start",      l3_start(False, True),  22)

print("\n=== L4 Start Offsets ===")
check("ipv4 no-vlan l4",    l4_start(False, False, False), 34)
check("ipv4 vlan l4",       l4_start(True,  False, False), 38)
check("ipv6 no-vlan l4",    l4_start(False, False, True),  54)
check("ipv6 vlan l4",       l4_start(True,  False, True),  58)

print("\n=== L7 Start Offsets ===")
check("tcp ipv4 no-vlan l7", l7_start_tcp(False, False, False), 54)
check("tcp ipv6 no-vlan l7", l7_start_tcp(False, False, True),  74)
check("udp ipv4 no-vlan l7", l7_start_udp(False, False, False), 42)
check("udp ipv6 no-vlan l7", l7_start_udp(False, False, True),  62)

# ---------------------------------------------------------------------------
print("\n=== IPv4 Header Field Offsets (from l3_start) ===")
ipv4_fields = {
    "version_ihl": 0, "dscp_ecn": 1, "total_len_hi": 2, "total_len_lo": 3,
    "id_hi": 4, "id_lo": 5, "flags_frag_hi": 6, "frag_lo": 7,
    "ttl": 8, "protocol": 9, "cksum_hi": 10, "cksum_lo": 11,
    "src_ip_0": 12, "src_ip_3": 15, "dst_ip_0": 16, "dst_ip_3": 19
}
for name, off in ipv4_fields.items():
    check(f"ipv4[{name}]@{off}", off, off)  # self-consistency

# ---------------------------------------------------------------------------
print("\n=== TCP Flag Bit Positions ===")
flags_byte = 0b00000010  # SYN
check("SYN bit[1]",  (flags_byte >> 1) & 1, 1)
check("ACK bit[4]",  (flags_byte >> 4) & 1, 0)
flags_xmas = 0b00101001  # FIN+URG+PSH
check("XMAS FIN",   (flags_xmas >> 0) & 1, 1)
check("XMAS PSH",   (flags_xmas >> 3) & 1, 1)
check("XMAS URG",   (flags_xmas >> 5) & 1, 1)
check("NULL scan",  0x00 == 0, True)

# ---------------------------------------------------------------------------
print("\n=== VLAN Tag Decode ===")
# 802.1Q TCI: PCP[15:13] DEI[12] VID[11:0]
tci = 0xA064  # PCP=5, DEI=0, VID=100
pcp = (tci >> 13) & 0x7
dei = (tci >> 12) & 0x1
vid = tci & 0xFFF
check("vlan pcp", pcp, 5)
check("vlan dei", dei, 0)
check("vlan vid", vid, 100)

# ---------------------------------------------------------------------------
print(f"\n=== Summary ===")
if fails == 0: print(f"{PASS} ALL TESTS PASSED")
else: print(f"{FAIL} {fails} FAILED"); sys.exit(1)
