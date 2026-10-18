// =============================================================================
// blaze_pkg.sv — Global Types, Parameters, Enumerations, Structs
// Project  : BLAZE NGFW
// Module   : M01 — Foundation Package
// Target   : AMD Xilinx Artix-7 (AX7203)
// Toolchain: Vivado 2023.x / SystemVerilog
// =============================================================================

`ifndef BLAZE_PKG_SV
`define BLAZE_PKG_SV

package blaze_pkg;

  // ---------------------------------------------------------------------------
  // Global Bus Parameters
  // ---------------------------------------------------------------------------
  parameter int unsigned DATA_WIDTH       = 64;
  parameter int unsigned KEEP_WIDTH       = DATA_WIDTH / 8;
  parameter int unsigned ADDR_WIDTH       = 32;
  parameter int unsigned ID_WIDTH         = 8;
  parameter int unsigned USER_WIDTH       = 1;

  // ---------------------------------------------------------------------------
  // Network Parameters
  // ---------------------------------------------------------------------------
  parameter int unsigned MAC_WIDTH        = 48;
  parameter int unsigned IPV4_WIDTH       = 32;
  parameter int unsigned IPV6_WIDTH       = 128;
  parameter int unsigned PORT_WIDTH       = 16;
  parameter int unsigned VLAN_WIDTH       = 12;
  parameter int unsigned TTL_WIDTH        = 8;
  parameter int unsigned PROTO_WIDTH      = 8;

  // ---------------------------------------------------------------------------
  // Table Sizing
  // ---------------------------------------------------------------------------
  parameter int unsigned FLOW_TABLE_BITS  = 18;   // 256K entries
  parameter int unsigned RULE_TABLE_BITS  = 17;   // 128K rules
  parameter int unsigned SESSION_BITS     = 18;
  parameter int unsigned HASH_WIDTH       = 32;
  parameter int unsigned LABEL_WIDTH      = 16;
  parameter int unsigned ZONE_WIDTH       = 8;
  parameter int unsigned QUEUE_WIDTH      = 4;    // 16 QoS queues
  parameter int unsigned VLAN_STACK_DEPTH = 2;

  // ---------------------------------------------------------------------------
  // Packet Buffer
  // ---------------------------------------------------------------------------
  parameter int unsigned PKT_BUF_DEPTH    = 4096;
  parameter int unsigned MAX_PKT_BYTES    = 9216; // jumbo frame
  parameter int unsigned MIN_PKT_BYTES    = 64;

  // ---------------------------------------------------------------------------
  // Timeout (cycles @ 125 MHz)
  // ---------------------------------------------------------------------------
  parameter int unsigned TCP_TIMEOUT_CYC  = 125_000_000 * 300;
  parameter int unsigned UDP_TIMEOUT_CYC  = 125_000_000 * 30;
  parameter int unsigned ICMP_TIMEOUT_CYC = 125_000_000 * 10;
  parameter int unsigned SYN_TIMEOUT_CYC  = 125_000_000 * 10;

  // ---------------------------------------------------------------------------
  // Protocol Enumeration
  // ---------------------------------------------------------------------------
  typedef enum logic [PROTO_WIDTH-1:0] {
    PROTO_ICMP   = 8'h01,
    PROTO_TCP    = 8'h06,
    PROTO_UDP    = 8'h11,
    PROTO_ICMPv6 = 8'h3A,
    PROTO_OTHER  = 8'hFF
  } proto_t;

  // ---------------------------------------------------------------------------
  // EtherType
  // ---------------------------------------------------------------------------
  typedef enum logic [15:0] {
    ETYPE_IPV4  = 16'h0800,
    ETYPE_ARP   = 16'h0806,
    ETYPE_VLAN  = 16'h8100,
    ETYPE_QINQ  = 16'h88A8,
    ETYPE_IPV6  = 16'h86DD,
    ETYPE_OTHER = 16'hFFFF
  } etype_t;

  // ---------------------------------------------------------------------------
  // TCP Flags
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic fin, syn, rst, psh, ack, urg, ece, cwr;
  } tcp_flags_t;

  // ---------------------------------------------------------------------------
  // TCP State Machine
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    TCP_CLOSED      = 4'd0,
    TCP_SYN_SENT    = 4'd1,
    TCP_SYN_RCVD    = 4'd2,
    TCP_ESTABLISHED = 4'd3,
    TCP_FIN_WAIT1   = 4'd4,
    TCP_FIN_WAIT2   = 4'd5,
    TCP_CLOSE_WAIT  = 4'd6,
    TCP_CLOSING     = 4'd7,
    TCP_LAST_ACK    = 4'd8,
    TCP_TIME_WAIT   = 4'd9
  } tcp_state_t;

  // ---------------------------------------------------------------------------
  // Firewall Action
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ACTION_ACCEPT  = 4'd0,
    ACTION_DROP    = 4'd1,
    ACTION_REJECT  = 4'd2,
    ACTION_LOG     = 4'd3,
    ACTION_MIRROR  = 4'd4,
    ACTION_MODIFY  = 4'd5,
    ACTION_QOS     = 4'd6,
    ACTION_NAT     = 4'd7,
    ACTION_LIMIT   = 4'd8,
    ACTION_INSPECT = 4'd9
  } action_t;

  // ---------------------------------------------------------------------------
  // Packet Direction
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    DIR_INGRESS  = 2'd0,
    DIR_EGRESS   = 2'd1,
    DIR_INTERNAL = 2'd2,
    DIR_UNKNOWN  = 2'd3
  } direction_t;

  // ---------------------------------------------------------------------------
  // Threat Level
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    THREAT_NONE     = 3'd0,
    THREAT_LOW      = 3'd1,
    THREAT_MEDIUM   = 3'd2,
    THREAT_HIGH     = 3'd3,
    THREAT_CRITICAL = 3'd4
  } threat_level_t;

  // ---------------------------------------------------------------------------
  // Application ID
  // ---------------------------------------------------------------------------
  typedef enum logic [7:0] {
    APP_UNKNOWN = 8'd0,
    APP_HTTP    = 8'd1,
    APP_HTTPS   = 8'd2,
    APP_DNS     = 8'd3,
    APP_SSH     = 8'd4,
    APP_FTP     = 8'd5,
    APP_SMTP    = 8'd6,
    APP_POP3    = 8'd7,
    APP_IMAP    = 8'd8,
    APP_DHCP    = 8'd9,
    APP_TELNET  = 8'd10,
    APP_SNMP    = 8'd11,
    APP_NTP     = 8'd12,
    APP_LDAP    = 8'd13,
    APP_RDP     = 8'd14,
    APP_CUSTOM  = 8'hFF
  } app_id_t;

  // ---------------------------------------------------------------------------
  // VLAN Tag
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [2:0]           pcp;
    logic                 dei;
    logic [VLAN_WIDTH-1:0] vid;
  } vlan_tag_t;

  // ---------------------------------------------------------------------------
  // Five-Tuple Flow Key (IPv4)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [IPV4_WIDTH-1:0]  src_ip;
    logic [IPV4_WIDTH-1:0]  dst_ip;
    logic [PORT_WIDTH-1:0]  src_port;
    logic [PORT_WIDTH-1:0]  dst_port;
    logic [PROTO_WIDTH-1:0] protocol;
  } flow_key_t;  // 104 bits

  // ---------------------------------------------------------------------------
  // Five-Tuple Flow Key (IPv6)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [IPV6_WIDTH-1:0]  src_ip6;
    logic [IPV6_WIDTH-1:0]  dst_ip6;
    logic [PORT_WIDTH-1:0]  src_port;
    logic [PORT_WIDTH-1:0]  dst_port;
    logic [PROTO_WIDTH-1:0] protocol;
  } flow_key6_t;  // 264 bits

  // ---------------------------------------------------------------------------
  // Packet Metadata — sideband bus between all pipeline stages
  // ---------------------------------------------------------------------------
  typedef struct packed {
    // Identifiers
    logic [31:0]             pkt_id;
    logic [HASH_WIDTH-1:0]   flow_hash;
    logic [LABEL_WIDTH-1:0]  flow_label;
    logic [ZONE_WIDTH-1:0]   src_zone;
    logic [ZONE_WIDTH-1:0]   dst_zone;

    // L2
    logic [MAC_WIDTH-1:0]    src_mac;
    logic [MAC_WIDTH-1:0]    dst_mac;
    logic [15:0]             ethertype;
    logic                    has_vlan;
    logic                    has_qinq;
    vlan_tag_t               outer_vlan;
    vlan_tag_t               inner_vlan;

    // L3
    logic                    is_ipv4;
    logic                    is_ipv6;
    logic                    is_arp;
    logic [IPV4_WIDTH-1:0]   src_ip4;
    logic [IPV4_WIDTH-1:0]   dst_ip4;
    logic [IPV6_WIDTH-1:0]   src_ip6;
    logic [IPV6_WIDTH-1:0]   dst_ip6;
    logic [TTL_WIDTH-1:0]    ttl;
    logic [PROTO_WIDTH-1:0]  ip_proto;
    logic [5:0]              dscp;
    logic [1:0]              ecn;
    logic                    is_fragment;
    logic                    is_first_frag;
    logic [12:0]             frag_offset;
    logic [15:0]             ip_id;
    logic [15:0]             ip_total_len;

    // L4
    logic [PORT_WIDTH-1:0]   src_port;
    logic [PORT_WIDTH-1:0]   dst_port;
    tcp_flags_t              tcp_flags;
    logic [31:0]             tcp_seq;
    logic [31:0]             tcp_ack;
    logic [15:0]             tcp_window;
    logic [15:0]             udp_len;
    logic [7:0]              icmp_type;
    logic [7:0]              icmp_code;

    // L7
    app_id_t                 app_id;
    logic [7:0]              l7_offset;

    // Session
    logic                    session_hit;
    logic [SESSION_BITS-1:0] session_id;
    tcp_state_t              tcp_state;

    // Decision
    action_t                 action;
    threat_level_t           threat;
    logic                    dpi_match;
    logic                    sig_match;
    logic [15:0]             sig_id;
    logic                    do_nat;
    logic                    do_log;
    logic                    do_mirror;
    logic [QUEUE_WIDTH-1:0]  qos_queue;

    // Geometry
    logic [13:0]             pkt_len;
    direction_t              direction;
    logic [7:0]              port_id;
    logic [63:0]             timestamp;
  } pkt_meta_t;

  // ---------------------------------------------------------------------------
  // Firewall Rule Entry
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [31:0]             rule_id;
    logic [ZONE_WIDTH-1:0]   src_zone;
    logic [ZONE_WIDTH-1:0]   dst_zone;
    logic [IPV4_WIDTH-1:0]   src_ip;
    logic [IPV4_WIDTH-1:0]   src_mask;
    logic [IPV4_WIDTH-1:0]   dst_ip;
    logic [IPV4_WIDTH-1:0]   dst_mask;
    logic [PORT_WIDTH-1:0]   src_port_lo;
    logic [PORT_WIDTH-1:0]   src_port_hi;
    logic [PORT_WIDTH-1:0]   dst_port_lo;
    logic [PORT_WIDTH-1:0]   dst_port_hi;
    logic [PROTO_WIDTH-1:0]  protocol;
    app_id_t                 app_id;
    action_t                 action;
    logic                    log_en;
    logic                    mirror_en;
    logic [QUEUE_WIDTH-1:0]  qos_queue;
    logic [31:0]             rule_priority;
    logic                    enabled;
  } rule_entry_t;

  // ---------------------------------------------------------------------------
  // Flow Table Entry
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic                    valid;
    flow_key_t               key;
    logic [SESSION_BITS-1:0] session_id;
    tcp_state_t              tcp_state;
    action_t                 cached_action;
    logic [QUEUE_WIDTH-1:0]  qos_queue;
    logic                    do_nat;
    logic [IPV4_WIDTH-1:0]   nat_ip;
    logic [PORT_WIDTH-1:0]   nat_port;
    logic [31:0]             pkt_count;
    logic [47:0]             byte_count;
    logic [31:0]             last_seen;
    logic [31:0]             timeout_val;
  } flow_entry_t;

  // ---------------------------------------------------------------------------
  // NAT Entry
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic                    valid;
    logic [IPV4_WIDTH-1:0]   orig_src_ip;
    logic [PORT_WIDTH-1:0]   orig_src_port;
    logic [IPV4_WIDTH-1:0]   xlat_src_ip;
    logic [PORT_WIDTH-1:0]   xlat_src_port;
    logic [31:0]             last_seen;
  } nat_entry_t;

  // ---------------------------------------------------------------------------
  // DPI Signature Entry
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [15:0]             sig_id;
    logic [7:0]              proto;
    threat_level_t           severity;
    action_t                 action;
    logic [15:0]             pattern_len;
    logic                    enabled;
  } sig_entry_t;

  // ---------------------------------------------------------------------------
  // Per-Port Statistics
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [63:0] rx_pkts;
    logic [63:0] rx_bytes;
    logic [63:0] tx_pkts;
    logic [63:0] tx_bytes;
    logic [63:0] drop_pkts;
    logic [63:0] drop_bytes;
    logic [63:0] fwd_pkts;
    logic [63:0] nat_pkts;
    logic [63:0] dpi_hits;
    logic [63:0] sig_hits;
    logic [63:0] acl_drops;
    logic [63:0] flood_drops;
  } port_stats_t;

  // ---------------------------------------------------------------------------
  // Helper Functions
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] bswap32(input logic [31:0] d);
    return {d[7:0], d[15:8], d[23:16], d[31:24]};
  endfunction

  function automatic logic [15:0] bswap16(input logic [15:0] d);
    return {d[7:0], d[15:8]};
  endfunction

  function automatic logic [3:0] onehot2bin(input logic [15:0] oh);
    // One-hot to binary encoder (unrolled for synthesis compatibility)
    logic [3:0] idx;
    idx = 4'd0;
    if (oh[0])  idx = 4'd0;
    if (oh[1])  idx = 4'd1;
    if (oh[2])  idx = 4'd2;
    if (oh[3])  idx = 4'd3;
    if (oh[4])  idx = 4'd4;
    if (oh[5])  idx = 4'd5;
    if (oh[6])  idx = 4'd6;
    if (oh[7])  idx = 4'd7;
    if (oh[8])  idx = 4'd8;
    if (oh[9])  idx = 4'd9;
    if (oh[10]) idx = 4'd10;
    if (oh[11]) idx = 4'd11;
    if (oh[12]) idx = 4'd12;
    if (oh[13]) idx = 4'd13;
    if (oh[14]) idx = 4'd14;
    if (oh[15]) idx = 4'd15;
    return idx;
  endfunction

endpackage : blaze_pkg

`endif // BLAZE_PKG_SV
