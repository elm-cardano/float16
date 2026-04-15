module VariantsTest exposing (suite)

{-| Verify that all variant implementations produce the same output
as the original float16 implementation.
-}

import Bitwise exposing (and, shiftRightBy)
import Bytes exposing (Endianness(..))
import Bytes.Decode as D
import Bytes.Encode as E
import Bytes.Floating.Decode as OrigDecode
import Bytes.Floating.Encode as OrigEncode
import Bytes.Floating.EncodeByDecode as EncodeByDecode
import Bytes.Floating.Float64 as Float64
import Bytes.Floating.LookupTable as LookupTable
import Bytes.Floating.Old as Old
import Bytes.Floating.PureArithmetic as PureArithmetic
import Bytes.Floating.ScaleFloor as ScaleFloor
import Bytes.Floating.SuccessiveBit as SuccessiveBit
import Expect
import Test exposing (..)



-- Reference: extract uint16 from the original encoder


referenceEncode : Float -> Int
referenceEncode f =
    OrigEncode.float16 BE f
        |> E.encode
        |> D.decode (D.unsignedInt16 BE)
        |> Maybe.withDefault -1


referenceDecode : Int -> Float
referenceDecode i =
    E.unsignedInt16 BE i
        |> E.encode
        |> D.decode (OrigDecode.float16 BE)
        |> Maybe.withDefault -999



-- Compare floats by their byte-level representation.
-- This avoids elm-test's "Do not use Expect.equal with floats" restriction
-- while giving exact equality for all values (including -0, Inf).
-- NaN is handled separately since different NaN payloads are acceptable.


compareFloats : Float -> Float -> Expect.Expectation
compareFloats expected actual =
    if isNaN expected && isNaN actual then
        Expect.pass

    else if isNaN expected || isNaN actual then
        Expect.fail
            ("NaN mismatch: expected "
                ++ Debug.toString expected
                ++ " but got "
                ++ Debug.toString actual
            )

    else
        Expect.equal (floatToBytes expected) (floatToBytes actual)


floatToBytes : Float -> List Int
floatToBytes f =
    f
        |> (E.float64 BE >> E.encode)
        |> D.decode
            (D.loop ( 8, [] )
                (\( n, xs ) ->
                    if n == 0 then
                        D.succeed (D.Done (List.reverse xs))

                    else
                        D.unsignedInt8
                            |> D.map (\x -> D.Loop ( n - 1, x :: xs ))
                )
            )
        |> Maybe.withDefault []



-- Test values (NaN excluded from main lists — tested separately)


testEncodeValues : List ( String, Float )
testEncodeValues =
    [ ( "0", 0 )
    , ( "-0", -0.0 )
    , ( "1", 1 )
    , ( "1.5", 1.5 )
    , ( "-0.25", -0.25 )
    , ( "0.375", 0.375 )
    , ( "1.001", 1.001 )
    , ( "0.99951", 0.99951 )
    , ( "12.375", 12.375 )
    , ( "82.125", 82.125 )
    , ( "65504", 65504 )
    , ( "0.000061035", 0.000061035 )
    , ( "0.000000059605", 0.000000059605 )
    , ( "0.000000001", 0.000000001 )
    , ( "12547414", 12547414 )
    , ( "+Inf", 1 / 0 )
    , ( "-Inf", -1 / 0 )
    ]


testDecodeValues : List ( String, Int )
testDecodeValues =
    [ ( "0x0000", 0x00 )
    , ( "0x0001", 0x01 )
    , ( "0x0400", 0x0400 )
    , ( "0x3BFF", 0x3BFF )
    , ( "0x3C00", 0x3C00 )
    , ( "0x3C01", 0x3C01 )
    , ( "0x3E00", 0x3E00 )
    , ( "0x4A30", 0x4A30 )
    , ( "0x7BFF", 0x7BFF )
    , ( "0x7C00", 0x7C00 )
    , ( "0x8000", 0x8000 )
    , ( "0xB400", 0xB400 )
    , ( "0xFC00", 0xFC00 )
    , ( "0xFC01 (NaN)", 0xFC01 )
    ]



