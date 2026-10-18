// =============================================================================
// axil_regfile.sv — AXI-Lite Register File (Control Plane)
// Project : BLAZE NGFW / M25
// =============================================================================
// Complete AXI-Lite slave register file.
// Memory map (word-addressed, 32-bit):
//   0x0000 : CTRL        — global enable, reset
//   0x0004 : STATUS      — link speed, lock status
//   0x0008 : VERSION     — firmware version
//   0x000C : PORT_ID     — port configuration
//   0x0010 : RULE_COUNT  — active rule count
//   0x0014 : FLOW_COUNT  — active flow count
//   0x0018 : LOG_WR_PTR  — log write pointer
//   0x001C : LOG_RD_PTR  — log read pointer
//   0x0020 : RATE_TICK   — rate tick divisor
//   0x0024 : NAT_POOL    — NAT pool base IP
//   0x0028 : THREAT_CFG  — threat action config
//   0x002C : IFG_CFG     — inter-frame gap
//   0x0100-0x01FF : per-queue rate config (64 queues x 2 regs)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module axil_regfile #(
  parameter int unsigned ADDR_W = 32,
  parameter int unsigned DATA_W = 32
)(
  input  wire        clk,
  input  wire        rst_n,

  // AXI-Lite slave
  input  wire [ADDR_W-1:0] s_awaddr,
  input  wire              s_awvalid,
  output reg               s_awready,
  input  wire [DATA_W-1:0] s_wdata,
  input  wire [3:0]        s_wstrb,
  input  wire              s_wvalid,
  output reg               s_wready,
  output reg [1:0]         s_bresp,
  output reg               s_bvalid,
  input  wire              s_bready,
  input  wire [ADDR_W-1:0] s_araddr,
  input  wire              s_arvalid,
  output reg               s_arready,
  output reg [DATA_W-1:0]  s_rdata,
  output reg [1:0]         s_rresp,
  output reg               s_rvalid,
  input  wire              s_rready,

  // Register outputs to datapath
  output reg         reg_global_en,
  output reg         reg_tx_en,
  output reg         reg_rx_en,
  output reg [7:0]   reg_ifg,
  output reg [15:0]  reg_rule_count,
  output reg [31:0]  reg_nat_pool,
  output reg [31:0]  reg_rate_tick_div,
  output reg [23:0]  reg_rate_cfg  [0:15],
  output reg [23:0]  reg_burst_cfg [0:15],

  // Register inputs from datapath
  input  wire [1:0]  status_speed,
  input  wire        status_locked,
  input  wire [31:0] status_flow_count,
  input  wire [31:0] status_log_wr_ptr,
  input  wire [31:0] status_log_rd_ptr
);

  // Write address latch
  reg [ADDR_W-1:0] wr_addr_r;

  // ---------------------------------------------------------------------------
  // Write channel
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_awready <= 1'b0; s_wready <= 1'b0;
      s_bvalid  <= 1'b0; s_bresp  <= 2'b00;
      reg_global_en    <= 1'b1;
      reg_tx_en        <= 1'b1;
      reg_rx_en        <= 1'b1;
      reg_ifg          <= 8'd12;
      reg_rule_count   <= 16'd0;
      reg_nat_pool     <= 32'hC0A80100;
      reg_rate_tick_div<= 32'd125000;
      for (int i = 0; i < 16; i++) begin
        reg_rate_cfg[i]  <= 24'hFFFFFF;  // unlimited by default
        reg_burst_cfg[i] <= 24'hFFFFFF;
      end
    end else begin
      s_awready <= 1'b1;
      s_wready  <= 1'b1;

      if (s_awvalid && s_awready) wr_addr_r <= s_awaddr;

      if (s_wvalid && s_wready) begin
        s_bvalid <= 1'b1;
        s_bresp  <= 2'b00;
        case (wr_addr_r[11:0])
          12'h000: {reg_rx_en, reg_tx_en, reg_global_en} <= s_wdata[2:0];
          12'h00C: ;  // port_id read-only
          12'h010: reg_rule_count   <= s_wdata[15:0];
          12'h020: reg_rate_tick_div<= s_wdata;
          12'h024: reg_nat_pool     <= s_wdata;
          12'h02C: reg_ifg          <= s_wdata[7:0];
          default: begin
            // Queue rate config: 0x100 + q*8 = rate, 0x104 + q*8 = burst
            if (wr_addr_r[11:8] == 4'h1) begin
              automatic int q = wr_addr_r[7:3];
              if (q < 16) begin
                if (!wr_addr_r[2]) reg_rate_cfg[q]  <= s_wdata[23:0];
                else               reg_burst_cfg[q] <= s_wdata[23:0];
              end
            end
          end
        endcase
      end

      if (s_bvalid && s_bready) s_bvalid <= 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // Read channel
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_arready <= 1'b0; s_rvalid <= 1'b0; s_rresp <= 2'b00;
    end else begin
      s_arready <= 1'b1;
      if (s_arvalid && s_arready) begin
        s_rvalid <= 1'b1;
        s_rresp  <= 2'b00;
        case (s_araddr[11:0])
          12'h000: s_rdata <= {29'h0, reg_rx_en, reg_tx_en, reg_global_en};
          12'h004: s_rdata <= {29'h0, status_locked, status_speed};
          12'h008: s_rdata <= 32'h0001_0000;  // version 1.0
          12'h010: s_rdata <= {16'h0, reg_rule_count};
          12'h014: s_rdata <= status_flow_count;
          12'h018: s_rdata <= status_log_wr_ptr;
          12'h01C: s_rdata <= status_log_rd_ptr;
          12'h020: s_rdata <= reg_rate_tick_div;
          12'h024: s_rdata <= reg_nat_pool;
          12'h02C: s_rdata <= {24'h0, reg_ifg};
          default: begin
            if (s_araddr[11:8] == 4'h1) begin
              automatic int q = s_araddr[7:3];
              if (q < 16)
                s_rdata <= s_araddr[2] ? {8'h0, reg_burst_cfg[q]}
                                       : {8'h0, reg_rate_cfg[q]};
              else s_rdata <= 32'h0;
            end else s_rdata <= 32'h0;
          end
        endcase
      end
      if (s_rvalid && s_rready) s_rvalid <= 1'b0;
    end
  end

endmodule : axil_regfile
`default_nettype wire
