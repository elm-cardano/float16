module Bytes.Floating.EncodeTests exposing (suite)

import Bytes exposing (Bytes, Endianness(..), width)
import Bytes.Decode as D
import Bytes.Encode as E
import Bytes.Floating.Encode exposing (float16)
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Bytes.Floating.Encode"
        [ expect "0" (float16 BE 0) [ 0x00, 0x00 ]
        , expect "82.125 LE" (float16 LE 82.125) [ 0x22, 0x55 ]
        , expect "12.375" (float16 BE 12.375) [ 0x4A, 0x30 ]
        , expect "-0.0" (float16 BE -0.0) [ 0x80, 0x00 ]
        , expect "1.0" (float16 BE 1.0) [ 0x3C, 0x00 ]
        , expect "1.5" (float16 BE 1.5) [ 0x3E, 0x00 ]
        , expect "-0.25" (float16 BE -0.25) [ 0xB4, 0x00 ]
        , expect "0.375" (float16 BE 0.375) [ 0x36, 0x00 ]
        , expect "1.001" (float16 BE 1.001) [ 0x3C, 0x01 ]
        , expect "0.99951" (float16 BE 0.99951) [ 0x3B, 0xFF ]
        , expect "65504" (float16 BE 65504) [ 0x7B, 0xFF ]
        , expect "smallest normal" (float16 BE 0.000061035) [ 0x04, 0x00 ]
        , expect "smallest subnormal" (float16 BE 0.000000059605) [ 0x00, 0x01 ]
        , expect "underflow to zero" (float16 BE 0.000000001) [ 0x00, 0x00 ]
        , expect "overflow to +Inf" (float16 BE 12547414) [ 0x7C, 0x00 ]
        , expect "+Inf" (float16 BE (1 / 0)) [ 0x7C, 0x00 ]
        , expect "-Inf" (float16 BE (-1 / 0)) [ 0xFC, 0x00 ]
        , expect "NaN" (float16 BE (0 / 0)) [ 0x7E, 0x00 ]

        -- IEEE 754 roundTiesToEven: at exact midpoints, round to even mantissa
        , expect "midpoint(1.0, 1.0009765625)" (float16 BE 1.00048828125) [ 0x3C, 0x00 ]
        , expect "midpoint(2.0, 2.001953125)" (float16 BE 2.0009765625) [ 0x40, 0x00 ]
        , expect "midpoint(1.001953125, 1.0029296875)" (float16 BE 1.00244140625) [ 0x3C, 0x02 ]
        , expect "midpoint(0, smallest subnormal)" (float16 BE 2.9802322387695313e-8) [ 0x00, 0x00 ]
        , expect "midpoint(1.0009765625, 1.001953125)" (float16 BE 1.00146484375) [ 0x3C, 0x02 ]
        ]


expect : String -> E.Encoder -> List Int -> Test
expect label input output =
    test (label ++ " -> " ++ Debug.toString output) <|
        \_ -> hex (E.encode input) |> Expect.equal (Just output)


hex : Bytes -> Maybe (List Int)
hex bytes =
    bytes
        |> D.decode
            (D.loop ( width bytes, [] )
                (\( n, xs ) ->
                    if n == 0 then
                        xs |> List.reverse |> D.Done |> D.succeed

                    else
                        D.unsignedInt8
                            |> D.map (\x -> D.Loop ( n - 1, x :: xs ))
                )
            )
