# Float16 Alternative Implementations: Comparative Report

## Overview

This report compares seven implementations of IEEE 754 half-precision (float16)
encoding and decoding in pure Elm. Each variant uses a fundamentally different
strategy. All implementations are tested against the original `elm-toulouse/float16`
encoder/decoder as the reference baseline.

### Reproducing the results

```sh
cd bench
elm-test
```

Expected output:

```
Running 236 tests.

TEST RUN PASSED

Duration: ~120 ms
Passed:   236
Failed:   0
```

All 236 tests pass. This includes:
- 7 variant suites x (17 encode + 1 NaN encode + 14 decode) = 224 equivalence tests
- 4 x 3 = 12 IEEE 754 midpoint rounding tests


## Implementations

### 1. Current (`Bytes.Floating.Current`)

**Strategy:** Exact copy of the original `Bytes.Floating.Encode` and
`Bytes.Floating.Decode` modules, combined into a single module.

**Encode pipeline:**
```
Float -> float32 encode -> unsignedInt32 decode -> bit-shift to float16 -> unsignedInt16
```

Reinterprets a Float as its 32-bit IEEE 754 representation by round-tripping
through `Bytes.Encode.float32` and `Bytes.Decode.unsignedInt32`. Then extracts
sign (1 bit), exponent (8 bits), and mantissa (23 bits) from the 32-bit
representation and maps them to 16-bit equivalents using explicit case analysis
for normal, subnormal, overflow, underflow, infinity, and NaN.

Rounding uses a single guard bit: if bit 12 of the truncated mantissa is 1,
round up.

**Decode pipeline:**
```
unsignedInt16 -> bit-shift to float32 -> unsignedInt32 encode -> float32 decode -> Float
```

The inverse: maps 16-bit sign/exponent/mantissa to 32-bit equivalents, then
reinterprets the 32-bit integer as a Float via the reverse bytes trick.

**Source:** `bench/src/Bytes/Floating/Current.elm`


### 2. EncodeByDecode (`Bytes.Floating.EncodeByDecode`)

**Strategy:** Implement decode first (pure arithmetic), then derive encode by
binary-searching for the uint16 whose decoded value is closest to the input.

**Encode pipeline:**
```
Float -> binary search [0, 0x7BFF] using decodeMagnitude as oracle -> round to nearest
```

The key insight is that decoding is simpler than encoding. The mapping from
uint16 to float is monotonically increasing (for positive values with the same
sign). A binary search over this mapping finds the nearest representable value
in ~15 iterations.

After finding the floor (largest uint16 whose decoded value <= target), a final
rounding step compares the distance to the floor and ceiling candidates:

```elm
if target - valLo <= valHi - target then lo else lo + 1
```

The `<=` means ties (exact midpoints) favor the floor. This produces
round-half-down behavior in magnitude.

**Decode pipeline:**
```
uint16 -> extract sign/exponent/mantissa -> pure arithmetic: sign * (1 + m/1024) * 2^(e-15)
```

No bit reinterpretation; the float is reconstructed from its mathematical
definition. Subnormals use `m * 2^(-24)`. Special values (zero, infinity, NaN)
are handled via explicit checks.

**Source:** `bench/src/Bytes/Floating/EncodeByDecode.elm`


### 3. PureArithmetic (`Bytes.Floating.PureArithmetic`)

**Strategy:** Decompose the float using a `frexp`-style loop (repeated
halving/doubling), then quantize the mantissa to 10 bits. No bit
reinterpretation at any stage.

**Encode pipeline:**
```
Float -> frexp (find mantissa in [1,2) and exponent) -> round((mantissa - 1) * 1024) -> pack
```

The `frexp` helper iterates: multiply by 0.5 if >= 2.0, multiply by 2.0 if
< 1.0, tracking the exponent. This converges in at most ~30 iterations for the
float16 exponent range.

Rounding uses Elm's built-in `round` function (JavaScript's `Math.round`),
which does round-half-up.

