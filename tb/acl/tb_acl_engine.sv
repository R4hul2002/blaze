// =============================================================================
// tb_acl_engine.sv — Firewall ACL Engine Testbench
// Tests: ACCEPT, DROP, default-DROP, protocol-miss, zone-block
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

`include "../../sim/blaze_pkg_sim_fixed.sv"

module tb_acl_engine;
  import blaze_pkg::*;

  // -------------------------------------------------------------------------
  // Clock / reset
  // -------------------------------------------------------------------------
  logic clk = 0, rst_n = 0;
  always #4 clk = ~clk;   // 125 MHz

  // -------------------------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------------------------
  pkt_meta_t  meta_in, meta_out;
  logic       meta_valid, result_valid;
  logic       rule_wr_en;
  logic [3:0] rule_wr_addr;
  rule_entry_t rule_wr_data;
  logic [3:0] rule_count;

  // -------------------------------------------------------------------------
  // DUT — acl_engine_sim (MAX_RULES=16)
  // -------------------------------------------------------------------------
  acl_engine_sim #(.MAX_RULES(16)) dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .meta_in      (meta_in),
    .meta_valid   (meta_valid),
    .result_valid (result_valid),
    .meta_out     (meta_out),
    .rule_wr_en   (rule_wr_en),
    .rule_wr_addr (rule_wr_addr),
    .rule_wr_data (rule_wr_data),
    .rule_count   (rule_count)
  );

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  int fail_count = 0;

  task automatic write_rule(
    input int          idx,
    input logic [31:0] src_ip,   src_mask,
    input logic [31:0] dst_ip,   dst_mask,
    input logic [15:0] sport_lo, sport_hi,
    input logic [15:0] dport_lo, dport_hi,
    input proto_t      proto,
    input action_t     act,
    input logic        en
  );
    @(posedge clk);
    rule_wr_en            = 1;
    rule_wr_addr          = idx[3:0];
    rule_wr_data          = '0;
    rule_wr_data.src_ip   = src_ip;
    rule_wr_data.src_mask = src_mask;
    rule_wr_data.dst_ip   = dst_ip;
    rule_wr_data.dst_mask = dst_mask;
    rule_wr_data.src_port_lo = sport_lo;
    rule_wr_data.src_port_hi = sport_hi;
    rule_wr_data.dst_port_lo = dport_lo;
    rule_wr_data.dst_port_hi = dport_hi;
    rule_wr_data.protocol = proto;
    rule_wr_data.action   = act;
    rule_wr_data.enabled  = en;
    @(posedge clk);
    rule_wr_en = 0;
  endtask

  task automatic send_pkt(
    input logic [31:0] src_ip, dst_ip,
    input logic [15:0] sport,  dport,
    input proto_t      proto
  );
    @(posedge clk);
    meta_in        = '0;
    meta_in.src_ip4  = src_ip;
    meta_in.dst_ip4  = dst_ip;
    meta_in.src_port = sport;
    meta_in.dst_port = dport;
    meta_in.ip_proto = proto;
    meta_in.is_ipv4  = 1;
    meta_valid = 1;
    @(posedge clk);
    meta_valid = 0;
    // wait for result
    while (!result_valid) @(posedge clk);
  endtask

  task automatic check_action(input string name, input action_t expected);
    if (meta_out.action !== expected) begin
      $error("FAIL [%s]: got=%0d expected=%0d", name,
             int'(meta_out.action), int'(expected));
      fail_count++;
    end else
      $display("PASS [%s]: action=%0d  src=%h dst=%h dport=%0d",
               name, int'(meta_out.action),
               meta_out.src_ip4, meta_out.dst_ip4, meta_out.dst_port);
  endtask

  // -------------------------------------------------------------------------
  // Main
  // -------------------------------------------------------------------------
  initial begin
    $dumpfile("waves/tb_acl_engine.vcd");
    $dumpvars(0, tb_acl_engine);

    rule_wr_en  = 0;
    meta_valid  = 0;
    rule_count  = 0;
    meta_in     = '0;

    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // -----------------------------------------------------------------------
    // Load firewall rule table
    // Rule 0: ACCEPT  — 10.0.0.0/8  -> any,  TCP  dport 80
    // Rule 1: ACCEPT  — 10.0.0.0/8  -> any,  TCP  dport 443
    // Rule 2: DROP    — 192.168.1.0/24 -> any, any  (blocked subnet)
    // Rule 3: ACCEPT  — any -> any,  UDP  dport 53  (DNS)
    // Rule 4: DROP    — any -> any,  any  (default deny — catch-all)
    // -----------------------------------------------------------------------
    $display("\n=== Loading Firewall Rules ===");

    // Rule 0: ACCEPT TCP:80 from 10.0.0.0/8
    write_rule(0,
      32'h0A000000, 32'hFF000000,   // src 10.x.x.x
      32'h00000000, 32'h00000000,   // dst any
      16'd0, 16'hFFFF,              // sport any
      16'd80, 16'd80,               // dport 80
      PROTO_TCP, ACTION_ACCEPT, 1);

    // Rule 1: ACCEPT TCP:443 from 10.0.0.0/8
    write_rule(1,
      32'h0A000000, 32'hFF000000,
      32'h00000000, 32'h00000000,
      16'd0, 16'hFFFF,
      16'd443, 16'd443,
      PROTO_TCP, ACTION_ACCEPT, 1);

    // Rule 2: DROP 192.168.1.0/24
    write_rule(2,
      32'hC0A80100, 32'hFFFFFF00,   // src 192.168.1.x
      32'h00000000, 32'h00000000,
      16'd0, 16'hFFFF,
      16'd0, 16'hFFFF,
      PROTO_OTHER, ACTION_DROP, 1);

    // Rule 3: ACCEPT UDP:53 (DNS) from anywhere
    write_rule(3,
      32'h00000000, 32'h00000000,
      32'h00000000, 32'h00000000,
      16'd0, 16'hFFFF,
      16'd53, 16'd53,
      PROTO_UDP, ACTION_ACCEPT, 1);

    // Rule 4: default DROP (catch-all)
    write_rule(4,
      32'h00000000, 32'h00000000,
      32'h00000000, 32'h00000000,
      16'd0, 16'hFFFF,
      16'd0, 16'hFFFF,
      PROTO_OTHER, ACTION_DROP, 1);

    rule_count = 5;
    repeat(2) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test cases
    // -----------------------------------------------------------------------
    $display("\n=== Firewall Simulation ===");

    // T1: 10.1.2.3 -> 8.8.8.8 TCP:80  → ACCEPT (rule 0)
    send_pkt(32'h0A010203, 32'h08080808, 16'd5000, 16'd80,  PROTO_TCP);
    check_action("T1 TCP:80  from 10.x (ACCEPT)", ACTION_ACCEPT);

    // T2: 10.1.2.3 -> 8.8.8.8 TCP:443 → ACCEPT (rule 1)
    send_pkt(32'h0A010203, 32'h08080808, 16'd5001, 16'd443, PROTO_TCP);
    check_action("T2 TCP:443 from 10.x (ACCEPT)", ACTION_ACCEPT);

    // T3: 192.168.1.50 -> any TCP:80  → DROP (rule 2 — blocked subnet)
    send_pkt(32'hC0A80132, 32'h08080808, 16'd6000, 16'd80,  PROTO_TCP);
    check_action("T3 TCP:80  from 192.168.1.x (DROP)", ACTION_DROP);

    // T4: any -> any UDP:53            → ACCEPT (rule 3 — DNS)
    send_pkt(32'h01020304, 32'h08080808, 16'd9000, 16'd53,  PROTO_UDP);
    check_action("T4 UDP:53  DNS (ACCEPT)", ACTION_ACCEPT);

    // T5: 172.16.0.1 -> any TCP:22    → DROP (no match → rule 4 default deny)
    send_pkt(32'hAC100001, 32'h08080808, 16'd7000, 16'd22,  PROTO_TCP);
    check_action("T5 TCP:22  no-match (DROP)", ACTION_DROP);

    // T6: 10.0.0.1 -> any TCP:8080   → DROP (rule 0 only covers :80/:443)
    send_pkt(32'h0A000001, 32'h08080808, 16'd8000, 16'd8080, PROTO_TCP);
    check_action("T6 TCP:8080 from 10.x no-rule (DROP)", ACTION_DROP);

    // T7: 10.0.0.1 -> any UDP:80     → DROP (rule 0 is TCP only)
    send_pkt(32'h0A000001, 32'h08080808, 16'd9001, 16'd80,  PROTO_UDP);
    check_action("T7 UDP:80  proto-miss (DROP)", ACTION_DROP);

    // -----------------------------------------------------------------------
    $display("\n=== Test Summary ===");
    if (fail_count == 0) $display("ALL %0d TESTS PASSED", 7);
    else                 $error("%0d TEST(S) FAILED", fail_count);

    #50;
    $finish;
  end

  initial begin #50000; $error("TIMEOUT"); $finish; end

endmodule
`default_nettype wire
