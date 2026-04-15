# Repository Analysis: elm-toulouse/float16

## Overview

**float16** is an Elm package that provides binary encoding and decoding of IEEE 754 half-precision (16-bit) floating-point numbers. It fills a gap in Elm's standard `elm/bytes` library, which only supports `float32` and `float64` out of the box.

- **Author:** KtorZ (Matthias Benkort)
- **License:** MIT
- **Elm version:** 0.19.x
- **Published as:** `elm-toulouse/float16` on the Elm package registry
- **First release:** 2019-04-23

## Repository Structure

```
float16/
  src/
    Bytes/Floating/
      Encode.elm          -- float16 encoder
      Decode.elm          -- float16 decoder
  tests/
    Bytes/Floating/
      EncodeTests.elm     -- unit tests for encoding
      DecodeTests.elm     -- unit tests for decoding
      FloatingTests.elm   -- fuzz/roundtrip tests
  bench/
    src/
      Bench.elm                         -- elm-bench entry points
      Bytes/Floating/
        Old.elm                         -- copy of the old implementation (for benchmarking)
        EncodeByDecode.elm              -- binary search approach
        PureArithmetic.elm              -- frexp decomposition (= current default)
        Float64.elm                     -- float64 bit reinterpretation
        SuccessiveBit.elm               -- ADC-style bit construction
        ScaleFloor.elm                  -- scale to integer range
        LookupTable.elm                 -- precomputed Array tables
    tests/
      VariantsTest.elm                  -- equivalence tests (236 tests)
    REPORT.md                           -- comparative report
  scripts/
    deploy               -- tag + publish script
  .travis.yml            -- CI configuration
  elm.json               -- package manifest
  CHANGELOG.md
  README.md
  LICENSE
```

## Dependencies

| Dependency | Version Constraint | Purpose |
|---|---|---|
| `elm/core` | 1.0.2 <= v < 2.0.0 | Standard library |
| `elm/bytes` | 1.0.8 <= v < 2.0.0 | Binary encoding/decoding primitives |
| `elm-explorations/test` | 2.0.0 <= v < 3.0.0 | Test framework (test-only) |

## Architecture & Implementation

### Half-precision float layout

```
       exponent
              |        mantissa
    sign      |               |
       |      |               |
       |      |               |
       | /---------\/-------------------\
       *  * * * * *  * * * * * * * * * *  (16-bit)
```

| Exponent (e) | Mantissa (m) | Value |
|---|---|---|
| e in [1..30] | any | (-1)^s * 2^(e-15) * (1 + m/1024) |
| e == 0 | m != 0 | (-1)^s * 2^(-14) * (m/1024) |
| e == 0 | m == 0 | +/- 0.0 |
| e == 31 | m == 0 | +/- Infinity |
| e == 31 | m != 0 | NaN |

Representable range: ~5.96e-8 (smallest subnormal) to 65504 (largest finite).

### Encoding (`Bytes.Floating.Encode`)

The encoder converts an Elm `Float` to a 16-bit IEEE 754 half-precision representation in 2 bytes.

**Pipeline:** `Float -> pure arithmetic (frexp + round) -> Int (uint16) -> Encoder`

The implementation uses a `frexp`-style decomposition to find the exponent and mantissa:

1. **Special cases** -- NaN, Infinity, and zero are handled first with explicit checks. NaN is encoded as canonical quiet NaN (`0x7E00`, mantissa MSB set). Negative zero is detected via `1.0 / f < 0` (division by `-0.0` yields `-Infinity`).

2. **`frexp` decomposition** -- For finite non-zero values, the absolute value is decomposed into `(mantissa, exponent)` where `mantissa` is in `[1.0, 2.0)` and `value = mantissa * 2^exponent`. This is done by iteratively halving (if >= 2.0) or doubling (if < 1.0), tracking the exponent. These operations are exact in IEEE 754 (they only adjust the float64 exponent field).

3. **Quantization** -- The fractional mantissa is quantized to 10 bits: `m = round((mantissa - 1.0) * 1024.0)`. If rounding pushes `m` to 1024, the exponent is bumped.

4. **Subnormals** -- Values with biased exponent in [-9, 0] are encoded as subnormals: `m = round(|f| * 2^24)`. Values below this range underflow to zero.

5. **Assembly** -- The final uint16 is `sign | (biased_exponent << 10) | mantissa`, passed to `E.unsignedInt16`.

No intermediate `Bytes` allocation occurs during the conversion -- only the final `E.unsignedInt16` produces bytes.

### Decoding (`Bytes.Floating.Decode`)

The decoder converts 2 bytes back into an Elm `Float`.

**Pipeline:** `Decoder (unsignedInt16) -> Int -> pure arithmetic -> Float`

The uint16 is decoded via `D.unsignedInt16`, then the three fields are extracted by bit masking:

- **Sign:** bit 15 -> multiplier +1.0 or -1.0
- **Exponent:** bits 14..10 (5 bits, biased by 15)
- **Mantissa:** bits 9..0 (10 bits)

The float value is reconstructed from the IEEE 754 formula:

