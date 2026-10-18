// =============================================================================
// ipv4_parser.sv — IPv4 Header Parser
// Project : BLAZE NGFW / M07
// =============================================================================
// Parses IPv4 header fields from byte stream.
// Handles variable IHL (options), fragmentation flags.
// Populates pkt_meta_t L3 fields.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module ipv4_parser (
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

  // L2 header offset: 14 bytes (no VLAN) or 18/22 with tags
  // We use s_meta.has_vlan / has_qinq to compute IPv4 start offset
  wire [7:0] l3_start = s_meta.has_qinq ? 8'd22 :
                        s_meta.has_vlan  ? 8'd18 : 8'd14;

  reg [7:0]  pos;
  reg [7:0]  ihl_bytes;   // IHL * 4
  reg [7:0]  ip_hdr [0:19]; // first 20 bytes of IP header

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos          <= 8'd0;
      ihl_bytes    <= 8'd20;
      m_tvalid     <= 1'b0;
      m_meta_valid <= 1'b0;
    end else begin
      m_meta_valid <= 1'b0;
      if (s_tvalid && s_tready) begin
        m_tdata  <= s_tdata;
        m_tvalid <= 1'b1;
        m_tlast  <= s_tlast;
        m_tuser  <= s_tuser;

        // Capture IPv4 header bytes
        if (s_meta.is_ipv4) begin
          automatic logic [7:0] ip_pos = (pos >= l3_start) ? (pos - l3_start) : 8'hFF;
          if (ip_pos < 8'd20)
            ip_hdr[ip_pos] <= s_tdata;
          // IHL from byte 0 of IP header
          if (ip_pos == 8'd0)
            ihl_bytes <= {s_tdata[3:0], 2'b00}; // IHL * 4
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

  // ---------------------------------------------------------------------------
  // Combinational metadata assembly from captured header bytes
  // ---------------------------------------------------------------------------
  always_comb begin
    m_meta = s_meta;
    if (s_meta.is_ipv4) begin
      m_meta.ttl          = ip_hdr[8];
      m_meta.ip_proto     = ip_hdr[9];
      m_meta.ip_total_len = {ip_hdr[2], ip_hdr[3]};
      m_meta.ip_id        = {ip_hdr[4], ip_hdr[5]};
      m_meta.dscp         = ip_hdr[1][7:2];
      m_meta.ecn          = ip_hdr[1][1:0];
      m_meta.is_fragment  = ip_hdr[6][5] | (|{ip_hdr[6][4:0], ip_hdr[7]});
      m_meta.is_first_frag= ip_hdr[6][5] & ~(|{ip_hdr[6][4:0], ip_hdr[7]});
      m_meta.frag_offset  = {ip_hdr[6][4:0], ip_hdr[7]};
      m_meta.src_ip4      = {ip_hdr[12], ip_hdr[13], ip_hdr[14], ip_hdr[15]};
      m_meta.dst_ip4      = {ip_hdr[16], ip_hdr[17], ip_hdr[18], ip_hdr[19]};
    end
  end

endmodule : ipv4_parser
`default_nettype wire
