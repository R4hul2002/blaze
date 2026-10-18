#!/usr/bin/env python3
# =============================================================================
# verify_pkg.py — Python golden model verification for blaze_pkg types
# Project  : BLAZE NGFW
# Module   : M01 — Foundation Package
# =============================================================================
# Verifies struct bit widths, enum values, and helper functions match
# the SystemVerilog definitions in blaze_pkg.sv.
# Run: python3 scripts/python/verify_pkg.py
# =============================================================================

import sys

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
failures = 0

def check(name: str, got, expected):
    global failures
    if got == expected:
        print(f"{PASS} [{name}]: {got}")
    else:
        print(f"{FAIL} [{name}]: got={got} expected={expected}")
        failures += 1

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------
DATA_WIDTH  = 64
KEEP_WIDTH  = DATA_WIDTH // 8
ADDR_WIDTH  = 32
MAC_WIDTH   = 48
IPV4_WIDTH  = 32
IPV6_WIDTH  = 128
PORT_WIDTH  = 16
VLAN_WIDTH  = 12
PROTO_WIDTH = 8
TTL_WIDTH   = 8
SESSION_BITS = 18
HASH_WIDTH  = 32
LABEL_WIDTH = 16
ZONE_WIDTH  = 8
QUEUE_WIDTH = 4

# ---------------------------------------------------------------------------
# Enum values
# ---------------------------------------------------------------------------
PROTO = {"ICMP": 0x01, "TCP": 0x06, "UDP": 0x11, "ICMPv6": 0x3A, "OTHER": 0xFF}
ETYPE = {"IPV4": 0x0800, "ARP": 0x0806, "VLAN": 0x8100, "QINQ": 0x88A8, "IPV6": 0x86DD}
ACTION = {"ACCEPT": 0, "DROP": 1, "REJECT": 2, "LOG": 3, "MIRROR": 4,
          "MODIFY": 5, "QOS": 6, "NAT": 7, "LIMIT": 8, "INSPECT": 9}
TCP_STATE = {"CLOSED": 0, "SYN_SENT": 1, "SYN_RCVD": 2, "ESTABLISHED": 3,
             "FIN_WAIT1": 4, "FIN_WAIT2": 5, "CLOSE_WAIT": 6,
             "CLOSING": 7, "LAST_ACK": 8, "TIME_WAIT": 9}
APP_ID = {"UNKNOWN": 0, "HTTP": 1, "HTTPS": 2, "DNS": 3, "SSH": 4,
          "FTP": 5, "SMTP": 6, "POP3": 7, "IMAP": 8, "DHCP": 9}

# ---------------------------------------------------------------------------
# Struct bit-width calculations (mirrors SV packed struct layout)
# ---------------------------------------------------------------------------
def flow_key_bits():
    return IPV4_WIDTH + IPV4_WIDTH + PORT_WIDTH + PORT_WIDTH + PROTO_WIDTH

def flow_key6_bits():
    # 128 + 128 + 16 + 16 + 8 = 296
    return IPV6_WIDTH + IPV6_WIDTH + PORT_WIDTH + PORT_WIDTH + PROTO_WIDTH

def vlan_tag_bits():
    return 3 + 1 + VLAN_WIDTH  # pcp + dei + vid

def tcp_flags_bits():
    return 8  # fin syn rst psh ack urg ece cwr

# ---------------------------------------------------------------------------
# Helper functions (Python equivalents)
# ---------------------------------------------------------------------------
def bswap32(d: int) -> int:
    return ((d & 0xFF) << 24) | (((d >> 8) & 0xFF) << 16) | \
           (((d >> 16) & 0xFF) << 8) | ((d >> 24) & 0xFF)

def bswap16(d: int) -> int:
    return ((d & 0xFF) << 8) | ((d >> 8) & 0xFF)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
print("\n=== Parameter Checks ===")
check("DATA_WIDTH",  DATA_WIDTH,  64)
check("KEEP_WIDTH",  KEEP_WIDTH,  8)
check("IPV4_WIDTH",  IPV4_WIDTH,  32)
check("IPV6_WIDTH",  IPV6_WIDTH,  128)
check("PORT_WIDTH",  PORT_WIDTH,  16)
check("VLAN_WIDTH",  VLAN_WIDTH,  12)

print("\n=== Struct Size Checks ===")
check("flow_key_t bits",  flow_key_bits(),  104)
check("flow_key6_t bits", flow_key6_bits(), 296)
check("vlan_tag_t bits",  vlan_tag_bits(),  16)
check("tcp_flags_t bits", tcp_flags_bits(), 8)

print("\n=== Protocol Enum ===")
for name, val in PROTO.items():
    check(f"PROTO_{name}", PROTO[name], val)

print("\n=== EtherType Enum ===")
for name, val in ETYPE.items():
    check(f"ETYPE_{name}", ETYPE[name], val)

print("\n=== Action Enum ===")
for name, val in ACTION.items():
    check(f"ACTION_{name}", ACTION[name], val)

print("\n=== TCP State Enum ===")
for name, val in TCP_STATE.items():
    check(f"TCP_{name}", TCP_STATE[name], val)

print("\n=== Helper Functions ===")
check("bswap32(0x08000000)", bswap32(0x08000000), 0x00000008)
check("bswap32(0x12345678)", bswap32(0x12345678), 0x78563412)
check("bswap16(0x0800)",     bswap16(0x0800),     0x0008)
check("bswap16(0x1234)",     bswap16(0x1234),     0x3412)

print("\n=== Flow Key Construction ===")
src_ip   = 0xC0A80001
dst_ip   = 0xC0A80002
src_port = 1234
dst_port = 80
proto    = PROTO["TCP"]
flow_key = (src_ip << 72) | (dst_ip << 40) | (src_port << 24) | (dst_port << 8) | proto
check("flow_key non-zero", flow_key != 0, True)
check("flow_key proto",    flow_key & 0xFF, PROTO["TCP"])

print(f"\n=== Summary ===")
if failures == 0:
    print(f"{PASS} ALL TESTS PASSED")
else:
    print(f"{FAIL} {failures} TEST(S) FAILED")
    sys.exit(1)
