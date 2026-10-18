// =============================================================================
// aho_corasick.sv — Aho-Corasick Multi-Pattern DPI Engine
// Project : BLAZE NGFW / M20
// =============================================================================
// Streaming Aho-Corasick automaton.
// State transitions stored in BRAM (goto table).
// Failure links pre-computed offline and loaded at init.
// Processes 1 byte per clock at 125 MHz = 1 Gbps throughput.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module aho_corasick #(
  parameter int unsigned STATE_BITS  = 12,   // 4096 states
  parameter int unsigned PATTERN_CNT = 256   // max patterns
)(
  input  wire        clk,
  input  wire        rst_n,

  // Byte stream input
  input  wire [7:0]  s_byte,
  input  wire        s_valid,
  input  wire        s_last,   // end of packet: reset to state 0

  // Match output
  output reg         match_valid,
  output reg [15:0]  match_pattern_id,
  output reg         match_last,

  // Goto table write port (loaded from MicroBlaze at init)
  // goto[state][char] -> next_state
  input  wire [STATE_BITS-1:0]  goto_wr_state,
  input  wire [7:0]             goto_wr_char,
  input  wire [STATE_BITS-1:0]  goto_wr_next,
  input  wire                   goto_wr_en,

  // Output table: state -> pattern_id (0 = no match)
  input  wire [STATE_BITS-1:0]  out_wr_state,
  input  wire [15:0]            out_wr_pattern,
  input  wire                   out_wr_en
);

  // ---------------------------------------------------------------------------
  // Goto table: BRAM [state][char] -> next_state
  // Addressed as {state, char} = STATE_BITS+8 bits wide
  // ---------------------------------------------------------------------------
  localparam int unsigned GOTO_DEPTH = (1 << STATE_BITS) * 256;
  // Flattened: addr = state * 256 + char
  reg [STATE_BITS-1:0] goto_mem [0:(1<<STATE_BITS)*256-1];

  // Output table: state -> pattern_id
  reg [15:0] out_mem [0:(1<<STATE_BITS)-1];

  // Write ports
  always_ff @(posedge clk) begin
    if (goto_wr_en)
      goto_mem[{goto_wr_state, goto_wr_char}] <= goto_wr_next;
    if (out_wr_en)
      out_mem[out_wr_state] <= out_wr_pattern;
  end

  // ---------------------------------------------------------------------------
  // Automaton state register
  // ---------------------------------------------------------------------------
  reg [STATE_BITS-1:0] cur_state;
  reg [STATE_BITS-1:0] next_state_r;

  // Pipeline stage 1: issue BRAM read
  reg [STATE_BITS-1:0] bram_addr_r;
  reg                  valid_r1, last_r1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cur_state  <= '0;
      valid_r1   <= 1'b0;
      last_r1    <= 1'b0;
    end else begin
      valid_r1   <= s_valid;
      last_r1    <= s_last;
      if (s_valid) begin
        bram_addr_r <= {cur_state, s_byte};
        if (s_last) cur_state <= '0;
      end
    end
  end

  // Pipeline stage 2: read BRAM result + check output table
  reg [STATE_BITS-1:0] next_st;
  reg [15:0]           out_val;
  reg                  valid_r2, last_r2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_r2 <= 1'b0; last_r2 <= 1'b0;
    end else begin
      next_st  <= goto_mem[bram_addr_r];
      out_val  <= out_mem[goto_mem[bram_addr_r]];
      valid_r2 <= valid_r1;
      last_r2  <= last_r1;
    end
  end

  // Pipeline stage 3: update state + emit match
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      match_valid      <= 1'b0;
      match_pattern_id <= 16'd0;
      match_last       <= 1'b0;
    end else begin
      match_valid      <= 1'b0;
      match_last       <= last_r2;
      if (valid_r2) begin
        cur_state <= last_r2 ? '0 : next_st;
        if (out_val != 16'd0) begin
          match_valid      <= 1'b1;
          match_pattern_id <= out_val;
        end
      end
    end
  end

endmodule : aho_corasick
`default_nettype wire
