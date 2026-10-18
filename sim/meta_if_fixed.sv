// =============================================================================
// meta_if.sv — Packet Metadata Sideband Interface
// Project  : BLAZE NGFW
// Module   : M01 — Foundation Interfaces
// =============================================================================
// Carries pkt_meta_t alongside the AXI-Stream packet data bus.
// Every pipeline stage reads/writes fields of this sideband.
// =============================================================================

`ifndef META_IF_SV
`define META_IF_SV


interface meta_if (
  input logic clk,
  input logic rst_n
);
  import blaze_pkg::*;

  pkt_meta_t  meta;
  logic       valid;
  logic       ready;

  modport producer (
    input  clk, rst_n,
    output meta, valid,
    input  ready
  );

  modport consumer (
    input  clk, rst_n,
    input  meta, valid,
    output ready
  );

  modport monitor (
    input clk, rst_n, meta, valid, ready
  );

endinterface : meta_if

`endif // META_IF_SV