- **Normal:** `sign * (1.0 + m/1024.0) * 2^(e-15)`
- **Subnormal:** `sign * m * 2^(-24)` (equivalent to `sign * (m/1024) * 2^(-14)`)
- **Zero:** `sign * 0.0` (preserves sign)
- **Infinity:** `sign * (1.0 / 0.0)`
- **NaN:** `0.0 / 0.0`

The conversion is exact: every float16 value is exactly representable in float64. No intermediate `Bytes` allocation occurs.

### Endianness

Both `float16` encoder and decoder accept an `Endianness` parameter (`BE` or `LE`), which is passed directly to the underlying `unsignedInt16` encoder/decoder. The conversion logic itself is endianness-agnostic.

### Previous implementation (v1.x)

The v1.x implementation used a different approach: **float32 bit-reinterpretation**. The encoder round-tripped through `Bytes.Encode.float32` and `Bytes.Decode.unsignedInt32` to extract the raw 32-bit IEEE 754 representation, then used bit manipulation to map it to float16. The decoder did the inverse. This approach required two `Bytes` allocations per conversion (one for bit extraction, one for output), which dominated the runtime at ~200-300 ns per operation.

The v2.0 rewrite uses pure arithmetic, reducing encode time by 58% and decode time by 83%. A `bench/` directory in the repository contains seven alternative implementations that were evaluated before selecting the pure arithmetic approach. See `bench/REPORT.md` for details.

## Test Coverage

### Unit Tests (EncodeTests, DecodeTests)

Cover the following categories with explicit byte-level assertions:

| Category | Examples |
|---|---|
| Zero | 0 -> 0x0000 |
| Normal positive | 1.0, 1.5, 12.375, 82.125 |
| Normal negative | -0.25 |
| Negative zero | -0.0 -> 0x8000 |
| Near-one values | 1.001, 0.99951 |
| Maximum representable | 65504 |
| Subnormal | 0.000061035, 0.000000059605 |
| Subnormal underflow | 0.000000001 -> 0x0000 |
| Overflow to infinity | 12547414 -> +Inf |
| Positive infinity | 1/0 -> 0x7C00 |
| Negative infinity | -1/0 -> 0xFC00 |
| NaN | 0/0 -> 0x7E00 (canonical quiet NaN) |
| Endianness | LE test for 82.125 |

### Fuzz Tests (FloatingTests)

A property-based roundtrip test: for any normalized half-float value (represented as a `uint16` in the valid normal ranges), encoding and decoding should produce the original value. The test fuzzes over integer ranges `[1024, 31744]` (positive normals) and `[33792, 64513]` (negative normals), deliberately excluding subnormals and special values where precision loss is expected.

## CI/CD

**Travis CI** with two stages:

1. **Build** -- `elm-format --validate` for code style, `elm make --optimize` for compilation
2. **Test** -- `elm-coverage` with Codecov integration for code coverage reporting

The `scripts/deploy` script handles publishing: verifies clean working tree, compiles, extracts version from `elm.json`, creates a git tag, and runs `elm publish`.

## Observations

### Strengths

- **Pure Elm implementation** -- No kernel code or native JS. The core conversion uses only arithmetic operations (multiplication, division, comparison, rounding).
- **Fast** -- Pure arithmetic avoids the `Bytes` allocation overhead of the previous bit-reinterpretation approach. Encode and decode each take ~6 ns for the core conversion.
- **Correct IEEE 754 handling** -- All edge cases (subnormals, infinities, NaN, rounding, overflow, underflow) are handled.
- **Comprehensive tests** -- Unit tests with known values, fuzz tests for roundtrip correctness, and a `bench/` directory with 236 equivalence tests across 7 implementation variants.
- **Minimal and focused** -- The package does one thing well with no unnecessary abstractions.
- **Clean API** -- Mirrors `elm/bytes` conventions (`float16 : Endianness -> ...`), making it a natural extension.

### Potential Concerns

- **Stale CI** -- Travis CI is used, which has been effectively deprecated for open-source projects since 2020. A migration to GitHub Actions would be appropriate.
- **Rounding is round-half-up** -- The encoder uses Elm's `round` function (JavaScript's `Math.round`), which rounds half-up rather than IEEE 754's default roundTiesToEven. This differs at exact midpoints between consecutive float16 values (15,872 values out of the continuous float range). The error is always exactly 1 ULP. See `bench/REPORT.md` for detailed analysis.
- **NaN sign is not preserved** -- The pure arithmetic approach cannot determine the sign of a NaN value (all comparisons with NaN return False in IEEE 754). NaN is always encoded as positive quiet NaN (0x7E00). This is arguably better than the old behavior (0x7C01, which was a signaling NaN).

### Relevance to elm-cardano

This repository lives under the `elm-cardano` GitHub organization, suggesting it's used for Cardano blockchain-related Elm projects. CBOR (Concise Binary Object Representation), which is central to Cardano's data serialization, includes a float16 type (IEEE 754 half-precision) in its specification. This package provides the float16 support needed for CBOR encoding/decoding in Elm-based Cardano tools.
