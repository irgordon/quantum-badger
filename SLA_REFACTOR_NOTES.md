# SLA Refactor Notes

## 1. Shared SLA Contract and Guard
- Rule: Define explicit per-function SLA contracts and enforce timeout/memory/audit.
- Risk removed: Ad-hoc limits and missing execution evidence made failures hard to diagnose.
- Follow-up: Apply `SLARuntimeGuard` to remaining public async entry points (`SearchIndexer`, cloud/local engines).

## 2. `AppCoordinator` Pipeline Split
- Rule: Single level of abstraction with one task per function.
- Risk removed: Previous `execute` mixed validation, sanitization, routing, formatting, indexing, and audit writes in one function.
- Follow-up: Replace heuristic multi-task prompt detection with a parser-backed policy module.

## 3. `HybridExecutionManager` Pipeline Split
- Rule: Separate policy orchestration from routing/execution implementation.
- Risk removed: Monolithic `execute` made cancellation/timeouts and auditability hard to reason about.
- Follow-up: Expose intent analysis artifact explicitly instead of returning `nil`.

## 4. Append-only Function Audit Events
- Rule: Every guarded function logs start/end hashes, duration, memory snapshot, and SLA compliance.
- Risk removed: Missing chain-linked records for function-level SLA compliance.
- Follow-up: Add audit verification tests for `FunctionExecution` records.

## 5. Second Pass Coverage
- Rule: Apply one SLA guard entrypoint per service boundary and keep existing APIs backward compatible.
- Risk removed: Inconsistent runtime enforcement across indexing, cloud inference, and web fetch paths.
- Follow-up: Add SLA wrappers for streaming APIs where backpressure/timeout semantics are stream-native.
