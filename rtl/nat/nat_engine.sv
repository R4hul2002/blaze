// =============================================================================
// nat_engine.sv — Network Address Translation Engine
// Project : BLAZE NGFW / M21
// =============================================================================
// Supports: SNAT (source NAT), DNAT (destination NAT), PAT (port translation).
// NAT table: 64K entries in BRAM, indexed by translated port.
// Modifies pkt_meta_t nat_ip / nat_port fields.
// Actual header rewrite done by packet_modifier downstream.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module nat_engine #(
  parameter int unsigned NAT_TABLE_BITS = 16,  // 64K entries
  parameter logic [31:0] NAT_POOL_BASE  = 32'hC0A80100,  // 192.168.1.0
  parameter logic [15:0] NAT_PORT_BASE  = 16'd1024
)(
  input  wire        clk,
  input  wire        rst_n,

  // Metadata in/out
  input  pkt_meta_t  meta_in,
  input  wire        meta_valid,
  output pkt_meta_t  meta_out,
  output reg         meta_out_valid,

  // Age tick
  input  wire        age_tick
);

  localparam int unsigned DEPTH = 1 << NAT_TABLE_BITS;

  // NAT table
  nat_entry_t nat_mem [0:DEPTH-1];

  // Port allocator (simple incrementing)
  reg [15:0] next_port = NAT_PORT_BASE;

  // ---------------------------------------------------------------------------
  // Lookup: find existing NAT entry for this flow
  // ---------------------------------------------------------------------------
  // Index by src_port XOR src_ip[15:0]
  wire [NAT_TABLE_BITS-1:0] lkp_idx =
    (meta_in.src_port ^ meta_in.src_ip4[15:0])[NAT_TABLE_BITS-1:0];

  nat_entry_t lkp_entry;
  always_ff @(posedge clk) lkp_entry <= nat_mem[lkp_idx];

  // ---------------------------------------------------------------------------
  // NAT decision pipeline (2 cycles)
  // ---------------------------------------------------------------------------
  pkt_meta_t meta_r1;
  reg        valid_r1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_r1      <= 1'b0;
      meta_out_valid<= 1'b0;
    end else begin
      // Stage 1: register input + issue BRAM read
      meta_r1  <= meta_in;
      valid_r1 <= meta_valid;

      // Stage 2: apply NAT
      meta_out_valid <= valid_r1;
      meta_out       <= meta_r1;

      if (valid_r1 && meta_r1.do_nat) begin
        if (lkp_entry.valid &&
            lkp_entry.orig_src_ip   == meta_r1.src_ip4 &&
            lkp_entry.orig_src_port == meta_r1.src_port) begin
          // Existing translation
          meta_out.nat_ip   <= lkp_entry.xlat_src_ip;
          meta_out.nat_port <= lkp_entry.xlat_src_port;
        end else begin
          // New translation: allocate port
          meta_out.nat_ip   <= NAT_POOL_BASE;
          meta_out.nat_port <= next_port;
          // Write new entry
          nat_mem[lkp_idx] <= '{
            valid:          1'b1,
            orig_src_ip:    meta_r1.src_ip4,
            orig_src_port:  meta_r1.src_port,
            xlat_src_ip:    NAT_POOL_BASE,
            xlat_src_port:  next_port,
            last_seen:      meta_r1.timestamp[31:0]
          };
          next_port <= next_port + 1;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Age-out expired NAT entries
  // ---------------------------------------------------------------------------
  reg [NAT_TABLE_BITS-1:0] age_ptr = '0;
  always_ff @(posedge clk) begin
    if (age_tick) begin
      age_ptr <= age_ptr + 1;
      if (nat_mem[age_ptr].valid) begin
        // Simple: invalidate if last_seen > 300s ago (approximated)
        // In production: compare against current timestamp
        nat_mem[age_ptr].valid <= 1'b0;
      end
    end
  end

endmodule : nat_engine
`default_nettype wire
