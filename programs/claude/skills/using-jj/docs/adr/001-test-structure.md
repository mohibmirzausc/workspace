# ADR 001: Test Structure Using Describe/Test Blocks

## Status
Accepted

## Context
We need a consistent test structure that makes test intent clear and organizes tests by the circumstances being tested rather than just listing assertions.

Tests should communicate:
- **What circumstances** are we testing? (describe blocks)
- **What assertions** do we make in those circumstances? (test blocks)

## Decision
We will structure all tests using nested `describe` and `test` blocks following this pattern:

### Structure
```typescript
describe("[Module/Function Name]", () => {
  describe("[Circumstances/Context]", () => {
    test("[Assertion about behavior]", () => {
      // Arrange
      // Act
      // Assert
    });
  });
});
```

### Naming Conventions

**Describe blocks** describe circumstances:
- Use present tense
- Describe the state/context
- Can be nested to add specificity
- Examples:
  - "when repository path is empty"
  - "when repository path is valid"
  - "after repository is set"

**Test blocks** make assertions:
- Use present tense, active voice
- State what the function does (not what it "should" do)
- Examples:
  - "throws error with message"
  - "returns status with changeId"
  - "resets module state"

### Example

```typescript
describe("setRepository", () => {
  describe("when repository path is invalid", () => {
    test("throws error when path is empty", async () => {
      await expect(
        setRepository({ repositoryPath: "" })
      ).rejects.toThrow("repositoryPath is required");
    });

    test("throws error when path does not exist", async () => {
      await expect(
        setRepository({ repositoryPath: "/nonexistent" })
      ).rejects.toThrow("repository not found");
    });
  });

  describe("when repository path is valid", () => {
    test("returns status with currentChangeId and changedFiles", async () => {
      const repoRoot = resolve(import.meta.dir, "../..");
      const result = await setRepository({ repositoryPath: repoRoot });

      expect(result.currentChangeId).toBeDefined();
      expect(Array.isArray(result.changedFiles)).toBe(true);
    });
  });
});
```

## Rationale

### Benefits
1. **Clarity**: Circumstances and assertions are explicitly separated
2. **Organization**: Related tests are grouped by context
3. **Readability**: Test structure mirrors natural language
4. **Scalability**: Easy to add new test cases to existing contexts
5. **Documentation**: Test structure serves as specification

### Why Not Flat Structure?
```typescript
// ❌ Flat structure loses context
test("setRepository throws error when path is empty", () => {});
test("setRepository throws error when path does not exist", () => {});
test("setRepository returns status when path is valid", () => {});
```

Problems:
- Repetitive test names
- Harder to see which tests cover similar circumstances
- No clear grouping

### Why Not "Should" Language?
```typescript
// ❌ "Should" is unnecessarily verbose
test("should throw error when path is empty", () => {});

// ✅ Present tense is clearer
test("throws error when path is empty", () => {});
```

"Should" adds no information and makes test names longer.

## Consequences

### Positive
- Consistent test structure across codebase
- Easier to understand test coverage at a glance
- Natural structure for TDD (write describe block for context, then tests)
- Better test output readability

### Negative
- Slightly more verbose than flat tests
- Requires discipline to maintain structure

### Migration
Existing tests should be refactored to follow this structure during normal maintenance. No need for bulk refactoring.

## References
- BDD (Behavior-Driven Development) testing patterns
- Jest/Vitest describe/test API
- RSpec describe/it pattern (Ruby)
