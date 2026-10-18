// =============================================================================
// arp_parser.sv — ARP Parser + ARP Spoofing Detection
// Project : BLAZE NGFW / M09
// =============================================================================
// Parses ARP (RFC 826) header.
// Detects ARP spoofing: sender MAC != known MAC for sender IP.
// Maintains a small ARP binding table in BRAM.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module arp_parser #(
  parameter int unsigned TABLE_DEPTH = 256  // ARP binding entries
)(
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

  // ARP spoofing alert
  output reg         arp_spoof_alert,
  output reg [47:0]  spoof_src_mac,
  output reg [31:0]  spoof_src_ip
);

  assign s_tready = m_tready;

  // ARP header starts at byte 14 (no VLAN)
  // Byte offsets within ARP payload:
  //  0-1: HTYPE, 2-3: PTYPE, 4: HLEN, 5: PLEN, 6-7: OPER
  //  8-13: Sender MAC, 14-17: Sender IP, 18-23: Target MAC, 24-27: Target IP

  wire [7:0] l3_start = s_meta.has_qinq ? 8'd22 :
                        s_meta.has_vlan  ? 8'd18 : 8'd14;

  reg [7:0] pos;
  reg [7:0] arp_hdr [0:27];

  // ARP binding table: IP -> MAC
  reg [47:0] arp_mac_table [0:TABLE_DEPTH-1];
  reg [31:0] arp_ip_table  [0:TABLE_DEPTH-1];
  reg        arp_valid_table[0:TABLE_DEPTH-1];

  // Simple hash: low bits of IP
  wire [$clog2(TABLE_DEPTH)-1:0] tbl_idx =
    arp_hdr[14][$clog2(TABLE_DEPTH)-1:0] ^ arp_hdr[17][$clog2(TABLE_DEPTH)-1:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos             <= 8'd0;
      m_tvalid        <= 1'b0;
      m_meta_valid    <= 1'b0;
      arp_spoof_alert <= 1'b0;
      for (int i = 0; i < TABLE_DEPTH; i++)
        arp_valid_table[i] <= 1'b0;
    end else begin
      m_meta_valid    <= 1'b0;
      arp_spoof_alert <= 1'b0;

      if (s_tvalid && s_tready) begin
        m_tdata  <= s_tdata;
        m_tvalid <= 1'b1;
        m_tlast  <= s_tlast;
        m_tuser  <= s_tuser;

        if (s_meta.is_arp) begin
          automatic logic [7:0] ap = (pos >= l3_start) ? (pos - l3_start) : 8'hFF;
          if (ap < 8'd28) arp_hdr[ap] <= s_tdata;
        end

        if (s_tlast) begin
          pos          <= 8'd0;
          m_meta_valid <= 1'b1;

          if (s_meta.is_arp) begin
            automatic logic [31:0] sender_ip  = {arp_hdr[14],arp_hdr[15],arp_hdr[16],arp_hdr[17]};
            automatic logic [47:0] sender_mac = {arp_hdr[8],arp_hdr[9],arp_hdr[10],
                                                  arp_hdr[11],arp_hdr[12],arp_hdr[13]};
            // Check binding table
            if (arp_valid_table[tbl_idx] &&
                arp_ip_table[tbl_idx] == sender_ip &&
                arp_mac_table[tbl_idx] != sender_mac) begin
              arp_spoof_alert <= 1'b1;
              spoof_src_mac   <= sender_mac;
              spoof_src_ip    <= sender_ip;
            end else begin
              // Learn / update
              arp_mac_table[tbl_idx]   <= sender_mac;
              arp_ip_table[tbl_idx]    <= sender_ip;
              arp_valid_table[tbl_idx] <= 1'b1;
            end
          end
        end else
          pos <= pos + 1;
      end else if (!s_tvalid)
        m_tvalid <= 1'b0;
    end
  end

  always_comb begin
    m_meta = s_meta;
    if (s_meta.is_arp) begin
      m_meta.src_ip4 = {arp_hdr[14],arp_hdr[15],arp_hdr[16],arp_hdr[17]};
      m_meta.dst_ip4 = {arp_hdr[24],arp_hdr[25],arp_hdr[26],arp_hdr[27]};
    end
  end

endmodule : arp_parser
`default_nettype wire
