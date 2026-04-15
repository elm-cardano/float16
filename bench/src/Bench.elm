module Bench exposing
    ( current_decode
    , current_encode
    , encodeByDecode_decode
    , encodeByDecode_encode
    , float64_decode
    , float64_encode
    , lookupTable_decode
    , lookupTable_encode
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

    elm-bench -f Bench.current_encode -f Bench.encodeByDecode_encode "()"
    elm-bench -f Bench.current_decode -f Bench.encodeByDecode_decode "()"

-}

import Bytes.Floating.Current as Current
import Bytes.Floating.EncodeByDecode as EncodeByDecode
import Bytes.Floating.Float64 as Float64
import Bytes.Floating.LookupTable as LookupTable
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



-- Current (baseline copy)


current_encode : () -> Int
current_encode () =
    Current.encode testFloat


current_decode : () -> Float
current_decode () =
    Current.decode testUint16



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
