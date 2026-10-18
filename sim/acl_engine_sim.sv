// =============================================================================
// acl_engine_sim.sv
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module acl_engine_sim
  import blaze_pkg::*;
#(parameter int unsigned MAX_RULES=16)(
  input  wire        clk, rst_n,
  input  pkt_meta_t  meta_in,
  input  wire        meta_valid,
  output reg         result_valid,
  output pkt_meta_t  meta_out,
  input  wire        rule_wr_en,
  input  wire [$clog2(MAX_RULES)-1:0] rule_wr_addr,
  input  rule_entry_t rule_wr_data,
  input  wire [$clog2(MAX_RULES)-1:0] rule_count
);
  rule_entry_t rule_mem [0:MAX_RULES-1];
  always_ff @(posedge clk)
    if (rule_wr_en) rule_mem[rule_wr_addr] <= rule_wr_data;

  function automatic logic rule_match(input rule_entry_t r, input pkt_meta_t m);
    return r.enabled
      & ((m.src_ip4 & r.src_mask)==(r.src_ip & r.src_mask))
      & ((m.dst_ip4 & r.dst_mask)==(r.dst_ip & r.dst_mask))
      & (m.src_port>=r.src_port_lo) & (m.src_port<=r.src_port_hi)
      & (m.dst_port>=r.dst_port_lo) & (m.dst_port<=r.dst_port_hi)
      & ((r.protocol==PROTO_OTHER)|(r.protocol==m.ip_proto));
  endfunction

  typedef enum logic [1:0] {IDLE=0,SCAN=1,DONE=2} st_t;
  st_t state;
  reg [$clog2(MAX_RULES)-1:0] ridx;
  pkt_meta_t meta_r;
  reg matched;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin state<=IDLE; result_valid<=0; matched<=0; end
    else begin
      result_valid<=0;
      case (state)
        IDLE: if (meta_valid) begin meta_r<=meta_in; ridx<=0; matched<=0; state<=SCAN; end
        SCAN: begin
          if (!matched && ridx<rule_count) begin
            if (rule_match(rule_mem[ridx],meta_r)) begin
              meta_r.action    <= rule_mem[ridx].action;
              meta_r.do_log    <= rule_mem[ridx].log_en;
              meta_r.do_mirror <= rule_mem[ridx].mirror_en;
              meta_r.qos_queue <= rule_mem[ridx].qos_queue;
              matched<=1; state<=DONE;
            end else ridx<=ridx+1;
          end else state<=DONE;
        end
        DONE: begin
          if (!matched) meta_r.action<=ACTION_DROP;
          meta_out<=meta_r; result_valid<=1; state<=IDLE;
        end
      endcase
    end
  end
endmodule
`default_nettype wire
