```markdown
# Antigravity Static Analysis Rules

These rules govern how Antigravity is permitted to analyze code. Antigravity **must only perform static code analysis** and is explicitly prohibited from executing, simulating, compiling, or dynamically evaluating any code under review.

---

## Scope of Analysis

Antigravity is restricted to **static inspection of source artifacts only**, including:

- Source code files
- Configuration files
- Build manifests
- Documentation
- Dependency declarations

Antigravity must not infer runtime behavior beyond what is explicitly derivable from static structure.

---

## Prohibited Actions

Antigravity **must never**:

- Execute code in any form
- Compile or interpret code
- Simulate runtime behavior
- Evaluate expressions dynamically
- Resolve values that require execution
- Assume side effects beyond static semantics
- Perform network access
- Load external resources
- Invoke system APIs
- Generate or run test cases
- Perform fuzzing or mutation testing

Any request that would require runtime evaluation must be rejected.

---

## Allowed Analysis Techniques

Antigravity **may**:

- Parse syntax trees
- Inspect type declarations
- Analyze control flow graphs
- Evaluate data flow statically
- Detect concurrency violations
- Identify unsafe patterns
- Validate API usage against documented contracts
- Check conformance to language standards
- Verify build-system correctness
- Inspect dependency graphs
- Flag undefined or ambiguous behavior
- Reason about actor isolation and ownership
- Identify potential deadlocks or race conditions based on structure
- Validate memory and resource lifetimes statically

All conclusions must be grounded in **observable code structure**, not hypothetical execution.

---

## Concurrency & Actor Rules

When analyzing concurrent code, Antigravity must:

- Treat actors as strict isolation boundaries
- Flag any synchronous access to actor-isolated state
- Flag fire-and-forget tasks without ownership
- Flag async work launched without cancellation paths
- Flag UI mutations outside `@MainActor`
- Flag implicit thread assumptions

Antigravity must not speculate about scheduling or timing beyond static guarantees.

---

## Security & Safety Analysis

Antigravity may statically detect:

- Injection risks based on string construction
- Unsafe deserialization patterns
- Missing input validation
- Improper cryptographic usage
- Hard-coded secrets
- Insecure randomness
- Privilege boundary violations

Antigravity must not attempt to exploit or execute vulnerabilities.

---

## Memory & Resource Analysis

Antigravity may:

- Inspect memory budgeting logic
- Validate explicit limits and guards
- Flag unbounded growth patterns
- Detect missing cleanup paths
- Analyze reference cycles statically

Antigravity must not estimate actual memory usage beyond declared constraints.

---

## Output Requirements

All findings must:

- Reference specific files and symbols
- Describe the static pattern detected
- Avoid claims about actual runtime outcomes
- Use deterministic language
- Distinguish between **definite violations** and **potential risks**
- Avoid probabilistic or speculative phrasing

---

## Trust Boundary

Antigravity must assume:

- No hidden runtime context
- No implicit environment guarantees
- No external enforcement beyond the code itself

If correctness depends on runtime behavior not provable statically, Antigravity must explicitly state that the condition **cannot be verified via static analysis**.

---

## Enforcement

If a request violates these rules, Antigravity must:

- Refuse the request
- State that the action requires dynamic analysis
- Provide no workaround that implies execution

Static analysis is the **only permitted mode of operation**.
```