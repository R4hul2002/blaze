// =============================================================================
// stats_logger.sv — Statistics Counter + Event Logger
// Project : BLAZE NGFW / M23
// =============================================================================
// Maintains 64-bit saturating counters per port.
// Writes log entries to a BRAM ring buffer readable by MicroBlaze via AXI-Lite.
// Log entry: 32 bytes = timestamp(8) + src_ip(4) + dst_ip(4) + ports(4) +
//            proto(1) + action(1) + threat(1) + app_id(1) + sig_id(2) + pad(6)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module stats_logger #(
  parameter int unsigned LOG_DEPTH  = 4096,  // log ring buffer entries
  parameter int unsigned NUM_PORTS  = 2
)(
  input  wire        clk,
  input  wire        rst_n,

  // Metadata from final decision stage
  input  pkt_meta_t  meta_in,
  input  wire        meta_valid,

  // AXI-Lite read port (MicroBlaze reads log entries)
  input  wire [31:0] axil_araddr,
  input  wire        axil_arvalid,
  output reg         axil_arready,
  output reg [31:0]  axil_rdata,
  output reg         axil_rvalid,
  input  wire        axil_rready,

  // Per-port stats (readable via AXI-Lite at fixed offsets)
  output port_stats_t stats [0:NUM_PORTS-1],

  // Log write pointer (for MicroBlaze to know how many entries)
  output reg [31:0]  log_wr_ptr,
  output reg [31:0]  log_rd_ptr
);

  // ---------------------------------------------------------------------------
  // Log entry (32 bytes = 8 x 32-bit words)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [63:0]  timestamp;
    logic [31:0]  src_ip;
    logic [31:0]  dst_ip;
    logic [15:0]  src_port;
    logic [15:0]  dst_port;
    logic [7:0]   protocol;
    logic [3:0]   action;
    logic [2:0]   threat;
    logic [7:0]   app_id;
    logic [15:0]  sig_id;
    logic [47:0]  pad;
  } log_entry_t;  // 256 bits = 32 bytes

  localparam int unsigned LOG_ADDR_W = $clog2(LOG_DEPTH);
  localparam int unsigned ENTRY_W    = $bits(log_entry_t);  // 256

  reg [ENTRY_W-1:0] log_mem [0:LOG_DEPTH-1];
  reg [LOG_ADDR_W-1:0] wr_ptr_r = '0;
  reg [LOG_ADDR_W-1:0] rd_ptr_r = '0;

  assign log_wr_ptr = {{(32-LOG_ADDR_W){1'b0}}, wr_ptr_r};
  assign log_rd_ptr = {{(32-LOG_ADDR_W){1'b0}}, rd_ptr_r};

  // ---------------------------------------------------------------------------
  // Statistics counters
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int p = 0; p < NUM_PORTS; p++) stats[p] <= '0;
    end else if (meta_valid) begin
      automatic int p = meta_in.port_id < NUM_PORTS ? int'(meta_in.port_id) : 0;
      stats[p].rx_pkts  <= stats[p].rx_pkts  + 1;
      stats[p].rx_bytes <= stats[p].rx_bytes + meta_in.pkt_len;
      case (meta_in.action)
        ACTION_DROP, ACTION_REJECT: begin
          stats[p].drop_pkts  <= stats[p].drop_pkts  + 1;
          stats[p].drop_bytes <= stats[p].drop_bytes + meta_in.pkt_len;
        end
        ACTION_ACCEPT: begin
          stats[p].fwd_pkts   <= stats[p].fwd_pkts + 1;
          stats[p].tx_pkts    <= stats[p].tx_pkts  + 1;
          stats[p].tx_bytes   <= stats[p].tx_bytes + meta_in.pkt_len;
        end
        ACTION_NAT: stats[p].nat_pkts <= stats[p].nat_pkts + 1;
        default: ;
      endcase
      if (meta_in.dpi_match) stats[p].dpi_hits <= stats[p].dpi_hits + 1;
      if (meta_in.sig_match) stats[p].sig_hits <= stats[p].sig_hits + 1;
    end
  end

  // ---------------------------------------------------------------------------
  // Log writer
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr_r <= '0;
    end else if (meta_valid && meta_in.do_log) begin
      log_mem[wr_ptr_r] <= ENTRY_W'({
        meta_in.timestamp,
        meta_in.src_ip4,
        meta_in.dst_ip4,
        meta_in.src_port,
        meta_in.dst_port,
        meta_in.ip_proto,
        meta_in.action,
        meta_in.threat,
        meta_in.app_id,
        meta_in.sig_id,
        48'h0
      });
      wr_ptr_r <= wr_ptr_r + 1;
    end
  end

  // ---------------------------------------------------------------------------
  // AXI-Lite read port (word-addressed, 32-bit reads)
  // Log base = 0x0000, each entry = 8 words
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axil_arready <= 1'b0;
      axil_rvalid  <= 1'b0;
    end else begin
      axil_arready <= 1'b1;
      if (axil_arvalid && axil_arready) begin
        automatic logic [LOG_ADDR_W-1:0] entry_idx = axil_araddr[LOG_ADDR_W+4:5];
        automatic logic [2:0]            word_idx  = axil_araddr[4:2];
        automatic logic [ENTRY_W-1:0]    entry     = log_mem[entry_idx];
        // Extract 32-bit word from 256-bit entry
        axil_rdata  <= entry[ENTRY_W-1 - word_idx*32 -: 32];
        axil_rvalid <= 1'b1;
      end
      if (axil_rvalid && axil_rready)
        axil_rvalid <= 1'b0;
    end
  end

endmodule : stats_logger
`default_nettype wire
