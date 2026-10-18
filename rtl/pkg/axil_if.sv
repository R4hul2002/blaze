// =============================================================================
// axil_if.sv — AXI4-Lite Interface Definition
// Project  : BLAZE NGFW
// Module   : M01 — Foundation Interfaces
// =============================================================================
// AXI4-Lite interface for control plane register access.
// ADDR_W : address bus width
// DATA_W : data bus width (32 or 64)
// =============================================================================

`ifndef AXIL_IF_SV
`define AXIL_IF_SV

interface axil_if #(
  parameter int unsigned ADDR_W = 32,
  parameter int unsigned DATA_W = 32
)(
  input logic clk,
  input logic rst_n
);
  localparam int unsigned STRB_W = DATA_W / 8;

  // Write address channel
  logic [ADDR_W-1:0]  awaddr;
  logic [2:0]         awprot;
  logic               awvalid;
  logic               awready;

  // Write data channel
  logic [DATA_W-1:0]  wdata;
  logic [STRB_W-1:0]  wstrb;
  logic               wvalid;
  logic               wready;

  // Write response channel
  logic [1:0]         bresp;
  logic               bvalid;
  logic               bready;

  // Read address channel
  logic [ADDR_W-1:0]  araddr;
  logic [2:0]         arprot;
  logic               arvalid;
  logic               arready;

  // Read data channel
  logic [DATA_W-1:0]  rdata;
  logic [1:0]         rresp;
  logic               rvalid;
  logic               rready;

  // Master (initiator) modport
  modport master (
    input  clk, rst_n,
    output awaddr, awprot, awvalid,
    input  awready,
    output wdata, wstrb, wvalid,
    input  wready,
    input  bresp, bvalid,
    output bready,
    output araddr, arprot, arvalid,
    input  arready,
    input  rdata, rresp, rvalid,
    output rready
  );

  // Slave (target) modport
  modport slave (
    input  clk, rst_n,
    input  awaddr, awprot, awvalid,
    output awready,
    input  wdata, wstrb, wvalid,
    output wready,
    output bresp, bvalid,
    input  bready,
    input  araddr, arprot, arvalid,
    output arready,
    output rdata, rresp, rvalid,
    input  rready
  );

  // Response codes
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_EXOKAY = 2'b01;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;

endinterface : axil_if

`endif // AXIL_IF_SV
