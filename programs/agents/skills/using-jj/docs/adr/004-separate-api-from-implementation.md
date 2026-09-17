# ADR-004: Separate Public API from Implementation

## Status
Proposed

## Context
Currently, `src/jj.ts` contains:
- Type definitions (interfaces)
- JSDoc documentation
- Full function implementations with business logic

This creates a large file (225 lines) that agents must load entirely to understand the public API. The implementation details add cognitive load and context size without providing value for API consumers.

We already have `src/jj-impl.ts` for internal helper functions. We should extend this pattern to separate the public API surface from its implementation.

## Decision
**Restructure `src/jj.ts` to contain only the public API surface:**

1. **Keep in `src/jj.ts`:**
   - Type definitions (interfaces for inputs/outputs)
   - JSDoc documentation for each function
   - Function signatures that delegate to implementation
   - Export statements

2. **Move to implementation file(s):**
   - All business logic
   - Implementation details
   - Internal state management

**File structure:**
```
src/
  jj.ts          # Public API: types, docs, thin delegates
  jj-impl.ts     # Implementation: business logic
  jj.test.ts     # Tests for public API
```

**Pattern for `src/jj.ts`:**
```typescript
/**
 * Start a new task
 *
 * Creates a described change for the task and an empty working copy.
 * If current change is empty with no description, describes it instead.
 */
export const startTask = async (input: StartTaskInput): Promise<StartTaskResult> => {
  return startTaskImpl(input);
};
```

**Pattern for `src/jj-impl.ts`:**
```typescript
export const startTaskImpl = async (input: StartTaskInput): Promise<StartTaskResult> => {
  // ... full implementation ...
};
```

## Consequences

### Positive
- **Reduced cognitive load**: Agents can read just the API surface without implementation noise
- **Faster comprehension**: JSDoc + types + signature conveys everything needed to use the API
- **Smaller context**: `jj.ts` becomes much smaller, loading faster for agents
- **Clear separation**: Public API vs private implementation is explicit
- **Better documentation**: Forces us to maintain good JSDoc since that's the primary documentation

### Negative
- **Extra indirection**: One more function call per public API
- **Two files to modify**: Changes to function signatures require updates in two places
- **Migration effort**: Need to refactor existing code

### Neutral
- Tests remain in `jj.test.ts` testing the public API (per ADR-002)
- Internal helpers stay in `jj-impl.ts` with `*Impl` suffix for public function implementations

## Implementation Notes
- Use `*Impl` suffix for implementation functions (e.g., `startTaskImpl`)
- Keep all type definitions in `jj.ts` (they're part of the public API)
- Maintain complete JSDoc on public functions
- Implementation functions don't need JSDoc (they're internal)

## Related
- ADR-002: Test File Location (tests stay adjacent to public API file)
- ADR-003: Prefer Arrow Functions (applies to both files)
