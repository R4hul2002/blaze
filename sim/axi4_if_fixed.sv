// =============================================================================
// axi4_if.sv — AXI4 Full Interface Definition
// Project  : BLAZE NGFW
// Module   : M01 — Foundation Interfaces
// =============================================================================
// Full AXI4 interface for high-bandwidth memory access (DDR3, DMA).
// =============================================================================

`ifndef AXI4_IF_SV
`define AXI4_IF_SV

interface axi4_if #(
  parameter int unsigned ADDR_W  = 32,
  parameter int unsigned DATA_W  = 64,
  parameter int unsigned ID_W    = 8,
  parameter int unsigned LEN_W   = 8,   // AxLEN width (AXI4 = 8)
  parameter int unsigned USER_W  = 1
)(
  input logic clk,
  input logic rst_n
);
  localparam int unsigned STRB_W = DATA_W / 8;

  // Write address channel
  logic [ID_W-1:0]    awid;
  logic [ADDR_W-1:0]  awaddr;
  logic [LEN_W-1:0]   awlen;
  logic [2:0]         awsize;
  logic [1:0]         awburst;
  logic               awlock;
  logic [3:0]         awcache;
  logic [2:0]         awprot;
  logic [3:0]         awqos;
  logic [3:0]         awregion;
  logic [USER_W-1:0]  awuser;
  logic               awvalid;
  logic               awready;

  // Write data channel
  logic [DATA_W-1:0]  wdata;
  logic [STRB_W-1:0]  wstrb;
  logic               wlast;
  logic [USER_W-1:0]  wuser;
  logic               wvalid;
  logic               wready;

  // Write response channel
  logic [ID_W-1:0]    bid;
  logic [1:0]         bresp;
  logic [USER_W-1:0]  buser;
  logic               bvalid;
  logic               bready;

  // Read address channel
  logic [ID_W-1:0]    arid;
  logic [ADDR_W-1:0]  araddr;
  logic [LEN_W-1:0]   arlen;
  logic [2:0]         arsize;
  logic [1:0]         arburst;
  logic               arlock;
  logic [3:0]         arcache;
  logic [2:0]         arprot;
  logic [3:0]         arqos;
  logic [3:0]         arregion;
  logic [USER_W-1:0]  aruser;
  logic               arvalid;
  logic               arready;

  // Read data channel
  logic [ID_W-1:0]    rid;
  logic [DATA_W-1:0]  rdata;
  logic [1:0]         rresp;
  logic               rlast;
  logic [USER_W-1:0]  ruser;
  logic               rvalid;
  logic               rready;

  modport master (
    input  clk, rst_n,
    output awid, awaddr, awlen, awsize, awburst, awlock, awcache,
           awprot, awqos, awregion, awuser, awvalid,
    input  awready,
    output wdata, wstrb, wlast, wuser, wvalid,
    input  wready,
    input  bid, bresp, buser, bvalid,
    output bready,
    output arid, araddr, arlen, arsize, arburst, arlock, arcache,
           arprot, arqos, arregion, aruser, arvalid,
    input  arready,
    input  rid, rdata, rresp, rlast, ruser, rvalid,
    output rready
  );

  modport slave (
    input  clk, rst_n,
    input  awid, awaddr, awlen, awsize, awburst, awlock, awcache,
           awprot, awqos, awregion, awuser, awvalid,
    output awready,
    input  wdata, wstrb, wlast, wuser, wvalid,
    output wready,
    output bid, bresp, buser, bvalid,
    input  bready,
    input  arid, araddr, arlen, arsize, arburst, arlock, arcache,
           arprot, arqos, arregion, aruser, arvalid,
    output arready,
    output rid, rdata, rresp, rlast, ruser, rvalid,
    input  rready
  );

  // Burst type constants
  localparam logic [1:0] BURST_FIXED = 2'b00;
  localparam logic [1:0] BURST_INCR  = 2'b01;
  localparam logic [1:0] BURST_WRAP  = 2'b10;

endinterface : axi4_if

`endif // AXI4_IF_SV
