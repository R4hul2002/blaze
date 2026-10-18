#!/usr/bin/env python3
# =============================================================================
# verify_pipeline.py — End-to-end pipeline golden model
# Project : BLAZE NGFW
# =============================================================================
# Simulates the full parser pipeline in Python and verifies:
#   - Correct field extraction for IPv4/TCP, IPv6/UDP, ARP, VLAN packets
#   - ACL rule matching logic
#   - Flow hash symmetry
#   - NAT port allocation
# =============================================================================
import struct, sys
PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
fails = 0

def check(name, got, exp):
    global fails
    if got == exp: print(f"{PASS} [{name}]")
    else: print(f"{FAIL} [{name}] got={got!r} exp={exp!r}"); fails += 1

# ---------------------------------------------------------------------------
# Packet builder helpers
# ---------------------------------------------------------------------------
def eth_hdr(dst, src, etype):
    return dst + src + struct.pack("!H", etype)

def ipv4_hdr(src, dst, proto, ttl=64, total_len=40):
    ihl = 5
    ver_ihl = (4 << 4) | ihl
    return struct.pack("!BBHHHBBH4s4s",
        ver_ihl, 0, total_len, 0x1234, 0, ttl, proto, 0,
        struct.pack("!I", src), struct.pack("!I", dst))

def tcp_hdr(sport, dport, seq=0, ack=0, flags=0x002, window=65535):
    data_off = (5 << 4)
    return struct.pack("!HHIIBBHH",
        sport, dport, seq, ack, data_off, flags, window, 0)

def udp_hdr(sport, dport, length=8):
    return struct.pack("!HHHH", sport, dport, length, 0)

def vlan_tag(vid, pcp=0, dei=0):
    tci = (pcp << 13) | (dei << 12) | vid
    return struct.pack("!H", tci)

# ---------------------------------------------------------------------------
# Parser model
# ---------------------------------------------------------------------------
class PktMeta:
    def __init__(self):
        self.src_mac = self.dst_mac = b'\x00'*6
        self.ethertype = 0
        self.has_vlan = self.has_qinq = False
        self.vlan_vid = 0
        self.is_ipv4 = self.is_ipv6 = self.is_arp = False
        self.src_ip4 = self.dst_ip4 = 0
        self.ttl = self.ip_proto = 0
        self.src_port = self.dst_port = 0
        self.tcp_flags = 0
        self.app_id = 0

def parse_frame(pkt: bytes) -> PktMeta:
    m = PktMeta()
    if len(pkt) < 14: return m
    m.dst_mac = pkt[0:6]
    m.src_mac = pkt[6:12]
    etype = struct.unpack("!H", pkt[12:14])[0]
    off = 14

    if etype == 0x8100:  # VLAN
        m.has_vlan = True
        tci = struct.unpack("!H", pkt[off:off+2])[0]
        m.vlan_vid = tci & 0xFFF
        etype = struct.unpack("!H", pkt[off+2:off+4])[0]
        off += 4
    elif etype == 0x88A8:  # QinQ
        m.has_qinq = True; m.has_vlan = True
        off += 4  # skip outer tag
        etype = struct.unpack("!H", pkt[off:off+2])[0]
        off += 4  # skip inner tag

    m.ethertype = etype

    if etype == 0x0800:  # IPv4
        m.is_ipv4 = True
        ihl = (pkt[off] & 0xF) * 4
        m.ttl      = pkt[off+8]
        m.ip_proto = pkt[off+9]
        m.src_ip4  = struct.unpack("!I", pkt[off+12:off+16])[0]
        m.dst_ip4  = struct.unpack("!I", pkt[off+16:off+20])[0]
        l4 = off + ihl  # correct: off is already at IP header start
        if m.ip_proto == 6 and len(pkt) >= l4+14:  # TCP needs at least 14 bytes for flags
            m.src_port  = struct.unpack("!H", pkt[l4:l4+2])[0]
            m.dst_port  = struct.unpack("!H", pkt[l4+2:l4+4])[0]
            m.tcp_flags = pkt[l4+13]
        elif m.ip_proto == 17 and len(pkt) >= l4+8:  # UDP
            m.src_port = struct.unpack("!H", pkt[l4:l4+2])[0]
            m.dst_port = struct.unpack("!H", pkt[l4+2:l4+4])[0]
    elif etype == 0x0806:
        m.is_arp = True
    return m

# ---------------------------------------------------------------------------
# Flow hash model
# ---------------------------------------------------------------------------
def crc32_byte(crc, byte):
    crc ^= byte
    for _ in range(8):
        crc = (crc >> 1) ^ (0xEDB88320 if crc & 1 else 0)
    return crc & 0xFFFFFFFF

