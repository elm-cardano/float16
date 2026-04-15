module Bytes.Floating.Old exposing (decode, encode, float16Decode, float16Encode)

{-| Copy of the old float16 implementation (bit-reinterpretation approach)
for benchmarking against the new pure-arithmetic implementation.
-}

import Bitwise exposing (and, or, shiftLeftBy, shiftRightBy)
import Bytes exposing (Endianness(..))
import Bytes.Decode as D
import Bytes.Encode as E


{-| Full encode: Float -> Bytes (matches the public API signature).
-}
float16Encode : Endianness -> Float -> E.Encoder
float16Encode endian =
    toUnsignedInt32 >> floatToHalf >> E.unsignedInt16 endian


{-| Full decode: Bytes -> Float (matches the public API signature).
-}
float16Decode : Endianness -> D.Decoder Float
float16Decode endian =
    D.unsignedInt16 endian |> D.map (halfToFloat >> fromUnsignedInt32)


{-| Internal encode: Float -> Int (for unit-level benchmarking).
-}
encode : Float -> Int
encode =
    toUnsignedInt32 >> floatToHalf


{-| Internal decode: Int -> Float (for unit-level benchmarking).
-}
decode : Int -> Float
decode =
    halfToFloat >> fromUnsignedInt32



-- Encoding internals


type Rounding
    = NoRounding
    | RoundUp


floatToHalf : Int -> Int
floatToHalf x =
    let
        s =
            x |> shiftRightBy 16 |> and 0x8000

        e =
            x |> shiftRightBy 23 |> and 0xFF

        m =
            x |> and 0x007FFFFF
    in
    case e of
        0 ->
            packHalf { s = s, e = 0, m = 0 } NoRounding

        255 ->
            let
                mNext =
                    if m == 0 then
                        0

                    else
                        0x01
            in
            packHalf { s = s, e = 31, m = mNext } NoRounding

        _ ->
            let
                eNext =
                    e - 127 + 15
            in
            if eNext >= 31 then
                packHalf { s = s, e = 31, m = 0 } NoRounding

            else if eNext <= 0 then
                if eNext >= -10 && eNext <= 0 then
                    let
                        r =
                            case m |> or 0x00800000 |> shiftRightBy (13 - eNext) |> and 1 of
                                1 ->
                                    RoundUp

                                _ ->
                                    NoRounding

                        mNext =
                            m |> or 0x00800000 |> shiftRightBy (14 - eNext)
                    in
                    packHalf { s = s, e = 0, m = mNext } r

                else
                    packHalf { s = s, e = 0, m = 0 } NoRounding

            else
                let
                    mNext =
                        m |> shiftRightBy 13

                    r =
                        case m |> shiftRightBy 12 |> and 1 of
                            1 ->
                                RoundUp

                            _ ->
                                NoRounding
                in
                packHalf { s = s, e = eNext, m = mNext } r


toUnsignedInt32 : Float -> Int
toUnsignedInt32 f =
    f
        |> (E.float32 BE >> E.encode)
        |> D.decode (D.unsignedInt32 BE)
        |> Maybe.withDefault (0 // 0)


packHalf : { s : Int, e : Int, m : Int } -> Rounding -> Int
packHalf { s, e, m } rounding =
    let
        r =
            case rounding of
                NoRounding ->
                    0

                RoundUp ->
                    1
    in
    r + (s |> or (e |> shiftLeftBy 10) |> or m)



-- Decoding internals


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
