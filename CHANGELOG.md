# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-05-15

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
