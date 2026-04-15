module Bytes.Floating.ScaleFloor exposing (decode, encode)

{-| Float16 via scale-and-round: multiply the float by a power of 2
so that the mantissa bits land in the integer part, then use round
to extract them.

Key insight: if value = 1.mmmmmmmmmm \* 2^e, then
value \* 2^(10-e) = 1mmmmmmmmmm.0 — an integer whose lower 10 bits
are the mantissa.

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
        in
        encodeMagnitude sign af


encodeMagnitude : Int -> Float -> Int
encodeMagnitude sign af =
    let
        ( biased, scaled ) =
            scaleToRange af 15
    in
    if biased >= 31 then
        -- Overflow to infinity
        sign + 0x7C00

    else if biased >= 1 then
        -- Normal: scaled is in [1024, 2048)
        let
            intVal =
                round scaled

            m =
                intVal - 1024
        in
        if m >= 1024 then
            -- Mantissa overflow from rounding, bump exponent
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


{-| Scale a positive float so that it falls in [1024, 2048), tracking
the float16 biased exponent. The resulting integer encodes the mantissa:
floor(scaled) - 1024 gives the 10-bit mantissa.
-}
scaleToRange : Float -> Int -> ( Int, Float )
scaleToRange f biased =
    let
        scaled =
            f * 1024.0
    in
    if scaled >= 2048.0 then
        scaleToRange (f * 0.5) (biased + 1)

    else if scaled < 1024.0 && f > 0 then
        scaleToRange (f * 2.0) (biased - 1)

    else
        ( biased, scaled )


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
            s * toFloat m * pow2 -24

    else if e == 31 then
        if m == 0 then
            s * (1.0 / 0.0)

        else
            0.0 / 0.0

    else
        s * (1.0 + toFloat m / 1024.0) * pow2 (e - 15)


pow2 : Int -> Float
pow2 n =
    if n >= 0 then
        toFloat (shiftLeftBy n 1)

    else
        1.0 / toFloat (shiftLeftBy -n 1)
