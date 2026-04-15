![](.github/logo.png)

---

[![](https://img.shields.io/elm-package/v/elm-toulouse/float16.svg?style=for-the-badge)](https://package.elm-lang.org/packages/elm-toulouse/float16/latest/)
[![](https://img.shields.io/travis/elm-toulouse/float16.svg?style=for-the-badge&label=%F0%9F%94%A8%20Build)](https://travis-ci.org/elm-toulouse/float16/builds)
[![](https://img.shields.io/codecov/c/gh/elm-toulouse/float16.svg?color=e84393&label=%E2%98%82%EF%B8%8F%20Coverage&style=for-the-badge)](https://codecov.io/gh/elm-toulouse/float16)
[![](https://img.shields.io/github/license/elm-toulouse/float16.svg?style=for-the-badge&label=%20%F0%9F%93%84%20License)](https://github.com/elm-toulouse/float16/blob/master/LICENSE)

## Getting Started

### Installation

```
elm install elm-toulouse/float16
```

### Usage

```elm
import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as D
import Bytes.Encode as E
import Bytes.Floating.Encode as E

-- ENCODER

encode : Float -> E.Encoder
encode f =
  E.sequence
    [ E.float16 BE f
    , E.float32 BE f
    , E.float64 BE f
    ]

-- DECODER

decode : D.Decoder (Float, Float, Float)
decode =
  D.map3 (\a b c -> (a, b, c))
    |> D.float16 BE
    |> D.float32 BE
    |> D.float64 BE
```

## Repository Structure

```
float16/
  src/Bytes/Floating/
    Encode.elm                  # float16 encoder
    Decode.elm                  # float16 decoder
  tests/Bytes/Floating/
    EncodeTests.elm             # unit tests for encoding
    DecodeTests.elm             # unit tests for decoding
  tests/Bytes/
    FloatingTests.elm           # fuzz/roundtrip tests
  bench/
    src/Bytes/Floating/         # 6 alternative encoder implementations
    tests/VariantsTest.elm      # equivalence tests across all variants (236 tests)
    REPORT.md                   # comparative benchmark report
  review/                       # elm-review configuration
  scripts/deploy                # tag + publish script
```

Development uses [pnpm](https://pnpm.io/):

```sh
pnpm install
pnpm test           # run main test suite
pnpm test:bench     # run bench equivalence tests
pnpm format:check   # check elm-format
pnpm review         # run elm-review
```

## How It Works

### Half-precision float layout (16 bits)

```
       exponent
              |        mantissa
    sign      |               |
       |      |               |
       |      |               |
       | /---------\/-------------------\
       *  * * * * *  * * * * * * * * * *
```

| Exponent (e) | Mantissa (m) | Value                                    |
| ------------ | ------------ | ---------------------------------------- |
| 1..30        | any          | (-1)^s _ 2^(e-15) _ (1 + m/1024)         |
| 0            | m != 0       | (-1)^s _ 2^(-14) _ (m/1024) -- subnormal |
| 0            | 0            | +/- 0.0                                  |
| 31           | 0            | +/- Infinity                             |
| 31           | m != 0       | NaN                                      |

Representable range: ~5.96e-8 (smallest subnormal) to 65504 (largest finite).

### Encoding

The encoder converts a `Float` to a 16-bit representation using pure arithmetic -- no intermediate `Bytes` allocation.

1. **Special cases** -- NaN, Infinity, and zero are handled first. NaN is encoded as canonical quiet NaN (`0x7E00`). Negative zero is detected via `1/f < 0`.
2. **frexp decomposition** -- The absolute value is decomposed into `(mantissa, exponent)` where `mantissa` is in `[1.0, 2.0)`, by iteratively halving or doubling (exact in IEEE 754).
3. **Quantization** -- The fractional mantissa is quantized to 10 bits with [roundTiesToEven](https://en.wikipedia.org/wiki/IEEE_754#Rounding_rules) (banker's rounding). Rounding overflow bumps the exponent.
4. **Subnormals** -- Values too small for normal representation are encoded as `m = roundEven(|f| * 2^24)`. Values below the subnormal range flush to zero.

### Decoding

The decoder reads 2 bytes as a `uint16`, extracts sign/exponent/mantissa by bit masking, and reconstructs the float from the IEEE 754 formula. The conversion is exact: every float16 value is exactly representable in float64.

### Performance

The v2.0 rewrite replaced the v1.x bit-reinterpretation approach (roundtrip through `float32` bytes) with pure arithmetic, yielding **2x faster encode** and **5x faster decode**. The `bench/` directory contains six alternative implementations that were evaluated; see [`bench/REPORT.md`](https://github.com/elm-toulouse/float16/blob/master/bench/REPORT.md) for the full comparison.

## Changelog

[CHANGELOG.md](https://github.com/elm-toulouse/float16/blob/master/CHANGELOG.md)
