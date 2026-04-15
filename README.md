![](.github/logo.png)

---

[![](https://img.shields.io/elm-package/v/elm-toulouse/float16.svg?style=for-the-badge)](https://package.elm-lang.org/packages/elm-toulouse/float16/latest/) 
[![](https://img.shields.io/travis/elm-toulouse/float16.svg?style=for-the-badge&label=%F0%9F%94%A8%20Build)](https://travis-ci.org/elm-toulouse/float16/builds)
[![](https://img.shields.io/codecov/c/gh/elm-toulouse/float16.svg?color=e84393&label=%E2%98%82%EF%B8%8F%20Coverage&style=for-the-badge)](https://codecov.io/gh/elm-toulouse/float16)
[![](https://img.shields.io/github/license/elm-toulouse/float16.svg?style=for-the-badge&label=%20%F0%9F%93%84%20License)](https://github.com/elm-toulouse/float16/blob/master/LICENSE)

## Getting Started

### Installation

```
elm install elm-toulouse/float16
```

### Usage

```elm
import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as D
import Bytes.Encode as E
import Bytes.Floating.Encode as E

-- ENCODER

encode : Float -> E.Encoder
encode f =
  E.sequence 
    [ E.float16 BE f
    , E.float32 BE f
    , E.float64 BE f
    ]

-- DECODER

decode : D.Decoder (Float, Float, Float)
decode =
  D.map3 (\a b c -> (a, b, c))
    |> D.float16 BE 
    |> D.float32 BE
    |> D.float64 BE
```

## Changelog

[CHANGELOG.md](https://github.com/elm-toulouse/float16/blob/master/CHANGELOG.md)
