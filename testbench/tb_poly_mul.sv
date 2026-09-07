`timescale 1ns / 1ps

import ntt_pkg::*;

module tb_poly_mul;

parameter CLK_PERIOD = 10;

logic clk;
logic reset_n;

poly_type x_in;
poly_type y_in;
poly_type c_out;

typedef logic [POLYNOMIAL_LENGTH-1:0][MODULUS_WIDTH-1:0] polynomial_t;

`ifndef NUM_POLY
parameter int num_poly_test = 2;
`else
parameter int num_poly_test = `NUM_POLY;
`endif

typedef polynomial_t poly_bank_t [0:num_poly_test-1];

localparam int MEM_TEST_LENGTH = POLYNOMIAL_LENGTH * num_poly_test;

logic [MODULUS_WIDTH-1:0] xram [0:MEM_TEST_LENGTH-1];
logic [MODULUS_WIDTH-1:0] yram [0:MEM_TEST_LENGTH-1];

task automatic load_decimal_mem(
    input  string                       filename,
    output logic [MODULUS_WIDTH-1:0]  mem    [0:MEM_TEST_LENGTH-1]
);
    int fd;
    int idx;
    int val;

    fd = $fopen(filename, "r");
    if (fd == 0) begin
        $fatal(1, "[TB] Failed to open %s", filename);
    end

    idx = 0;
    while (!$feof(fd) && idx < MEM_TEST_LENGTH) begin
        if ($fscanf(fd, "%d", val) == 1) begin
            mem[idx] = val[MODULUS_WIDTH-1:0];
            idx++;
        end
    end
    $fclose(fd);

    if (idx < MEM_TEST_LENGTH) begin
        $fatal(1, "[TB] Expected %0d decimal values in %s, read %0d",
               MEM_TEST_LENGTH, filename, idx);
    end
endtask

initial begin
    load_decimal_mem("mem_files/x.txt", xram);
    load_decimal_mem("mem_files/y.txt", yram);
end

function automatic poly_bank_t load_poly_bank_from_mem(
    input logic [MODULUS_WIDTH-1:0] mem [0:MEM_TEST_LENGTH-1],
    input int n
);
    poly_bank_t polys_ret;
    for (int i = 0; i < n && i < num_poly_test; i++) begin
        for (int j = 0; j < POLYNOMIAL_LENGTH; j++) begin
            polys_ret[i][j] = mem[i * POLYNOMIAL_LENGTH + j];
        end
    end
    return polys_ret;
endfunction

poly_mul u_poly_mul (x_in, y_in, c_out, clk, reset_n);

integer addr_a;
integer addr_b;

poly_bank_t rndPolyBankX;
poly_bank_t rndPolyBankY;

polynomial_t testPolyX;
polynomial_t testPolyY;

integer testPolyIndex;
integer wait_counter;

int wait_constants[0:num_poly_test-1];

function automatic void generate_wait_constants(
    input int num_tests,
    input int maxWaitConstant,
    input int minWaitConstant
);
    for (int i = 0; i < num_tests; i++) begin
        wait_constants[i] = $urandom_range(maxWaitConstant, minWaitConstant);
    end
endfunction

`ifndef WAIT_MAX
int maxWaitConstant = 3;
`else
int maxWaitConstant = `WAIT_MAX;
`endif
`ifndef WAIT_MIN
int minWaitConstant = 0;
`else
int minWaitConstant = `WAIT_MIN;
`endif

task automatic drive_poly_chunk(
    input polynomial_t poly,
    ref poly_type      poly_if
);
    poly_if.valid = 1'b1;
    for (int i = 0; i < NUM_COEFS_PER_STAGE/2; i++) begin
        poly_if.coefs[2*i]     = poly[addr_a + i];
        poly_if.coefs[2*i + 1] = poly[addr_b + i];
    end
endtask

initial begin
    reset_n = 0;
    #50
    reset_n = 0;
    #100
    reset_n = 1;
end

initial begin
    rndPolyBankX = load_poly_bank_from_mem(xram, num_poly_test);
    rndPolyBankY = load_poly_bank_from_mem(yram, num_poly_test);
    clk = 1'b0;
    wait_counter = '0;
    testPolyIndex = '0;
    addr_a = 0;
    addr_b = POLYNOMIAL_LENGTH/2;
    testPolyX = rndPolyBankX[testPolyIndex];
    testPolyY = rndPolyBankY[testPolyIndex];
    generate_wait_constants(num_poly_test, maxWaitConstant, minWaitConstant);

    forever begin
        #10 clk = !clk;

        if (reset_n == 0) begin
            x_in.valid = '0;
            x_in.coefs = '0;
            y_in.valid = '0;
            y_in.coefs = '0;
        end else if (clk == 1'b0) begin
            if (testPolyIndex < num_poly_test) begin
                if (addr_a < POLYNOMIAL_LENGTH/2) begin
                    drive_poly_chunk(testPolyX, x_in);
                    drive_poly_chunk(testPolyY, y_in);
                    addr_a = addr_a + NUM_COEFS_PER_STAGE/2;
                    addr_b = addr_b + NUM_COEFS_PER_STAGE/2;
                end else if (testPolyIndex < num_poly_test - 1) begin
                    if (wait_counter < wait_constants[testPolyIndex]) begin
                        x_in.valid = '0;
                        x_in.coefs = '0;
                        y_in.valid = '0;
                        y_in.coefs = '0;
                        wait_counter = wait_counter + 1;
                    end else begin
                        wait_counter = '0;
                        testPolyIndex = testPolyIndex + 1;
                        testPolyX = rndPolyBankX[testPolyIndex];
                        testPolyY = rndPolyBankY[testPolyIndex];
                        addr_a = 0;
                        addr_b = POLYNOMIAL_LENGTH/2;
                        drive_poly_chunk(testPolyX, x_in);
                        drive_poly_chunk(testPolyY, y_in);
                        addr_a = addr_a + NUM_COEFS_PER_STAGE/2;
                        addr_b = addr_b + NUM_COEFS_PER_STAGE/2;
                    end
                end else begin
                    x_in.valid = '0;
                    x_in.coefs = '0;
                    y_in.valid = '0;
                    y_in.coefs = '0;
                end
            end else begin
                x_in.valid = '0;
                x_in.coefs = '0;
                y_in.valid = '0;
                y_in.coefs = '0;
            end
        end
    end
end

localparam time SIM_RUN_TIME = 5ms;

initial begin
    $display("[TB] poly_mul stimulus started at %0t ns", $time);
    $display("[TB] Driving %0d polynomial pairs (x, y) from mem_files/x.txt and y.txt", num_poly_test);
    #(SIM_RUN_TIME);
    $display("[TB] Simulation finished at %0t ns", $time);
    $finish;
end

initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_poly_mul);
end

endmodule
