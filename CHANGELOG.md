# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-02-17

### Changed
- Refactored `PromptComplexity.assess` to use a static property `complexityIndicators` instead of a hardcoded local array.

### Added
- `PromptComplexity.complexityIndicators` static property containing the list of keywords used for complexity assessment.

## [0.1.1] - 2025-05-15

### Added
- Initial release of Quantum Badger.
- Privacy Egress Filter for PII/PHI detection and redaction.
- Local-first execution with MLX support.
- Cloud fallback with user consent.
- Audit logging and system health monitoring.

### Fixed
- Logic bug in PrivacyEgressFilter deduplication where overlapping detections were incorrectly prioritized by start position instead of confidence level.
- Improved reliability of sensitive data detection by preferring high-confidence and longer matches.
- Added comprehensive unit tests for overlapping privacy detections.

## [0.1.0] - 2026-01-14

### Fixed
- **Security**: Fixed a vulnerability where audit logging failures were silently ignored in `SLARuntimeGuard`. The system now explicitly handles logging errors and returns a failure result if logging fails after a successful function execution.
- Added `auditLoggingFailed` case to `FunctionError` for better error reporting.
- Improved reliability of `SLARuntimeGuard` by ensuring all execution outcomes are either audited or reported as failed.
