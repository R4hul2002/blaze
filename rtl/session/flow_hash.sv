// =============================================================================
// flow_hash.sv — Five-Tuple Hash Engine (Toeplitz / CRC32-based)
// Project : BLAZE NGFW / M16
// =============================================================================
// Computes a 32-bit hash of the five-tuple in 1 clock cycle.
// Uses XOR-folded CRC32 for good distribution.
// Symmetric option: hash(A->B) == hash(B->A) for bidirectional flow lookup.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module flow_hash #(
  parameter bit SYMMETRIC = 1  // 1 = bidirectional hash
)(
  input  wire        clk,
  input  wire        rst_n,

  input  pkt_meta_t  meta_in,
  input  wire        meta_valid,

  output reg  [HASH_WIDTH-1:0] hash_out,
  output reg                   hash_valid
);

  // ---------------------------------------------------------------------------
  // CRC32 step function (combinational)
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] crc32_byte(
    input logic [31:0] crc,
    input logic [7:0]  data
  );
    logic [31:0] c;
    c = crc ^ {24'h0, data};
    for (int i = 0; i < 8; i++)
      c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
    return c;
  endfunction

  // ---------------------------------------------------------------------------
  // Hash computation (pipeline stage 1: combinational)
  // ---------------------------------------------------------------------------
  logic [31:0] h_fwd, h_rev, h_final;
  logic [31:0] src_ip, dst_ip;
  logic [15:0] sp, dp;
  logic [7:0]  proto;

  always_comb begin
    if (meta_in.is_ipv6) begin
      // Fold IPv6 to 32 bits
      src_ip = meta_in.src_ip6[127:96] ^ meta_in.src_ip6[95:64] ^
               meta_in.src_ip6[63:32]  ^ meta_in.src_ip6[31:0];
      dst_ip = meta_in.dst_ip6[127:96] ^ meta_in.dst_ip6[95:64] ^
               meta_in.dst_ip6[63:32]  ^ meta_in.dst_ip6[31:0];
    end else begin
      src_ip = meta_in.src_ip4;
      dst_ip = meta_in.dst_ip4;
    end
    sp    = meta_in.src_port;
    dp    = meta_in.dst_port;
    proto = meta_in.ip_proto;

    // Forward hash: src->dst
    h_fwd = 32'hFFFFFFFF;
    h_fwd = crc32_byte(h_fwd, src_ip[31:24]);
    h_fwd = crc32_byte(h_fwd, src_ip[23:16]);
    h_fwd = crc32_byte(h_fwd, src_ip[15:8]);
    h_fwd = crc32_byte(h_fwd, src_ip[7:0]);
    h_fwd = crc32_byte(h_fwd, dst_ip[31:24]);
    h_fwd = crc32_byte(h_fwd, dst_ip[23:16]);
    h_fwd = crc32_byte(h_fwd, dst_ip[15:8]);
    h_fwd = crc32_byte(h_fwd, dst_ip[7:0]);
    h_fwd = crc32_byte(h_fwd, sp[15:8]);
    h_fwd = crc32_byte(h_fwd, sp[7:0]);
    h_fwd = crc32_byte(h_fwd, dp[15:8]);
    h_fwd = crc32_byte(h_fwd, dp[7:0]);
    h_fwd = crc32_byte(h_fwd, proto);
    h_fwd = ~h_fwd;

    if (SYMMETRIC) begin
      // Reverse hash: dst->src
      h_rev = 32'hFFFFFFFF;
      h_rev = crc32_byte(h_rev, dst_ip[31:24]);
      h_rev = crc32_byte(h_rev, dst_ip[23:16]);
      h_rev = crc32_byte(h_rev, dst_ip[15:8]);
      h_rev = crc32_byte(h_rev, dst_ip[7:0]);
      h_rev = crc32_byte(h_rev, src_ip[31:24]);
      h_rev = crc32_byte(h_rev, src_ip[23:16]);
      h_rev = crc32_byte(h_rev, src_ip[15:8]);
      h_rev = crc32_byte(h_rev, src_ip[7:0]);
      h_rev = crc32_byte(h_rev, dp[15:8]);
      h_rev = crc32_byte(h_rev, dp[7:0]);
      h_rev = crc32_byte(h_rev, sp[15:8]);
      h_rev = crc32_byte(h_rev, sp[7:0]);
      h_rev = crc32_byte(h_rev, proto);
      h_rev = ~h_rev;
      h_final = h_fwd ^ h_rev;
    end else
      h_final = h_fwd;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hash_out   <= '0;
      hash_valid <= 1'b0;
    end else begin
      hash_out   <= h_final;
      hash_valid <= meta_valid;
    end
  end

endmodule : flow_hash
`default_nettype wire
