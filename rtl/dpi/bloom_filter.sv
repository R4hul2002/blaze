// =============================================================================
// bloom_filter.sv — Bloom Filter Pre-filter for DPI
// Project : BLAZE NGFW / M19
// =============================================================================
// 3-hash Bloom filter to quickly reject non-matching payloads before
// running the full Aho-Corasick engine.
// False positive rate ~1% at 1M entries with 3 hashes and 10M bits.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module bloom_filter #(
  parameter int unsigned FILTER_BITS = 20,   // 2^20 = 1M bits
  parameter int unsigned NUM_HASHES  = 3
)(
  input  wire        clk,
  input  wire        rst_n,

  // Query: check if byte is in filter
  input  wire [7:0]  query_byte,
  input  wire [31:0] query_hash_seed,  // rolling hash from upstream
  input  wire        query_valid,
  output reg         query_hit,        // 1 = possibly present

  // Insert (from signature loader)
  input  wire [31:0] insert_hash [0:NUM_HASHES-1],
  input  wire        insert_valid
);

  localparam int unsigned DEPTH = 1 << FILTER_BITS;

  // BRAM-based bit array (packed into 32-bit words)
  localparam int unsigned WORDS = DEPTH / 32;
  reg [31:0] bram [0:WORDS-1];

  // Hash functions: H0=seed, H1=seed^0xDEAD, H2=seed^0xBEEF
  wire [FILTER_BITS-1:0] h0 = query_hash_seed[FILTER_BITS-1:0];
  wire [FILTER_BITS-1:0] h1 = (query_hash_seed ^ 32'hDEADBEEF)[FILTER_BITS-1:0];
  wire [FILTER_BITS-1:0] h2 = (query_hash_seed ^ 32'hCAFEBABE)[FILTER_BITS-1:0];

  // Read bits
  wire b0 = bram[h0[FILTER_BITS-1:5]][h0[4:0]];
  wire b1 = bram[h1[FILTER_BITS-1:5]][h1[4:0]];
  wire b2 = bram[h2[FILTER_BITS-1:5]][h2[4:0]];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      query_hit <= 1'b0;
      for (int i = 0; i < WORDS; i++) bram[i] <= 32'h0;
    end else begin
      query_hit <= query_valid & b0 & b1 & b2;

      if (insert_valid) begin
        for (int h = 0; h < NUM_HASHES; h++) begin
          automatic logic [FILTER_BITS-1:0] idx = insert_hash[h][FILTER_BITS-1:0];
          bram[idx[FILTER_BITS-1:5]][idx[4:0]] <= 1'b1;
        end
      end
    end
  end

endmodule : bloom_filter
`default_nettype wire
