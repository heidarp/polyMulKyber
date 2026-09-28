---
title: "Qryptic Polynomial Multiplier — Datasheet"
---

# Qryptic Polynomial Multiplier

**Datasheet**

**Qryptic Inc.**

**Contact:** [email]

## 1. Description

The Qryptic polynomial multiplier is a streaming hardware core. It multiplies two polynomials with a number-theoretic transform: coefficients stream in, each stage of the transform starts as soon as its operands are ready, the pair is multiplied, the product is inverse-transformed and scaled, and the result streams out.

The build that has been implemented, verified, and measured is CRYSTALS-Kyber / ML-KEM, degree 256, modulus 3329. That ring is shared by ML-KEM-512, ML-KEM-768, and ML-KEM-1024, so one Kyber build serves all three security levels. Degree and modulus are settings. A version can be built for another polynomial degree and another modulus.

## 2. Features

- Streaming multiply of two polynomials, with valid/ready flow control
- Overlapped transform stages: the next stage consumes coefficients as soon as they are ready, so a stage does not wait for a full polynomial
- No block RAM in the measured Kyber builds
- Twiddle factors computed as the data moves, with no twiddle table in memory
- No separate bit-reversal step; the schedule emits coefficients in the order the multiply needs
- Alignment storage local to each stage, shrinking as the transform proceeds
- Butterfly parallelism of 1, 2, 4, or 8 as a throughput-versus-area setting
- Second operand transformed inside the core, or supplied already transformed
- Kyber arithmetic follows the FIPS 203 transform (forward transform, pairwise multiply, inverse transform, final scale). This is a description of the arithmetic, not a certification claim
- Suitable for an FPGA or an ASIC. The core does not depend on FPGA block RAM

## 3. Applications

- ML-KEM key generation, encapsulation, and decapsulation
- Other algorithms whose bottleneck is a number-theoretic-transform polynomial multiply, once degree and modulus are set
- Hardware security modules and FPGA security subsystems
- An ASIC implementation of the same dataflow

## 4. Operation

The datapath is a single stream:

1. Forward transform of the first polynomial. The second polynomial is transformed on a matching path, unless it is already in the transform domain.
2. Pairwise multiplication of the transformed coefficients, including the twiddle that ML-KEM attaches to each pair.
3. Inverse transform.
4. A final scale. For the Kyber modulus this scale is 3303, which is \(128^{-1} \bmod 3329\).

Each stage keeps only the coefficients it still needs in order to form the next butterfly pair. That local storage gets smaller from stage to stage. The stage starts when the first required pair is available, so later stages run while earlier stages are still emitting coefficients.

Twiddle factors are produced in step with the butterflies. Coefficient order is the order the multiply consumes, so a separate bit-reversal permutation is not part of the core.

## 5. Interface

The Kyber build uses 12-bit coefficients, because \(3329\) fits in 12 bits. A different modulus changes that width.

Each beat carries \(2 \times B\) coefficients, where \(B\) is the butterfly setting. Those coefficients are pairs drawn from the low half and the high half of the polynomial: within each pair, the first coefficient is from the low half and the second is from the high half. A degree-256 polynomial therefore occupies \(128 / B\) beats: 128, 64, 32, or 16 beats for \(B = 1, 2, 4, 8\).

| Port | Direction | Role |
|---|---|---|
| `clk` | Input | Clock |
| `reset_n` | Input | Reset, active low |
| `input_poly_x` | Input | First polynomial, streaming. Coefficients plus a valid flag |
| `input_poly_y` | Input | Second polynomial, streaming. Coefficients plus a valid flag |
| `output_poly` | Output | Product, streaming. Coefficients plus a valid flag |
| `downstream_ready` | Input | Consumer accepts the current output beat when high |
| `NTT_ready` | Output | Producer may present a new input beat when high |

Streaming rules:

- While `NTT_ready` is low, hold `input_poly_x` and `input_poly_y`.
- When `output_poly` is valid and `downstream_ready` is low, the held output beat does not change, and the pipeline waits with it.
- When the second polynomial is supplied already transformed, its valid flag must line up with the transformed first polynomial.

