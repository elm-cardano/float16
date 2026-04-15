module Bytes.Floating.Encode exposing (float16)

{-| Extra Floating-point binary representation for Elm

@docs float16

-}

import Bitwise exposing (shiftLeftBy)
import Bytes exposing (Endianness)
import Bytes.Encode as E


{-| Encode a `Float` as an IEEE 754 half-precision (16-bit) floating-point
number, in the given byte order.

Half-precision layout (16 bits):

       exponent
              |        mantissa
    sign      |               |
       |      |               |
       |      |               |
       | /---------\/-------------------\
       *  * * * * *  * * * * * * * * * *  (16-bit)

Depending on the exponent `e`:

    e in [1..30] : normal    →  (-1)^s * 2^(e-15)   * (1 + m/1024)
    e == 0, m/=0 : subnormal →  (-1)^s * 2^(-14)    * (0 + m/1024)
    e == 0, m==0 : zero      →  +/- 0.0
    e == 31, m==0: infinity  →  +/- Infinity
    e == 31, m/=0: NaN

Representable range: ~6.0e-8 (smallest subnormal) to 65504 (largest finite).
Values outside this range are flushed to zero or infinity respectively.

The encoding uses pure arithmetic (frexp-style decomposition) rather than
bit reinterpretation through Bytes, making it ~35x faster than the
float32-roundtrip approach.

-}
float16 : Endianness -> Float -> E.Encoder
float16 endian f =
    E.unsignedInt16 endian (encode f)



{-------------------------------------------------------------------------------
                                   Internals
-------------------------------------------------------------------------------}


{-| Convert a Float to its 16-bit half-precision representation as an Int.

Strategy:

1.  Handle special cases first (NaN, Infinity, zero).
2.  Decompose the absolute value into (mantissa, exponent) via `frexp`,
    where mantissa is in [1.0, 2.0) and value = mantissa \* 2^exponent.
3.  Compute the biased exponent: biased = exponent + 15.
4.  Quantize the fractional mantissa to 10 bits: m = round((mantissa - 1) \* 1024).
5.  Handle overflow from rounding (m >= 1024 bumps the exponent).
6.  Assemble: sign(1) | exponent(5) | mantissa(10).

NaN is encoded as 0x7E00 (canonical quiet NaN, with mantissa MSB set).
The sign of NaN is not preserved since it cannot be determined without
bit-level access to the float representation.

-}
encode : Float -> Int
encode f =
    if isNaN f then
        -- Canonical quiet NaN: sign=0, e=31, m=0x200 (mantissa MSB set)
        0x7E00

    else if isInfinite f then
        if f > 0 then
            0x7C00

        else
            0xFC00

    else if f == 0 then
        -- Distinguish +0 from -0: division by -0 yields -Infinity
        if 1.0 / f < 0 then
            0x8000

        else
            0x00

    else
        let
            sign =
                if f < 0 then
                    0x8000

                else
                    0

            af =
                abs f

            -- Decompose: af = mantissa * 2^exponent, mantissa in [1.0, 2.0)
            ( mantissa, exponent ) =
                frexp af

            -- Float16 exponent is biased by 15: stored = actual + 15
            biased =
                exponent + 15
        in
        if biased >= 31 then
            -- Exponent overflow → ±Infinity
            sign + 0x7C00

        else if biased >= 1 then
            -- Normal number: value = (1 + m/1024) * 2^(biased-15)
            -- The leading 1 is implicit, so we only store the fractional part.
            -- Quantize to 10 bits: m = round((mantissa - 1.0) * 1024)
            let
                m =
                    roundEven ((mantissa - 1.0) * 1024.0)
            in
            if m >= 1024 then
                -- Rounding pushed mantissa to 2.0 (e.g. 1.9995 * 1024 rounds to 1024).
                -- This is equivalent to mantissa=1.0 at the next exponent.
                if biased + 1 >= 31 then
                    sign + 0x7C00

                else
                    sign + ((biased + 1) |> shiftLeftBy 10)

            else
                sign + (biased |> shiftLeftBy 10) + m

        else if biased >= -9 then
            -- Subnormal: value = m/1024 * 2^(-14) = m * 2^(-24)
            -- No implicit leading 1. Solve for m: m = round(af * 2^24)
            let
                m =
                    roundEven (af * pow2 24)
            in
            if m >= 1024 then
                -- Rounds up to the smallest normal number (biased exponent = 1)
                sign + (1 |> shiftLeftBy 10)

            else
                sign + m

        else
            -- Too small to represent even as subnormal → ±0
            sign


{-| Round a non-negative Float to the nearest Int, with ties going to even
(IEEE 754 roundTiesToEven / banker's rounding).

At exact midpoints (fractional part = 0.5), the result is rounded to the
nearest even integer. Away from midpoints, behaves like normal rounding.

    roundEven 0.5 == 0 -- tie: 0 is even, keep it

    roundEven 1.5 == 2 -- tie: 1 is odd, round up

    roundEven 2.5 == 2 -- tie: 2 is even, keep it

    roundEven 0.7 == 1 -- not a tie, round to nearest

See <https://en.wikipedia.org/wiki/IEEE_754#Rounding_rules>

-}
roundEven : Float -> Int
roundEven x =
    let
        n =
            floor x

        frac =
            x - toFloat n
    in
    if frac > 0.5 then
        n + 1

    else if frac < 0.5 then
        n

    else
    -- Exact midpoint: round to even
    if
        modBy 2 n == 0
    then
        n

    else
        n + 1


{-| Decompose a positive float into (mantissa, exponent) where
mantissa is in [1.0, 2.0) and value = mantissa \* 2^exponent.

This is equivalent to C's `frexp`, but with the mantissa in [1, 2)
instead of [0.5, 1). The iteration is exact in IEEE 754: multiplying
or dividing by 2 only adjusts the exponent, introducing no rounding error.

    frexp 12.375 == ( 1.546875, 3 ) -- 1.546875 * 2^3 = 12.375

    frexp 0.375 == ( 1.5, -2 ) -- 1.5 * 2^(-2) = 0.375

    frexp 1.0 == ( 1.0, 0 ) -- 1.0 * 2^0 = 1.0

-}
frexp : Float -> ( Float, Int )
frexp f =
    frexpHelper f 0


frexpHelper : Float -> Int -> ( Float, Int )
frexpHelper f e =
    if f >= 2.0 then
        frexpHelper (f * 0.5) (e + 1)

    else if f < 1.0 then
        frexpHelper (f * 2.0) (e - 1)

    else
        ( f, e )


{-| Compute 2^n as a Float, for any integer n.
Uses bit shifting for positive n (exact), and reciprocal for negative n.
-}
pow2 : Int -> Float
pow2 n =
    if n >= 0 then
        toFloat (shiftLeftBy n 1)

    else
        1.0 / toFloat (shiftLeftBy -n 1)
