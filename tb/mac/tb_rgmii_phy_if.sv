// =============================================================================
// tb_rgmii_phy_if.sv — Testbench for RGMII PHY Interface
// Project  : BLAZE NGFW / M02
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_rgmii_phy_if;

  // -------------------------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------------------------
  logic        sys_clk_p = 0, sys_clk_n = 1;
  logic        sys_rst_n = 0;

  logic        rgmii_rxc = 0;
  logic [3:0]  rgmii_rxd = 0;
  logic        rgmii_rx_ctl = 0;

  wire         rgmii_txc;
  wire [3:0]   rgmii_txd;
  wire         rgmii_tx_ctl;
  wire         phy_reset_n;

  wire         clk_125m, clk_200m, rst_125m_n;
  wire [7:0]   rx_data;
  wire         rx_valid, rx_error, rx_last;

  logic [7:0]  tx_data  = 0;
  logic        tx_valid = 0;
  logic        tx_last  = 0;
  wire         tx_ready;

  // -------------------------------------------------------------------------
  // Clocks
  // -------------------------------------------------------------------------
  always #2.5  sys_clk_p = ~sys_clk_p;  // 200 MHz
  always #2.5  sys_clk_n = ~sys_clk_n;
  always #4.0  rgmii_rxc = ~rgmii_rxc;  // 125 MHz RGMII RX clock

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  rgmii_phy_if #(
    .IDELAY_VALUE (16)
  ) dut (
    .sys_clk_p    (sys_clk_p),
    .sys_clk_n    (sys_clk_n),
    .sys_rst_n    (sys_rst_n),
    .rgmii_rxc    (rgmii_rxc),
    .rgmii_rxd    (rgmii_rxd),
    .rgmii_rx_ctl (rgmii_rx_ctl),
    .rgmii_txc    (rgmii_txc),
    .rgmii_txd    (rgmii_txd),
    .rgmii_tx_ctl (rgmii_tx_ctl),
    .phy_reset_n  (phy_reset_n),
    .clk_125m     (clk_125m),
    .clk_200m     (clk_200m),
    .rst_125m_n   (rst_125m_n),
    .rx_data      (rx_data),
    .rx_valid     (rx_valid),
    .rx_error     (rx_error),
    .rx_last      (rx_last),
    .tx_data      (tx_data),
    .tx_valid     (tx_valid),
    .tx_last      (tx_last),
    .tx_ready     (tx_ready)
  );

  // -------------------------------------------------------------------------
  // Task: drive one RGMII byte (low nibble rise, high nibble fall)
  // -------------------------------------------------------------------------
  task automatic drive_rgmii_byte(input logic [7:0] data, input logic dv);
    @(posedge rgmii_rxc);
    rgmii_rxd    = data[3:0];
    rgmii_rx_ctl = dv;
    @(negedge rgmii_rxc);
    rgmii_rxd    = data[7:4];
    rgmii_rx_ctl = dv;
  endtask

  // -------------------------------------------------------------------------
  // Task: drive a frame
  // -------------------------------------------------------------------------
  task automatic drive_frame(input logic [7:0] bytes[], input int len);
    for (int i = 0; i < len; i++)
      drive_rgmii_byte(bytes[i], 1'b1);
    // End of frame: deassert DV
    @(posedge rgmii_rxc);
    rgmii_rxd    = 4'h0;
    rgmii_rx_ctl = 1'b0;
    @(negedge rgmii_rxc);
    rgmii_rxd    = 4'h0;
    rgmii_rx_ctl = 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // Scoreboard
  // -------------------------------------------------------------------------
  logic [7:0] expected_q[$];
  int         pass_cnt = 0, fail_cnt = 0;

  always_ff @(posedge clk_125m) begin
    if (rx_valid) begin
      if (expected_q.size() > 0) begin
        automatic logic [7:0] exp = expected_q.pop_front();
        if (rx_data === exp) begin
          pass_cnt++;
        end else begin
          $error("BYTE MISMATCH: got=%02h expected=%02h", rx_data, exp);
          fail_cnt++;
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // Main stimulus
  // -------------------------------------------------------------------------
  initial begin
    sys_rst_n = 0;
    repeat(20) @(posedge sys_clk_p);
    sys_rst_n = 1;

    // Wait for MMCM lock + reset release
    wait(rst_125m_n === 1'b1);
    repeat(10) @(posedge clk_125m);

    // --- Test 1: Single byte ---
    $display("[TB] Test 1: Single byte 0xAB");
    expected_q.push_back(8'hAB);
    drive_rgmii_byte(8'hAB, 1'b1);
    @(posedge rgmii_rxc); rgmii_rx_ctl = 0;
    repeat(4) @(posedge clk_125m);

    // --- Test 2: 8-byte frame ---
    $display("[TB] Test 2: 8-byte frame");
    begin
      logic [7:0] frame[8] = '{8'hDE,8'hAD,8'hBE,8'hEF,8'h01,8'h02,8'h03,8'h04};
      foreach (frame[i]) expected_q.push_back(frame[i]);
      drive_frame(frame, 8);
    end
    repeat(8) @(posedge clk_125m);

    // --- Test 3: TX path smoke ---
    $display("[TB] Test 3: TX path");
    @(posedge clk_125m);
    tx_data  = 8'h55;
    tx_valid = 1'b1;
    @(posedge clk_125m);
    tx_data  = 8'hAA;
    @(posedge clk_125m);
    tx_last  = 1'b1;
    @(posedge clk_125m);
    tx_valid = 1'b0;
    tx_last  = 1'b0;
    repeat(4) @(posedge clk_125m);

    // --- Summary ---
    $display("\n=== M02 RGMII PHY TB Summary ===");
    $display("PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
      $display("ALL TESTS PASSED");
    else
      $error("%0d FAILURES", fail_cnt);

    $finish;
  end

  // Timeout
  initial begin
    #500000;
    $error("TIMEOUT");
    $finish;
  end

endmodule : tb_rgmii_phy_if
`default_nettype wire
