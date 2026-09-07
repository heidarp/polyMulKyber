`timescale 1ns/1ps

import ntt_pkg::*;

// Modulus-dependent arithmetic helpers. Update this file when MODULUS changes.
package modulus_funcs_pkg;

    import ntt_pkg::*;

    // Barrett constants derive from MODULUS, so they stay valid if MODULUS changes.
    localparam int              BARRETT_SHIFT = 2*MODULUS_WIDTH;
    localparam longint unsigned BARRETT_MU    =
        (longint'(1) << BARRETT_SHIFT) / longint'(MODULUS);

    function automatic logic [MODULUS_WIDTH-1:0] barret_reduce(
        input logic [2*MODULUS_WIDTH-1:0] shifted_in
    );
//        // quot underestimates floor(x/q) by at most 2, so two conditional subtractions suffice.
//        logic [3*MODULUS_WIDTH:0]   scaled;
//        logic [MODULUS_WIDTH:0]     quot;
//        // Kept as its own signal so the product is evaluated at full width, not quot's.
//        logic [2*MODULUS_WIDTH-1:0] quot_times_mod;
//        logic [MODULUS_WIDTH+2:0]   rem;

//        scaled         = shifted_in * BARRETT_MU;
//        quot           = (MODULUS_WIDTH+1)'(scaled >> BARRETT_SHIFT);
//        quot_times_mod = quot * MODULUS_BIN;
//        rem            = shifted_in - quot_times_mod;

//        if (rem >= 2*MODULUS)
//            barret_reduce = MODULUS_WIDTH'(rem - 2*MODULUS) ;
//        else if (rem >= MODULUS)
//            barret_reduce = MODULUS_WIDTH'(rem - MODULUS) ;
//        else
//            barret_reduce = MODULUS_WIDTH'(rem);
//================================

// Stage 1: t = floor(inp*5039 / 2^24), computed with 4 guard bits.
  // Shift amounts are 12,14,18,20,24 minus 4 guard bits -> 8,10,14,16,20.
//  logic signed [17:0] s;
//  logic signed [13:0] t;
// logic [12:0] tl;
// logic [12:0] r13;
// 
//   s = $signed({ 2'b0, shifted_in[23: 8]})    // inp >> 8
//           + $signed({ 4'b0, shifted_in[23:10]})    // inp >> 10
//           - $signed({ 8'b0, shifted_in[23:14]})    // inp >> 14
//           - $signed({10'b0, shifted_in[23:16]})    // inp >> 16
//           - $signed({14'b0, shifted_in[23:20]})    // inp >> 20
//           - 18'sd3;                         // truncation bias

//   t = 14'(s >>> 4);                        // range [-1, 5038]

//  // Stage 2: res13 = inp - t*3329, evaluated mod 2^13.
// 
//   tl  = t[12:0];
//   r13 = shifted_in[12:0]
//             - {tl[0],   12'b0}              // (t<<12) mod 2^13
//             + {tl[2:0], 10'b0}              // (t<<10) mod 2^13
//             - {tl[4:0],  8'b0}              // (t<<8)  mod 2^13
//             - tl;

//  // r13 in [198, 6343] < 2q, so one conditional subtract is enough
//   barret_reduce = MODULUS_WIDTH '((r13 >= 13'd3329) ? (r13 - 13'd3329) : r13);

        logic [23:0] tmp_a;
        logic [12+2:0]   tmp_b;

        
        logic [12:0] tl;
 logic [13:0] r14;
  logic [12:0] r13;
  
  logic [12:0] shifted_in_13;
  
  shifted_in_13 = shifted_in[12:0];
  
  
 tmp_a = shifted_in + shifted_in[23:2] - shifted_in[23:6] - shifted_in[23:8];
   tl  = tmp_a[23:12];
   r13 = {shifted_in_13}
             - {tl[0],   12'b0}              // (t<<12) mod 2^13
             + {tl[2:0], 10'b0}              // (t<<10) mod 2^13
             - {tl[4:0],  8'b0}              // (t<<8)  mod 2^13
             - {tl}
             +{MODULUS_BIN};
             
             
             //r13=r14[12:0];
               barret_reduce = MODULUS_WIDTH '((r13 >= 13'd3329) ? (r13 - 13'd3329) : r13);   
//             if (r14[13] ==1) begin
//             barret_reduce = r13 + {1'b00,MODULUS_BIN};
//             end
//             else begin
//             barret_reduce=r13;
//             
//             end
             
      //barret_reduce = MODULUS_WIDTH '((r13 >= 13'd3329) ? (r13 - 13'd3329) : r13);   
//==================================



//        logic [2*MODULUS_WIDTH-1:0] tmp_a;
//        logic [MODULUS_WIDTH+2:0]   tmp_b;

//        tmp_a = shifted_in - shifted_in[2*MODULUS_WIDTH-1:2]-shifted_in[2*MODULUS_WIDTH-1:6]-shifted_in[2*MODULUS_WIDTH-1:8];
//        tmp_b = {1'b0, shifted_in[MODULUS_WIDTH+1:0]}
//            - ({1'b0, tmp_a[12], 12'b0}
//            + {1'b0, tmp_a[14:12], 12'b0}
//            - {1'b0, tmp_a[16:12], 8'b0}
//            - {1'b0, tmp_a[2*MODULUS_WIDTH-1:12]});
//            

//        // MSB of tmp_b set => under-subtracted; add q back into range.
//        case (tmp_b[MODULUS_WIDTH+1])
//            1: barret_reduce = tmp_b[MODULUS_WIDTH-1:0] + MODULUS_BIN;
//            default: barret_reduce = tmp_b[MODULUS_WIDTH-1:0];
//        endcase




    endfunction




    // w * W_VALUE (17 = 2^4 + 1) via shift-add; update shifts when W_VALUE changes.
    function automatic logic [2*MODULUS_WIDTH-1:0] fwd_w0_multiply(
        input logic [MODULUS_WIDTH-1:0] w
    );
        fwd_w0_multiply =
            {8'b0, w, 4'b0}
            + {12'b0, w};
    endfunction

    // w * INV_W_VALUE (1175 = 2^10 + 2^7 + 2^4 + 2^3 - 1) via shift-add.
    function automatic logic [2*MODULUS_WIDTH-1:0] inv_w0_multiply(
        input logic [MODULUS_WIDTH-1:0] w
    );
        inv_w0_multiply =
            {2'b0, w, 10'b0}
            + {5'b0, w,  7'b0}
            + {8'b0, w,  4'b0}
            + {9'b0, w,  3'b0}
            - {12'b0, w};
    endfunction

endpackage
