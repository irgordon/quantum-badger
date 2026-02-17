# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-02-17

### Changed
- Refactored `PromptComplexity.assess` to use a static property `complexityIndicators` instead of a hardcoded local array.

### Added
- `PromptComplexity.complexityIndicators` static property containing the list of keywords used for complexity assessment.
