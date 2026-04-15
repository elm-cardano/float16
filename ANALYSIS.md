# Repository Analysis: elm-toulouse/float16

## Overview

**float16** is an Elm package (v1.0.1) that provides binary encoding and decoding of IEEE 754 half-precision (16-bit) floating-point numbers. It fills a gap in Elm's standard `elm/bytes` library, which only supports `float32` and `float64` out of the box.

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
  scripts/
    deploy               -- tag + publish script
  .travis.yml            -- CI configuration
  elm.json               -- package manifest
  CHANGELOG.md
  README.md
  LICENSE
```

The codebase is minimal and focused: **2 source files** and **3 test files**, with no unnecessary abstractions.

## Dependencies

| Dependency | Version Constraint | Purpose |
|---|---|---|
| `elm/core` | 1.0.2 <= v < 2.0.0 | Standard library |
| `elm/bytes` | 1.0.8 <= v < 2.0.0 | Binary encoding/decoding primitives |
| `elm-explorations/test` | 1.2.1 <= v < 2.0.0 | Test framework (test-only) |
| `elm/random` | 1.0.0 <= v < 2.0.0 | Random generators for fuzz tests (test-only) |

## Architecture & Implementation

### Encoding (`Bytes.Floating.Encode`)

The encoder converts an Elm `Float` to a 16-bit IEEE 754 half-precision representation in 2 bytes.

**Pipeline:** `Float -> unsignedInt32 (via float32 reinterpretation) -> floatToHalf (bit manipulation) -> unsignedInt16`

Key implementation details:

1. **`toUnsignedInt32`** -- Reinterprets a `Float` as its raw 32-bit unsigned integer bit pattern by round-tripping through `Bytes.Encode.float32` and `Bytes.Decode.unsignedInt32`. This is the clever trick that avoids needing kernel code or native FFI.

2. **`floatToHalf`** -- The core conversion function. Extracts sign (s), exponent (e), and mantissa (m) from the 32-bit representation and maps them to 16-bit equivalents. Handles all IEEE 754 edge cases:
   - Subnormal underflow (e == 0)
   - Infinity and NaN (e == 255)
   - Overflow to infinity (half-exponent >= 31)
   - Subnormal range (half-exponent in [-10, 0])
   - Normal numbers

3. **Rounding** -- Implements a simple rounding mechanism (`NoRounding` / `RoundUp`) based on the truncated bit, which can propagate overflow naturally via integer addition.

### Decoding (`Bytes.Floating.Decode`)

The decoder converts 2 bytes back into an Elm `Float`.

**Pipeline:** `unsignedInt16 -> halfToFloat (bit manipulation) -> fromUnsignedInt32 (via float32 reinterpretation) -> Float`

Key implementation details:

1. **`halfToFloat`** -- Extracts sign, exponent, and mantissa from the 16-bit integer and maps them to 32-bit IEEE 754 representation. Handles:
   - Zero (e == 0, m == 0)
   - Subnormal numbers (e == 0, m != 0) -- requires renormalization
   - Infinity and NaN (e == 31)
   - Normal numbers (exponent bias adjustment: +112, i.e. 127 - 15)

2. **`renormalize`** -- Recursively shifts the mantissa left until the implicit leading 1 is found, adjusting the exponent accordingly. This converts a subnormal half-float into a normalized single-precision float.

3. **`fromUnsignedInt32`** -- The inverse of `toUnsignedInt32`: reinterprets a raw 32-bit integer as a `Float` by round-tripping through `Bytes.Encode.unsignedInt32` and `Bytes.Decode.float32`.

### Endianness

Both `float16` encoder and decoder accept an `Endianness` parameter (`BE` or `LE`), which is passed directly to the underlying `unsignedInt16` encoder/decoder. The bit-manipulation logic itself is endianness-agnostic.

## Test Coverage

### Unit Tests (EncodeTests, DecodeTests)

Cover the following categories with explicit byte-level assertions:

| Category | Examples |
|---|---|
| Normal positive | 1.0, 1.5, 12.375, 82.125 |
| Normal negative | -0.25 |
| Negative zero | -0.0 |
| Near-one values | 1.001, 0.99951 |
| Maximum representable | 65504 |
| Subnormal | 0.000061035, 0.000000059605 |
| Subnormal underflow | 0.000000001 -> 0x0000 |
| Overflow to infinity | 12547414 -> +Inf |
| Negative infinity | -1/0 |
| NaN | 0/0 (platform-dependent sign) |
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

- **Pure Elm implementation** -- No kernel code or native JS; achieves float bit reinterpretation via the elegant `float32 encode -> unsignedInt32 decode` round-trip trick.
- **Correct IEEE 754 handling** -- All edge cases (subnormals, infinities, NaN, rounding, overflow) are handled.
- **Comprehensive tests** -- Both unit tests with known values and fuzz tests for roundtrip correctness.
- **Minimal and focused** -- The package does one thing well with no unnecessary abstractions.
- **Clean API** -- Mirrors `elm/bytes` conventions (`float16 : Endianness -> ...`), making it a natural extension.

### Potential Concerns

- **Stale CI** -- Travis CI is used, which has been effectively deprecated for open-source projects since 2020. A migration to GitHub Actions would be appropriate.
- **NaN encoding is platform-dependent** -- The `0/0` test uses `expectOneOf` to handle different NaN sign representations across platforms, which is documented but worth noting.
- **Rounding is basic** -- Only round-to-nearest is partially implemented (checking a single guard bit). Full IEEE 754 "round to nearest, ties to even" would require checking both guard and sticky bits. For most practical purposes this is sufficient.
- **No float16 -> float16 precision loss documentation** -- When encoding, values like `1.001` become `1.0009765625` after the float32-to-float16 truncation. This is inherent to the format but not explicitly documented in the module docs.
- **`renormalize` is recursive** -- Though bounded (max 10 iterations for 10-bit mantissa), it uses recursion rather than a loop. In Elm this is fine since the compiler performs tail-call optimization for this pattern.

### Relevance to elm-cardano

This repository lives under the `elm-cardano` GitHub organization, suggesting it's used for Cardano blockchain-related Elm projects. CBOR (Concise Binary Object Representation), which is central to Cardano's data serialization, includes a float16 type (IEEE 754 half-precision) in its specification. This package likely provides the float16 support needed for CBOR encoding/decoding in Elm-based Cardano tools.
