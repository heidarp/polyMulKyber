`timescale 1ns/1ps

import ntt_pkg::*;
import modulus_funcs_pkg::*;



//module barret_reduce_mod  (
//    input  logic [2*MODULUS_WIDTH-1:0] shifted_in,
//    output logic [MODULUS_WIDTH-1:0]   barret_reduce
//);

//    // Stage 1: t = floor(inp*5039 / 2^24), computed with 4 guard bits.
//    // Shift amounts are 12,14,18,20,24 minus 4 guard bits -> 8,10,14,16,20.
//    logic signed [17:0] s;
//    logic signed [13:0] t;
//    logic        [12:0] tl;
//    logic        [12:0] r13;
//    logic [12:0] temp1, temp2, temp3;
//always_comb begin
//    // Stage 1: All unsigned operations
//    s = {2'b0, shifted_in[23:8]}     // inp >> 8
//      + {4'b0, shifted_in[23:10]}    // inp >> 10
//      - {8'b0, shifted_in[23:14]}    // inp >> 14
//      - {10'b0, shifted_in[23:16]}  // inp >> 16
//      - {14'b0, shifted_in[23:20]}   // inp >> 20
//      - 18'd3;                        // truncation bias (no sign extension needed)

//    t = s >>> 4;                      // Logical shift right (unsigned)
//    tl = t[12:0];

//    // Stage 2: res13 = inp - t*3329, evaluated mod 2^13
//    r13 = shifted_in[12:0]
//        - {tl[0],   12'b0}            // (t<<12) mod 2^13
//        + {tl[2:0], 10'b0}            // (t<<10) mod 2^13
//        - {tl[4:0],  8'b0}            // (t<<8)  mod 2^13
//        - tl;

//    barret_reduce = (r13 >= 13'd3329) ? (r13 - 13'd3329) : r13[MODULUS_WIDTH-1:0];
//end
/*
module barret_reduce_mod  (
    input  logic [2*MODULUS_WIDTH-1:0] shifted_in,
    output logic [MODULUS_WIDTH-1:0]   barret_reduce
);
always_comb begin
        logic [23:0] tmp_a;
        logic [12+2:0]   tmp_b;

        
        logic [12:0] tl;
 logic [13:0] r14;
  logic [12:0] r13;
  
 tmp_a = shifted_in + shifted_in[23:2] - shifted_in[23:6] - shifted_in[23:8];
      
//        tmp_b = {1'b0, shifted_in[MODULUS_WIDTH+1:0]}
//            - ({1'b0, tmp_a[2*MODULUS_WIDTH-9:MODULUS_WIDTH-1], 9'b0}
//            +  {1'b0, tmp_a[MODULUS_WIDTH+1:MODULUS_WIDTH-1], tmp_a[2*MODULUS_WIDTH-3:MODULUS_WIDTH-1]});


   tl  = tmp_a[23:12];
   r14 = {1'b0,shifted_in[12:0]}
             - {1'b0,tl[0],   12'b0}              // (t<<12) mod 2^13
             + {1'b0,tl[2:0], 10'b0}              // (t<<10) mod 2^13
             - {1'b0,tl[4:0],  8'b0}              // (t<<8)  mod 2^13
             - {1'b0,tl}
             +{1'b00,MODULUS_BIN};
             
             
             r13=r14[12:0];
               barret_reduce = MODULUS_WIDTH '((r13 >= 13'd3329) ? (r13 - 13'd3329) : r13);   
//             if (r14[13] ==1) begin
//             barret_reduce = r13 + {1'b00,MODULUS_BIN};
//             end
//             else begin
//             barret_reduce=r13;
//             
//             end
             
      barret_reduce = MODULUS_WIDTH '((r13 >= 13'd3329) ? (r13 - 13'd3329) : r13);          
//        tmp_b = {1'b0, shifted_in[11:0]}
//            - {1'b0, tmp_a[12], 12'b0}
//            + {1'b0, tmp_a[14:12], 12'b0}
//            - {1'b0, tmp_a[16:12], 8'b0}
//            - {1'b0, tmp_a[23:12]};
//            

//        // MSB of tmp_b set => under-subtracted; add q back into range.
//        case (tmp_b[MODULUS_WIDTH+1])
//            1: barret_reduce = tmp_b[MODULUS_WIDTH-1:0] + MODULUS_BIN;
//            default: barret_reduce = tmp_b[MODULUS_WIDTH-1:0];
        //endcase
end
endmodule
*/











module mod_mul(oprnd_x, oprnd_y, mul_reduced, input_valid, output_valid, clk, reset);

input clk, reset, input_valid;
output output_valid;
input [MODULUS_WIDTH-1:0] oprnd_x, oprnd_y;
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

always @(posedge clk) begin
    if (reset == 1'b0) begin
        R_mul_res_wide <= '0;
        R_mul_reduced  <= '0;
    end
    else begin
        R_mul_res_wide <= oprnd_x * oprnd_y;
        R_mul_reduced  <= barret_reduce(R_mul_res_wide);
    end
end

assign mul_reduced = R_mul_reduced;


//barret_reduce_mod u_barret_reduce (.shifted_in(R_mul_res_wide), .barret_reduce(mul_reduced));





endmodule
