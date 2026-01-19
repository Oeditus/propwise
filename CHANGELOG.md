# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-19

### Added
- Initial release of PropWise
- AST-based analysis for identifying property-based testing candidates
- Purity analysis to detect functions without side effects
- Pattern detection for seven types of testable patterns:
  - Collection operations (Enum, Stream, comprehensions)
  - Data transformations (pipelines, struct/map manipulation)
  - Validation functions (predicates, boolean checks)
  - Algebraic structures (merge, concat, compose operations)
  - Encoder/decoder functions
  - Parser functions
  - Numeric algorithms
- Inverse function pair detection (encode/decode, serialize/deserialize, etc.)
- Concrete property-based test generation using stream_data
- Testability scoring system with configurable threshold
- Command-line interface via escript
- Mix task integration (`mix propwise`)
- JSON and text output formats
- Configuration file support (`.propwise.exs`)
- Comprehensive documentation and scoring guide

[Unreleased]: https://github.com/Oeditus/propwise/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Oeditus/propwise/releases/tag/v0.1.0
