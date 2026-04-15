# Changelog

# v1.0.0 (unreleased)

Move package from `elm-toulouse/float16` to `elm-cardano/float16`. Version reset to 1.0.0 as required by the Elm package registry for a new package name.

- Rewrite encoder and decoder using pure arithmetic instead of float32 bit-reinterpretation
  - Encoder uses frexp-style decomposition (repeated halving/doubling) to find exponent and mantissa, then quantizes to 10 bits with IEEE 754 roundTiesToEven
  - Decoder reconstructs the float directly from the IEEE 754 formula: `sign * (1 + m/1024) * 2^(e-15)`
  - No intermediate `Bytes` allocation in the core conversion logic
- Performance improvement: **58% faster encode**, **83% faster decode** (full pipeline including Bytes I/O)
- Fix rounding: use IEEE 754 roundTiesToEven (banker's rounding) instead of round-half-up at exact midpoints between consecutive float16 values
- NaN encoding changed from sign-preserving signaling NaN (0x7C01/0xFC01) to canonical quiet NaN (0x7E00)
- Upgrade test dependency from elm-explorations/test 1.x to 2.x
- Improve test coverage: add cases for positive zero, +Infinity, explicit NaN validation, and IEEE 754 midpoint rounding

---

Previous releases under `elm-toulouse/float16`:

# v1.0.1 (2019-04-23)

- Minor documentation adjustments

# v1.0.0 (2019-04-23)

- Implement binary encoder & decoder for half-precision floating numbers
- Provide unit & fuzz tests
- Initial README with example usage
