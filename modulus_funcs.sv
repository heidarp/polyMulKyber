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
        // quot underestimates floor(x/q) by at most 2, so two conditional subtractions suffice.
        logic [3*MODULUS_WIDTH:0]   scaled;
        logic [MODULUS_WIDTH:0]     quot;
        // Kept as its own signal so the product is evaluated at full width, not quot's.
        logic [2*MODULUS_WIDTH-1:0] quot_times_mod;
        logic [MODULUS_WIDTH+2:0]   rem;

        scaled         = shifted_in * BARRETT_MU;
        quot           = scaled >> BARRETT_SHIFT;
        quot_times_mod = quot * MODULUS_BIN;
        rem            = shifted_in - quot_times_mod;

        if (rem >= 2*MODULUS)
            barret_reduce = rem - 2*MODULUS;
        else if (rem >= MODULUS)
            barret_reduce = rem - MODULUS;
        else
            barret_reduce = rem;
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
