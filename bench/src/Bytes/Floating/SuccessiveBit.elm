module Bytes.Floating.SuccessiveBit exposing (decode, encode)

{-| Float16 via successive bit construction (ADC-style).
Builds the 16-bit result one bit at a time from MSB to LSB,
using decode as a threshold oracle at each step.

This is equivalent to a successive-approximation ADC in hardware.
After finding the floor, a final rounding step picks the nearest
representable value.

-}

import Bitwise exposing (and, or, shiftLeftBy, shiftRightBy)


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
        if af >= 65536.0 then
            sign + 0x7C00

        else
            sign + buildBits af 14 0


{-| Build the 15-bit unsigned magnitude one bit at a time.
At each step, tentatively set the current bit and check if the
decoded value is still <= the target. If yes, keep the bit.
-}
buildBits : Float -> Int -> Int -> Int
buildBits target bit acc =
    if bit < 0 then
        -- Round to nearest: compare distance to floor vs ceil
        if acc >= 0x7BFF then
            acc

        else
            let
                valLo =
                    decodeMagnitude acc

                valHi =
                    decodeMagnitude (acc + 1)
            in
            if target - valLo <= valHi - target then
                acc

            else
                acc + 1

    else
        let
            candidate =
                acc |> or (shiftLeftBy bit 1)

            candidateVal =
                decodeMagnitude candidate
        in
        if candidateVal <= target then
            buildBits target (bit - 1) candidate

        else
            buildBits target (bit - 1) acc


{-| Decode a 15-bit unsigned magnitude to its float value.
Used as the threshold oracle during encoding.
-}
decodeMagnitude : Int -> Float
decodeMagnitude bits =
    let
        e =
            bits |> shiftRightBy 10 |> and 0x1F

        m =
            bits |> and 0x03FF
    in
    if e == 0 then
        if m == 0 then
            0.0

        else
            toFloat m * pow2 -24

    else if e == 31 then
        1.0 / 0.0

    else
        (1.0 + toFloat m / 1024.0) * pow2 (e - 15)


decode : Int -> Float
decode bits =
    let
        s =
            if and bits 0x8000 /= 0 then
                -1.0

            else
                1.0

        magnitude =
            and bits 0x7FFF
    in
    if magnitude == 0 then
        s * 0.0

    else if magnitude >= 0x7C00 then
        if magnitude == 0x7C00 then
            s * (1.0 / 0.0)

        else
            0.0 / 0.0

    else
        s * decodeMagnitude magnitude


pow2 : Int -> Float
pow2 n =
    if n >= 0 then
        toFloat (shiftLeftBy n 1)

    else
        1.0 / toFloat (shiftLeftBy -n 1)
