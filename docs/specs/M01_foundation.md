# MODULE 01 — Foundation Package & Interfaces
## BLAZE NGFW — Functional Specification

---

## 1. Purpose

Establishes the shared type system, constants, interfaces, and build infrastructure
used by every subsequent module. No logic is synthesized from this module — it is
purely a compile-time dependency.

---

## 2. Files Delivered

| File | Description |
|------|-------------|
| `rtl/pkg/blaze_pkg.sv` | SystemVerilog package: all types, enums, structs, functions |
| `rtl/pkg/axis_if.sv` | AXI4-Stream parameterized interface |
| `rtl/pkg/axil_if.sv` | AXI4-Lite parameterized interface |
| `rtl/pkg/axi4_if.sv` | AXI4 full parameterized interface |
| `rtl/pkg/meta_if.sv` | Packet metadata sideband interface |
| `tb/pkg/tb_blaze_pkg.sv` | Self-checking SystemVerilog testbench |
| `scripts/python/verify_pkg.py` | Python golden model verification |
| `scripts/tcl/create_project.tcl` | Vivado project creation |
| `scripts/tcl/sim_pkg.tcl` | xsim simulation script |
| `scripts/build/build.sh` | Build orchestration |
| `constraints/blaze_timing.xdc` | Master timing constraints |

---

## 3. Key Types

### pkt_meta_t (sideband metadata)
Carried alongside every AXI-Stream beat through the entire pipeline.
Contains all parsed header fields, session state, and firewall decision.

Fields grouped by layer:
- Identifiers: pkt_id, flow_hash, flow_label, zones
- L2: src_mac, dst_mac, ethertype, VLAN tags
- L3: IPv4/IPv6 addresses, TTL, protocol, fragmentation
- L4: ports, TCP flags/seq/ack/window, UDP len, ICMP type/code
- L7: app_id, l7_offset
- Session: session_hit, session_id, tcp_state
- Decision: action, threat, dpi_match, sig_match, NAT/log/mirror flags
- Geometry: pkt_len, direction, port_id, timestamp

### flow_key_t (104 bits)
`{src_ip[32], dst_ip[32], src_port[16], dst_port[16], protocol[8]}`

### rule_entry_t
Full firewall rule with IP/port ranges, protocol, app_id, action, priority.

### flow_entry_t
Flow table entry with cached action, NAT translation, counters, timeout.

---

## 4. Interface Summary

### axis_if
```
tdata  [DATA_W]   — payload
tkeep  [DATA_W/8] — byte enables
tvalid            — data valid
tready            — downstream ready
tlast             — end of packet
tuser  [USER_W]   — tuser[0] = error
```

### axil_if
Standard AXI4-Lite with 5 channels (AW, W, B, AR, R).
Used for all control plane register access.

### axi4_if
Full AXI4 with burst support. Used for DDR3 and DMA.

### meta_if
Wraps pkt_meta_t with valid/ready handshake.
Flows in parallel with axis_if through the pipeline.

---

## 5. Resource Estimation

| Item | Resources |
|------|-----------|
| blaze_pkg.sv | 0 LUTs (compile-time only) |
| axis_if | 0 LUTs (interface wires) |
| axil_if | 0 LUTs (interface wires) |
| axi4_if | 0 LUTs (interface wires) |
| meta_if | 0 LUTs (interface wires) |

---

## 6. Timing

No timing paths — purely structural/type definitions.

---

## 7. Verification Status

| Test | Result |
|------|--------|
| Python verify_pkg.py | PASS (30/30) |
| SV tb_blaze_pkg.sv | Ready for xsim |

---

## 8. Dependencies

None. This is the root of the dependency graph.

---

## 9. Next Module

**M02 — RGMII PHY Interface**
Implements the RGMII DDR I/O interface to the Ethernet PHY,
including IDELAYCTRL calibration and clock domain handling.