-- IEEE 754 roundTiesToEven test cases.
-- These are exact midpoints between consecutive float16 values where
-- the floor has an even mantissa. IEEE 754 says: keep the floor (even).
-- The current implementation incorrectly rounds up (guard-bit-only rounding).
--
-- Each entry: ( label, input float, IEEE 754 correct uint16 )


ieee754MidpointCases : List ( String, Float, Int )
ieee754MidpointCases =
    [ ( "midpoint(1.0, 1.0009765625) = 1.00048828125"
      , 1.00048828125
      , 0x3C00
        -- floor: m=0 (even), IEEE 754 keeps it
      )
    , ( "midpoint(2.0, 2.001953125) = 2.0009765625"
      , 2.0009765625
      , 0x4000
        -- floor: m=0 (even)
      )
    , ( "midpoint(1.001953125, 1.0029296875) = 1.00244140625"
      , 1.00244140625
      , 0x3C02
        -- floor: m=2 (even)
      )
    , ( "midpoint(0, 5.96e-8) = 2.98e-8 (subnormal)"
      , 2.9802322387695313e-8
      , 0x00
        -- floor: m=0 (even)
      )
    ]



-- Test suite


suite : Test
suite =
    describe "Variant equivalence with original"
        [ variantSuite "Old" Old.encode Old.decode
        , variantSuite "EncodeByDecode" EncodeByDecode.encode EncodeByDecode.decode
        , variantSuite "PureArithmetic" PureArithmetic.encode PureArithmetic.decode
        , variantSuite "Float64" Float64.encode Float64.decode
        , variantSuite "SuccessiveBit" SuccessiveBit.encode SuccessiveBit.decode
        , variantSuite "ScaleFloor" ScaleFloor.encode ScaleFloor.decode
        , variantSuite "LookupTable" LookupTable.encode LookupTable.decode
        , ieee754Suite
        ]


{-| Tests documenting IEEE 754 roundTiesToEven behavior at exact midpoints.
The current implementation uses guard-bit-only rounding (round-half-up),
which incorrectly rounds up at midpoints where the floor mantissa is even.
-}
ieee754Suite : Test
ieee754Suite =
    describe "IEEE 754 roundTiesToEven (midpoint, even floor)"
        (List.map
            (\( label, input, correctUint16 ) ->
                describe label
                    [ test "old impl rounds UP (incorrect per IEEE 754)" <|
                        \_ ->
                            Old.encode input
                                |> Expect.equal (correctUint16 + 1)
                    , test "EncodeByDecode rounds DOWN (correct)" <|
                        \_ ->
                            EncodeByDecode.encode input
                                |> Expect.equal correctUint16
                    , test "SuccessiveBit rounds DOWN (correct)" <|
                        \_ ->
                            SuccessiveBit.encode input
                                |> Expect.equal correctUint16
                    ]
            )
            ieee754MidpointCases
        )


variantSuite : String -> (Float -> Int) -> (Int -> Float) -> Test
variantSuite name encodeFn decodeFn =
    describe name
        [ describe "encode"
            (List.map
                (\( label, f ) ->
                    test label <|
                        \_ -> encodeFn f |> Expect.equal (referenceEncode f)
                )
                testEncodeValues
            )
        , describe "encode NaN"
            [ test "NaN -> valid float16 NaN" <|
                \_ ->
                    let
                        result =
                            encodeFn (0 / 0)

                        e =
                            result |> shiftRightBy 10 |> and 0x1F

                        m =
                            result |> and 0x03FF
                    in
                    if e == 31 && m /= 0 then
                        Expect.pass

                    else
                        Expect.fail
                            ("expected e=31 and m/=0, got e="
                                ++ String.fromInt e
                                ++ " m="
                                ++ String.fromInt m
                            )
            ]
        , describe "decode"
            (List.map
                (\( label, i ) ->
                    test label <|
                        \_ -> compareFloats (referenceDecode i) (decodeFn i)
                )
                testDecodeValues
            )
        ]
