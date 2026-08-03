`timescale 1ns/1ps

import ntt_pkg::*;

module butterfly(btfly_oprnd_a, btfly_oprnd_b, btfly_res_a, btfly_res_b, twdl_fctr, clk, reset_n);
input  [MODULUS_WIDTH-1:0] btfly_oprnd_a, btfly_oprnd_b, twdl_fctr;
output wire [MODULUS_WIDTH-1:0] btfly_res_a, btfly_res_b;
input clk, reset_n;

wire [MODULUS_WIDTH-1:0] mul_result;
wire                     mod_mul_output_valid_unused;

// Signed wide ops so add/sub can overshoot [0, q) before correction.
reg signed [MODULUS_WIDTH+1:0] R_sub_mod, R_plus_mod, R_add, R_sub, R_subc1, R_addc1;
reg [MODULUS_WIDTH-1:0] R_btfly_res_a, R_btfly_res_b;
// Align operand A with pipelined (b * w) so both sides of the butterfly meet.
reg  [MUL_PIPE_DEPTH-1:0]   [MODULUS_WIDTH-1:0]     R_btfly_oprnd_a_pipe;
//TODO remove or connect input_valid
mod_mul u_mod_mul (
    .oprnd_x      (btfly_oprnd_b),
    .oprnd_y      (twdl_fctr),
    .mul_reduced  (mul_result),
    .input_valid  (1'b1),
    .output_valid (mod_mul_output_valid_unused),
    .clk          (clk),
    .reset        (reset_n)
);

always @(posedge clk) begin
    if (reset_n == 1'b0) begin

        R_btfly_oprnd_a_pipe <= '0;
        R_btfly_res_a <= '0;
        R_btfly_res_b <= '0;
        R_sub_mod  <= '0;
        R_plus_mod <= '0;
        R_add      <= '0;
        R_sub      <= '0;
        R_subc1    <= '0;
        R_addc1    <= '0;
    end
    else begin
        R_btfly_oprnd_a_pipe[0] <= btfly_oprnd_a;
        for (int i = 0; i < MUL_PIPE_DEPTH-1; i++) begin
            R_btfly_oprnd_a_pipe[i+1] <= R_btfly_oprnd_a_pipe[i];
        end

        // Cooley-Tukey: a' = a + b*w,  b' = a - b*w  (mod q)
        R_add <= {2'b00, mul_result} + {2'b00, R_btfly_oprnd_a_pipe[MUL_PIPE_DEPTH-1]};
        R_sub <= -{2'b00, mul_result} + {2'b00, R_btfly_oprnd_a_pipe[MUL_PIPE_DEPTH-1]};

        // Precompute +/- q one cycle early; R_*c1 holds the raw sum/diff to match that delay.
        R_sub_mod  <= R_add - MODULUS_BIN;
        R_plus_mod <= R_sub + MODULUS_BIN;
        R_subc1    <= R_sub;
        R_addc1    <= R_add;

        // Bring results into [0, q): subtract q if add overflowed, add q if sub went negative.
        case (R_addc1 > MODULUS_BIN)
            1: R_btfly_res_a <= R_sub_mod[MODULUS_WIDTH-1:0];
            default: R_btfly_res_a <= R_addc1[MODULUS_WIDTH-1:0];
        endcase
        case (R_subc1 < 0)
            1: R_btfly_res_b <= R_plus_mod[MODULUS_WIDTH-1:0];
            default: R_btfly_res_b <= R_subc1[MODULUS_WIDTH-1:0];
        endcase
    end
end

assign btfly_res_a = R_btfly_res_a;
assign btfly_res_b = R_btfly_res_b;

endmodule
