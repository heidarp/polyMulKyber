`timescale 1ns/1ps
// =============================================================================
//  DEBUG-ONLY FILE - not part of the design.
//
//  Dumps every valid beat of every pipeline stage of poly_mul to a text file
//  so check_ntt_stages.py can compare each stage against a software Kyber
//  model.  Nothing in the design depends on it.
//
//  Enable:   make poly_mul DEBUG_PROBE=1        (adds +define+NTT_DEBUG_PROBE)
//  Rename:   ./simv +ntt_trace=some_other_name.txt
//
//  To remove the whole debug facility, delete:
//    1. this file
//    2. the `ifdef NTT_DEBUG_PROBE block at the bottom of poly_mul.sv
//    3. the "DEBUG PROBE" block in the Makefile
//    4. check_ntt_stages.py
// =============================================================================

`ifdef NTT_DEBUG_PROBE

import ntt_pkg::*;

module ntt_debug_probe (
    input logic                              clk,
    input logic                              reset_n,
    input poly_type                          x_in,
    input poly_type                          y_in,
    input poly_type [TOTAL_NUM_STAGES-1:0]   fwd_x,   // outputs of forward stages 1..7 (x)
    input poly_type [TOTAL_NUM_STAGES-1:0]   fwd_y,   // outputs of forward stages 1..7 (y)
    input poly_type                          pm,      // basemul (pointwise) result
    input poly_type [TOTAL_NUM_STAGES-1:0]   inv,     // outputs of inverse stages 1..7
    input poly_type                          out      // final, after the SCALER multiply
);

localparam int BEATS_PER_POLY = POLYNOMIAL_LENGTH / NUM_COEFS_PER_STAGE;
localparam int NUM_TAGS       = 4 + 3*TOTAL_NUM_STAGES;

// Tag layout: x_in, y_in, fx1..fxS, fy1..fyS, pm, in1..inS, out
localparam int TAG_X_IN = 0;
localparam int TAG_Y_IN = 1;
localparam int TAG_FX   = 2;
localparam int TAG_FY   = TAG_FX + TOTAL_NUM_STAGES;
localparam int TAG_PM   = TAG_FY + TOTAL_NUM_STAGES;
localparam int TAG_INV  = TAG_PM + 1;
localparam int TAG_OUT  = TAG_INV + TOTAL_NUM_STAGES;

string tag_name [0:NUM_TAGS-1];
int    beat_cnt [0:NUM_TAGS-1];
int    trace_fd;
string trace_file;

initial begin
    trace_file = "ntt_debug_trace.txt";
    void'($value$plusargs("ntt_trace=%s", trace_file));

    trace_fd = $fopen(trace_file, "w");
    if (trace_fd == 0) begin
        $fatal(1, "[ntt_debug_probe] cannot open %s for writing", trace_file);
    end

    tag_name[TAG_X_IN] = "x_in";
    tag_name[TAG_Y_IN] = "y_in";
    tag_name[TAG_PM]   = "pm";
    tag_name[TAG_OUT]  = "out";
    for (int s = 0; s < TOTAL_NUM_STAGES; s++) begin
        tag_name[TAG_FX  + s] = $sformatf("fx%0d", s+1);
        tag_name[TAG_FY  + s] = $sformatf("fy%0d", s+1);
        tag_name[TAG_INV + s] = $sformatf("in%0d", s+1);
    end
    for (int i = 0; i < NUM_TAGS; i++) begin
        beat_cnt[i] = 0;
    end

    $fwrite(trace_fd, "# tag poly beat coef0..coef%0d\n", NUM_COEFS_PER_STAGE-1);
    $fwrite(trace_fd, "# q=%0d n=%0d stages=%0d lanes=%0d beats_per_poly=%0d\n",
            MODULUS, POLYNOMIAL_LENGTH, TOTAL_NUM_STAGES,
            NUM_COEFS_PER_STAGE, BEATS_PER_POLY);
    $display("[ntt_debug_probe] tracing %0d signals to %s", NUM_TAGS, trace_file);
end

// Sampled at posedge, so every tag records the value that was presented during
// the cycle just ending -- one line per valid beat, counted per tag.
task automatic log_beat(input int tag_idx, input poly_type p);
    if (p.valid === 1'b1) begin
        $fwrite(trace_fd, "%s %0d %0d",
                tag_name[tag_idx],
                beat_cnt[tag_idx] / BEATS_PER_POLY,
                beat_cnt[tag_idx] % BEATS_PER_POLY);
        for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
            $fwrite(trace_fd, " %0d", p.coefs[i]);
        end
        $fwrite(trace_fd, "\n");
        beat_cnt[tag_idx] = beat_cnt[tag_idx] + 1;
    end
endtask

always @(posedge clk) begin
    if (reset_n === 1'b1) begin
        log_beat(TAG_X_IN, x_in);
        log_beat(TAG_Y_IN, y_in);
        for (int s = 0; s < TOTAL_NUM_STAGES; s++) begin
            log_beat(TAG_FX  + s, fwd_x[s]);
            log_beat(TAG_FY  + s, fwd_y[s]);
            log_beat(TAG_INV + s, inv[s]);
        end
        log_beat(TAG_PM,  pm);
        log_beat(TAG_OUT, out);
    end
end

final begin
    $display("[ntt_debug_probe] beats captured (%0d per polynomial):", BEATS_PER_POLY);
    for (int i = 0; i < NUM_TAGS; i++) begin
        $display("[ntt_debug_probe]   %-6s %0d", tag_name[i], beat_cnt[i]);
    end
    $fclose(trace_fd);
    $display("[ntt_debug_probe] wrote %s -- check with: python3 check_ntt_stages.py -t %s",
             trace_file, trace_file);
end

endmodule

`endif
