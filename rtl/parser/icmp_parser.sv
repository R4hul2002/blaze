// =============================================================================
// icmp_parser.sv — ICMP / ICMPv6 Parser + ICMP Inspection
// Project : BLAZE NGFW / M12
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module icmp_parser (
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

  // ICMP flood alert (rate tracked externally)
  output reg         icmp_alert
);

  assign s_tready = m_tready;

  wire is_icmp = (s_meta.ip_proto == PROTO_ICMP) | (s_meta.ip_proto == PROTO_ICMPv6);

  wire [7:0] l3_start = s_meta.has_qinq ? 8'd22 :
                        s_meta.has_vlan  ? 8'd18 : 8'd14;
  wire [7:0] l4_start = s_meta.is_ipv6  ? (l3_start + 8'd40) :
                                           (l3_start + 8'd20);

  reg [7:0] pos;
  reg [7:0] icmp_hdr [0:3];  // type, code, cksum_hi, cksum_lo

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos <= 8'd0; m_tvalid <= 1'b0; m_meta_valid <= 1'b0; icmp_alert <= 1'b0;
    end else begin
      m_meta_valid <= 1'b0;
      icmp_alert   <= 1'b0;
      if (s_tvalid && s_tready) begin
        m_tdata  <= s_tdata;
        m_tvalid <= 1'b1;
        m_tlast  <= s_tlast;
        m_tuser  <= s_tuser;

        if (is_icmp) begin
          automatic logic [7:0] ip = (pos >= l4_start) ? (pos - l4_start) : 8'hFF;
          if (ip < 8'd4) icmp_hdr[ip] <= s_tdata;
        end

        if (s_tlast) begin
          pos          <= 8'd0;
          m_meta_valid <= 1'b1;
          // Alert on ICMP echo request flood (type=8 code=0)
          if (is_icmp && icmp_hdr[0] == 8'd8 && icmp_hdr[1] == 8'd0)
            icmp_alert <= 1'b1;
        end else pos <= pos + 1;
      end else if (!s_tvalid) m_tvalid <= 1'b0;
    end
  end

  always_comb begin
    m_meta = s_meta;
    if (is_icmp) begin
      m_meta.icmp_type = icmp_hdr[0];
      m_meta.icmp_code = icmp_hdr[1];
    end
  end

endmodule : icmp_parser
`default_nettype wire
