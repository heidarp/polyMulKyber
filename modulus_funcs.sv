`timescale 1ns/1ps

import ntt_pkg::*;

// Modulus-dependent arithmetic helpers. Update this file when MODULUS changes.
package modulus_funcs_pkg;

    import ntt_pkg::*;

    function automatic logic [MODULUS_WIDTH-1:0] barret_reduce(
        input logic [2*MODULUS_WIDTH-1:0] shifted_in
    );
        // Custom Barrett-style reduce tuned for this MODULUS (not a generic mu-mul form).
        // SHIFT_LO / slice widths are modulus-specific; rebuild if MODULUS changes.
        localparam int SHIFT_LO = MODULUS_WIDTH - 10;
        logic [2*MODULUS_WIDTH-1:0] tmp_a;
        logic [MODULUS_WIDTH+2:0]   tmp_b;

        tmp_a = shifted_in - shifted_in[2*MODULUS_WIDTH-1:SHIFT_LO];
        tmp_b = {1'b0, shifted_in[MODULUS_WIDTH+1:0]}
            - ({1'b0, tmp_a[2*MODULUS_WIDTH-9:MODULUS_WIDTH-1], 9'b0}
            +  {1'b0, tmp_a[MODULUS_WIDTH+1:MODULUS_WIDTH-1], tmp_a[2*MODULUS_WIDTH-3:MODULUS_WIDTH-1]});

        // MSB of tmp_b set => under-subtracted; add q back into range.
        case (tmp_b[MODULUS_WIDTH+1])
            1: barret_reduce = tmp_b[MODULUS_WIDTH-1:0] + MODULUS_BIN;
            default: barret_reduce = tmp_b[MODULUS_WIDTH-1:0];
        endcase
    endfunction

    // w * FWD_W0 (462262) via shift-add; update shifts when MODULUS changes.
    function automatic logic [2*MODULUS_WIDTH-1:0] fwd_w0_multiply(
        input logic [MODULUS_WIDTH-1:0] w
    );
        fwd_w0_multiply =
            {2'b0, w, 19'b0}
            - {5'b0, w, 16'b0}
            + {9'b0, w, 12'b0}
            - {12'b0, w,  9'b0}
            - {15'b0, w,  6'b0}
            - {18'b0, w,  3'b0}
            - {20'b0, w,  1'b0};
    endfunction

    // w * INV_W0 (744574) via shift-add; update shifts when MODULUS changes.
    function automatic logic [2*MODULUS_WIDTH-1:0] inv_w0_multiply(
        input logic [MODULUS_WIDTH-1:0] w
    );
        inv_w0_multiply =
            {1'b0, w, 20'b0}
            - {3'b0, w, 18'b0}
            - {6'b0, w, 15'b0}
            - {8'b0, w, 13'b0}
            - {11'b0, w, 10'b0}
            + {14'b0, w,  7'b0}
            - {20'b0, w,  1'b0};
    endfunction

endpackage
