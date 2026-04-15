module Bench exposing
    ( encodeByDecode_decode
    , encodeByDecode_encode
    , float64_decode
    , float64_encode
    , lookupTable_decode
    , lookupTable_encode
    , new_full_decode
    , new_full_encode
    , old_decode
    , old_encode
    , old_full_decode
    , old_full_encode
    , pureArithmetic_decode
    , pureArithmetic_encode
    , pureArithmetic_encode_batch
    , scaleFloor_decode
    , scaleFloor_encode
    , scaleFloor_encode_batch
    , successiveBit_decode
    , successiveBit_encode
    )

{-| Benchmark functions for float16 encode/decode variants.

    elm-bench -f Bench.old_encode -f Bench.encodeByDecode_encode "()"
    elm-bench -f Bench.old_decode -f Bench.encodeByDecode_decode "()"

Full pipeline (Float -> Encoder -> Bytes / Bytes -> Decoder -> Float):

    elm-bench -f Bench.old_full_encode -f Bench.new_full_encode "()"
    elm-bench -f Bench.old_full_decode -f Bench.new_full_decode "()"

-}

import Bytes exposing (Endianness(..))
import Bytes.Decode as D
import Bytes.Encode as E
import Bytes.Floating.Decode as NewDecode
import Bytes.Floating.Encode as NewEncode
import Bytes.Floating.EncodeByDecode as EncodeByDecode
import Bytes.Floating.Float64 as Float64
import Bytes.Floating.LookupTable as LookupTable
import Bytes.Floating.Old as Old
import Bytes.Floating.PureArithmetic as PureArithmetic
import Bytes.Floating.ScaleFloor as ScaleFloor
import Bytes.Floating.SuccessiveBit as SuccessiveBit



-- Test data


testFloat : Float
testFloat =
    12.375


testUint16 : Int
testUint16 =
    0x4A30


{-| Diverse encode inputs spanning all float16 regions.
Exercises different loop iteration counts in frexp/scaleToRange:

  - near 1.0: 0 iterations
  - large values (65504): ~15 halvings
  - tiny subnormals (5.96e-8): ~24 doublings
  - negative, overflow, zero

-}
batchFloats : List Float
batchFloats =
    [ 0
    , -0.0
    , 1.0
    , 1.5
    , -0.25
    , 0.375
    , 1.001
    , 0.99951
    , 12.375
    , 82.125
    , 65504.0
    , 0.000061035
    , 5.96046e-8
    , 1.0e-9
    , 12547414.0
    ]


testBytesEncoded : Bytes.Bytes
testBytesEncoded =
    E.unsignedInt16 BE testUint16 |> E.encode



-- Old (baseline: bit-reinterpretation via float32 Bytes roundtrip)


old_encode : () -> Int
old_encode () =
    Old.encode testFloat


old_decode : () -> Float
old_decode () =
    Old.decode testUint16



-- Old: full pipeline (Float -> Encoder -> Bytes -> Decoder -> result)


old_full_encode : () -> Bytes.Bytes
old_full_encode () =
    Old.float16Encode BE testFloat |> E.encode


old_full_decode : () -> Maybe Float
old_full_decode () =
    D.decode (Old.float16Decode BE) testBytesEncoded



-- EncodeByDecode


encodeByDecode_encode : () -> Int
encodeByDecode_encode () =
    EncodeByDecode.encode testFloat


encodeByDecode_decode : () -> Float
encodeByDecode_decode () =
    EncodeByDecode.decode testUint16



-- PureArithmetic


pureArithmetic_encode : () -> Int
pureArithmetic_encode () =
    PureArithmetic.encode testFloat


pureArithmetic_decode : () -> Float
pureArithmetic_decode () =
    PureArithmetic.decode testUint16



-- Float64


float64_encode : () -> Int
float64_encode () =
    Float64.encode testFloat


float64_decode : () -> Float
float64_decode () =
    Float64.decode testUint16



-- SuccessiveBit


successiveBit_encode : () -> Int
successiveBit_encode () =
    SuccessiveBit.encode testFloat


successiveBit_decode : () -> Float
successiveBit_decode () =
    SuccessiveBit.decode testUint16



-- ScaleFloor


scaleFloor_encode : () -> Int
scaleFloor_encode () =
    ScaleFloor.encode testFloat


scaleFloor_decode : () -> Float
scaleFloor_decode () =
    ScaleFloor.decode testUint16



-- Batch: PureArithmetic vs ScaleFloor over diverse inputs


pureArithmetic_encode_batch : () -> List Int
pureArithmetic_encode_batch () =
    List.map PureArithmetic.encode batchFloats


scaleFloor_encode_batch : () -> List Int
scaleFloor_encode_batch () =
    List.map ScaleFloor.encode batchFloats



-- LookupTable


lookupTable_encode : () -> Int
lookupTable_encode () =
    LookupTable.encode testFloat


lookupTable_decode : () -> Float
lookupTable_decode () =
    LookupTable.decode testUint16



-- New (public API): full pipeline


new_full_encode : () -> Bytes.Bytes
new_full_encode () =
    NewEncode.float16 BE testFloat |> E.encode


new_full_decode : () -> Maybe Float
new_full_decode () =
    D.decode (NewDecode.float16 BE) testBytesEncoded
