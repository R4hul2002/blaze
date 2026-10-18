// =============================================================================
// tcp_parser.sv — TCP Header Parser + TCP State Machine
// Project : BLAZE NGFW / M10
// =============================================================================
// Parses TCP header: ports, seq, ack, flags, window.
// Drives tcp_state in pkt_meta_t based on flag analysis.
// Detects: FIN scan, NULL scan, XMAS scan, SYN flood indicators.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module tcp_parser (
  input  wire        clk,
  input  wire        rst_n,

  input  wire [7:0]  s_tdata,
  input  wire        s_tvalid,
  output wire        s_tready,
  input  wire        s_tlast,
  input  wire        s_tuser,
  input  pkt_meta_t  s_meta,
  input  wire        s_meta_valid,

  output reg  [7:0]  m_tdata,
  output reg         m_tvalid,
  input  wire        m_tready,
  output reg         m_tlast,
  output reg         m_tuser,
  output pkt_meta_t  m_meta,
  output reg         m_meta_valid,

  // Scan detection alerts
  output reg         alert_fin_scan,
  output reg         alert_null_scan,
  output reg         alert_xmas_scan,
  output reg         alert_syn_only    // SYN without ACK (potential flood)
);

  assign s_tready = m_tready;

  // TCP starts after IP header
  // IPv4: l3_start + IHL*4, IPv6: l3_start + 40
  // We use a simplified fixed offset for IPv4 (IHL=5 -> 20 bytes)
  wire [7:0] l3_start  = s_meta.has_qinq ? 8'd22 :
                         s_meta.has_vlan  ? 8'd18 : 8'd14;
  wire [7:0] l4_start  = s_meta.is_ipv6  ? (l3_start + 8'd40) :
                                            (l3_start + 8'd20);

  reg [7:0] pos;
  reg [7:0] tcp_hdr [0:19];  // first 20 bytes of TCP header

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos             <= 8'd0;
      m_tvalid        <= 1'b0;
      m_meta_valid    <= 1'b0;
      alert_fin_scan  <= 1'b0;
      alert_null_scan <= 1'b0;
      alert_xmas_scan <= 1'b0;
      alert_syn_only  <= 1'b0;
    end else begin
      m_meta_valid    <= 1'b0;
      alert_fin_scan  <= 1'b0;
      alert_null_scan <= 1'b0;
      alert_xmas_scan <= 1'b0;
      alert_syn_only  <= 1'b0;

      if (s_tvalid && s_tready) begin
        m_tdata  <= s_tdata;
        m_tvalid <= 1'b1;
        m_tlast  <= s_tlast;
        m_tuser  <= s_tuser;

        if (s_meta.ip_proto == PROTO_TCP) begin
          automatic logic [7:0] tp = (pos >= l4_start) ? (pos - l4_start) : 8'hFF;
          if (tp < 8'd20) tcp_hdr[tp] <= s_tdata;
        end

        if (s_tlast) begin
          pos          <= 8'd0;
          m_meta_valid <= 1'b1;

          if (s_meta.ip_proto == PROTO_TCP) begin
            automatic logic [7:0] flags = tcp_hdr[13];
            // Scan detection
            alert_fin_scan  <= flags[0] & ~flags[1] & ~flags[2] & ~flags[4]; // FIN only
            alert_null_scan <= (flags == 8'h00);
            alert_xmas_scan <= flags[0] & flags[5] & flags[3]; // FIN+URG+PSH
            alert_syn_only  <= flags[1] & ~flags[4];           // SYN, no ACK
          end
        end else
          pos <= pos + 1;
      end else if (!s_tvalid)
        m_tvalid <= 1'b0;
    end
  end

  always_comb begin
    m_meta = s_meta;
    if (s_meta.ip_proto == PROTO_TCP) begin
      m_meta.src_port   = {tcp_hdr[0],  tcp_hdr[1]};
      m_meta.dst_port   = {tcp_hdr[2],  tcp_hdr[3]};
      m_meta.tcp_seq    = {tcp_hdr[4],  tcp_hdr[5],  tcp_hdr[6],  tcp_hdr[7]};
      m_meta.tcp_ack    = {tcp_hdr[8],  tcp_hdr[9],  tcp_hdr[10], tcp_hdr[11]};
      m_meta.tcp_window = {tcp_hdr[14], tcp_hdr[15]};
      m_meta.tcp_flags.cwr = tcp_hdr[13][7];
      m_meta.tcp_flags.ece = tcp_hdr[13][6];
      m_meta.tcp_flags.urg = tcp_hdr[13][5];
      m_meta.tcp_flags.ack = tcp_hdr[13][4];
      m_meta.tcp_flags.psh = tcp_hdr[13][3];
      m_meta.tcp_flags.rst = tcp_hdr[13][2];
      m_meta.tcp_flags.syn = tcp_hdr[13][1];
      m_meta.tcp_flags.fin = tcp_hdr[13][0];
      // L7 offset
      m_meta.l7_offset  = l4_start + {tcp_hdr[12][7:4], 2'b00}; // data offset * 4
    end
  end

endmodule : tcp_parser
`default_nettype wire
