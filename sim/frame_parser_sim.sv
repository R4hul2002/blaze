// =============================================================================
// frame_parser_sim.sv  (simulation copy — no primitive deps)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module frame_parser_sim
  import blaze_pkg::*;
#(parameter int unsigned PKT_ID_INIT = 0)(
  input  wire        clk, rst_n,
  input  wire [7:0]  s_tdata,
  input  wire        s_tvalid,
  output wire        s_tready,
  input  wire        s_tlast,
  input  wire        s_tuser,
  output reg  [7:0]  m_tdata,
  output reg         m_tvalid,
  input  wire        m_tready,
  output reg         m_tlast,
  output reg         m_tuser,
  output pkt_meta_t  meta_out,
  output reg         meta_valid,
  input  wire [63:0] timestamp,
  input  wire [7:0]  port_id
);
  typedef enum logic [2:0] {
    ST_IDLE=3'd0, ST_DST_MAC=3'd1, ST_SRC_MAC=3'd2,
    ST_ETYPE=3'd3, ST_PAYLOAD=3'd4
  } state_t;

  state_t state;
  reg [2:0]  byte_cnt;
  reg [47:0] dst_mac_r, src_mac_r;
  reg [15:0] ethertype_r;
  reg [31:0] pkt_id_cnt = PKT_ID_INIT;
  reg [31:0] pkt_id_r;

  assign s_tready = m_tready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE; byte_cnt <= 0;
      dst_mac_r <= 0; src_mac_r <= 0; ethertype_r <= 0;
      m_tvalid <= 0; m_tlast <= 0; m_tuser <= 0; m_tdata <= 0;
      meta_valid <= 0;
    end else begin
      meta_valid <= 0;
      if (s_tvalid && s_tready) begin
        m_tdata <= s_tdata; m_tvalid <= 1; m_tlast <= s_tlast; m_tuser <= s_tuser;
        case (state)
          ST_IDLE: begin
            pkt_id_cnt <= pkt_id_cnt + 1; pkt_id_r <= pkt_id_cnt;
            dst_mac_r <= {40'h0, s_tdata}; byte_cnt <= 1; state <= ST_DST_MAC;
          end
          ST_DST_MAC: begin
            dst_mac_r <= {dst_mac_r[39:0], s_tdata};
            if (byte_cnt==5) begin byte_cnt<=0; state<=ST_SRC_MAC; end
            else byte_cnt <= byte_cnt+1;
          end
          ST_SRC_MAC: begin
            src_mac_r <= {src_mac_r[39:0], s_tdata};
            if (byte_cnt==5) begin byte_cnt<=0; state<=ST_ETYPE; end
            else byte_cnt <= byte_cnt+1;
          end
          ST_ETYPE: begin
            if (byte_cnt==0) begin ethertype_r[15:8]<=s_tdata; byte_cnt<=1; end
            else begin ethertype_r[7:0]<=s_tdata; byte_cnt<=0; state<=ST_PAYLOAD; end
          end
          ST_PAYLOAD: if (s_tlast) begin state<=ST_IDLE; meta_valid<=1; end
          default: state<=ST_IDLE;
        endcase
        if (s_tlast && state!=ST_IDLE) state<=ST_IDLE;
      end else if (!s_tvalid) m_tvalid<=0;
    end
  end

  always_comb begin
    meta_out = '0;
    meta_out.pkt_id    = pkt_id_r;
    meta_out.dst_mac   = dst_mac_r;
    meta_out.src_mac   = src_mac_r;
    meta_out.ethertype = ethertype_r;
    meta_out.is_ipv4   = (ethertype_r==16'h0800);
    meta_out.is_ipv6   = (ethertype_r==16'h86DD);
    meta_out.is_arp    = (ethertype_r==16'h0806);
    meta_out.has_vlan  = (ethertype_r==16'h8100);
    meta_out.has_qinq  = (ethertype_r==16'h88A8);
    meta_out.direction = DIR_INGRESS;
    meta_out.port_id   = port_id;
    meta_out.timestamp = timestamp;
  end
endmodule
`default_nettype wire
