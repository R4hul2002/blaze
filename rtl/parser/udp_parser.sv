// =============================================================================
// udp_parser.sv — UDP Header Parser
// Project : BLAZE NGFW / M11
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module udp_parser (
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
  output reg         m_meta_valid
);

  assign s_tready = m_tready;

  wire [7:0] l3_start = s_meta.has_qinq ? 8'd22 :
                        s_meta.has_vlan  ? 8'd18 : 8'd14;
  wire [7:0] l4_start = s_meta.is_ipv6  ? (l3_start + 8'd40) :
                                           (l3_start + 8'd20);

  reg [7:0] pos;
  reg [7:0] udp_hdr [0:7];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos <= 8'd0; m_tvalid <= 1'b0; m_meta_valid <= 1'b0;
    end else begin
      m_meta_valid <= 1'b0;
      if (s_tvalid && s_tready) begin
        m_tdata  <= s_tdata;
        m_tvalid <= 1'b1;
        m_tlast  <= s_tlast;
        m_tuser  <= s_tuser;

        if (s_meta.ip_proto == PROTO_UDP) begin
          automatic logic [7:0] up = (pos >= l4_start) ? (pos - l4_start) : 8'hFF;
          if (up < 8'd8) udp_hdr[up] <= s_tdata;
        end

        if (s_tlast) begin
          pos <= 8'd0; m_meta_valid <= 1'b1;
        end else pos <= pos + 1;
      end else if (!s_tvalid) m_tvalid <= 1'b0;
    end
  end

  always_comb begin
    m_meta = s_meta;
    if (s_meta.ip_proto == PROTO_UDP) begin
      m_meta.src_port  = {udp_hdr[0], udp_hdr[1]};
      m_meta.dst_port  = {udp_hdr[2], udp_hdr[3]};
      m_meta.udp_len   = {udp_hdr[4], udp_hdr[5]};
      m_meta.l7_offset = l4_start + 8'd8;
    end
  end

endmodule : udp_parser
`default_nettype wire
