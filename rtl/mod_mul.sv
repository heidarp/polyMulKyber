`timescale 1ns/1ps

import ntt_pkg::*;
import modulus_funcs_pkg::*;

(* use_dsp = "no" *)
module barret_reduce_mod (
    input  logic                       clk,
    input  logic                       reset,
    input  logic [2*MODULUS_WIDTH-1:0] shifted_in,
    output logic [MODULUS_WIDTH-1:0]   reduced
);

    logic [2*MODULUS_WIDTH-1:0] tmp_a;

    always_comb begin
        tmp_a = shifted_in
              + shifted_in[2*MODULUS_WIDTH-1:2]
              - shifted_in[2*MODULUS_WIDTH-1:6]
              - shifted_in[2*MODULUS_WIDTH-1:8];
    end

    reg [MODULUS_WIDTH-1:0] R_tl;
    reg [MODULUS_WIDTH:0]   R_shifted_in_low;
    reg [MODULUS_WIDTH-1:0] R_reduced;

    logic [MODULUS_WIDTH:0] tl;
    logic [MODULUS_WIDTH:0] r13_n_mod;

    always_comb begin
        tl = {1'b0, R_tl};

        r13_n_mod = R_shifted_in_low
                  - {tl[0],   12'b0}
                  + {tl[2:0], 10'b0}
                  - {tl[4:0],  8'b0}
                  - tl;
    end

    always @(posedge clk) begin
        if (reset == 1'b0) begin
            R_tl             <= '0;
            R_shifted_in_low <= '0;
            R_reduced        <= '0;
        end
        else begin
            R_tl             <= tmp_a[2*MODULUS_WIDTH-1:MODULUS_WIDTH];
            R_shifted_in_low <= shifted_in[MODULUS_WIDTH:0];

            case (r13_n_mod[MODULUS_WIDTH])
                1:       R_reduced <= MODULUS_WIDTH'(r13_n_mod + MODULUS_BIN);
                default: R_reduced <= r13_n_mod[MODULUS_WIDTH-1:0];
            endcase
        end
    end

    assign reduced = R_reduced;

endmodule

module mod_mul(oprnd_x, oprnd_y, mul_reduced, input_valid, output_valid, clk, reset);

    input  clk, reset, input_valid;
    output output_valid;
    input  [MODULUS_WIDTH-1:0] oprnd_x, oprnd_y;
    output wire [MODULUS_WIDTH-1:0] mul_reduced;

    reg [MODULUS_WIDTH-1:0]     R_oprnd_x, R_oprnd_y;
    reg [2*MODULUS_WIDTH-1:0] R_mul_res_wide;
    reg [MUL_PIPE_DEPTH-1:0]  R_out_valid_dly;

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
            R_oprnd_x      <= '0;
            R_oprnd_y      <= '0;
            R_mul_res_wide <= '0;
        end
        else begin
            R_oprnd_x      <= oprnd_x;
            R_oprnd_y      <= oprnd_y;
            R_mul_res_wide <= R_oprnd_x * R_oprnd_y;
        end
    end

    barret_reduce_mod u_barret_reduce (
        .clk        (clk),
        .reset      (reset),
        .shifted_in (R_mul_res_wide),
        .reduced    (mul_reduced)
    );

endmodule