Subnormals are handled separately: `m = round(|f| * 2^24)`.

**Decode pipeline:** Same pure arithmetic approach as EncodeByDecode.

**Source:** `bench/src/Bytes/Floating/PureArithmetic.elm`


### 4. Float64 (`Bytes.Floating.Float64`)

**Strategy:** Same bit-reinterpretation trick as Current, but using the 64-bit
float representation instead of 32-bit. Since Elm's `Float` is natively a
float64, this avoids the intermediate float32 precision loss.

**Encode pipeline:**
```
Float -> float64 encode -> 2x unsignedInt32 decode -> extract from high word -> pack
```

The 64-bit representation is read as two 32-bit words. The high word contains
the sign (bit 31), exponent (bits 30-20, 11 bits, bias 1023), and the top 20
bits of the 52-bit mantissa (bits 19-0). For float16, only the top 10 mantissa
bits are needed, plus a guard bit at position 9.

Exponent rebiasing: `e16 = e64 - 1008` (where 1008 = 1023 - 15).

**Decode pipeline:**
```
uint16 -> construct float64 high/low words -> float64 decode -> Float
```

The 16-bit components are mapped to 64-bit equivalents and placed in the high
word, with the low word zeroed. Subnormal renormalization shifts the mantissa
left until the implicit leading 1 is found, adjusting the exponent.

**Source:** `bench/src/Bytes/Floating/Float64.elm`


### 5. SuccessiveBit (`Bytes.Floating.SuccessiveBit`)

**Strategy:** Build the 16-bit result one bit at a time from MSB to LSB, using
decode as a threshold oracle at each step. This is equivalent to a
successive-approximation ADC (analog-to-digital converter) in hardware.

**Encode pipeline:**
```
Float -> for each bit 14..0: set if decodeMagnitude(candidate) <= target -> round to nearest
```

At each of the 15 bit positions, the algorithm tentatively sets the bit, decodes
the candidate value, and keeps the bit only if the decoded value does not exceed
the target. This produces the floor in exactly 15 steps.

