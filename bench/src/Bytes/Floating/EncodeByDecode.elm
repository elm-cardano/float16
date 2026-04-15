module Bytes.Floating.EncodeByDecode exposing (decode, encode)

{-| Float16 via binary search: implement decode first, then derive
encode by searching for the uint16 whose decoded value is closest.

Only the decode function needs to be correct; encode correctness
follows from the search.
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
        in
        if af >= 65536.0 then
            -- Exponent overflow (float16 can't represent >= 2^16)
            sign + 0x7C00

        else
            sign + searchNearest af


{-| Find the uint16 (unsigned magnitude, 15 bits) whose decoded value
is closest to the target. Uses binary search to find the floor, then
checks if rounding up gives a closer match.
-}
searchNearest : Float -> Int
searchNearest target =
    let
        lo =
            findFloor 0 0x7BFF target
    in
    if lo >= 0x7BFF then
        lo

    else
        let
            valLo =
                decodeMagnitude lo

            valHi =
                decodeMagnitude (lo + 1)
        in
        if target - valLo <= valHi - target then
            lo

        else
            lo + 1


{-| Binary search: find the largest uint16 in [lo, hi] whose decoded
value is <= target.
-}
findFloor : Int -> Int -> Float -> Int
findFloor lo hi target =
    if lo >= hi then
        lo

    else
        let
            mid =
                (lo + hi + 1) // 2

            midVal =
                decodeMagnitude mid
        in
        if midVal <= target then
            findFloor mid hi target

        else
            findFloor lo (mid - 1) target


{-| Decode a 15-bit unsigned magnitude (no sign bit) to its float value.
This is the core building block: encode is derived from this via search.
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
            toFloat m * pow2 (-24)

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
        1.0 / toFloat (shiftLeftBy (-n) 1)
