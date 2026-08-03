`timescale 1ns/1ps

import ntt_pkg::*;
import modulus_funcs_pkg::*;

module mod_mul(oprnd_x, oprnd_y, mul_reduced, input_valid, output_valid, clk, reset);

input clk, reset, input_valid;
output output_valid;
input [MODULUS_WIDTH-1:0] oprnd_x, oprnd_y;
output wire [MODULUS_WIDTH-1:0] mul_reduced;

reg [2*MODULUS_WIDTH-1:0] R_mul_res_wide;
reg [MUL_PIPE_DEPTH-1:0] R_out_valid_dly;

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

always @(posedge clk) begin
    if (reset == 1'b0) begin
        R_mul_res_wide <= '0;
    end
    else begin
        R_mul_res_wide <= oprnd_x * oprnd_y;
    end
end

assign mul_reduced = barret_reduce(R_mul_res_wide);

endmodule
