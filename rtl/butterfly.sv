`timescale 1ns/1ps

import ntt_pkg::*;

module butterfly #(
    parameter FWD_INV = 0
) (btfly_oprnd_a, btfly_oprnd_b, btfly_res_a, btfly_res_b, twdl_fctr, clk, reset_n);

    input  [MODULUS_WIDTH-1:0] btfly_oprnd_a, btfly_oprnd_b, twdl_fctr;
    output wire [MODULUS_WIDTH-1:0] btfly_res_a, btfly_res_b;
    input  clk, reset_n;

    generate
        if (FWD_INV == 0) begin : ct_butterfly

            wire [MODULUS_WIDTH-1:0] mul_result;
            wire                     mod_mul_output_valid_UNUSED;

            reg signed [MODULUS_WIDTH+1:0] R_sub_mod, R_plus_mod, R_add, R_sub, R_subc1, R_addc1;
            reg [MODULUS_WIDTH-1:0] R_btfly_res_a, R_btfly_res_b;
            reg [MUL_PIPE_DEPTH-1:0] [MODULUS_WIDTH-1:0] R_btfly_oprnd_a_pipe;

            mod_mul u_mod_mul (
                .oprnd_x      (btfly_oprnd_b),
                .oprnd_y      (twdl_fctr),
                .mul_reduced  (mul_result),
                .input_valid  (1'b1),
                .output_valid (mod_mul_output_valid_UNUSED),
                .clk          (clk),
                .reset        (reset_n)
            );

            always @(posedge clk) begin
                if (reset_n == 1'b0) begin
                    R_btfly_oprnd_a_pipe <= '0;
                    R_btfly_res_a        <= '0;
                    R_btfly_res_b        <= '0;
                    R_sub_mod            <= '0;
                    R_plus_mod           <= '0;
                    R_add                <= '0;
                    R_sub                <= '0;
                    R_subc1              <= '0;
                    R_addc1              <= '0;
                end
                else begin
                    R_btfly_oprnd_a_pipe[0] <= btfly_oprnd_a;
                    for (int i = 0; i < MUL_PIPE_DEPTH-1; i++) begin
                        R_btfly_oprnd_a_pipe[i+1] <= R_btfly_oprnd_a_pipe[i];
                    end

                    R_add <= {2'b00, mul_result} + {2'b00, R_btfly_oprnd_a_pipe[MUL_PIPE_DEPTH-1]};
                    R_sub <= -{2'b00, mul_result} + {2'b00, R_btfly_oprnd_a_pipe[MUL_PIPE_DEPTH-1]};

                    R_sub_mod  <= R_add - MODULUS_BIN;
                    R_plus_mod <= R_sub + MODULUS_BIN;
                    R_subc1    <= R_sub;
                    R_addc1    <= R_add;

                    case (R_addc1 >= MODULUS_BIN)
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

        end
        else begin : gs_butterfly

            wire [MODULUS_WIDTH-1:0] mul_result;
            wire                     mod_mul_output_valid_UNUSED;

            reg signed [MODULUS_WIDTH+1:0] R_sub_mod, R_plus_mod, R_add, R_sub, R_subc1, R_addc1;
            reg [MODULUS_WIDTH-1:0] R_btfly_res_a, R_btfly_res_b;
            reg signed [MODULUS_WIDTH+1:0] R_add_pipe [MUL_PIPE_DEPTH-1:0];
            reg [MODULUS_WIDTH-1:0] R_oprnd_a, R_oprnd_b, R_twdl;

            logic signed [MODULUS_WIDTH+1:0] oprna_sub_oprnd_b;
            logic [MODULUS_WIDTH-1:0] oprna_sub_oprnd_b_reduced;

            always_comb begin
                oprna_sub_oprnd_b = R_oprnd_a - R_oprnd_b;
                if (oprna_sub_oprnd_b < 0) begin
                    oprna_sub_oprnd_b_reduced = oprna_sub_oprnd_b + MODULUS_BIN;
                end
                else begin
                    oprna_sub_oprnd_b_reduced = oprna_sub_oprnd_b[MODULUS_WIDTH-1:0];
                end
            end

            mod_mul u_mod_mul (
                .oprnd_x      (oprna_sub_oprnd_b_reduced),
                .oprnd_y      (R_twdl),
                .mul_reduced  (mul_result),
                .input_valid  (1'b1),
                .output_valid (mod_mul_output_valid_UNUSED),
                .clk          (clk),
                .reset        (reset_n)
            );

            always @(posedge clk) begin
                if (reset_n == 1'b0) begin
                    R_oprnd_a     <= '0;
                    R_oprnd_b     <= '0;
                    R_twdl        <= '0;
                    R_sub_mod     <= '0;
                    R_plus_mod    <= '0;
                    R_add         <= '0;
                    R_sub         <= '0;
                    R_subc1       <= '0;
                    R_addc1       <= '0;
                    R_btfly_res_a <= '0;
                    R_btfly_res_b <= '0;
                    for (int i = 0; i < MUL_PIPE_DEPTH; i++) begin
                        R_add_pipe[i] <= '0;
                    end
                end
                else begin
                    R_oprnd_a <= btfly_oprnd_a;
                    R_oprnd_b <= btfly_oprnd_b;
                    R_twdl    <= twdl_fctr;

                    R_add <= R_oprnd_a + R_oprnd_b;

                    R_add_pipe[0] <= R_add;
                    for (int i = 0; i < MUL_PIPE_DEPTH-1; i++) begin
                        R_add_pipe[i+1] <= R_add_pipe[i];
                    end

                    R_sub <= mul_result;

                    R_sub_mod  <= R_add_pipe[MUL_PIPE_DEPTH-1] - MODULUS_BIN;
                    R_plus_mod <= R_sub + MODULUS_BIN;
                    R_subc1    <= R_sub;
                    R_addc1    <= R_add_pipe[MUL_PIPE_DEPTH-1];

                    case (R_addc1 >= MODULUS_BIN)
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

        end
    endgenerate

endmodule
