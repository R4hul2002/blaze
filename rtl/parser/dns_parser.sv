// =============================================================================
// dns_parser.sv — DNS Header Parser + DNS Tunneling Detection
// Project : BLAZE NGFW / M13
// =============================================================================
// Parses DNS header (UDP port 53).
// Extracts: transaction ID, flags, question count, query name (first label).
// Detects DNS tunneling: abnormally long query names (> 50 chars).
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module dns_parser (
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

  // DNS tunneling alert
  output reg         dns_tunnel_alert,
  output reg [7:0]   dns_qname_len     // length of first query name
);

  assign s_tready = m_tready;

  wire is_dns = (s_meta.ip_proto == PROTO_UDP) &&
                ((s_meta.src_port == 16'd53) || (s_meta.dst_port == 16'd53));

  reg [7:0] pos;
  reg [7:0] dns_hdr [0:11];   // 12-byte DNS header
  reg [7:0] qname_len_r;
  reg       in_qname;

  // DNS starts at l7_offset (set by udp_parser)
  wire [7:0] dns_start = s_meta.l7_offset;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos              <= 8'd0;
      m_tvalid         <= 1'b0;
      m_meta_valid     <= 1'b0;
      dns_tunnel_alert <= 1'b0;
      qname_len_r      <= 8'd0;
      in_qname         <= 1'b0;
    end else begin
      m_meta_valid     <= 1'b0;
      dns_tunnel_alert <= 1'b0;

      if (s_tvalid && s_tready) begin
        m_tdata  <= s_tdata;
        m_tvalid <= 1'b1;
        m_tlast  <= s_tlast;
        m_tuser  <= s_tuser;

        if (is_dns) begin
          automatic logic [7:0] dp = (pos >= dns_start) ? (pos - dns_start) : 8'hFF;

          if (dp < 8'd12)
            dns_hdr[dp] <= s_tdata;

          // Count QNAME bytes (after 12-byte header, until null label)
          if (dp == 8'd12) begin
            in_qname    <= 1'b1;
            qname_len_r <= 8'd0;
          end else if (in_qname) begin
            if (s_tdata == 8'h00)
              in_qname <= 1'b0;
            else
              qname_len_r <= qname_len_r + 1;
          end
        end

        if (s_tlast) begin
          pos          <= 8'd0;
          m_meta_valid <= 1'b1;
          in_qname     <= 1'b0;
          if (is_dns && qname_len_r > 8'd50)
            dns_tunnel_alert <= 1'b1;
        end else
          pos <= pos + 1;
      end else if (!s_tvalid)
        m_tvalid <= 1'b0;
    end
  end

  assign dns_qname_len = qname_len_r;

  always_comb begin
    m_meta = s_meta;
    if (is_dns)
      m_meta.app_id = APP_DNS;
  end

endmodule : dns_parser
`default_nettype wire
