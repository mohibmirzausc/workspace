# ADR 002: Test File Location

## Status
Accepted

## Context
We need a clear convention for where test files are located relative to the source code they test. Different projects use different approaches:

1. **Separate test directory** (e.g., `src/` and `test/` as siblings)
   - Pro: Clear separation of concerns
   - Con: Test file far from implementation, harder to find related tests
   - Con: Duplicates directory structure

2. **Tests adjacent to implementation** (e.g., `foo.ts` and `foo.test.ts` in same directory)
   - Pro: Easy to find tests for a given file
   - Pro: Single directory structure to maintain
   - Pro: Natural collocation of related code
   - Con: Source and test files intermixed in directory listings

3. **Tests in subdirectory** (e.g., `foo.ts` and `__tests__/foo.test.ts`)
   - Pro: Keeps tests slightly separated
   - Con: Extra nesting, harder to navigate
   - Con: Still duplicates some structure

## Decision
**One test file per TypeScript file, located in the same directory as the source file.**

### File Naming Convention
- Source file: `[name].ts`
- Test file: `[name].test.ts`

### Example Structure
```
api/
  src/
    jj.ts          # Source code
    jj.test.ts     # Tests for jj.ts
    util.ts        # Source code
    util.test.ts   # Tests for util.ts
```

### Rules
1. Each `.ts` source file MUST have a corresponding `.test.ts` file in the same directory
2. Test file name MUST match source file name with `.test.ts` suffix
3. Test file MUST be in the exact same directory as the source file it tests
4. One test file per source file (no shared test files)

### Exceptions
- Files that only export types (no runtime code) may skip test files
- Configuration files (`config.ts`, etc.) may skip test files if they contain no logic
- Entry point files that only import/export may skip test files

## Rationale

### Benefits
1. **Discoverability**: Tests are immediately visible next to the code they test
2. **Refactoring**: Moving/renaming a file naturally includes its tests
3. **Code Review**: Can see implementation and tests in single directory view
4. **Convention**: Clear, unambiguous location for tests
5. **Tooling**: Many tools (IDEs, test runners) prefer this pattern

### Why Not Separate Test Directory?
- Harder to find tests for a given file
- Duplicate directory structures to maintain
- Easy to forget updating tests when moving files
- Test location doesn't reflect source location

### Why Not Subdirectory?
- Extra nesting reduces discoverability
- Adds complexity without significant benefit
- Tooling often expects adjacent pattern

## Consequences

### Positive
- Clear, predictable test location
- Easy to verify test coverage (check for `.test.ts` adjacent to each `.ts`)
- Natural pairing of implementation and tests
- IDE navigation between source and test is simpler

### Negative
- Source directories contain both `.ts` and `.test.ts` files
- Directory listings show more files (but with clear `.test.ts` naming)

### Migration
Existing tests in separate `test/` directory should be moved to be adjacent to their corresponding source files.

**Migration steps:**
1. For each test file in `test/[name].test.ts`
2. Find corresponding source file `src/[name].ts`
3. Move test file to `src/[name].test.ts`
4. Update import paths in test file
5. Remove empty `test/` directory

## Verification
To verify compliance:
```bash
# For each .ts file, check for adjacent .test.ts
find src -name "*.ts" -not -name "*.test.ts" -not -name "*.d.ts" | while read f; do
  test_file="${f%.ts}.test.ts"
  if [ ! -f "$test_file" ]; then
    echo "Missing test: $test_file"
  fi
done
```

## References
- Jest documentation: "By default, Jest looks for `.test.js` and `.spec.js` files... adjacent to the source code"
- Vitest/Bun test patterns follow similar conventions
- Many modern TypeScript projects use this pattern (Remix, tRPC, etc.)
