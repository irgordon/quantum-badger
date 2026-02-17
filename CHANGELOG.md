# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-01-14

### Fixed
- **Security**: Fixed a vulnerability where audit logging failures were silently ignored in `SLARuntimeGuard`. The system now explicitly handles logging errors and returns a failure result if logging fails after a successful function execution.
- Added `auditLoggingFailed` case to `FunctionError` for better error reporting.
- Improved reliability of `SLARuntimeGuard` by ensuring all execution outcomes are either audited or reported as failed.
