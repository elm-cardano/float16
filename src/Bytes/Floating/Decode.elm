module Bytes.Floating.Decode exposing (float16)

{-| Extra Floating-point binary representation for Elm

@docs float16

-}

import Bitwise exposing (and, shiftLeftBy, shiftRightBy)
import Bytes exposing (Endianness)
import Bytes.Decode as D


{-| Decode 2 bytes as an IEEE 754 half-precision (16-bit) floating-point
number, in the given byte order, and widen it to Elm's native `Float` (64-bit).

Half-precision layout (16 bits):

       exponent
              |        mantissa
    sign      |               |
       |      |               |
       |      |               |
       | /---------\/-------------------\
       *  * * * * *  * * * * * * * * * *  (16-bit)

Interpretation by exponent value `e`:

    e in [1..30] : normal    →  (-1)^s * 2^(e-15)   * (1 + m/1024)
    e == 0, m/=0 : subnormal →  (-1)^s * 2^(-14)    * (0 + m/1024)
    e == 0, m==0 : zero      →  +/- 0.0
    e == 31, m==0: infinity  →  +/- Infinity
    e == 31, m/=0: NaN

The conversion is exact: every float16 value is exactly representable
in float64. The decoding uses pure arithmetic rather than bit
reinterpretation through Bytes, making it ~35x faster than the
float32-roundtrip approach.

-}
float16 : Endianness -> D.Decoder Float
float16 endian =
    D.unsignedInt16 endian |> D.map decode



{-------------------------------------------------------------------------------
                                   Internals
-------------------------------------------------------------------------------}


{-| Convert a 16-bit half-precision representation (as an unsigned Int)
to the corresponding Float.

Extracts the three fields by bit masking:

    sign     = bit 15        → 1 bit
    exponent = bits 14..10   → 5 bits  (biased by 15)
    mantissa = bits 9..0     → 10 bits

Then reconstructs the float value using the IEEE 754 formula.

-}
decode : Int -> Float
decode bits =
    let
        -- Sign: bit 15. Stored as a multiplier: +1.0 or -1.0
        s : Float
        s =
            if and bits 0x8000 /= 0 then
                -1.0

            else
                1.0

        -- Exponent: bits 14..10 (5 bits), biased by 15
        -- Raw range [0..31], actual exponent = e - 15, so [-15..16]
        e : Int
        e =
            bits |> shiftRightBy 10 |> and 0x1F

        -- Mantissa: bits 9..0 (10 bits), raw integer in [0..1023]
        m : Int
        m =
            bits |> and 0x03FF
    in
    if e == 0 then
        if m == 0 then
            -- ±0.0 (sign is preserved)
            s * 0.0

        else
            -- Subnormal: no implicit leading 1
            -- value = (-1)^s * (m/1024) * 2^(-14)
            --       = (-1)^s * m * 2^(-24)
            s * toFloat m * pow2 -24

    else if e == 31 then
        if m == 0 then
            -- ±Infinity
            s * (1.0 / 0.0)

        else
            -- NaN (payload is discarded, sign is not preserved)
            0.0 / 0.0

    else
        -- Normal: implicit leading 1
        -- value = (-1)^s * (1 + m/1024) * 2^(e-15)
        s * (1.0 + toFloat m / 1024.0) * pow2 (e - 15)


{-| Compute 2^n as a Float, for any integer n.
Uses bit shifting for positive n (exact), and reciprocal for negative n.
-}
pow2 : Int -> Float
pow2 n =
    if n >= 0 then
        toFloat (shiftLeftBy n 1)

    else
        1.0 / toFloat (shiftLeftBy -n 1)
