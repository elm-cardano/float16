module Bytes.Floating.PureArithmetic exposing (decode, encode)

{-| Float16 via pure arithmetic: no bit reinterpretation at all.
Uses frexp-style decomposition to find exponent and mantissa,
then quantizes to float16 precision.
-}

import Bitwise exposing (and, shiftLeftBy, shiftRightBy)


encode : Float -> Int
encode f =
    if isNaN f then
        0x7E00

    else if isInfinite f then
        if f > 0 then
            0x7C00

        else
            0xFC00

    else if f == 0 then
        if 1.0 / f < 0 then
            0x8000

        else
            0x0000

    else
        let
            sign =
                if f < 0 then
                    0x8000

                else
                    0

            af =
                abs f

            ( mantissa, exponent ) =
                frexp af

            biased =
                exponent + 15
        in
        if biased >= 31 then
            -- Overflow to infinity
            sign + 0x7C00

        else if biased >= 1 then
            -- Normal number
            let
                m =
                    round ((mantissa - 1.0) * 1024.0)
            in
            if m >= 1024 then
                -- Mantissa rounded up past 1024, bump exponent
                if biased + 1 >= 31 then
                    sign + 0x7C00

                else
                    sign + ((biased + 1) |> shiftLeftBy 10)

            else
                sign + (biased |> shiftLeftBy 10) + m

        else if biased >= -9 then
            -- Subnormal: value = m/1024 * 2^(-14), so m = value * 2^24
            let
                m =
                    round (af * pow2 24)
            in
            if m >= 1024 then
                -- Rounds up to smallest normal
                sign + (1 |> shiftLeftBy 10)

            else
                sign + m

        else
            -- Underflow to zero
            sign


{-| Decompose a positive float into (mantissa, exponent) where
mantissa is in [1.0, 2.0) and value = mantissa * 2^exponent.
Equivalent to C's frexp but with mantissa in [1,2) instead of [0.5,1).
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


decode : Int -> Float
decode bits =
    let
        s =
            if and bits 0x8000 /= 0 then
                -1.0

            else
                1.0

        e =
            bits |> shiftRightBy 10 |> and 0x1F

        m =
            bits |> and 0x03FF
    in
    if e == 0 then
        if m == 0 then
            s * 0.0

        else
            -- Subnormal: value = m/1024 * 2^(-14) = m * 2^(-24)
            s * toFloat m * pow2 (-24)

    else if e == 31 then
        if m == 0 then
            s * (1.0 / 0.0)

        else
            0.0 / 0.0

    else
        -- Normal: value = (1 + m/1024) * 2^(e-15)
        s * (1.0 + toFloat m / 1024.0) * pow2 (e - 15)


pow2 : Int -> Float
pow2 n =
    if n >= 0 then
        toFloat (shiftLeftBy n 1)

    else
        1.0 / toFloat (shiftLeftBy (-n) 1)
