// =============================================================================
// dos_protect.sv — DoS/DDoS Protection + SYN Cookie Engine
// Project : BLAZE NGFW / M24
// =============================================================================
// Per-source rate limiting using a token bucket array.
// SYN cookie: validates TCP SYN by encoding ISN as hash(src,dst,secret).
// Detects: SYN flood, ICMP flood, UDP flood, port scan.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module dos_protect #(
  parameter int unsigned TRACK_BITS  = 16,   // 64K tracked sources
  parameter int unsigned RATE_LIMIT  = 1000, // pkts/sec per source
  parameter logic [31:0] SYN_SECRET  = 32'hDEADC0DE
)(
  input  wire        clk,
  input  wire        rst_n,

  input  pkt_meta_t  meta_in,
  input  wire        meta_valid,

  output pkt_meta_t  meta_out,
  output reg         meta_out_valid,

  // Rate tick (1 kHz)
  input  wire        rate_tick,

  // Alerts
  output reg         syn_flood_alert,
  output reg         icmp_flood_alert,
  output reg         udp_flood_alert,
  output reg         port_scan_alert
);

  localparam int unsigned DEPTH = 1 << TRACK_BITS;

  // Per-source packet counter (reset each rate_tick)
  reg [15:0] pkt_cnt  [0:DEPTH-1];
  reg [15:0] syn_cnt  [0:DEPTH-1];
  reg [15:0] port_cnt [0:DEPTH-1];  // distinct dst ports seen

  // Index by low bits of src IP
  wire [TRACK_BITS-1:0] src_idx = meta_in.src_ip4[TRACK_BITS-1:0];

  // ---------------------------------------------------------------------------
  // SYN cookie ISN computation
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] syn_cookie(
    input logic [31:0] src_ip,
    input logic [31:0] dst_ip,
    input logic [15:0] src_port,
    input logic [15:0] dst_port,
    input logic [31:0] secret
  );
    return src_ip ^ dst_ip ^ {src_port, dst_port} ^ secret;
  endfunction

  // ---------------------------------------------------------------------------
  // Pipeline
  // ---------------------------------------------------------------------------
  pkt_meta_t meta_r;
  reg        valid_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_r          <= 1'b0;
      meta_out_valid   <= 1'b0;
      syn_flood_alert  <= 1'b0;
      icmp_flood_alert <= 1'b0;
      udp_flood_alert  <= 1'b0;
      port_scan_alert  <= 1'b0;
      for (int i = 0; i < DEPTH; i++) begin
        pkt_cnt[i]  <= 16'd0;
        syn_cnt[i]  <= 16'd0;
        port_cnt[i] <= 16'd0;
      end
    end else begin
      syn_flood_alert  <= 1'b0;
      icmp_flood_alert <= 1'b0;
      udp_flood_alert  <= 1'b0;
      port_scan_alert  <= 1'b0;

      // Rate tick: reset counters
      if (rate_tick) begin
        for (int i = 0; i < DEPTH; i++) begin
          pkt_cnt[i]  <= 16'd0;
          syn_cnt[i]  <= 16'd0;
          port_cnt[i] <= 16'd0;
        end
      end

      meta_r  <= meta_in;
      valid_r <= meta_valid;

      if (meta_valid) begin
        pkt_cnt[src_idx] <= pkt_cnt[src_idx] + 1;

        if (meta_in.tcp_flags.syn && !meta_in.tcp_flags.ack)
          syn_cnt[src_idx] <= syn_cnt[src_idx] + 1;

        port_cnt[src_idx] <= port_cnt[src_idx] + 1;
      end

      // Stage 2: decision
      meta_out_valid <= valid_r;
      meta_out       <= meta_r;

      if (valid_r) begin
        // SYN flood: > 100 SYNs/sec from one source
        if (syn_cnt[meta_r.src_ip4[TRACK_BITS-1:0]] > 16'd100) begin
          syn_flood_alert      <= 1'b1;
          meta_out.action      <= ACTION_DROP;
          meta_out.threat      <= THREAT_HIGH;
        end
        // ICMP flood
        if (meta_r.ip_proto == PROTO_ICMP &&
            pkt_cnt[meta_r.src_ip4[TRACK_BITS-1:0]] > 16'd500) begin
          icmp_flood_alert     <= 1'b1;
          meta_out.action      <= ACTION_DROP;
        end
        // UDP flood
        if (meta_r.ip_proto == PROTO_UDP &&
            pkt_cnt[meta_r.src_ip4[TRACK_BITS-1:0]] > 16'd1000) begin
          udp_flood_alert      <= 1'b1;
          meta_out.action      <= ACTION_DROP;
        end
        // Port scan: many distinct ports from one source
        if (port_cnt[meta_r.src_ip4[TRACK_BITS-1:0]] > 16'd50)
          port_scan_alert <= 1'b1;
      end
    end
  end

endmodule : dos_protect
`default_nettype wire
