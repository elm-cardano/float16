module Bytes.Floating.Float64 exposing (decode, encode)

{-| Float16 via float64 bit reinterpretation.
Same trick as the current implementation but using 64-bit floats
instead of 32-bit, giving direct access to the full-precision bits.
-}

import Bitwise exposing (and, or, shiftLeftBy, shiftRightBy)
import Bytes exposing (Endianness(..))
import Bytes.Decode as D
import Bytes.Encode as E


encode : Float -> Int
encode f =
    if isNaN f then
        let
            { high } =
                toFloat64Bits f

            s =
                high |> shiftRightBy 16 |> and 0x8000
        in
        s |> or 0x7C01

    else
        let
            { high, low } =
                toFloat64Bits f

            s =
                high |> shiftRightBy 16 |> and 0x8000

            e64 =
                high |> shiftRightBy 20 |> and 0x07FF

            -- Top 10 bits of 52-bit mantissa
            m10 =
                high |> shiftRightBy 10 |> and 0x03FF

            -- 11th mantissa bit (guard bit for rounding)
            roundBit =
                high |> shiftRightBy 9 |> and 1
        in
        if e64 == 0 then
            -- Float64 subnormal (way too small for float16)
            s

        else if e64 == 0x07FF then
            -- Infinity (NaN already handled above)
            s |> or 0x7C00

        else
            let
                e16 =
                    e64 - 1008
            in
            if e16 >= 31 then
                -- Overflow to infinity
                s |> or 0x7C00

            else if e16 >= 1 then
                -- Normal
                s |> or (e16 |> shiftLeftBy 10) |> or m10 |> (+) roundBit

            else if e16 >= -10 then
                -- Subnormal: shift mantissa with implicit leading 1
                let
                    fullM =
                        m10 |> or 0x0400

                    shift =
                        1 - e16

                    mSub =
                        fullM |> shiftRightBy shift

                    rSub =
                        fullM |> shiftRightBy (shift - 1) |> and 1
                in
                s + mSub + rSub

            else
                -- Underflow to zero
                s


decode : Int -> Float
decode bits =
    let
        s =
            bits |> shiftRightBy 15 |> and 1

        e =
            bits |> shiftRightBy 10 |> and 0x1F

        m =
            bits |> and 0x03FF
    in
    if e == 0 then
        if m == 0 then
            fromFloat64Bits { high = s |> shiftLeftBy 31, low = 0 }

        else
            let
                { eR, mR } =
                    renormalize16 0 m
            in
            fromFloat64Bits
                { high =
                    (s |> shiftLeftBy 31)
                        |> or ((eR + 1009) |> shiftLeftBy 20)
                        |> or (mR |> shiftLeftBy 10)
                , low = 0
                }

    else if e == 31 then
        fromFloat64Bits
            { high =
                (s |> shiftLeftBy 31)
                    |> or (0x07FF |> shiftLeftBy 20)
                    |> or (m |> shiftLeftBy 10)
            , low = 0
            }

    else
        fromFloat64Bits
            { high =
                (s |> shiftLeftBy 31)
                    |> or ((e + 1008) |> shiftLeftBy 20)
                    |> or (m |> shiftLeftBy 10)
            , low = 0
            }


{-| Renormalize a subnormal half-float mantissa.
Shifts left until the implicit leading 1 is at bit 10, tracking the
exponent adjustment.
-}
renormalize16 : Int -> Int -> { eR : Int, mR : Int }
renormalize16 e m =
    if and m 0x0400 == 0 then
        renormalize16 (e - 1) (m |> shiftLeftBy 1)

    else
        { eR = e, mR = and m 0x03FF }


{-| Reinterpret a Float as its 64-bit IEEE 754 representation,
split into high and low 32-bit words.
-}
toFloat64Bits : Float -> { high : Int, low : Int }
toFloat64Bits f =
    f
        |> (E.float64 BE >> E.encode)
        |> D.decode
            (D.map2 (\h l -> { high = h, low = l })
                (D.unsignedInt32 BE)
                (D.unsignedInt32 BE)
            )
        |> Maybe.withDefault { high = 0, low = 0 }


{-| Reconstruct a Float from its 64-bit IEEE 754 representation.
-}
fromFloat64Bits : { high : Int, low : Int } -> Float
fromFloat64Bits { high, low } =
    E.sequence [ E.unsignedInt32 BE high, E.unsignedInt32 BE low ]
        |> E.encode
        |> D.decode (D.float64 BE)
        |> Maybe.withDefault (0 / 0)
