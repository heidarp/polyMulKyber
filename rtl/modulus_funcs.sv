`timescale 1ns/1ps

import ntt_pkg::*;

package modulus_funcs_pkg;

    import ntt_pkg::*;

    localparam int              BARRETT_SHIFT = 2*MODULUS_WIDTH;
    localparam longint unsigned BARRETT_MU    =
        (longint'(1) << BARRETT_SHIFT) / longint'(MODULUS);

    function automatic logic [MODULUS_WIDTH-1:0] barret_reduce(
        input logic [2*MODULUS_WIDTH-1:0] shifted_in
    );
        logic [23:0] tmp_a;
        logic [12:0] tl;
        logic signed [12:0] r13_n_mod;

        tmp_a = shifted_in + shifted_in[23:2] - shifted_in[23:6] - shifted_in[23:8];
        tl = tmp_a[23:12];

        r13_n_mod = shifted_in[12:0] - tl * 13'd3329;

        case (r13_n_mod[12])
            1:       barret_reduce = r13_n_mod + MODULUS_BIN;
            default: barret_reduce = r13_n_mod;
        endcase
    endfunction

    function automatic logic [2*MODULUS_WIDTH-1:0] fwd_w0_multiply(
        input logic [MODULUS_WIDTH-1:0] w
    );
        fwd_w0_multiply =
            {8'b0, w, 4'b0}
            + {12'b0, w};
    endfunction

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
