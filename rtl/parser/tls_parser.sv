// =============================================================================
// tls_parser.sv — TLS ClientHello Parser + SNI Extraction
// Project : BLAZE NGFW / M15
// =============================================================================
// Detects TLS ClientHello (record type 0x16, handshake type 0x01).
// Extracts SNI hostname from server_name extension (type 0x0000).
// SNI stored in sni_buf[0:SNI_LEN-1], length in sni_len.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module tls_parser #(
  parameter int unsigned SNI_LEN = 64
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

  // SNI output
  output reg [7:0]   sni_buf [0:SNI_LEN-1],
  output reg [7:0]   sni_len,
  output reg         sni_valid
);

  assign s_tready = m_tready;

  wire is_tls_port = (s_meta.ip_proto == PROTO_TCP) &&
                     ((s_meta.dst_port == 16'd443) || (s_meta.src_port == 16'd443));

  // TLS record header: [0]=content_type [1-2]=version [3-4]=length
  // Handshake header:  [5]=hs_type [6-8]=hs_length
  // ClientHello:       [9-10]=client_version [11-42]=random [43]=session_id_len
  // We scan for SNI extension by searching for extension type 0x0000

  typedef enum logic [3:0] {
    S_IDLE      = 4'd0,
    S_TLS_HDR   = 4'd1,
    S_HS_HDR    = 4'd2,
    S_CH_SKIP   = 4'd3,
    S_EXT_LEN   = 4'd4,
    S_EXT_TYPE  = 4'd5,
    S_EXT_DLEN  = 4'd6,
    S_SNI_LIST  = 4'd7,
    S_SNI_NAME  = 4'd8,
    S_DONE      = 4'd9
  } tls_state_t;

  tls_state_t tls_st;
  reg [7:0]  pos;
  reg [15:0] skip_cnt;
  reg [15:0] ext_total_len;
  reg [15:0] ext_data_len;
  reg [7:0]  sni_idx;
  reg [7:0]  l7_start_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pos          <= 8'd0;
      tls_st       <= S_IDLE;
      skip_cnt     <= 16'd0;
      sni_idx      <= 8'd0;
      sni_len      <= 8'd0;
      sni_valid    <= 1'b0;
      m_tvalid     <= 1'b0;
      m_meta_valid <= 1'b0;
    end else begin
      m_meta_valid <= 1'b0;
      sni_valid    <= 1'b0;

      if (s_tvalid && s_tready) begin
        m_tdata  <= s_tdata;
        m_tvalid <= 1'b1;
        m_tlast  <= s_tlast;
        m_tuser  <= s_tuser;

        if (is_tls_port) begin
          automatic logic [7:0] lp = (pos >= s_meta.l7_offset) ?
                                      (pos - s_meta.l7_offset) : 8'hFF;
          case (tls_st)
            S_IDLE: begin
              if (lp == 8'd0) begin
                // content_type must be 0x16 (handshake)
                if (s_tdata == 8'h16) tls_st <= S_TLS_HDR;
                skip_cnt <= 16'd1;
              end
            end
            S_TLS_HDR: begin
              // skip version(2) + length(2) = 4 bytes, then hs_type
              skip_cnt <= skip_cnt + 1;
              if (skip_cnt == 16'd4) begin
                if (s_tdata == 8'h01) tls_st <= S_HS_HDR; // ClientHello
                else                  tls_st <= S_DONE;
                skip_cnt <= 16'd0;
              end
            end
            S_HS_HDR: begin
              // skip hs_length(3) + client_version(2) + random(32) + session_id_len(1) = 38
              skip_cnt <= skip_cnt + 1;
              if (skip_cnt == 16'd37) begin
                // s_tdata = session_id_len; skip that many bytes next
                skip_cnt <= {8'h00, s_tdata};
                tls_st   <= S_CH_SKIP;
              end
            end
            S_CH_SKIP: begin
              // skip session_id, then cipher_suites_len(2)+cipher_suites+comp_len+comp
              // simplified: skip 2 more bytes for cipher suite length then skip that
              if (skip_cnt == 16'd0) begin
                // now at cipher_suites_len high byte
                skip_cnt <= {s_tdata, 8'h00};
                tls_st   <= S_EXT_LEN;
              end else
                skip_cnt <= skip_cnt - 1;
            end
            S_EXT_LEN: begin
              // extensions total length (2 bytes)
              if (skip_cnt[15:8] != 8'h00) begin
                ext_total_len[15:8] <= s_tdata;
                skip_cnt <= 16'd1;
              end else begin
                ext_total_len[7:0] <= s_tdata;
                skip_cnt <= 16'd0;
                tls_st   <= S_EXT_TYPE;
              end
            end
            S_EXT_TYPE: begin
              // extension type high byte
              skip_cnt <= {s_tdata, 8'h00};
              tls_st   <= S_EXT_DLEN;
            end
            S_EXT_DLEN: begin
              if (skip_cnt[15:8] != 8'h00) begin
                // low byte of ext type
                if ({skip_cnt[15:8], s_tdata} == 16'h0000) begin
                  // SNI extension found
                  tls_st   <= S_SNI_LIST;
                  skip_cnt <= 16'd0;
                end else begin
                  tls_st   <= S_EXT_TYPE; // skip this ext
                  skip_cnt <= 16'd0;
                end
              end
            end
            S_SNI_LIST: begin
              // SNI list length (2) + entry type (1) + name length (2)
              skip_cnt <= skip_cnt + 1;
              if (skip_cnt == 16'd4) begin
                sni_idx  <= 8'd0;
                // s_tdata = low byte of name length (use as sni_len)
                sni_len  <= s_tdata;
                tls_st   <= S_SNI_NAME;
                skip_cnt <= 16'd0;
              end
            end
            S_SNI_NAME: begin
              if (sni_idx < SNI_LEN && sni_idx < sni_len) begin
                sni_buf[sni_idx] <= s_tdata;
                sni_idx          <= sni_idx + 1;
              end
              if (sni_idx + 1 >= sni_len)
                tls_st <= S_DONE;
            end
            default: ; // S_DONE: pass through
          endcase
        end

        if (s_tlast) begin
          pos          <= 8'd0;
          tls_st       <= S_IDLE;
          skip_cnt     <= 16'd0;
          m_meta_valid <= 1'b1;
          sni_valid    <= is_tls_port && (tls_st == S_DONE || tls_st == S_SNI_NAME);
        end else
          pos <= pos + 1;
      end else if (!s_tvalid)
        m_tvalid <= 1'b0;
    end
  end

  always_comb begin
    m_meta = s_meta;
    if (is_tls_port) m_meta.app_id = APP_HTTPS;
  end

endmodule : tls_parser
`default_nettype wire
