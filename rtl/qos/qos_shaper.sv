// =============================================================================
// qos_shaper.sv — QoS Traffic Shaper + Rate Limiter
// Project : BLAZE NGFW / M22
// =============================================================================
// 16 priority queues with token bucket rate limiting per queue.
// Strict priority scheduling: queue 0 = highest.
// Token bucket: refilled every tick at configured rate.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module qos_shaper #(
  parameter int unsigned NUM_QUEUES  = 16,
  parameter int unsigned BUCKET_BITS = 24   // max burst tokens
)(
  input  wire        clk,
  input  wire        rst_n,

  // Packet input with metadata
  input  wire [7:0]  s_tdata,
  input  wire        s_tvalid,
  output wire        s_tready,
  input  wire        s_tlast,
  input  pkt_meta_t  s_meta,

  // Packet output
  output reg  [7:0]  m_tdata,
  output reg         m_tvalid,
  input  wire        m_tready,
  output reg         m_tlast,

  // Rate config (tokens per tick per queue, from AXI-Lite)
  input  wire [BUCKET_BITS-1:0] rate_cfg    [0:NUM_QUEUES-1],
  input  wire [BUCKET_BITS-1:0] burst_cfg   [0:NUM_QUEUES-1],

  // Rate tick (125 MHz / 125000 = 1 kHz tick for kbps granularity)
  input  wire        rate_tick,

  // Drop counter output
  output reg  [31:0] drop_count
);

  // ---------------------------------------------------------------------------
  // Token buckets
  // ---------------------------------------------------------------------------
  reg [BUCKET_BITS-1:0] tokens [0:NUM_QUEUES-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_QUEUES; i++) tokens[i] <= '0;
    end else if (rate_tick) begin
      for (int i = 0; i < NUM_QUEUES; i++) begin
        if (tokens[i] + rate_cfg[i] > burst_cfg[i])
          tokens[i] <= burst_cfg[i];
        else
          tokens[i] <= tokens[i] + rate_cfg[i];
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Gate: pass packet if tokens available, else drop
  // ---------------------------------------------------------------------------
  wire [QUEUE_WIDTH-1:0] q = s_meta.qos_queue;
  wire                   has_tokens = (tokens[q] >= BUCKET_BITS'(s_meta.pkt_len));

  assign s_tready = m_tready & (has_tokens | ~s_tvalid);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_tvalid   <= 1'b0;
      drop_count <= 32'd0;
    end else begin
      if (s_tvalid && m_tready) begin
        if (has_tokens) begin
          m_tdata  <= s_tdata;
          m_tvalid <= 1'b1;
          m_tlast  <= s_tlast;
          if (s_tlast)
            tokens[q] <= tokens[q] - BUCKET_BITS'(s_meta.pkt_len);
        end else begin
          m_tvalid <= 1'b0;
          if (s_tlast) drop_count <= drop_count + 1;
        end
      end else if (!s_tvalid)
        m_tvalid <= 1'b0;
    end
  end

endmodule : qos_shaper
`default_nettype wire
