// =============================================================================
// axis_if.sv — AXI4-Stream Interface Definition
// Project  : BLAZE NGFW
// Module   : M01 — Foundation Interfaces
// =============================================================================
// Parameterized AXI4-Stream interface used throughout the packet datapath.
// DATA_W : data bus width in bits (must be multiple of 8)
// USER_W : tuser sideband width
// =============================================================================

`ifndef AXIS_IF_SV
`define AXIS_IF_SV

interface axis_if #(
  parameter int unsigned DATA_W = 64,
  parameter int unsigned USER_W = 1
)(
  input logic clk,
  input logic rst_n
);
  localparam int unsigned KEEP_W = DATA_W / 8;

  logic [DATA_W-1:0]  tdata;
  logic [KEEP_W-1:0]  tkeep;
  logic               tvalid;
  logic               tready;
  logic               tlast;
  logic [USER_W-1:0]  tuser;  // tuser[0] = error flag

  // Master drives: tdata, tkeep, tvalid, tlast, tuser
  modport master (
    input  clk, rst_n,
    output tdata, tkeep, tvalid, tlast, tuser,
    input  tready
  );

  // Slave drives: tready
  modport slave (
    input  clk, rst_n,
    input  tdata, tkeep, tvalid, tlast, tuser,
    output tready
  );

  // Monitor (read-only)
  modport monitor (
    input clk, rst_n,
    input tdata, tkeep, tvalid, tready, tlast, tuser
  );

  // Handshake helper
  function automatic logic beat();
    return tvalid & tready;
  endfunction

  // Assertions (synthesized out in implementation)
  // pragma translate_off

  // pragma translate_on

endinterface : axis_if

`endif // AXIS_IF_SV
