# Float16 Benchmarks

Benchmarking infrastructure for comparing alternative float16 encode/decode implementations.

## Implementations

| Module | Encode strategy | Decode strategy |
|---|---|---|
| `Current` | Copy of current (float32 bit reinterpretation + bit shifts) | Copy of current |
| `EncodeByDecode` | Binary search over decode results | Pure arithmetic |
| `PureArithmetic` | frexp decomposition, no bit reinterpretation | Pure arithmetic |
| `Float64` | float64 bit reinterpretation | float64 bit reinterpretation |
| `SuccessiveBit` | ADC-style bit-by-bit construction | Pure arithmetic |
| `ScaleFloor` | Scale to integer range + round | Pure arithmetic |
| `LookupTable` | Precomputed Array tables | Copy of current |

## Running benchmarks

```sh
cd bench
elm-bench -f Bench.current_encode -f Bench.encodeByDecode_encode "()"
elm-bench -f Bench.current_decode -f Bench.encodeByDecode_decode "()"
```

## Correctness checks

```sh
cd bench
elm-test
```
