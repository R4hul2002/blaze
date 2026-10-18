// =============================================================================
// packet_buffer.sv — BRAM-backed Packet Buffer with AXI-Stream I/O
// Project  : BLAZE NGFW / M05
// =============================================================================
// Stores complete packets in BRAM while metadata is processed.
// Supports:
//   - Store-and-forward (full packet buffered before forwarding)
//   - Drop on full
//   - Per-packet metadata tagging
//   - Parameterized depth and data width
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

import blaze_pkg::*;

module packet_buffer #(
  parameter int unsigned DATA_W    = 8,
  parameter int unsigned DEPTH     = 4096,   // entries (bytes at DATA_W=8)
  parameter int unsigned META_FIFO = 64      // max concurrent packets
)(
  input  wire        clk,
  input  wire        rst_n,

  // Write port (from frame parser)
  input  wire [DATA_W-1:0] wr_tdata,
  input  wire              wr_tvalid,
  output wire              wr_tready,
  input  wire              wr_tlast,
  input  wire              wr_tuser,   // error flag

  // Write metadata (captured at wr_tlast)
  input  pkt_meta_t        wr_meta,
  input  wire              wr_meta_valid,

  // Read port (to VLAN/IP parsers)
  output reg  [DATA_W-1:0] rd_tdata,
  output reg               rd_tvalid,
  input  wire              rd_tready,
  output reg               rd_tlast,
  output reg               rd_tuser,

  // Read metadata (valid with first byte of each packet)
  output pkt_meta_t        rd_meta,
  output reg               rd_meta_valid,

  // Status
  output wire              buf_full,
  output wire              buf_empty,
  output wire [15:0]       pkt_count    // packets currently buffered
);

  localparam int unsigned ADDR_W = $clog2(DEPTH);
  localparam int unsigned LEN_W  = 14;  // max 9216 bytes

  // ---------------------------------------------------------------------------
  // BRAM (simple dual-port: write on wr_clk, read on rd_clk — same clock here)
  // ---------------------------------------------------------------------------
  reg [DATA_W-1:0] mem [0:DEPTH-1];

  // Write pointer, read pointer (byte granularity)
  reg [ADDR_W-1:0] wr_ptr = '0;
  reg [ADDR_W-1:0] rd_ptr = '0;
  reg [ADDR_W:0]   occupancy = '0;  // extra bit for full detection

  assign buf_full  = (occupancy >= DEPTH - 16);
  assign buf_empty = (occupancy == 0);
  assign wr_tready = ~buf_full;

  // ---------------------------------------------------------------------------
  // Packet length FIFO (stores start_ptr + length for each packet)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [ADDR_W-1:0] start_ptr;
    logic [LEN_W-1:0]  length;
    logic              error;
  } pkt_desc_t;

  pkt_desc_t desc_fifo [0:META_FIFO-1];
  reg [$clog2(META_FIFO)-1:0] desc_wr_ptr = '0;
  reg [$clog2(META_FIFO)-1:0] desc_rd_ptr = '0;
  reg [$clog2(META_FIFO):0]   desc_count  = '0;

  wire desc_full  = (desc_count == META_FIFO);
  wire desc_empty = (desc_count == 0);

  // Metadata FIFO (parallel to desc_fifo)
  pkt_meta_t meta_fifo_mem [0:META_FIFO-1];

  // Per-packet write tracking
  reg [ADDR_W-1:0] pkt_start_ptr = '0;
  reg [LEN_W-1:0]  pkt_len_cnt   = '0;

  assign pkt_count = desc_count[15:0];

  // ---------------------------------------------------------------------------
  // Write path
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr       <= '0;
      pkt_start_ptr<= '0;
      pkt_len_cnt  <= '0;
      desc_wr_ptr  <= '0;
      desc_count   <= '0;
      occupancy    <= '0;
    end else begin
      if (wr_tvalid && wr_tready) begin
        mem[wr_ptr]  <= wr_tdata;
        wr_ptr       <= wr_ptr + 1;
        pkt_len_cnt  <= pkt_len_cnt + 1;
        occupancy    <= occupancy + 1;

        if (wr_tlast) begin
          // Commit packet descriptor
          if (!desc_full) begin
            desc_fifo[desc_wr_ptr].start_ptr <= pkt_start_ptr;
            desc_fifo[desc_wr_ptr].length    <= pkt_len_cnt + 1;
            desc_fifo[desc_wr_ptr].error     <= wr_tuser;
            if (wr_meta_valid)
              meta_fifo_mem[desc_wr_ptr] <= wr_meta;
            desc_wr_ptr <= desc_wr_ptr + 1;
            desc_count  <= desc_count + 1;
          end
          pkt_start_ptr <= wr_ptr + 1;
          pkt_len_cnt   <= '0;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Read path (state machine)
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    RD_IDLE   = 2'd0,
    RD_META   = 2'd1,
    RD_DATA   = 2'd2
  } rd_state_t;

  rd_state_t rd_state = RD_IDLE;
  reg [LEN_W-1:0]  rd_remain = '0;
  reg [ADDR_W-1:0] rd_addr   = '0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_state    <= RD_IDLE;
      rd_ptr      <= '0;
      rd_addr     <= '0;
      rd_remain   <= '0;
      rd_tvalid   <= 1'b0;
      rd_tlast    <= 1'b0;
      rd_tuser    <= 1'b0;
      rd_tdata    <= '0;
      rd_meta_valid <= 1'b0;
      desc_rd_ptr <= '0;
    end else begin
      rd_meta_valid <= 1'b0;

      case (rd_state)
        RD_IDLE: begin
          rd_tvalid <= 1'b0;
          if (!desc_empty) begin
            rd_addr    <= desc_fifo[desc_rd_ptr].start_ptr;
            rd_remain  <= desc_fifo[desc_rd_ptr].length;
            rd_meta    <= meta_fifo_mem[desc_rd_ptr];
            rd_meta_valid <= 1'b1;
            rd_state   <= RD_DATA;
          end
        end

        RD_DATA: begin
          if (!rd_tvalid || rd_tready) begin
            rd_tdata  <= mem[rd_addr];
            rd_tvalid <= 1'b1;
            rd_tuser  <= desc_fifo[desc_rd_ptr].error;
            rd_tlast  <= (rd_remain == 1);
            rd_addr   <= rd_addr + 1;
            rd_remain <= rd_remain - 1;
            occupancy <= occupancy - 1;

            if (rd_remain == 1) begin
              desc_rd_ptr <= desc_rd_ptr + 1;
              desc_count  <= desc_count - 1;
              rd_state    <= RD_IDLE;
            end
          end
        end

        default: rd_state <= RD_IDLE;
      endcase
    end
  end

  // rd_meta registered output
  pkt_meta_t rd_meta_r;
  always_ff @(posedge clk) begin
    if (rd_meta_valid) rd_meta_r <= rd_meta;
  end
  assign rd_meta = rd_meta_r;

endmodule : packet_buffer

`default_nettype wire