## 6. Configuration

| Setting | What it changes |
|---|---|
| Polynomial degree | Number of transform stages, and how many coefficients make one polynomial |
| Modulus | Coefficient width and the modular arithmetic |
| Butterflies (1, 2, 4, or 8) | Coefficients per beat, area, and multiplications per second |
| Second operand | Transformed inside the core, or supplied already transformed |

A wider butterfly setting raises the sustained rate and the lookup-table, flip-flop, and DSP cost together. The Kyber measurements below are the menu for that tradeoff. Other degrees and moduli are built to order; the table does not describe them.

## 7. Kyber implementation results

Device: Xilinx Artix-7 `xc7a100tiftg256-1L`. Flow: place-and-route, out of context. Constraint period: 6.600 ns.

The clock in the table is \(1000 / (6.600 - \mathrm{WNS})\), in MHz, where WNS is the worst setup slack in nanoseconds after routing. A negative slack means that build did not close at 6.600 ns; the listed clock is the resulting estimate. Block RAM is 0 on every build. Distributed memory (LUTRAM) holds the stage-local alignment state.

Multiplications per second equal that clock, in hertz, divided by the number of beats in one polynomial. The figure assumes the consumer accepts every beat.

| Butterflies | Second operand | LUT | Flip-flops | LUTRAM | BRAM | DSP | WNS (ns) | Clock (MHz) | Beats per polynomial | Multiplications per second |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | Transformed in the core | 6,105 | 5,789 | 802 | 0 | 29 | 0.003 | 151.584 | 128 | 1.18 million |
| 1 | Already transformed | 4,482 | 4,139 | 567 | 0 | 22 | 0.138 | 154.751 | 128 | 1.21 million |
| 2 | Transformed in the core | 9,966 | 9,764 | 1,283 | 0 | 50 | −0.053 | 150.308 | 64 | 2.35 million |
| 2 | Already transformed | 7,210 | 6,806 | 916 | 0 | 36 | 0.028 | 152.161 | 64 | 2.38 million |
| 4 | Transformed in the core | 18,334 | 18,093 | 2,255 | 0 | 100 | −0.289 | 145.159 | 32 | 4.54 million |
| 4 | Already transformed | 13,320 | 12,668 | 1,613 | 0 | 72 | −0.149 | 148.170 | 32 | 4.63 million |
| 8 | Transformed in the core | 34,490 | 34,434 | 3,887 | 0 | 200 | −0.464 | 141.563 | 16 | 8.85 million |
| 8 | Already transformed | 25,196 | 24,142 | 2,827 | 0 | 144 | −0.395 | 142.959 | 16 | 8.93 million |

## 8. Verification

The Kyber configuration was checked against an independent schoolbook multiplier in \(Z_{3329}[x]/(x^{256}+1)\). Coefficients were compared in order.

The regression includes:

- Random polynomials, including long runs and back-to-back polynomials
- Edge cases: both operands zero, one operand zero, multiply by the constant 1, every coefficient at the modulus minus one, and a single nonzero coefficient
- The same pair repeated, and both orders of the two operands
- A consumer that is always ready, a consumer that stalls at random, a stall on the first output beat, a stall on the beat that finishes a polynomial, and a beat held for many cycles
- Idle cycles between polynomials
- Reset while idle, reset in the middle of a polynomial, and reset while an output beat is held

A stalled beat must stay unchanged, and the producer-ready flag must stay low for the whole stall. The same checks were run across butterfly settings 1, 2, 4, and 8 and across both treatments of the second operand.

Code coverage was collected on that regression. This datasheet does not quote a coverage percentage.

## 9. Deliverables

A configured drop of the core for the agreed degree, modulus, butterfly width, and second-operand mode, together with the streaming interface in Section 5. An FPGA family port, an ASIC port, or a bus wrapper is scoped with the engagement.

## 10. Next step

Reply with:

- The algorithm, or the polynomial degree and modulus
- Whether the second polynomial is already in the transform domain
- The multiplications per second you need
- The target: FPGA family and device, or ASIC
- The bus or handshake you want around the streaming ports, if any

**Contact:** [email]

Qryptic Inc.
