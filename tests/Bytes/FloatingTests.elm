module Bytes.FloatingTests exposing (suite)

import Bytes exposing (Endianness(..))
import Bytes.Decode as D
import Bytes.Encode as E
import Bytes.Floating.Decode as D
import Bytes.Floating.Encode as E
import Expect
import Fuzz exposing (intRange, oneOf)
import Test exposing (Test, describe, fuzz)


suite : Test
suite =
    -- NOTE Ranges picks only normalized numbers
    describe "Roundtrips"
        [ fuzz
            (oneOf [ intRange 1024 31744, intRange 33792 64513 ])
            "Encode >> Decode ~ Just (1)"
          <|
            \i ->
                let
                    f : Maybe Float
                    f =
                        D.decode (D.float16 BE) <| E.encode (E.unsignedInt16 BE i)
                in
                f
                    |> Maybe.map (E.float16 BE >> E.encode)
                    |> Maybe.andThen (D.decode (D.unsignedInt16 BE))
                    |> Expect.equal (Just i)
        ]
