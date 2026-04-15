module Bytes.Floating.DecodeTests exposing (suite)

import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as D
import Bytes.Encode as E
import Bytes.Floating.Decode exposing (float16)
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Bytes.Floating.Decode"
        [ hex [ 0x00, 0x00 ]
            |> expect (float16 BE) (Just 0.0)
        , hex [ 0x22, 0x55 ]
            |> expect (float16 LE) (Just 82.125)
        , hex [ 0x4A, 0x30 ]
            |> expect (float16 BE) (Just 12.375)
        , hex [ 0x80, 0x00 ]
            |> expect (float16 BE) (Just -0.0)
        , hex [ 0x3C, 0x00 ]
            |> expect (float16 BE) (Just 1.0)
        , hex [ 0x3E, 0x00 ]
            |> expect (float16 BE) (Just 1.5)
        , hex [ 0xB4, 0x00 ]
            |> expect (float16 BE) (Just -0.25)
        , hex [ 0x36, 0x00 ]
            |> expect (float16 BE) (Just 0.375)
        , hex [ 0x3C, 0x01 ]
            |> expect (float16 BE) (Just 1.0009765625)
        , hex [ 0x3B, 0xFF ]
            |> expect (float16 BE) (Just 0.99951171875)
        , hex [ 0x7B, 0xFF ]
            |> expect (float16 BE) (Just 65504)
        , hex [ 0x04, 0x00 ]
            |> expect (float16 BE) (Just 0.00006103515625)
        , hex [ 0x00, 0x01 ]
            |> expect (float16 BE) (Just 0.00000005960464477539063)
        , hex [ 0x7C, 0x00 ]
            |> expect (float16 BE) (Just (1 / 0))
        , hex [ 0xFC, 0x00 ]
            |> expect (float16 BE) (Just (-1 / 0))
        , hex [ 0xFC, 0x01 ]
            |> expect (D.map isNaN <| float16 BE) (Just True)
        ]


{-| Alias / Shortcut to write test cases
-}
expect : D.Decoder a -> Maybe a -> ( List Int, Bytes ) -> Test
expect decoder output ( readable, input ) =
    test (Debug.toString readable ++ " -> " ++ Debug.toString output) <|
        \_ -> input |> D.decode decoder |> Expect.equal output


{-| Convert a list of BE unsigned8 to bytes
-}
hex : List Int -> ( List Int, Bytes )
hex xs =
    ( xs, xs |> List.map E.unsignedInt8 >> E.sequence >> E.encode )
