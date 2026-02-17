# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2024-11-26

### Fixed
- **Performance**: Optimized regex compilation in `InputSanitizer`. Regex patterns are now compiled once during initialization and cached, rather than being recompiled in every loop iteration during sanitization.

## [1.0.0] - 2024-11-15

### Added
- Initial release of Quantum Badger.
- BadgerCore: Core sanitization and SLA logic.
- BadgerRuntime: Cloud and local inference management.
- BadgerApp: macOS application and UI.
