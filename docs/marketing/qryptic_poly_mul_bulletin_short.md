---
title: "Qryptic Polynomial Multiplier"
---

# Qryptic Polynomial Multiplier

**Qryptic Inc.** · **Contact:** [email]

Streaming polynomial multiplier. The measured configuration is CRYSTALS-Kyber / ML-KEM at degree 256 and modulus 3329, the ring shared by ML-KEM-512, ML-KEM-768, and ML-KEM-1024. Degree, modulus, and butterfly count are settings, so a version can be built for another algorithm and for a chosen throughput.

Coefficients stream in, then through a forward number-theoretic transform, a pairwise multiply, an inverse transform, and a final scale. On this Kyber build that sequence is the FIPS 203 transform; the core is not a certified implementation. The second polynomial is either transformed in the core or supplied already transformed, as with a public matrix prepared ahead of time.

Butterfly counts of 1, 2, 4, and 8 trade lookup tables, flip-flops, and DSP blocks for multiplications per second. Each stage starts as soon as the coefficients it needs are ready, and keeps only that stage’s alignment storage. Measured builds use no block RAM. Twiddle factors are computed as the data moves, with no separate bit-reversal step. The same dataflow is what an ASIC port implements. If the consumer stalls, the current output beat stays unchanged and the producer is told to hold its inputs.

The rows below are the small end and the large end after place-and-route, out of context, on Artix-7 `xc7a100tiftg256-1L`. Block RAM is 0. Clocks are rounded to the nearest megahertz. The rate uses the unrounded post-route clock divided by the beats in one polynomial, when the consumer accepts every beat. Widths of 2 and 4 butterflies, and the already-transformed second operand at the wider settings, fall between these rows in area and in rate.

| Butterflies | Second operand | LUT | Flip-flops | DSP | Clock (MHz) | Multiplications per second |
|---:|---|---:|---:|---:|---:|---:|
| 1 | Already transformed | 4,482 | 4,139 | 22 | 155 | 1.21 million |
| 1 | Transformed in the core | 6,105 | 5,789 | 29 | 152 | 1.18 million |
| 8 | Transformed in the core | 34,490 | 34,434 | 200 | 142 | 8.85 million |

The Kyber configuration was compared with an independent schoolbook multiplier in the same ring, including random polynomials, stalls, and reset, across every butterfly setting and both treatments of the second operand. Code coverage was collected on that regression.

Reply with the algorithm or the degree and modulus, the multiplications per second you need, the FPGA or ASIC target, and whether the second polynomial is already transformed. A bus wrapper can be added on the streaming interface.
