`timescale 1ns/1ps

import ntt_pkg::*;

module basemul( 
    input [MODULUS_WIDTH-1:0] x,y,
    output wire [MODULUS_WIDTH-1:0] r,
    input input_valid,
    output output_valid,
    input clk, reset, is_negate
);


logic  [MODULUS_WIDTH - 1 : 0 ]  generated_w;

logic generate_new_w;





logic p00_out_valid;
logic p11_out_valid;
logic s01_out_valid;

logic karatsuba_muls_output_valid;

assign karatsuba_muls_output_valid = p00_out_valid & p11_out_valid & s01_out_valid;

assign  generate_new_w = karatsuba_muls_output_valid;

logic  [2:0] [MODULUS_WIDTH-1:0] fifo_x; 
logic  [2:0] [MODULUS_WIDTH-1:0] fifo_y; 

always @(posedge clk) begin
    if (reset_n == 1'b0) begin
       fifo_x <= '0;
       fifo_y <= '0;
    end
    else begin
        if input_valid begin
            fifo_x[0] <= x;
            fifo_y[0] <= y;
            fifo_x[1] <= fifo_x[0];
            fifo_y[1] <= fifo_y[0];
        end
    end
end

logic [MODULUS_WIDTH-1:0] p00,p11,s01,sa_reduced,sb_reduced;
logic [MODULUS_WIDTH-1:0] p00_c2;
logic [MODULUS_WIDTH:0] sa,sb;

logic [MODULUS_WIDTH-1:0] R_p00, R_p11,R_s01;

logic generate_new_w;

//w_gen 	#(.CNT_RST_VALUE(64),.STAGE_INDEX(6),.FWD_INV(0),.INITIAL_W(INITIAL_VALUE_W[5])  ) u_w_gen ( generated_w , generate_new_w , clk , reset);



w_gen #(
    .CNT_RST_VALUE(64),
    .STAGE_INDEX(6),
    .FWD_INV(0),
    .NUM_W_GENS(NUM_W_GENS)
) u_w_gen(generated_w, generate_new_w, clk, reset_n);


// Karatsuba parts
mod_mul u_mod_mul_p00 (fifo_x[0], fifo_y[0], p00, input_valid, p11_out_valid, clk, reset);
mod_mul u_mod_mul_p11 (fifo_x[1], fifo_y[1], p11, input_valid, p11_out_valid, clk, reset);
mod_mul u_mod_mul_s01 (fifo_x[1], fifo_y[1], s01, input_valid, s01_out_valid, clk, reset);


always_comb begin

sa = fifo_x[0] + fifo_x[1];
sb = fifo_y[0] + fifo_y[1];
    if (sa > MODULUS) begin
        sa_reduced = sa - MODULUS;
    end
    else begin
        sa_reduced = MODULUS_WIDTH'(sa);
    end
    if (sb > MODULUS) begin
        sb_reduced = sb - MODULUS;
    end
    else begin
        sb_reduced = MODULUS_WIDTH'(sb);
    end
end






always @(posedge clk) begin
    if (reset_n == 1'b0) begin
       fifo_x <= '0;
       fifo_y <= '0;
    end
    else begin
    //clk1
    R_p00 <= p00;
    R_p11 <= p11;
    R_s01 <= R_s01;
    //clk2

    
    
    end
    
    
end