A final rounding step (identical to EncodeByDecode's) compares distances:
```elm
if target - valLo <= valHi - target then acc else acc + 1
```

**Note on the initial bug:** The first version of this implementation omitted
the rounding step entirely, producing pure truncation (round-toward-zero). This
caused two test failures for values clearly past the midpoint (0.99951 and
0.000061035). The fix was adding the rounding step above. Truncation is not
"a different valid rounding mode" when the goal is to produce the nearest
representable value -- it is simply incorrect for values closer to the ceiling.

**Decode pipeline:** Same pure arithmetic approach as EncodeByDecode.

**Source:** `bench/src/Bytes/Floating/SuccessiveBit.elm`


### 6. ScaleFloor (`Bytes.Floating.ScaleFloor`)

**Strategy:** Multiply the float by a power of 2 so that the mantissa bits land
in the integer part, then use `round` to extract them.

**Encode pipeline:**
```
Float -> scaleToRange (multiply/divide by 2 until f*1024 is in [1024, 2048)) -> round -> pack
```

The key insight: if `value = 1.mmmmmmmmmm * 2^e`, then `value * 2^(10-e)`
gives an integer `1mmmmmmmmmm` in binary, whose lower 10 bits are the mantissa.

The `scaleToRange` function iterates: halve if `f*1024 >= 2048`, double if
`f*1024 < 1024`, tracking the biased exponent. The result is the scaled value in
`[1024, 2048)`.

Rounding uses `round(scaled)`, then subtracts 1024 to remove the implicit
leading 1. Mantissa overflow (rounds to 1024) bumps the exponent.

**Decode pipeline:** Same pure arithmetic approach as EncodeByDecode.

**Source:** `bench/src/Bytes/Floating/ScaleFloor.elm`


### 7. LookupTable (`Bytes.Floating.LookupTable`)

**Strategy:** Replace all branching logic with precomputed lookup tables indexed
by the upper 9 bits of the float32 representation (sign + 8-bit exponent = 512
entries per table).

**Encode pipeline:**
```
Float -> float32 reinterpret -> table lookups by index -> base + (mantissa|mask) >> shift + roundBit
```

Four `Array` tables (512 entries each, computed at module load time via
`Array.initialize`):

| Table | Purpose |
|---|---|
| `baseTable` | Float16 sign + exponent bits |
| `shiftTable` | Mantissa right-shift amount |
| `orMaskTable` | Implicit-1 mask for subnormals (0x00800000 or 0) |
| `roundShiftTable` | Guard bit position for rounding |

The encoding reduces to four `Array.get` calls, one OR, two shifts, one AND,
and one addition -- no branches except the `isNaN` check (required because the
table can't collapse NaN payloads).

**Note on Elm's Array:** Elm's `Array` is implemented as a relaxed radix
balanced tree (RRB-tree, branching factor 32), not a flat memory array.
`Array.get` returns `Maybe a`, adding pattern-matching overhead. For 512
entries, the tree is 2 levels deep. This means the "branchless" table approach
still involves tree traversal and Maybe unwrapping per lookup -- the performance
characteristics differ significantly from C/C++ lookup tables.

**Decode pipeline:** Same bit-reinterpretation approach as Current (tables are
not beneficial for decoding).

**Source:** `bench/src/Bytes/Floating/LookupTable.elm`


## Equivalence Results

### Encode: 17 test values (non-NaN)

Test values: 0, -0, 1, 1.5, -0.25, 0.375, 1.001, 0.99951, 12.375, 82.125,
65504, 0.000061035, 0.000000059605, 0.000000001, 12547414, +Inf, -Inf.

| Variant | Pass | Fail | Notes |
|---|---|---|---|
| Current | 17/17 | 0 | Exact copy of reference |
| EncodeByDecode | 17/17 | 0 | Search finds correct values |
| PureArithmetic | 17/17 | 0 | `round()` matches guard-bit rounding |
| Float64 | 17/17 | 0 | Same guard-bit logic via 64-bit path |
| SuccessiveBit | 17/17 | 0 | Rounding step matches (after bugfix) |
| ScaleFloor | 17/17 | 0 | `round()` matches guard-bit rounding |
| LookupTable | 17/17 | 0 | Tables reproduce guard-bit logic exactly |

### Encode: NaN

All 7 variants produce a valid float16 NaN (exponent = 31, mantissa != 0).
The exact NaN payload varies between implementations but all are valid.

### Decode: 14 test values (including NaN)

Test values: 0x0000 (+0), 0x0001 (smallest subnormal), 0x0400 (smallest
normal), 0x3BFF (0.9995), 0x3C00 (1.0), 0x3C01 (1.001), 0x3E00 (1.5),
0x4A30 (12.375), 0x7BFF (65504), 0x7C00 (+Inf), 0x8000 (-0), 0xB400 (-0.25),
0xFC00 (-Inf), 0xFC01 (NaN).

| Variant | Pass | Fail | Notes |
|---|---|---|---|
| Current | 14/14 | 0 | Bit reinterpretation via float32 |
| EncodeByDecode | 14/14 | 0 | Pure arithmetic decode |
| PureArithmetic | 14/14 | 0 | Pure arithmetic decode |
| Float64 | 14/14 | 0 | Bit reinterpretation via float64 |
| SuccessiveBit | 14/14 | 0 | Pure arithmetic decode |
| ScaleFloor | 14/14 | 0 | Pure arithmetic decode |
| LookupTable | 14/14 | 0 | Bit reinterpretation via float32 |

All decode implementations produce bit-identical results for all test values.
Float comparison uses byte-level representation (`float64 -> 8 bytes`) to avoid
elm-test's restriction on `Expect.equal` with floats, while correctly handling
-0, infinity, and NaN.


## IEEE 754 Rounding Analysis

### Background

IEEE 754 defines five rounding modes. The default is **roundTiesToEven**
(banker's rounding): when a value falls exactly at the midpoint between two
representable numbers, round to the one whose least significant mantissa bit is
0 (even).

Proper roundTiesToEven requires three pieces of information from the truncated
bits:

- **Guard bit (G):** the first bit beyond the target precision
- **Round bit (R):** the second bit beyond the target precision
- **Sticky bit (S):** the OR of all remaining bits

The decision rule:

```
round_up = G AND (R OR S OR result_LSB)
```

In plain terms: round up if past the midpoint, OR at the exact midpoint with an
odd result. At exact midpoints with an even result, keep the floor.

### What the current implementation does

The current encoder (`src/Bytes/Floating/Encode.elm`, line 117) checks only the
guard bit:

```elm
r =
    case m |> shiftRightBy 12 |> and 1 of
        1 -> RoundUp
        _ -> NoRounding
```

This is **round-half-up**: round up whenever G=1, regardless of R, S, or the
result's parity. This diverges from IEEE 754 at exact midpoints (G=1, R=0, S=0)
where the floor mantissa is even -- IEEE 754 would keep the floor, but the
current code rounds up.

### How often does this matter?

At midpoints between consecutive float16 values with the same exponent, the
float32 representation has G=1, R=0, S=0 **systematically** (the midpoint is
always exactly representable in float32). This means:

- For each of the 30 normal exponents (1-30): 512 even-mantissa values exist
  (m = 0, 2, 4, ..., 1022), each with an affected midpoint.
- For subnormals: 512 even-mantissa values (m = 0, 2, 4, ..., 1022).
- **Total: 15,872 affected midpoint values** out of the continuous float range.

The error magnitude is always exactly 1 ULP (unit in the last place) of the
float16 representation. For practical purposes, this rarely matters since
real-world values seldom land exactly on a midpoint. But it is a systematic
deviation from the IEEE 754 standard.

### Test cases demonstrating the issue

Four test cases are included that land exactly on midpoints between consecutive
float16 values where the floor has an even mantissa:

| Input | IEEE 754 correct | Current impl gives | Error |
|---|---|---|---|
| `1.00048828125` (midpoint of 1.0 and 1.0009765625) | `0x3C00` (m=0, even) | `0x3C01` (m=1, odd) | +1 ULP |
| `2.0009765625` (midpoint of 2.0 and 2.001953125) | `0x4000` (m=0, even) | `0x4001` (m=1, odd) | +1 ULP |
| `1.00244140625` (midpoint of 1.001953125 and 1.0029296875) | `0x3C02` (m=2, even) | `0x3C03` (m=3, odd) | +1 ULP |
| `2.98e-8` (midpoint of 0 and smallest subnormal) | `0x0000` (m=0, even) | `0x0001` (m=1, odd) | +1 ULP |

These tests are in `bench/tests/VariantsTest.elm` under the
`"IEEE 754 roundTiesToEven (midpoint, even floor)"` describe block.

To reproduce:

```sh
cd bench
elm-test
```

The tests verify:

1. The current implementation (reference) produces `correctUint16 + 1`
   (rounds up -- incorrect per IEEE 754).
2. EncodeByDecode produces `correctUint16` (keeps floor -- correct).
3. SuccessiveBit produces `correctUint16` (keeps floor -- correct).

### Rounding behavior by variant

| Variant | Rounding method | At midpoint (even floor) | At midpoint (odd floor) | IEEE 754 compliant? |
|---|---|---|---|---|
| **Current** | Guard bit only | Rounds up (wrong) | Rounds up (correct) | No (round-half-up) |
| **LookupTable** | Guard bit via table | Rounds up (wrong) | Rounds up (correct) | No (same as Current) |
| **Float64** | Guard bit (from float64) | Rounds up (wrong) | Rounds up (correct) | No (same logic) |
| **PureArithmetic** | `round()` (JS Math.round) | Rounds up (wrong) | Rounds up (correct) | No (round-half-up) |
| **ScaleFloor** | `round()` (JS Math.round) | Rounds up (wrong) | Rounds up (correct) | No (round-half-up) |
| **EncodeByDecode** | Distance comparison (`<=`) | Keeps floor (correct) | Keeps floor (wrong) | No (round-half-down) |
| **SuccessiveBit** | Distance comparison (`<=`) | Keeps floor (correct) | Keeps floor (wrong) | No (round-half-down) |

**No implementation achieves full IEEE 754 roundTiesToEven compliance.** They
split into two groups:

- **Round-half-up** (Current, LookupTable, Float64, PureArithmetic, ScaleFloor):
  correct when the floor is odd, incorrect when even.
- **Round-half-down** (EncodeByDecode, SuccessiveBit): correct when the floor is
  even, incorrect when odd.

True roundTiesToEven would need to inspect the result mantissa's LSB at the
tie-breaking step. For the bit-manipulation approaches (Current, LookupTable,
Float64), this would mean checking the LSB of the truncated mantissa in addition
to the guard bit. For the search-based approaches (EncodeByDecode, SuccessiveBit),
this would mean replacing `<=` with a tie-breaking comparison that checks the
mantissa parity of both candidates.


## Architecture Comparison

### Dependency on elm/bytes for core logic

| Variant | Needs elm/bytes for encode | Needs elm/bytes for decode |
|---|---|---|
| Current | Yes (float32 reinterpret) | Yes (float32 reinterpret) |
| EncodeByDecode | No (pure arithmetic) | No (pure arithmetic) |
| PureArithmetic | No (pure arithmetic) | No (pure arithmetic) |
| Float64 | Yes (float64 reinterpret) | Yes (float64 reinterpret) |
| SuccessiveBit | No (pure arithmetic) | No (pure arithmetic) |
| ScaleFloor | No (pure arithmetic) | No (pure arithmetic) |
| LookupTable | Yes (float32 reinterpret) | Yes (float32 reinterpret) |

Four of the seven variants (EncodeByDecode, PureArithmetic, SuccessiveBit,
ScaleFloor) require `elm/bytes` only for I/O plumbing (wrapping as
`Encoder`/`Decoder`), not for the core conversion logic. This means the
conversion functions could be used independently of the bytes library.

### Decode approach

| Approach | Used by |
|---|---|
| Bit reinterpretation via float32 | Current, LookupTable |
| Bit reinterpretation via float64 | Float64 |
| Pure arithmetic | EncodeByDecode, PureArithmetic, SuccessiveBit, ScaleFloor |

The pure arithmetic decode computes `sign * (1 + m/1024) * 2^(e-15)` directly.
All operations involve powers of 2 and small integers, so the results are
exact in float64 (no precision loss). This is confirmed by the byte-level
comparison in the tests.

### Encode approach

| Approach | Core operation | Iterations |
|---|---|---|
| Current | Bit extraction + case analysis | 1 (direct) |
| EncodeByDecode | Binary search over decode | ~15 (log2 of search range) |
| PureArithmetic | frexp loop + round | ~15-30 (exponent search) |
| Float64 | Bit extraction from 64-bit repr | 1 (direct) |
| SuccessiveBit | 15 decode calls + 2 (rounding) | 17 (fixed) |
| ScaleFloor | Scale loop + round | ~15-30 (exponent search) |
| LookupTable | 4 table lookups + arithmetic | 1 (direct) |


## File Listing

```
bench/
  elm.json                                  # Application project
  README.md                                 # Quick-start guide
  REPORT.md                                 # This report
  src/
    Bench.elm                               # elm-bench entry points
    Bytes/Floating/
      Current.elm                           # Copy of current implementation
      EncodeByDecode.elm                    # Binary search approach
      PureArithmetic.elm                    # frexp decomposition
      Float64.elm                           # float64 bit reinterpretation
      SuccessiveBit.elm                     # ADC-style bit construction
      ScaleFloor.elm                        # Scale to integer range
      LookupTable.elm                       # Precomputed Array tables
  tests/
    VariantsTest.elm                        # 236 tests
```
