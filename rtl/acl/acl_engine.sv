// =============================================================================
// acl_engine.sv — ACL / Firewall Rule Engine
// Project : BLAZE NGFW / M18
// =============================================================================
// Linear priority-ordered rule lookup over BRAM rule table.
// Supports: IP prefix match, port range, protocol, zone, app_id.
// Pipeline: 1 rule checked per cycle -> N cycles for N rules.
// For production: replace with TCAM or parallel BRAM banks.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
import blaze_pkg::*;

module acl_engine #(
  parameter int unsigned MAX_RULES  = 1024,
  parameter int unsigned RULE_BITS  = $clog2(MAX_RULES)
)(
  input  wire        clk,
  input  wire        rst_n,

  // Metadata input (from session lookup)
  input  pkt_meta_t  meta_in,
  input  wire        meta_valid,

  // Result output (1 cycle after last rule checked)
  output reg         result_valid,
  output pkt_meta_t  meta_out,

  // Rule table write port (from MicroBlaze via AXI-Lite)
  input  wire                    rule_wr_en,
  input  wire [RULE_BITS-1:0]    rule_wr_addr,
  input  rule_entry_t            rule_wr_data,

  // Active rule count
  input  wire [RULE_BITS-1:0]    rule_count
);

  // ---------------------------------------------------------------------------
  // Rule BRAM
  // ---------------------------------------------------------------------------
  rule_entry_t rule_mem [0:MAX_RULES-1];

  always_ff @(posedge clk) begin
    if (rule_wr_en)
      rule_mem[rule_wr_addr] <= rule_wr_data;
  end

  // ---------------------------------------------------------------------------
  // Match logic (combinational per rule)
  // ---------------------------------------------------------------------------
  function automatic logic rule_match(
    input rule_entry_t r,
    input pkt_meta_t   m
  );
    logic ip_src_ok, ip_dst_ok, port_src_ok, port_dst_ok, proto_ok, app_ok, zone_ok;
    ip_src_ok   = ((m.src_ip4 & r.src_mask) == (r.src_ip & r.src_mask));
    ip_dst_ok   = ((m.dst_ip4 & r.dst_mask) == (r.dst_ip & r.dst_mask));
    port_src_ok = (m.src_port >= r.src_port_lo) && (m.src_port <= r.src_port_hi);
    port_dst_ok = (m.dst_port >= r.dst_port_lo) && (m.dst_port <= r.dst_port_hi);
    proto_ok    = (r.protocol == PROTO_OTHER) || (r.protocol == m.ip_proto);
    app_ok      = (r.app_id == APP_UNKNOWN)   || (r.app_id   == m.app_id);
    zone_ok     = (r.src_zone == 8'hFF)       || (r.src_zone == m.src_zone);
    return r.enabled & ip_src_ok & ip_dst_ok & port_src_ok &
           port_dst_ok & proto_ok & app_ok & zone_ok;
  endfunction

  // ---------------------------------------------------------------------------
  // Sequential rule scan state machine
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    ACL_IDLE  = 2'd0,
    ACL_SCAN  = 2'd1,
    ACL_DONE  = 2'd2
  } acl_state_t;

  acl_state_t   state;
  reg [RULE_BITS-1:0] rule_idx;
  pkt_meta_t    meta_r;
  reg           matched;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= ACL_IDLE;
      rule_idx     <= '0;
      result_valid <= 1'b0;
      matched      <= 1'b0;
    end else begin
      result_valid <= 1'b0;

      case (state)
        ACL_IDLE: begin
          if (meta_valid) begin
            meta_r   <= meta_in;
            rule_idx <= '0;
            matched  <= 1'b0;
            state    <= ACL_SCAN;
          end
        end

        ACL_SCAN: begin
          if (!matched && rule_idx < rule_count) begin
            if (rule_match(rule_mem[rule_idx], meta_r)) begin
              meta_r.action    <= rule_mem[rule_idx].action;
              meta_r.do_log    <= rule_mem[rule_idx].log_en;
              meta_r.do_mirror <= rule_mem[rule_idx].mirror_en;
              meta_r.qos_queue <= rule_mem[rule_idx].qos_queue;
              matched          <= 1'b1;
              state            <= ACL_DONE;
            end else
              rule_idx <= rule_idx + 1;
          end else
            state <= ACL_DONE;
        end

        ACL_DONE: begin
          // Default action: DROP if no match
          if (!matched) meta_r.action <= ACTION_DROP;
          meta_out     <= meta_r;
          result_valid <= 1'b1;
          state        <= ACL_IDLE;
        end

        default: state <= ACL_IDLE;
      endcase
    end
  end

endmodule : acl_engine
`default_nettype wire
