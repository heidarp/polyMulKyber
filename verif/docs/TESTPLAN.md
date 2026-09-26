# poly_mul test plan

DUT is [`rtl/poly_mul.sv`](../../rtl/poly_mul.sv): streamed multiplication in \(Z_{3329}[x]/(x^{256}+1)\).

Each beat carries `2 * NUM_BUTFLY_PER_STAGE` coefficients, taken as pairs from the low and high halves of the polynomial. Seven NTT stages feed a degree-1 basemul, then inverse NTT and a scale by 3303. `downstream_ready` low freezes the pipe. `NTT_ready` tells the producer to hold its inputs.

The scoreboard is the schoolbook product in [`verif/common/ref_model.svh`](../common/ref_model.svh), reduced mod \(x^{256}+1\) and mod 3329. Coefficients are compared in order. The driver and the collector use the same lane map: `coefs[2*i]` is the low half, `coefs[2*i+1]` is the high half.

## Layout

- [`verif/tb/tb_poly_mul_rand.sv`](../tb/tb_poly_mul_rand.sv) — clock, DUT, optional y-bypass NTT
- [`verif/common/harness.svh`](../common/harness.svh) — drive, stall, collect, compare
- [`verif/tests/test_<name>.sv`](../tests) — one scenario per file

`NUM_BUTFLY_PER_STAGE` outside `{1, 2, 4, 8}` is not a supported build.

## Tests

| Test | File | What it checks |
| --- | --- | --- |
| `random` | `test_random.sv` | Several random pairs, one back-to-back and later gaps |
| `long_random` | `test_long_random.sv` | 50 random pairs; idle 0 to 3*256 clocks between them |
| `both_zero` | `test_both_zero.sv` | Zero times zero |
| `one_zero` | `test_one_zero.sv` | A zero operand on either side |
| `unit` | `test_unit.sv` | Multiply by the polynomial 1 |
| `all_qm1` | `test_all_qm1.sv` | Every coefficient is q-1 |
| `single_coeff` | `test_single_coeff.sv` | One hot coefficient, including a wrap through x^256 = -1 |
| `repeat_pair` | `test_repeat_pair.sv` | The same pair twice |
| `commute` | `test_commute.sv` | x\*y and y\*x |
| `ready_tied` | `test_ready_tied.sv` | `downstream_ready` held high; `NTT_ready` stays high |
| `bp_random` | `test_bp_random.sv` | Random ready |
| `stall_first` | `test_stall_first.sv` | Stall the first output beat |
| `stall_last` | `test_stall_last.sv` | Stall the beat that finishes a polynomial |
| `stall_long` | `test_stall_long.sv` | Hold a beat for 64 cycles |
| `gaps` | `test_gaps.sv` | Idle cycles only between polynomials |
| `reset_idle` | `test_reset_idle.sv` | Check a polynomial, reset while idle, check the next one |
| `reset_mid` | `test_reset_mid.sv` | Reset mid-polynomial, then a fresh pair |
| `reset_stall` | `test_reset_stall.sv` | Reset while an output beat is held |

A test passes when every coefficient matches in order, the output count matches, a stalled beat does not change, and `NTT_ready` is low while that beat is stalled.

## Pass and fail reporting

A failed check calls `fail_check` in the harness. That prints one `[TB] CHECK FAIL: <reason>` line and keeps going, so a single run reports every check that failed rather than stopping at the first one.

Each phase of a test ends in a verdict. A phase that compares polynomials ends in `finish_and_check`; one that only checks protocol, such as the reset window, ends in `report_phase`.

Every run ends with one line for the whole test:

```
TEST RESULT: PASS (reset_idle, 2 phase(s))
TEST RESULT: FAIL (reset_idle, 3 failed check(s))
```

A test with no phase at all is reported as `FAIL (no checks ran)`, so a scenario cannot pass by running and checking nothing. `make regression` and `make sanity` grep for `TEST RESULT: PASS`.

## How to run

One test:

```
make test TEST=unit
```

Every scenario, one compile, butterfly width 1, y in the coefficient domain. This is the regression:

```
make regression
```

Coverage for that same elaboration. Merge only runs that share one butterfly width and one y path. A width-1 database and a width-4 database are different designs.

```
make regression_cov
make regression_cov NUM_BUTFLY_PER_STAGE=4
```

`regression_cov` passes width and y-bypass through to the compile when you set them on the command line. The report is `coverage_report/hierarchy.html`.

When the generated RTL matters, this repeats `random` and `bp_random` at widths 1, 2, 4, and 8 and both y paths:

```
make regression_configs
```

`make sanity` and `make sanity_bp` still sweep those builds with the random test. `make lint` stays the SpyGlass check and is not part of the functional regression.

The older stimulus benches (`tb_poly_mul`, `tb_fwd_ntt`) stay in `testbench/`.
