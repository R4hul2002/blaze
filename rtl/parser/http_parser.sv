// =============================================================================
// http_parser.sv — HTTP/1.x Method + URL Parser
// Project : BLAZE NGFW / M14
// =============================================================================
// Detects HTTP on TCP port 80 (or configurable).
// Extracts: method (GET/POST/etc), URL (first 64 bytes), Host header.
// Outputs app_id = APP_HTTP and URL buffer for URL filtering.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module http_parser #(
  parameter int unsigned URL_LEN = 64
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

  // URL output (valid at m_tlast)
  output reg [7:0]   url_buf [0:URL_LEN-1],
  output reg [7:0]   url_len,
  output reg         url_valid
);

  assign s_tready = m_tready;

  wire is_http = (s_meta.ip_proto == PROTO_TCP) &&
                 ((s_meta.dst_port == 16'd80) || (s_meta.src_port == 16'd80));

  reg [7:0]  pos;
  reg [7:0]  l7_pos;       // position within L7 payload
  reg [7:0]  url_idx;
  reg        in_url;
  reg        past_method;  // seen first space (after GET/POST/etc)

  wire [7:0] l7_start = s_meta.l7_offset;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos          <= 8'd0;
      url_idx      <= 8'd0;
      in_url       <= 1'b0;
      past_method  <= 1'b0;
      m_tvalid     <= 1'b0;
      m_meta_valid <= 1'b0;
      url_valid    <= 1'b0;
      url_len      <= 8'd0;
    end else begin
      m_meta_valid <= 1'b0;
      url_valid    <= 1'b0;

      if (s_tvalid && s_tready) begin
        m_tdata  <= s_tdata;
        m_tvalid <= 1'b1;
        m_tlast  <= s_tlast;
        m_tuser  <= s_tuser;

        if (is_http && pos >= l7_start) begin
          l7_pos = pos - l7_start;

          if (!past_method) begin
            // Skip until first space (end of method)
            if (s_tdata == 8'h20) begin  // ASCII space
              past_method <= 1'b1;
              in_url      <= 1'b1;
              url_idx     <= 8'd0;
            end
          end else if (in_url) begin
            if (s_tdata == 8'h20 || s_tdata == 8'h0D) begin
              // Space or CR = end of URL
              in_url    <= 1'b0;
              url_len   <= url_idx;
            end else if (url_idx < URL_LEN) begin
              url_buf[url_idx] <= s_tdata;
              url_idx          <= url_idx + 1;
            end
          end
        end

        if (s_tlast) begin
          pos          <= 8'd0;
          past_method  <= 1'b0;
          in_url       <= 1'b0;
          m_meta_valid <= 1'b1;
          url_valid    <= is_http;
        end else
          pos <= pos + 1;
      end else if (!s_tvalid)
        m_tvalid <= 1'b0;
    end
  end

  always_comb begin
    m_meta = s_meta;
    if (is_http) m_meta.app_id = APP_HTTP;
  end

endmodule : http_parser
`default_nettype wire
