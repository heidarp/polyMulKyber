---
title: "Qryptic Polynomial Multiplier"
---

# Suggested email — delete this section before attaching

**Subject:** Polynomial-multiplier IP for ML-KEM, configurable for other algorithms

Qryptic Inc. has a streaming polynomial-multiplier core aimed at CRYSTALS-Kyber / ML-KEM. Degree, modulus, and throughput are settings, so a version can be built for the algorithm and the device you are using. The attached note describes the core, the Artix-7 measurements for the Kyber configuration, and what we can change. If this is relevant, reply with the algorithm (or the degree and modulus), the target device, and the multiplications per second you need.

---

# Qryptic Polynomial Multiplier

**Qryptic Inc.**

A streaming hardware core that multiplies two polynomials. The measured build is CRYSTALS-Kyber / ML-KEM. Degree, modulus, and speed are settings, so the same core can be built for another algorithm.

## What it does

Coefficients stream in. The core transforms them, multiplies the pair, inverse-transforms the product, applies the final scale, and streams the result out.

For ML-KEM the arithmetic follows the FIPS 203 transform: a forward number-theoretic transform, a pairwise multiply, an inverse transform, and a final scale. One Kyber build covers ML-KEM-512, ML-KEM-768, and ML-KEM-1024, because those three security levels share one polynomial ring. This describes the arithmetic. It is not a certification claim.

The second polynomial can be transformed inside the core, or it can arrive already transformed. The second choice is the usual one when a public matrix has been transformed ahead of time.

## Speed is a setting

Parallelism is the throughput-versus-area choice. A build with fewer butterflies uses fewer lookup tables, flip-flops, and DSP blocks, and it completes fewer multiplications per second. A wider build does the opposite. The four measured settings are 1, 2, 4, and 8 butterflies.

## Why the area stays modest

Each transform stage starts as soon as the coefficients it needs are ready. A stage does not wait until the previous stage has finished the whole polynomial. Alignment storage is local to each stage and shrinks as the transform proceeds, so the core does not hold a second copy of the polynomial between stages.

The measured builds use no block RAM. Twiddle factors are computed as the data moves, so there is no twiddle table in memory. The transform schedule emits coefficients in the order the multiply needs, with no separate bit-reversal step. Because the core does not depend on FPGA block RAM, an ASIC port does not have to replace a memory compiler block.

The consumer can stall an output beat. While that beat is held, it does not change, and the producer is told to hold its inputs.

## Measured example: Kyber on Artix-7

These figures are for degree 256 and modulus 3329 only, after place-and-route, out of context, on Xilinx Artix-7 `xc7a100tiftg256-1L`. They are not measurements of every degree and modulus.

Block RAM is 0 on every row. "Already transformed" means the second polynomial is supplied in the transform domain. Clocks below are rounded to the nearest megahertz. Multiplications per second use the unrounded post-route clock, divided by the number of beats in one polynomial, for a consumer that accepts every beat.

| Butterflies | Second operand | LUT | Flip-flops | DSP | Clock (MHz) | Multiplications per second |
|---:|---|---:|---:|---:|---:|---:|
| 1 | Transformed in the core | 6,105 | 5,789 | 29 | 152 | 1.18 million |
| 1 | Already transformed | 4,482 | 4,139 | 22 | 155 | 1.21 million |
| 2 | Transformed in the core | 9,966 | 9,764 | 50 | 150 | 2.35 million |
| 2 | Already transformed | 7,210 | 6,806 | 36 | 152 | 2.38 million |
| 4 | Transformed in the core | 18,334 | 18,093 | 100 | 145 | 4.54 million |
| 4 | Already transformed | 13,320 | 12,668 | 72 | 148 | 4.63 million |
| 8 | Transformed in the core | 34,490 | 34,434 | 200 | 142 | 8.85 million |
| 8 | Already transformed | 25,196 | 24,142 | 144 | 143 | 8.93 million |

## Checked against an independent multiplier

The Kyber configuration was compared with an independent schoolbook multiplier in the same ring, including random polynomials, stalls, and reset. Those checks were repeated across the speed settings and both treatments of the second operand, and code coverage was collected on that regression.

## A version for your algorithm

Tell us the degree and the modulus, or the algorithm that fixes them. Tell us the multiplications per second you need and the device you are targeting: an FPGA family or an ASIC. We will set the butterfly width to that throughput, and we can supply the second polynomial already transformed or transform both inside the core. A bus wrapper can be added around the streaming interface.

**Contact:** [email]

Qryptic Inc.
