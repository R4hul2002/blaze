// =============================================================================
// blaze_mac_wrapper.sv — Ethernet MAC Wrapper (Alex Forencich eth_mac_1g_rgmii_fifo)
// Project  : BLAZE NGFW
// Module   : M03
// =============================================================================
// Wraps eth_mac_1g_rgmii_fifo with:
//   - MMCM for gtx_clk (125 MHz) and gtx_clk90 (125 MHz, 90-deg)
//   - AXI-Stream interfaces (blaze axis_if)
//   - Status/error outputs to statistics engine
//   - AXI-Lite config port
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module blaze_mac_wrapper #(
  parameter int unsigned TX_FIFO_DEPTH = 4096,
  parameter int unsigned RX_FIFO_DEPTH = 4096,
  parameter int unsigned AXIS_DATA_W   = 8
)(
  // Clocks from MMCM (generated externally or internally)
  input  wire        gtx_clk,      // 125 MHz TX clock
  input  wire        gtx_clk90,    // 125 MHz, 90-degree phase
  input  wire        gtx_rst,      // active-high reset (gtx_clk domain)
  input  wire        logic_clk,    // core logic clock (125 MHz)
  input  wire        logic_rst,    // active-high reset (logic_clk domain)

  // RGMII PHY pins
  input  wire        rgmii_rx_clk,
  input  wire [3:0]  rgmii_rxd,
  input  wire        rgmii_rx_ctl,
  output wire        rgmii_tx_clk,
  output wire [3:0]  rgmii_txd,
  output wire        rgmii_tx_ctl,

  // TX AXI-Stream (logic_clk domain) — from packet forward engine
  input  wire [AXIS_DATA_W-1:0] tx_axis_tdata,
  input  wire                   tx_axis_tvalid,
  output wire                   tx_axis_tready,
  input  wire                   tx_axis_tlast,
  input  wire                   tx_axis_tuser,  // 1 = bad frame, discard

  // RX AXI-Stream (logic_clk domain) — to frame parser
  output wire [AXIS_DATA_W-1:0] rx_axis_tdata,
  output wire                   rx_axis_tvalid,
  input  wire                   rx_axis_tready,
  output wire                   rx_axis_tlast,
  output wire                   rx_axis_tuser,  // 1 = bad FCS

  // Status
  output wire        tx_error_underflow,
  output wire        rx_error_bad_frame,
  output wire        rx_error_bad_fcs,
  output wire        rx_fifo_overflow,
  output wire [1:0]  speed,

  // Configuration (static or AXI-Lite driven)
  input  wire [7:0]  cfg_ifg,        // inter-frame gap (default 12)
  input  wire        cfg_tx_enable,
  input  wire        cfg_rx_enable
);

  // tkeep not used at 8-bit width (always 1'b1)
  wire tx_axis_tkeep = 1'b1;
  wire rx_axis_tkeep;

  eth_mac_1g_rgmii_fifo #(
    .TARGET                  ("XILINX"),
    .IODDR_STYLE             ("IODDR"),
    .CLOCK_INPUT_STYLE       ("BUFR"),
    .USE_CLK90               ("TRUE"),
    .AXIS_DATA_WIDTH         (AXIS_DATA_W),
    .AXIS_KEEP_ENABLE        (0),
    .AXIS_KEEP_WIDTH         (1),
    .ENABLE_PADDING          (1),
    .MIN_FRAME_LENGTH        (64),
    .TX_FIFO_DEPTH           (TX_FIFO_DEPTH),
    .TX_FIFO_RAM_PIPELINE    (1),
    .TX_FRAME_FIFO           (1),
    .TX_DROP_OVERSIZE_FRAME  (1),
    .TX_DROP_BAD_FRAME       (1),
    .TX_DROP_WHEN_FULL       (0),
    .RX_FIFO_DEPTH           (RX_FIFO_DEPTH),
    .RX_FIFO_RAM_PIPELINE    (1),
    .RX_FRAME_FIFO           (1),
    .RX_DROP_OVERSIZE_FRAME  (1),
    .RX_DROP_BAD_FRAME       (1),
    .RX_DROP_WHEN_FULL       (1)
  ) u_mac (
    .gtx_clk              (gtx_clk),
    .gtx_clk90            (gtx_clk90),
    .gtx_rst              (gtx_rst),
    .logic_clk            (logic_clk),
    .logic_rst            (logic_rst),

    .tx_axis_tdata        (tx_axis_tdata),
    .tx_axis_tkeep        (tx_axis_tkeep),
    .tx_axis_tvalid       (tx_axis_tvalid),
    .tx_axis_tready       (tx_axis_tready),
    .tx_axis_tlast        (tx_axis_tlast),
    .tx_axis_tuser        (tx_axis_tuser),

    .rx_axis_tdata        (rx_axis_tdata),
    .rx_axis_tkeep        (rx_axis_tkeep),
    .rx_axis_tvalid       (rx_axis_tvalid),
    .rx_axis_tready       (rx_axis_tready),
    .rx_axis_tlast        (rx_axis_tlast),
    .rx_axis_tuser        (rx_axis_tuser),

    .rgmii_rx_clk         (rgmii_rx_clk),
    .rgmii_rxd            (rgmii_rxd),
    .rgmii_rx_ctl         (rgmii_rx_ctl),
    .rgmii_tx_clk         (rgmii_tx_clk),
    .rgmii_txd            (rgmii_txd),
    .rgmii_tx_ctl         (rgmii_tx_ctl),

    .tx_error_underflow   (tx_error_underflow),
    .tx_fifo_overflow     (),
    .tx_fifo_bad_frame    (),
    .tx_fifo_good_frame   (),
    .rx_error_bad_frame   (rx_error_bad_frame),
    .rx_error_bad_fcs     (rx_error_bad_fcs),
    .rx_fifo_overflow     (rx_fifo_overflow),
    .rx_fifo_bad_frame    (),
    .rx_fifo_good_frame   (),
    .speed                (speed),

    .cfg_ifg              (cfg_ifg),
    .cfg_tx_enable        (cfg_tx_enable),
    .cfg_rx_enable        (cfg_rx_enable)
  );

endmodule : blaze_mac_wrapper

`default_nettype wire