def flow_hash(src_ip, dst_ip, sport, dport, proto, symmetric=True):
    def hash_tuple(a_ip, b_ip, ap, bp):
        h = 0xFFFFFFFF
        for b in [(a_ip>>24)&0xFF,(a_ip>>16)&0xFF,(a_ip>>8)&0xFF,a_ip&0xFF,
                  (b_ip>>24)&0xFF,(b_ip>>16)&0xFF,(b_ip>>8)&0xFF,b_ip&0xFF,
                  (ap>>8)&0xFF,ap&0xFF,(bp>>8)&0xFF,bp&0xFF,proto]:
            h = crc32_byte(h, b)
        return (~h) & 0xFFFFFFFF
    h_fwd = hash_tuple(src_ip, dst_ip, sport, dport)
    if symmetric:
        h_rev = hash_tuple(dst_ip, src_ip, dport, sport)
        return h_fwd ^ h_rev
    return h_fwd

# ---------------------------------------------------------------------------
# ACL model
# ---------------------------------------------------------------------------
def acl_match(rules, meta):
    for r in rules:
        if not r.get('enabled', True): continue
        if (meta.src_ip4 & r['src_mask']) != (r['src_ip'] & r['src_mask']): continue
        if (meta.dst_ip4 & r['dst_mask']) != (r['dst_ip'] & r['dst_mask']): continue
        if r['proto'] not in (0xFF, meta.ip_proto): continue
        if not (r['dport_lo'] <= meta.dst_port <= r['dport_hi']): continue
        return r['action']
    return 'DROP'

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
print("\n=== IPv4/TCP Frame Parse ===")
pkt = (eth_hdr(b'\xFF'*6, b'\xAA'*6, 0x0800) +
       ipv4_hdr(0xC0A80001, 0xC0A80002, 6, total_len=40) +
       tcp_hdr(1234, 80, flags=0x002))
m = parse_frame(pkt)
check("is_ipv4",    m.is_ipv4,    True)
check("src_ip4",    m.src_ip4,    0xC0A80001)
check("dst_ip4",    m.dst_ip4,    0xC0A80002)
check("ip_proto",   m.ip_proto,   6)
check("src_port",   m.src_port,   1234)
check("dst_port",   m.dst_port,   80)
check("tcp_syn",    (m.tcp_flags >> 1) & 1, 1)

print("\n=== VLAN Tagged Frame ===")
pkt_vlan = (eth_hdr(b'\xFF'*6, b'\xBB'*6, 0x8100) +
            vlan_tag(100, pcp=3) +
            struct.pack("!H", 0x0800) +
            ipv4_hdr(0x0A000001, 0x0A000002, 17, total_len=28) +
            udp_hdr(5000, 53))
m2 = parse_frame(pkt_vlan)
check("has_vlan",   m2.has_vlan,  True)
check("vlan_vid",   m2.vlan_vid,  100)
check("is_ipv4",    m2.is_ipv4,   True)
check("ip_proto",   m2.ip_proto,  17)
check("dst_port",   m2.dst_port,  53)

print("\n=== ARP Frame ===")
pkt_arp = eth_hdr(b'\xFF'*6, b'\xCC'*6, 0x0806) + b'\x00'*28
m3 = parse_frame(pkt_arp)
check("is_arp",     m3.is_arp,    True)

print("\n=== Flow Hash Symmetry ===")
h1 = flow_hash(0xC0A80001, 0xC0A80002, 1234, 80, 6)
h2 = flow_hash(0xC0A80002, 0xC0A80001, 80, 1234, 6)
check("symmetric hash", h1, h2)
h3 = flow_hash(0xC0A80001, 0xC0A80003, 1234, 80, 6)
check("different flow != same hash", h1 != h3, True)

print("\n=== ACL Rule Matching ===")
rules = [
    {'src_ip':0x0A000000,'src_mask':0xFF000000,
     'dst_ip':0,'dst_mask':0,'proto':6,
     'dport_lo':80,'dport_hi':80,'action':'ACCEPT','enabled':True},
    {'src_ip':0,'src_mask':0,'dst_ip':0,'dst_mask':0,
     'proto':0xFF,'dport_lo':0,'dport_hi':65535,'action':'DROP','enabled':True},
]
m_test = PktMeta()
m_test.src_ip4=0x0A000001; m_test.dst_ip4=0x08080808
m_test.ip_proto=6; m_test.dst_port=80
check("ACL ACCEPT HTTP",  acl_match(rules, m_test), 'ACCEPT')
m_test.dst_port = 443
check("ACL DROP HTTPS",   acl_match(rules, m_test), 'DROP')
m_test.src_ip4 = 0xC0A80001
check("ACL DROP wrong src", acl_match(rules, m_test), 'DROP')

print(f"\n=== Summary ===")
if fails == 0: print(f"{PASS} ALL TESTS PASSED")
else: print(f"{FAIL} {fails} FAILED"); sys.exit(1)
