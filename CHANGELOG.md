# Changelog

# v2.0.0 (unreleased)

- Rewrite encoder and decoder using pure arithmetic instead of float32 bit-reinterpretation
  - Encoder uses frexp-style decomposition (repeated halving/doubling) to find exponent and mantissa, then quantizes to 10 bits via `round`
  - Decoder reconstructs the float directly from the IEEE 754 formula: `sign * (1 + m/1024) * 2^(e-15)`
  - No intermediate `Bytes` allocation in the core conversion logic
- Performance improvement: **58% faster encode**, **83% faster decode** (full pipeline including Bytes I/O)
- NaN encoding changed from sign-preserving signaling NaN (0x7C01/0xFC01) to canonical quiet NaN (0x7E00)
- Upgrade test dependency from elm-explorations/test 1.x to 2.x
- Remove elm/random from test dependencies (transitive via elm-explorations/test)
- Improve test coverage: add cases for positive zero, +Infinity, and explicit NaN validation

# v1.0.1 (2019-04-23)

- Minor documentation adjustments

# v1.0.0 (2019-04-23)

- Implement binary encoder & decoder for half-precision floating numbers
- Provide unit & fuzz tests
- Initial README with example usage
