// =============================================================================
// ipv4_parser_sim.sv
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module ipv4_parser_sim
  import blaze_pkg::*;
(
  input  wire        clk, rst_n,
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
  reg [7:0] ip_hdr [0:19];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos<=0; m_tvalid<=0; m_meta_valid<=0;
    end else begin
      m_meta_valid<=0;
      if (s_tvalid && s_tready) begin
        m_tdata<=s_tdata; m_tvalid<=1; m_tlast<=s_tlast; m_tuser<=s_tuser;
        if (s_meta.is_ipv4) begin
          if (pos>=l3_start && (pos-l3_start)<20)
            ip_hdr[pos-l3_start] <= s_tdata;
        end
        if (s_tlast) begin pos<=0; m_meta_valid<=1; end
        else pos<=pos+1;
      end else if (!s_tvalid) m_tvalid<=0;
    end
  end

  always_comb begin
    m_meta = s_meta;
    if (s_meta.is_ipv4) begin
      m_meta.ttl          = ip_hdr[8];
      m_meta.ip_proto     = ip_hdr[9];
      m_meta.ip_total_len = {ip_hdr[2],ip_hdr[3]};
      m_meta.ip_id        = {ip_hdr[4],ip_hdr[5]};
      m_meta.dscp         = ip_hdr[1][7:2];
      m_meta.ecn          = ip_hdr[1][1:0];
      m_meta.is_fragment  = ip_hdr[6][5]|(|{ip_hdr[6][4:0],ip_hdr[7]});
      m_meta.frag_offset  = {ip_hdr[6][4:0],ip_hdr[7]};
      m_meta.src_ip4      = {ip_hdr[12],ip_hdr[13],ip_hdr[14],ip_hdr[15]};
      m_meta.dst_ip4      = {ip_hdr[16],ip_hdr[17],ip_hdr[18],ip_hdr[19]};
    end
  end
endmodule
`default_nettype wire
