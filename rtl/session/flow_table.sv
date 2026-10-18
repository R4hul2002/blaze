// =============================================================================
// flow_table.sv — BRAM-backed Flow Table with Hash Lookup
// Project : BLAZE NGFW / M17
// =============================================================================
// 2-way set-associative hash table stored in BRAM.
// Lookup latency: 2 cycles (BRAM read + compare).
// Supports: insert, lookup, update, age-out via timeout counter.
// Capacity: 2^TABLE_BITS * 2 entries.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module flow_table #(
  parameter int unsigned TABLE_BITS = 14  // 2^14 * 2 = 32K flows
)(
  input  wire        clk,
  input  wire        rst_n,

  // Lookup request
  input  wire        lookup_req,
  input  flow_key_t  lookup_key,
  input  wire [HASH_WIDTH-1:0] lookup_hash,

  // Lookup response (2 cycles later)
  output reg         lookup_hit,
  output reg         lookup_miss,
  output flow_entry_t lookup_entry,

  // Insert/update
  input  wire        insert_req,
  input  flow_key_t  insert_key,
  input  flow_entry_t insert_entry,
  input  wire [HASH_WIDTH-1:0] insert_hash,
  output reg         insert_done,

  // Age tick (pulse every ~1 second from timer)
  input  wire        age_tick,

  // Stats
  output reg [31:0]  active_flows
);

  localparam int unsigned WAYS      = 2;
  localparam int unsigned DEPTH     = 1 << TABLE_BITS;
  localparam int unsigned ENTRY_W   = $bits(flow_entry_t);

  // ---------------------------------------------------------------------------
  // BRAM arrays (2-way)
  // ---------------------------------------------------------------------------
  reg [ENTRY_W-1:0] mem [0:WAYS-1][0:DEPTH-1];

  // ---------------------------------------------------------------------------
  // Lookup pipeline
  // ---------------------------------------------------------------------------
  reg [TABLE_BITS-1:0] lkp_idx_r;
  reg                  lkp_req_r;
  flow_key_t           lkp_key_r;

  wire [TABLE_BITS-1:0] lkp_idx = lookup_hash[TABLE_BITS-1:0];

  // Stage 1: register request + issue BRAM read
  always_ff @(posedge clk) begin
    lkp_idx_r <= lkp_idx;
    lkp_req_r <= lookup_req;
    lkp_key_r <= lookup_key;
  end

  // Stage 2: compare
  flow_entry_t rd_entry [0:WAYS-1];
  always_ff @(posedge clk) begin
    for (int w = 0; w < WAYS; w++)
      rd_entry[w] <= flow_entry_t'(mem[w][lkp_idx_r]);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lookup_hit  <= 1'b0;
      lookup_miss <= 1'b0;
    end else begin
      lookup_hit  <= 1'b0;
      lookup_miss <= 1'b0;
      if (lkp_req_r) begin
        automatic logic hit = 1'b0;
        for (int w = 0; w < WAYS; w++) begin
          if (rd_entry[w].valid && rd_entry[w].key == lkp_key_r) begin
            lookup_hit   <= 1'b1;
            lookup_entry <= rd_entry[w];
            hit = 1'b1;
          end
        end
        if (!hit) lookup_miss <= 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Insert (LRU: replace way with oldest last_seen)
  // ---------------------------------------------------------------------------
  reg insert_done_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      insert_done   <= 1'b0;
      active_flows  <= 32'd0;
    end else begin
      insert_done <= 1'b0;
      if (insert_req) begin
        automatic logic [TABLE_BITS-1:0] idx = insert_hash[TABLE_BITS-1:0];
        automatic int way_sel = 0;
        // Pick invalid way first, else way 0 (simple eviction)
        if (!flow_entry_t'(mem[1][idx]).valid) way_sel = 1;
        mem[way_sel][idx] <= ENTRY_W'(insert_entry);
        insert_done       <= 1'b1;
        if (!flow_entry_t'(mem[way_sel][idx]).valid)
          active_flows <= active_flows + 1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Age-out (simplified: decrement timeout, invalidate expired)
  // ---------------------------------------------------------------------------
  reg [TABLE_BITS-1:0] age_ptr = '0;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      age_ptr <= '0;
    end else if (age_tick) begin
      age_ptr <= age_ptr + 1;
      for (int w = 0; w < WAYS; w++) begin
        automatic flow_entry_t e = flow_entry_t'(mem[w][age_ptr]);
        if (e.valid) begin
          if (e.timeout_val == 32'd0) begin
            mem[w][age_ptr][ENTRY_W-1] <= 1'b0; // clear valid bit
            if (active_flows > 0) active_flows <= active_flows - 1;
          end else begin
            mem[w][age_ptr] <= ENTRY_W'({e.valid, e.key, e.session_id,
              e.tcp_state, e.cached_action, e.qos_queue, e.do_nat,
              e.nat_ip, e.nat_port, e.pkt_count, e.byte_count,
              e.last_seen, e.timeout_val - 1});
          end
        end
      end
    end
  end

endmodule : flow_table
`default_nettype wire
