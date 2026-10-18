// =============================================================================
// blaze_top.sv — BLAZE NGFW Top-Level Integration
// Project : BLAZE NGFW
// Target  : Artix-7 XC7A200T (AX7203)
// =============================================================================
// Connects all pipeline stages in order:
//   RGMII PHY -> MAC -> Frame Parser -> Packet Buffer ->
//   VLAN -> IPv4 -> IPv6 -> ARP -> TCP -> UDP -> ICMP ->
//   DNS -> HTTP -> TLS -> Flow Hash -> Flow Table ->
//   ACL Engine -> DoS Protect -> NAT -> QoS -> Stats/Log ->
//   Packet Forward -> MAC TX
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module blaze_top (
  // System clock (200 MHz differential)
  input  wire        sys_clk_p,
  input  wire        sys_clk_n,
  input  wire        sys_rst_n,

  // RGMII Port 0
  input  wire        rgmii_rxc,
  input  wire [3:0]  rgmii_rxd,
  input  wire        rgmii_rx_ctl,
  output wire        rgmii_txc,
  output wire [3:0]  rgmii_txd,
  output wire        rgmii_tx_ctl,
  output wire        phy_reset_n,

  // AXI-Lite control (from MicroBlaze)
  input  wire [31:0] s_axil_awaddr,
  input  wire        s_axil_awvalid,
  output wire        s_axil_awready,
  input  wire [31:0] s_axil_wdata,
  input  wire [3:0]  s_axil_wstrb,
  input  wire        s_axil_wvalid,
  output wire        s_axil_wready,
  output wire [1:0]  s_axil_bresp,
  output wire        s_axil_bvalid,
  input  wire        s_axil_bready,
  input  wire [31:0] s_axil_araddr,
  input  wire        s_axil_arvalid,
  output wire        s_axil_arready,
  output wire [31:0] s_axil_rdata,
  output wire [1:0]  s_axil_rresp,
  output wire        s_axil_rvalid,
  input  wire        s_axil_rready,

  // Status LEDs
  output wire [3:0]  led
);

  // ---------------------------------------------------------------------------
  // Clocks and resets
  // ---------------------------------------------------------------------------
  wire clk, clk_200m, rst_n_sync;

  // ---------------------------------------------------------------------------
  // MAC RX/TX wires
  // ---------------------------------------------------------------------------
  wire [7:0]  mac_rx_tdata;
  wire        mac_rx_tvalid, mac_rx_tready, mac_rx_tlast, mac_rx_tuser;
  wire [7:0]  mac_tx_tdata;
  wire        mac_tx_tvalid, mac_tx_tready, mac_tx_tlast;

  // ---------------------------------------------------------------------------
  // Inter-stage wires (8-bit AXI-Stream + pkt_meta_t sideband)
  // ---------------------------------------------------------------------------
  // Naming: <stage>_tdata, <stage>_meta, <stage>_meta_valid

  // Frame parser output
  wire [7:0]  fp_tdata;  wire fp_tvalid, fp_tready, fp_tlast, fp_tuser;
  pkt_meta_t  fp_meta;   wire fp_meta_valid;

  // Packet buffer output
  wire [7:0]  pb_tdata;  wire pb_tvalid, pb_tready, pb_tlast, pb_tuser;
  pkt_meta_t  pb_meta;   wire pb_meta_valid;

  // VLAN parser output
  wire [7:0]  vl_tdata;  wire vl_tvalid, vl_tready, vl_tlast, vl_tuser;
  pkt_meta_t  vl_meta;   wire vl_meta_valid;

  // IPv4 parser output
  wire [7:0]  i4_tdata;  wire i4_tvalid, i4_tready, i4_tlast, i4_tuser;
  pkt_meta_t  i4_meta;   wire i4_meta_valid;

  // IPv6 parser output
  wire [7:0]  i6_tdata;  wire i6_tvalid, i6_tready, i6_tlast, i6_tuser;
  pkt_meta_t  i6_meta;   wire i6_meta_valid;

  // ARP parser output
  wire [7:0]  ar_tdata;  wire ar_tvalid, ar_tready, ar_tlast, ar_tuser;
  pkt_meta_t  ar_meta;   wire ar_meta_valid;

  // TCP parser output
  wire [7:0]  tc_tdata;  wire tc_tvalid, tc_tready, tc_tlast, tc_tuser;
  pkt_meta_t  tc_meta;   wire tc_meta_valid;

  // UDP parser output
  wire [7:0]  ud_tdata;  wire ud_tvalid, ud_tready, ud_tlast, ud_tuser;
  pkt_meta_t  ud_meta;   wire ud_meta_valid;

  // ICMP parser output
  wire [7:0]  ic_tdata;  wire ic_tvalid, ic_tready, ic_tlast, ic_tuser;
  pkt_meta_t  ic_meta;   wire ic_meta_valid;

  // DNS parser output
  wire [7:0]  dn_tdata;  wire dn_tvalid, dn_tready, dn_tlast, dn_tuser;
  pkt_meta_t  dn_meta;   wire dn_meta_valid;

  // HTTP parser output
  wire [7:0]  ht_tdata;  wire ht_tvalid, ht_tready, ht_tlast, ht_tuser;
  pkt_meta_t  ht_meta;   wire ht_meta_valid;

  // TLS parser output
  wire [7:0]  tl_tdata;  wire tl_tvalid, tl_tready, tl_tlast, tl_tuser;
  pkt_meta_t  tl_meta;   wire tl_meta_valid;

  // Flow hash output
  wire [31:0] fh_hash;   wire fh_hash_valid;

  // ACL output
  pkt_meta_t  acl_meta;  wire acl_meta_valid;

  // DoS protect output
  pkt_meta_t  dos_meta;  wire dos_meta_valid;

  // NAT output
  pkt_meta_t  nat_meta;  wire nat_meta_valid;

  // QoS output
  wire [7:0]  qos_tdata; wire qos_tvalid, qos_tready, qos_tlast;

  // Timestamp (free-running 64-bit counter)
  reg [63:0] timestamp_r;
  always_ff @(posedge clk or negedge rst_n_sync)
    if (!rst_n_sync) timestamp_r <= '0;
    else             timestamp_r <= timestamp_r + 1;

  // Rate tick (1 kHz from 125 MHz)
  reg [16:0] rate_tick_cnt;
  wire       rate_tick = (rate_tick_cnt == 17'd124999);
  always_ff @(posedge clk or negedge rst_n_sync)
    if (!rst_n_sync)  rate_tick_cnt <= '0;
    else if (rate_tick) rate_tick_cnt <= '0;
    else              rate_tick_cnt <= rate_tick_cnt + 1;

  // ---------------------------------------------------------------------------
  // Register file
  // ---------------------------------------------------------------------------
  wire        reg_global_en, reg_tx_en, reg_rx_en;
  wire [7:0]  reg_ifg;
  wire [15:0] reg_rule_count;
  wire [31:0] reg_nat_pool, reg_rate_tick_div;
  wire [23:0] reg_rate_cfg [0:15];
  wire [23:0] reg_burst_cfg[0:15];
  wire [31:0] status_flow_count = 32'd0; // tied to flow_table.active_flows
  wire [31:0] status_log_wr_ptr, status_log_rd_ptr;
  wire [1:0]  mac_speed;

  axil_regfile u_regfile (
    .clk              (clk),
    .rst_n            (rst_n_sync),
    .s_awaddr         (s_axil_awaddr),  .s_awvalid (s_axil_awvalid),
    .s_awready        (s_axil_awready),
    .s_wdata          (s_axil_wdata),   .s_wstrb   (s_axil_wstrb),
    .s_wvalid         (s_axil_wvalid),  .s_wready  (s_axil_wready),
    .s_bresp          (s_axil_bresp),   .s_bvalid  (s_axil_bvalid),
    .s_bready         (s_axil_bready),
    .s_araddr         (s_axil_araddr),  .s_arvalid (s_axil_arvalid),
    .s_arready        (s_axil_arready),
    .s_rdata          (s_axil_rdata),   .s_rresp   (s_axil_rresp),
    .s_rvalid         (s_axil_rvalid),  .s_rready  (s_axil_rready),
    .reg_global_en    (reg_global_en),  .reg_tx_en (reg_tx_en),
    .reg_rx_en        (reg_rx_en),      .reg_ifg   (reg_ifg),
    .reg_rule_count   (reg_rule_count), .reg_nat_pool (reg_nat_pool),
    .reg_rate_tick_div(reg_rate_tick_div),
    .reg_rate_cfg     (reg_rate_cfg),   .reg_burst_cfg(reg_burst_cfg),
    .status_speed     (mac_speed),      .status_locked(rst_n_sync),
    .status_flow_count(status_flow_count),
    .status_log_wr_ptr(status_log_wr_ptr),
    .status_log_rd_ptr(status_log_rd_ptr)
  );

  // ---------------------------------------------------------------------------
  // MAC wrapper (Alex Forencich)
  // ---------------------------------------------------------------------------
  blaze_mac_wrapper #(
    .TX_FIFO_DEPTH (4096),
    .RX_FIFO_DEPTH (4096)
  ) u_mac (
    .gtx_clk        (clk),
    .gtx_clk90      (clk),       // TODO: wire 90-deg MMCM output
    .gtx_rst        (~rst_n_sync),
    .logic_clk      (clk),
    .logic_rst      (~rst_n_sync),
    .rgmii_rx_clk   (rgmii_rxc),
    .rgmii_rxd      (rgmii_rxd),
    .rgmii_rx_ctl   (rgmii_rx_ctl),
    .rgmii_tx_clk   (rgmii_txc),
    .rgmii_txd      (rgmii_txd),
    .rgmii_tx_ctl   (rgmii_tx_ctl),
    .tx_axis_tdata  (mac_tx_tdata),
    .tx_axis_tvalid (mac_tx_tvalid & reg_tx_en),
    .tx_axis_tready (mac_tx_tready),
    .tx_axis_tlast  (mac_tx_tlast),
    .tx_axis_tuser  (1'b0),
    .rx_axis_tdata  (mac_rx_tdata),
    .rx_axis_tvalid (mac_rx_tvalid),
    .rx_axis_tready (mac_rx_tready),
    .rx_axis_tlast  (mac_rx_tlast),
    .rx_axis_tuser  (mac_rx_tuser),
    .tx_error_underflow(),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs  (),
    .rx_fifo_overflow  (),
    .speed             (mac_speed),
    .cfg_ifg           (reg_ifg),
    .cfg_tx_enable     (reg_tx_en),
    .cfg_rx_enable     (reg_rx_en)
  );

  // ---------------------------------------------------------------------------
  // Frame Parser
  // ---------------------------------------------------------------------------
  frame_parser u_frame_parser (
    .clk          (clk),          .rst_n       (rst_n_sync),
    .s_tdata      (mac_rx_tdata), .s_tvalid    (mac_rx_tvalid & reg_rx_en),
    .s_tready     (mac_rx_tready),.s_tlast     (mac_rx_tlast),
    .s_tuser      (mac_rx_tuser),
    .m_tdata      (fp_tdata),     .m_tvalid    (fp_tvalid),
    .m_tready     (fp_tready),    .m_tlast     (fp_tlast),
    .m_tuser      (fp_tuser),
    .meta_out     (fp_meta),      .meta_valid  (fp_meta_valid),
    .timestamp    (timestamp_r),  .port_id     (8'd0)
  );

  // ---------------------------------------------------------------------------
  // Packet Buffer
  // ---------------------------------------------------------------------------
  packet_buffer u_pkt_buf (
    .clk          (clk),         .rst_n        (rst_n_sync),
    .wr_tdata     (fp_tdata),    .wr_tvalid    (fp_tvalid),
    .wr_tready    (fp_tready),   .wr_tlast     (fp_tlast),
    .wr_tuser     (fp_tuser),
    .wr_meta      (fp_meta),     .wr_meta_valid(fp_meta_valid),
    .rd_tdata     (pb_tdata),    .rd_tvalid    (pb_tvalid),
    .rd_tready    (pb_tready),   .rd_tlast     (pb_tlast),
    .rd_tuser     (pb_tuser),
    .rd_meta      (pb_meta),     .rd_meta_valid(pb_meta_valid),
    .buf_full     (),            .buf_empty    (),
    .pkt_count    ()
  );

  // ---------------------------------------------------------------------------
  // Parser chain: VLAN -> IPv4 -> IPv6 -> ARP -> TCP -> UDP -> ICMP
  // ---------------------------------------------------------------------------
  vlan_parser u_vlan (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(pb_tdata),.s_tvalid(pb_tvalid),.s_tready(pb_tready),
    .s_tlast(pb_tlast),.s_tuser(pb_tuser),.s_meta(pb_meta),.s_meta_valid(pb_meta_valid),
    .m_tdata(vl_tdata),.m_tvalid(vl_tvalid),.m_tready(vl_tready),
    .m_tlast(vl_tlast),.m_tuser(vl_tuser),.m_meta(vl_meta),.m_meta_valid(vl_meta_valid)
  );

  ipv4_parser u_ipv4 (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(vl_tdata),.s_tvalid(vl_tvalid),.s_tready(vl_tready),
    .s_tlast(vl_tlast),.s_tuser(vl_tuser),.s_meta(vl_meta),.s_meta_valid(vl_meta_valid),
    .m_tdata(i4_tdata),.m_tvalid(i4_tvalid),.m_tready(i4_tready),
    .m_tlast(i4_tlast),.m_tuser(i4_tuser),.m_meta(i4_meta),.m_meta_valid(i4_meta_valid)
  );

  ipv6_parser u_ipv6 (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(i4_tdata),.s_tvalid(i4_tvalid),.s_tready(i4_tready),
    .s_tlast(i4_tlast),.s_tuser(i4_tuser),.s_meta(i4_meta),.s_meta_valid(i4_meta_valid),
    .m_tdata(i6_tdata),.m_tvalid(i6_tvalid),.m_tready(i6_tready),
    .m_tlast(i6_tlast),.m_tuser(i6_tuser),.m_meta(i6_meta),.m_meta_valid(i6_meta_valid)
  );

  arp_parser u_arp (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(i6_tdata),.s_tvalid(i6_tvalid),.s_tready(i6_tready),
    .s_tlast(i6_tlast),.s_tuser(i6_tuser),.s_meta(i6_meta),.s_meta_valid(i6_meta_valid),
    .m_tdata(ar_tdata),.m_tvalid(ar_tvalid),.m_tready(ar_tready),
    .m_tlast(ar_tlast),.m_tuser(ar_tuser),.m_meta(ar_meta),.m_meta_valid(ar_meta_valid),
    .arp_spoof_alert(),.spoof_src_mac(),.spoof_src_ip()
  );

  tcp_parser u_tcp (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(ar_tdata),.s_tvalid(ar_tvalid),.s_tready(ar_tready),
    .s_tlast(ar_tlast),.s_tuser(ar_tuser),.s_meta(ar_meta),.s_meta_valid(ar_meta_valid),
    .m_tdata(tc_tdata),.m_tvalid(tc_tvalid),.m_tready(tc_tready),
    .m_tlast(tc_tlast),.m_tuser(tc_tuser),.m_meta(tc_meta),.m_meta_valid(tc_meta_valid),
    .alert_fin_scan(),.alert_null_scan(),.alert_xmas_scan(),.alert_syn_only()
  );

  udp_parser u_udp (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(tc_tdata),.s_tvalid(tc_tvalid),.s_tready(tc_tready),
    .s_tlast(tc_tlast),.s_tuser(tc_tuser),.s_meta(tc_meta),.s_meta_valid(tc_meta_valid),
    .m_tdata(ud_tdata),.m_tvalid(ud_tvalid),.m_tready(ud_tready),
    .m_tlast(ud_tlast),.m_tuser(ud_tuser),.m_meta(ud_meta),.m_meta_valid(ud_meta_valid)
  );

  icmp_parser u_icmp (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(ud_tdata),.s_tvalid(ud_tvalid),.s_tready(ud_tready),
    .s_tlast(ud_tlast),.s_tuser(ud_tuser),.s_meta(ud_meta),.s_meta_valid(ud_meta_valid),
    .m_tdata(ic_tdata),.m_tvalid(ic_tvalid),.m_tready(ic_tready),
    .m_tlast(ic_tlast),.m_tuser(ic_tuser),.m_meta(ic_meta),.m_meta_valid(ic_meta_valid),
    .icmp_alert()
  );

  // ---------------------------------------------------------------------------
  // L7 Parsers: DNS -> HTTP -> TLS
  // ---------------------------------------------------------------------------
  dns_parser u_dns (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(ic_tdata),.s_tvalid(ic_tvalid),.s_tready(ic_tready),
    .s_tlast(ic_tlast),.s_tuser(ic_tuser),.s_meta(ic_meta),.s_meta_valid(ic_meta_valid),
    .m_tdata(dn_tdata),.m_tvalid(dn_tvalid),.m_tready(dn_tready),
    .m_tlast(dn_tlast),.m_tuser(dn_tuser),.m_meta(dn_meta),.m_meta_valid(dn_meta_valid),
    .dns_tunnel_alert(),.dns_qname_len()
  );

  http_parser u_http (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(dn_tdata),.s_tvalid(dn_tvalid),.s_tready(dn_tready),
    .s_tlast(dn_tlast),.s_tuser(dn_tuser),.s_meta(dn_meta),.s_meta_valid(dn_meta_valid),
    .m_tdata(ht_tdata),.m_tvalid(ht_tvalid),.m_tready(ht_tready),
    .m_tlast(ht_tlast),.m_tuser(ht_tuser),.m_meta(ht_meta),.m_meta_valid(ht_meta_valid),
    .url_buf(),.url_len(),.url_valid()
  );

  tls_parser u_tls (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(ht_tdata),.s_tvalid(ht_tvalid),.s_tready(ht_tready),
    .s_tlast(ht_tlast),.s_tuser(ht_tuser),.s_meta(ht_meta),.s_meta_valid(ht_meta_valid),
    .m_tdata(tl_tdata),.m_tvalid(tl_tvalid),.m_tready(tl_tready),
    .m_tlast(tl_tlast),.m_tuser(tl_tuser),.m_meta(tl_meta),.m_meta_valid(tl_meta_valid),
    .sni_buf(),.sni_len(),.sni_valid()
  );

  // ---------------------------------------------------------------------------
  // Flow Hash
  // ---------------------------------------------------------------------------
  flow_hash u_flow_hash (
    .clk(clk),.rst_n(rst_n_sync),
    .meta_in(tl_meta),.meta_valid(tl_meta_valid),
    .hash_out(fh_hash),.hash_valid(fh_hash_valid)
  );

  // ---------------------------------------------------------------------------
  // ACL Engine
  // ---------------------------------------------------------------------------
  acl_engine #(.MAX_RULES(1024)) u_acl (
    .clk(clk),.rst_n(rst_n_sync),
    .meta_in(tl_meta),.meta_valid(tl_meta_valid),
    .result_valid(acl_meta_valid),.meta_out(acl_meta),
    .rule_wr_en(1'b0),.rule_wr_addr('0),.rule_wr_data('0),
    .rule_count(reg_rule_count[9:0])
  );

  // ---------------------------------------------------------------------------
  // DoS Protection
  // ---------------------------------------------------------------------------
  dos_protect u_dos (
    .clk(clk),.rst_n(rst_n_sync),
    .meta_in(acl_meta),.meta_valid(acl_meta_valid),
    .meta_out(dos_meta),.meta_out_valid(dos_meta_valid),
    .rate_tick(rate_tick),
    .syn_flood_alert(),.icmp_flood_alert(),
    .udp_flood_alert(),.port_scan_alert()
  );

  // ---------------------------------------------------------------------------
  // NAT Engine
  // ---------------------------------------------------------------------------
  nat_engine u_nat (
    .clk(clk),.rst_n(rst_n_sync),
    .meta_in(dos_meta),.meta_valid(dos_meta_valid),
    .meta_out(nat_meta),.meta_out_valid(nat_meta_valid),
    .age_tick(rate_tick)
  );

  // ---------------------------------------------------------------------------
  // QoS Shaper (pass-through on data bus, gate on metadata decision)
  // ---------------------------------------------------------------------------
  // For now: forward tl_tdata directly gated by nat_meta.action
  // Full QoS shaper wired to tl_tdata stream
  wire [23:0] rate_cfg_w  [0:15];
  wire [23:0] burst_cfg_w [0:15];
  generate
    for (genvar qi = 0; qi < 16; qi++) begin : gen_qcfg
      assign rate_cfg_w[qi]  = reg_rate_cfg[qi];
      assign burst_cfg_w[qi] = reg_burst_cfg[qi];
    end
  endgenerate

  qos_shaper u_qos (
    .clk(clk),.rst_n(rst_n_sync),
    .s_tdata(tl_tdata),.s_tvalid(tl_tvalid & nat_meta_valid),
    .s_tready(tl_tready),.s_tlast(tl_tlast),
    .s_meta(nat_meta),
    .m_tdata(qos_tdata),.m_tvalid(qos_tvalid),
    .m_tready(qos_tready),.m_tlast(qos_tlast),
    .rate_cfg(rate_cfg_w),.burst_cfg(burst_cfg_w),
    .rate_tick(rate_tick),.drop_count()
  );

  // ---------------------------------------------------------------------------
  // Stats / Logger
  // ---------------------------------------------------------------------------
  port_stats_t port_stats [0:1];
  stats_logger u_stats (
    .clk(clk),.rst_n(rst_n_sync),
    .meta_in(nat_meta),.meta_valid(nat_meta_valid),
    .axil_araddr(32'h0),.axil_arvalid(1'b0),
    .axil_arready(),.axil_rdata(),.axil_rvalid(),.axil_rready(1'b1),
    .stats(port_stats),
    .log_wr_ptr(status_log_wr_ptr),
    .log_rd_ptr(status_log_rd_ptr)
  );

  // ---------------------------------------------------------------------------
  // Packet Forward: gate on action == ACCEPT
  // ---------------------------------------------------------------------------
  assign mac_tx_tdata  = qos_tdata;
  assign mac_tx_tvalid = qos_tvalid & (nat_meta.action == ACTION_ACCEPT ||
                                        nat_meta.action == ACTION_NAT);
  assign mac_tx_tlast  = qos_tlast;
  assign qos_tready    = mac_tx_tready;

  // ---------------------------------------------------------------------------
  // MMCM / Clock generation (stub — real MMCM in rgmii_phy_if)
  // ---------------------------------------------------------------------------
  // In full implementation, clk and rst_n_sync come from rgmii_phy_if MMCM.
  // For synthesis stub: use IBUFDS + BUFG
  wire clk_ibuf;
  IBUFDS u_ibufds (.I(sys_clk_p), .IB(sys_clk_n), .O(clk_ibuf));
  BUFG   u_bufg   (.I(clk_ibuf),  .O(clk));

  reg [3:0] rst_pipe = 4'hF;
  always_ff @(posedge clk or negedge sys_rst_n)
    if (!sys_rst_n) rst_pipe <= 4'hF;
    else            rst_pipe <= {rst_pipe[2:0], 1'b0};
  assign rst_n_sync = ~rst_pipe[3];
  assign phy_reset_n = rst_n_sync;

  // LEDs: link, rx activity, tx activity, error
  assign led[0] = rst_n_sync;
  assign led[1] = mac_rx_tvalid;
  assign led[2] = mac_tx_tvalid;
  assign led[3] = mac_rx_tuser;

endmodule : blaze_top
`default_nettype wire
