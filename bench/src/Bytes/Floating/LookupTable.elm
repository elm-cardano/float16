module Bytes.Floating.LookupTable exposing (decode, encode)

{-| Float16 via precomputed lookup tables.
Four tables indexed by the upper 9 bits of the float32 representation
(sign + 8-bit exponent = 512 entries each) replace all branching logic
in the encoder. The decoder reuses the current bit-reinterpretation approach.

Tables:
  - baseTable:       float16 sign + exponent bits
  - shiftTable:      mantissa right-shift amount
  - orMaskTable:     implicit-1 mask for subnormals
  - roundShiftTable: guard bit position for rounding
-}

import Array exposing (Array)
import Bitwise exposing (and, or, shiftLeftBy, shiftRightBy)
import Bytes exposing (Endianness(..))
import Bytes.Decode as D
import Bytes.Encode as E



-- TABLES


baseTable : Array Int
baseTable =
    Array.initialize 512 computeBase


shiftTable : Array Int
shiftTable =
    Array.initialize 512 computeShift


orMaskTable : Array Int
orMaskTable =
    Array.initialize 512 computeOrMask


roundShiftTable : Array Int
roundShiftTable =
    Array.initialize 512 computeRoundShift


computeBase : Int -> Int
computeBase i =
    let
        sign =
            if i >= 256 then
                0x8000

            else
                0

        e =
            modBy 256 i
    in
    if e < 102 then
        sign

    else if e < 113 then
        -- Subnormal float16: base is just sign
        sign

    else if e < 143 then
        -- Normal: biased float16 exponent = e - 112
        sign + ((e - 112) |> shiftLeftBy 10)

    else
        -- Overflow to infinity (and inf/nan passthrough)
        sign + 0x7C00


computeShift : Int -> Int
computeShift i =
    let
        e =
            modBy 256 i
    in
    if e < 102 then
        24

    else if e < 113 then
        -- Subnormal: 14 - (e - 112) = 126 - e
        126 - e

    else if e < 143 then
        -- Normal: 23-bit to 10-bit mantissa
        13

    else
        -- Overflow and inf/nan: shift away mantissa
        24


computeOrMask : Int -> Int
computeOrMask i =
    let
        e =
            modBy 256 i
    in
    if e >= 102 && e < 113 then
        -- Subnormal: add implicit leading 1 to mantissa
        0x00800000

    else
        0


computeRoundShift : Int -> Int
computeRoundShift i =
    let
        e =
            modBy 256 i
    in
    if e < 102 then
        24

    else if e < 113 then
        -- Subnormal: 13 - (e - 112) = 125 - e
        125 - e

    else if e < 143 then
        -- Normal: guard bit at position 12
        12

    else
        24



-- ENCODE


encode : Float -> Int
encode f =
    if isNaN f then
        -- Special case: canonical NaN (tables can't collapse NaN payloads)
        let
            bits =
                toUnsignedInt32 f

            s =
                bits |> shiftRightBy 16 |> and 0x8000
        in
        s |> or 0x7C01

    else
        let
            bits =
                toUnsignedInt32 f

            index =
                bits |> shiftRightBy 23 |> and 0x01FF

            mantissa =
                bits |> and 0x007FFFFF

            base =
                Array.get index baseTable |> Maybe.withDefault 0

            shift =
                Array.get index shiftTable |> Maybe.withDefault 24

            mask =
                Array.get index orMaskTable |> Maybe.withDefault 0

            rshift =
                Array.get index roundShiftTable |> Maybe.withDefault 24

            masked =
                mantissa |> or mask

            roundBit =
                masked |> shiftRightBy rshift |> and 1
        in
        base + (masked |> shiftRightBy shift) + roundBit


toUnsignedInt32 : Float -> Int
toUnsignedInt32 f =
    f
        |> (E.float32 BE >> E.encode)
        |> D.decode (D.unsignedInt32 BE)
        |> Maybe.withDefault (0 // 0)



-- DECODE (same as current implementation)


decode : Int -> Float
decode =
    halfToFloat >> fromUnsignedInt32


halfToFloat : Int -> Int
halfToFloat x =
    let
        s =
            x |> shiftRightBy 15 |> and 1

        e =
            x |> shiftRightBy 10 |> and 0x1F

        m =
            x |> and 0x03FF
    in
    if e == 0 then
        if m == 0 then
            s |> shiftLeftBy 31

        else
            packFloat32 <| renormalize { s = s, e = e, m = m }

    else if e == 31 then
        packFloat32 { s = s, e = 255, m = m |> shiftLeftBy 13 }

    else
        packFloat32 { s = s, e = e + 112, m = m |> shiftLeftBy 13 }


renormalize : { s : Int, e : Int, m : Int } -> { s : Int, e : Int, m : Int }
renormalize { s, e, m } =
    case m |> and 0x0400 of
        0 ->
            renormalize { s = s, e = e - 1, m = m |> shiftLeftBy 1 }

        _ ->
            { s = s, e = e + 113, m = m |> and -1025 }


fromUnsignedInt32 : Int -> Float
fromUnsignedInt32 =
    E.unsignedInt32 BE
        >> E.encode
        >> D.decode (D.float32 BE)
        >> Maybe.withDefault (0 / 0)


packFloat32 : { s : Int, e : Int, m : Int } -> Int
packFloat32 { s, e, m } =
    (s |> shiftLeftBy 31) |> or (e |> shiftLeftBy 23) |> or m
