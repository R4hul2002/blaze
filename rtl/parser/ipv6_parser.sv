// =============================================================================
// ipv6_parser.sv — IPv6 Header Parser
// Project : BLAZE NGFW / M08
// =============================================================================
// Parses fixed 40-byte IPv6 header.
// Extracts: src/dst addr, next header, hop limit, traffic class, flow label.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module ipv6_parser (
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

  reg [7:0] pos;
  reg [7:0] ip6_hdr [0:39];  // 40-byte fixed header

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos          <= 8'd0;
      m_tvalid     <= 1'b0;
      m_meta_valid <= 1'b0;
    end else begin
      m_meta_valid <= 1'b0;
      if (s_tvalid && s_tready) begin
        m_tdata  <= s_tdata;
        m_tvalid <= 1'b1;
        m_tlast  <= s_tlast;
        m_tuser  <= s_tuser;

        if (s_meta.is_ipv6) begin
          automatic logic [7:0] ip_pos = (pos >= l3_start) ? (pos - l3_start) : 8'hFF;
          if (ip_pos < 8'd40)
            ip6_hdr[ip_pos] <= s_tdata;
        end

        if (s_tlast) begin
          pos          <= 8'd0;
          m_meta_valid <= 1'b1;
        end else
          pos <= pos + 1;
      end else if (!s_tvalid)
        m_tvalid <= 1'b0;
    end
  end

  always_comb begin
    m_meta = s_meta;
    if (s_meta.is_ipv6) begin
      m_meta.dscp     = {ip6_hdr[0][3:0], ip6_hdr[1][7:6]};
      m_meta.ecn      = ip6_hdr[1][5:4];
      m_meta.ttl      = ip6_hdr[7];   // hop limit
      m_meta.ip_proto = ip6_hdr[6];   // next header
      // src: bytes 8..23, dst: bytes 24..39
      m_meta.src_ip6  = {ip6_hdr[8],  ip6_hdr[9],  ip6_hdr[10], ip6_hdr[11],
                         ip6_hdr[12], ip6_hdr[13], ip6_hdr[14], ip6_hdr[15],
                         ip6_hdr[16], ip6_hdr[17], ip6_hdr[18], ip6_hdr[19],
                         ip6_hdr[20], ip6_hdr[21], ip6_hdr[22], ip6_hdr[23]};
      m_meta.dst_ip6  = {ip6_hdr[24], ip6_hdr[25], ip6_hdr[26], ip6_hdr[27],
                         ip6_hdr[28], ip6_hdr[29], ip6_hdr[30], ip6_hdr[31],
                         ip6_hdr[32], ip6_hdr[33], ip6_hdr[34], ip6_hdr[35],
                         ip6_hdr[36], ip6_hdr[37], ip6_hdr[38], ip6_hdr[39]};
    end
  end

endmodule : ipv6_parser
`default_nettype wire
