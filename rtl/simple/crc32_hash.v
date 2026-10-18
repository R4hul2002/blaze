// =============================================================================
// crc32_hash.v — Simple CRC32-based hash (Verilog-2001 for Yosys)
// Demonstrates BLAZE synthesis capability
// =============================================================================

module crc32_hash (
  input wire clk,
  input wire rst_n,
  
  // Input data
  input wire [31:0] src_ip,
  input wire [31:0] dst_ip,
  input wire [15:0] src_port,
  input wire [15:0] dst_port,
  input wire [7:0]  protocol,
  input wire        data_valid,
  
  // Output hash
  output reg [31:0] hash_out,
  output reg        hash_valid
);

  // CRC32 polynomial
  parameter [31:0] CRC_POLY = 32'hEDB88320;
  
  // Compute CRC32 for one byte
  function [31:0] crc32_step;
    input [31:0] crc;
    input [7:0] data;
    reg [31:0] c;
    integer i;
    begin
      c = crc ^ {24'h0, data};
      for (i = 0; i < 8; i = i + 1)
        c = c[0] ? ((c >> 1) ^ CRC_POLY) : (c >> 1);
      crc32_step = c;
    end
  endfunction
  
  // Sequential CRC computation
  reg [31:0] crc_reg;
  reg [3:0] byte_cnt;
  reg computing;
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crc_reg <= 32'hFFFFFFFF;
      byte_cnt <= 4'd0;
      computing <= 1'b0;
      hash_out <= 32'd0;
      hash_valid <= 1'b0;
    end else begin
      hash_valid <= 1'b0;
      
      if (data_valid && !computing) begin
        // Start new hash
        crc_reg <= 32'hFFFFFFFF;
        byte_cnt <= 4'd0;
        computing <= 1'b1;
      end else if (computing) begin
        case (byte_cnt)
          4'd0: crc_reg <= crc32_step(crc_reg, src_ip[31:24]);
          4'd1: crc_reg <= crc32_step(crc_reg, src_ip[23:16]);
          4'd2: crc_reg <= crc32_step(crc_reg, src_ip[15:8]);
          4'd3: crc_reg <= crc32_step(crc_reg, src_ip[7:0]);
          4'd4: crc_reg <= crc32_step(crc_reg, dst_ip[31:24]);
          4'd5: crc_reg <= crc32_step(crc_reg, dst_ip[23:16]);
          4'd6: crc_reg <= crc32_step(crc_reg, dst_ip[15:8]);
          4'd7: crc_reg <= crc32_step(crc_reg, dst_ip[7:0]);
          4'd8: crc_reg <= crc32_step(crc_reg, src_port[15:8]);
          4'd9: crc_reg <= crc32_step(crc_reg, src_port[7:0]);
          4'd10: crc_reg <= crc32_step(crc_reg, dst_port[15:8]);
          4'd11: crc_reg <= crc32_step(crc_reg, dst_port[7:0]);
          4'd12: crc_reg <= crc32_step(crc_reg, protocol);
        endcase
        
        if (byte_cnt == 4'd12) begin
          hash_out <= ~crc_reg;
          hash_valid <= 1'b1;
          computing <= 1'b0;
        end
        byte_cnt <= byte_cnt + 1'd1;
      end
    end
  end

endmodule
