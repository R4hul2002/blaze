// =============================================================================
// vlan_parser.sv — VLAN / QinQ Parser
// Project : BLAZE NGFW / M06
// =============================================================================
// Strips 802.1Q and 802.1ad (QinQ) tags from the byte stream.
// Updates pkt_meta_t: has_vlan, has_qinq, outer_vlan, inner_vlan, ethertype.
// Pass-through: forwards every byte downstream unchanged.
// Latency: 0 extra cycles (combinational metadata update at tlast).
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module vlan_parser (
  input  wire        clk,
  input  wire        rst_n,

  // Upstream (from packet_buffer)
  input  wire [7:0]  s_tdata,
  input  wire        s_tvalid,
  output wire        s_tready,
  input  wire        s_tlast,
  input  wire        s_tuser,
  input  pkt_meta_t  s_meta,
  input  wire        s_meta_valid,

  // Downstream
  output reg  [7:0]  m_tdata,
  output reg         m_tvalid,
  input  wire        m_tready,
  output reg         m_tlast,
  output reg         m_tuser,
  output pkt_meta_t  m_meta,
  output reg         m_meta_valid
);

  assign s_tready = m_tready;

  // Byte position counter within frame
  reg [7:0] pos;

  // Capture bytes for tag parsing (bytes 12-19 cover etype + up to 2 tags)
  reg [7:0] hdr [0:7];

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

        // Capture bytes 12..19 (ethertype + possible tags)
        if (pos >= 8'd12 && pos <= 8'd19)
          hdr[pos - 8'd12] <= s_tdata;

        if (s_tlast) begin
          pos          <= 8'd0;
          m_meta_valid <= 1'b1;
        end else
          pos <= pos + 1;
      end else if (!s_tvalid)
        m_tvalid <= 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // Combinational metadata decode
  // ---------------------------------------------------------------------------
  always_comb begin
    m_meta = s_meta;

    // hdr[0:1] = first ethertype (bytes 12-13)
    // 802.1Q:  8100 + 2-byte TCI + inner etype
    // 802.1ad: 88A8 + 2-byte outer TCI + 8100 + 2-byte inner TCI + inner etype

    automatic logic [15:0] et0 = {hdr[0], hdr[1]};
    automatic logic [15:0] et2 = {hdr[4], hdr[5]};

    if (et0 == 16'h88A8) begin
      // QinQ
      m_meta.has_qinq             = 1'b1;
      m_meta.has_vlan             = 1'b1;
      m_meta.outer_vlan.pcp       = hdr[2][7:5];
      m_meta.outer_vlan.dei       = hdr[2][4];
      m_meta.outer_vlan.vid       = {hdr[2][3:0], hdr[3]};
      m_meta.inner_vlan.pcp       = hdr[6][7:5];
      m_meta.inner_vlan.dei       = hdr[6][4];
      m_meta.inner_vlan.vid       = {hdr[6][3:0], hdr[7]};
      m_meta.ethertype            = et2;
      m_meta.is_ipv4              = (et2 == 16'h0800);
      m_meta.is_ipv6              = (et2 == 16'h86DD);
    end else if (et0 == 16'h8100) begin
      // Single VLAN
      m_meta.has_vlan             = 1'b1;
      m_meta.has_qinq             = 1'b0;
      m_meta.outer_vlan.pcp       = hdr[2][7:5];
      m_meta.outer_vlan.dei       = hdr[2][4];
      m_meta.outer_vlan.vid       = {hdr[2][3:0], hdr[3]};
      m_meta.ethertype            = et2;
      m_meta.is_ipv4              = (et2 == 16'h0800);
      m_meta.is_ipv6              = (et2 == 16'h86DD);
    end
    // else: no tag, meta unchanged from frame_parser
  end

endmodule : vlan_parser
`default_nettype wire
