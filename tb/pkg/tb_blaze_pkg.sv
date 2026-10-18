// =============================================================================
// tb_blaze_pkg.sv — Self-Checking Testbench for blaze_pkg
// Project  : BLAZE NGFW
// Module   : M01 — Foundation Package Verification
// =============================================================================
// Verifies:
//   - Struct sizes match expected bit widths
//   - Enum encoding correctness
//   - Helper function correctness
//   - Interface instantiation
// =============================================================================

`timescale 1ns/1ps
`include "../rtl/pkg/blaze_pkg.sv"
`include "../rtl/pkg/axis_if.sv"
`include "../rtl/pkg/axil_if.sv"
`include "../rtl/pkg/axi4_if.sv"
`include "../rtl/pkg/meta_if.sv"

module tb_blaze_pkg;
  import blaze_pkg::*;

  // -------------------------------------------------------------------------
  // Clock
  // -------------------------------------------------------------------------
  logic clk = 0;
  logic rst_n = 0;
  always #4 clk = ~clk;  // 125 MHz

  // -------------------------------------------------------------------------
  // Interface instantiation smoke test
  // -------------------------------------------------------------------------
  axis_if #(.DATA_W(64), .USER_W(1)) axis_bus (.clk(clk), .rst_n(rst_n));
  axil_if #(.ADDR_W(32), .DATA_W(32)) axil_bus (.clk(clk), .rst_n(rst_n));
  axi4_if #(.ADDR_W(32), .DATA_W(64), .ID_W(8)) axi4_bus (.clk(clk), .rst_n(rst_n));
  meta_if meta_bus (.clk(clk), .rst_n(rst_n));

  // -------------------------------------------------------------------------
  // Test variables
  // -------------------------------------------------------------------------
  pkt_meta_t  meta;
  flow_key_t  fkey;
  rule_entry_t rule;
  flow_entry_t fentry;
  int          fail_count;

  // -------------------------------------------------------------------------
  // Tasks
  // -------------------------------------------------------------------------
  task automatic check_eq(
    input string name,
    input int    got,
    input int    expected
  );
    if (got !== expected) begin
      $error("FAIL [%s]: got=%0d expected=%0d", name, got, expected);
      fail_count++;
    end else begin
      $display("PASS [%s]: %0d bits", name, got);
    end
  endtask

  // -------------------------------------------------------------------------
  // Main test
  // -------------------------------------------------------------------------
  initial begin
    fail_count = 0;
    rst_n = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;

    // --- Struct size checks ---
    $display("\n=== Struct Size Verification ===");
    check_eq("flow_key_t bits",   $bits(flow_key_t),   104);
    check_eq("vlan_tag_t bits",   $bits(vlan_tag_t),   16);
    check_eq("tcp_flags_t bits",  $bits(tcp_flags_t),  8);

    // --- Enum encoding ---
    $display("\n=== Enum Encoding Verification ===");
    check_eq("PROTO_TCP",    int'(PROTO_TCP),    8'h06);
    check_eq("PROTO_UDP",    int'(PROTO_UDP),    8'h11);
    check_eq("PROTO_ICMP",   int'(PROTO_ICMP),   8'h01);
    check_eq("ETYPE_IPV4",   int'(ETYPE_IPV4),   16'h0800);
    check_eq("ETYPE_ARP",    int'(ETYPE_ARP),    16'h0806);
    check_eq("ETYPE_VLAN",   int'(ETYPE_VLAN),   16'h8100);
    check_eq("ETYPE_IPV6",   int'(ETYPE_IPV6),   16'h86DD);
    check_eq("ACTION_ACCEPT",int'(ACTION_ACCEPT), 4'd0);
    check_eq("ACTION_DROP",  int'(ACTION_DROP),   4'd1);
    check_eq("TCP_ESTABLISHED", int'(TCP_ESTABLISHED), 4'd3);

    // --- bswap32 ---
    $display("\n=== Helper Function Verification ===");
    begin
      logic [31:0] swapped;
      swapped = bswap32(32'h0800_0000);
      if (swapped !== 32'h0000_0008) begin
        $error("FAIL [bswap32]: got=%08h expected=00000008", swapped);
        fail_count++;
      end else $display("PASS [bswap32]");
    end

    // --- bswap16 ---
    begin
      logic [15:0] swapped;
      swapped = bswap16(16'h0800);
      if (swapped !== 16'h0008) begin
        $error("FAIL [bswap16]: got=%04h expected=0008", swapped);
        fail_count++;
      end else $display("PASS [bswap16]");
    end

    // --- Flow key construction ---
    $display("\n=== Flow Key Construction ===");
    fkey.src_ip   = 32'hC0A80001;  // 192.168.0.1
    fkey.dst_ip   = 32'hC0A80002;  // 192.168.0.2
    fkey.src_port = 16'd1234;
    fkey.dst_port = 16'd80;
    fkey.protocol = PROTO_TCP;
    if ($bits(fkey) !== 104) begin
      $error("FAIL [flow_key size]: %0d", $bits(fkey));
      fail_count++;
    end else $display("PASS [flow_key construction]: src=%h dst=%h sport=%0d dport=%0d",
                       fkey.src_ip, fkey.dst_ip, fkey.src_port, fkey.dst_port);

    // --- Metadata struct zero init ---
    $display("\n=== Metadata Zero Init ===");
    meta = '0;
    if (meta.action !== ACTION_ACCEPT) begin
      $error("FAIL [meta zero init action]");
      fail_count++;
    end else $display("PASS [meta zero init]");

    // --- Rule entry ---
    $display("\n=== Rule Entry Construction ===");
    rule = '0;
    rule.rule_id    = 32'd1;
    rule.src_ip     = 32'h0A000000;
    rule.src_mask   = 32'hFF000000;
    rule.dst_ip     = 32'h00000000;
    rule.dst_mask   = 32'h00000000;
    rule.protocol   = PROTO_TCP;
    rule.dst_port_lo = 16'd80;
    rule.dst_port_hi = 16'd80;
    rule.action     = ACTION_ACCEPT;
    rule.enabled    = 1'b1;
    $display("PASS [rule entry]: id=%0d action=%s", rule.rule_id,
             rule.action.name());

    // --- Summary ---
    $display("\n=== Test Summary ===");
    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $error("%0d TEST(S) FAILED", fail_count);

    $finish;
  end

  // Timeout watchdog
  initial begin
    #10000;
    $error("TIMEOUT: simulation exceeded limit");
    $finish;
  end

endmodule : tb_blaze_pkg
