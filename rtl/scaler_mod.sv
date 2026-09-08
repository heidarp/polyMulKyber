`timescale 1ns/1ps

import ntt_pkg::*;
import modulus_funcs_pkg::*;

module scaler_mod(oprnd_x,  mul_reduced, input_valid, output_valid, clk, reset);

input clk, reset, input_valid;
output output_valid;
input [MODULUS_WIDTH-1:0] oprnd_x;
output wire [MODULUS_WIDTH-1:0] mul_reduced;

reg [2*MODULUS_WIDTH-1:0]   R_mul_res_wide;
reg [MODULUS_WIDTH-1:0]     R_mul_reduced;
reg [MUL_PIPE_DEPTH-1:0]    R_out_valid_dly;

assign output_valid = R_out_valid_dly[MUL_PIPE_DEPTH-1];

always @(posedge clk) begin
    if (reset == 1'b0) begin
        R_out_valid_dly <= '0;
    end
    else begin
        R_out_valid_dly[0] <= input_valid;
        for (int i = 0; i < (MUL_PIPE_DEPTH-1); i++) begin
            R_out_valid_dly[i+1] <= R_out_valid_dly[i];
        end
    end
end



localparam int WX = $bits(oprnd_x);   // or hardcode your operand width

wire [WX+1  : 0] t3    = {oprnd_x, 1'b0}  + oprnd_x;   // 3x
wire [WX+2  : 0] t7    = {oprnd_x, 3'b0}  - oprnd_x;   // 7x
wire [WX+7  : 0] t231  = {t7, 5'b0}       + t7;        // 231x
wire [WX+11 : 0] mul_c = {t3, 10'b0}      + t231;      // 3303x

always @(posedge clk) begin
    if (reset == 1'b0) begin
        R_mul_res_wide <= '0;
        R_mul_reduced  <= '0;
    end
    else begin
        R_mul_res_wide <= mul_c;
        R_mul_reduced  <= barret_reduce(R_mul_res_wide);
    end
end









assign mul_reduced = R_mul_reduced;

endmodule
