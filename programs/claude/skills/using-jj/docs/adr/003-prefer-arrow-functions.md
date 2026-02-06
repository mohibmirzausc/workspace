# ADR 003: Prefer Arrow Functions Over Function Keyword

## Status
Accepted

## Context
TypeScript/JavaScript provides two main ways to define functions:

1. **Function declarations** (function keyword):
   ```typescript
   function foo() {
     return "bar";
   }
   ```

2. **Arrow functions** (lambda syntax):
   ```typescript
   const foo = () => {
     return "bar";
   };
   ```

These have different behaviors regarding hoisting, `this` binding, and usage patterns.

### Hoisting Behavior

**Function declarations are hoisted:**
```typescript
// This works - function is hoisted to top of scope
console.log(foo()); // "bar"

function foo() {
  return "bar";
}
```

**Arrow functions are not hoisted:**
```typescript
// This fails - ReferenceError: Cannot access 'foo' before initialization
console.log(foo());

const foo = () => {
  return "bar";
};
```

### `this` Binding

**Function declarations have dynamic `this`:**
```typescript
const obj = {
  value: 42,
  getValue: function() {
    return this.value; // 'this' depends on how function is called
  }
};
```

**Arrow functions have lexical `this`:**
```typescript
const obj = {
  value: 42,
  getValue: () => {
    return this.value; // 'this' is captured from surrounding scope
  }
};
```

## Decision
**Prefer arrow functions (`const foo = () => {}`) over function keyword (`function foo() {}`) for all function definitions.**

### Rules

1. **Module-level functions:** Use arrow functions assigned to `const`
   ```typescript
   // ✅ Preferred
   export const parseStatus = (text: string): string[] => {
     // ...
   };

   // ❌ Avoid
   export function parseStatus(text: string): string[] {
     // ...
   }
   ```

2. **Helper functions:** Use arrow functions assigned to `const`
   ```typescript
   // ✅ Preferred
   const validatePath = (path: string): boolean => {
     return path.length > 0;
   };

   // ❌ Avoid
   function validatePath(path: string): boolean {
     return path.length > 0;
   }
   ```

3. **Callbacks and inline functions:** Use arrow functions
   ```typescript
   // ✅ Already standard practice
   items.map(item => item.value);
   setTimeout(() => console.log("done"), 1000);
   ```

### Exceptions

**Methods in classes or object literals MAY use method shorthand:**
```typescript
// Acceptable - method shorthand in object
const obj = {
  getValue() {
    return this.value;
  }
};

// Acceptable - class methods
class Foo {
  getValue() {
    return this.value;
  }
}
```

These are not function declarations - they're method definitions with intentional `this` binding.

## Rationale

### Benefits

1. **Prevents unexpected hoisting:**
   - Arrow functions enforce declaration-before-use
   - Makes code order matter (more predictable)
   - Prevents subtle bugs from hoisting behavior

2. **Consistent `this` behavior:**
   - Lexical `this` is more predictable
   - Less confusion about what `this` refers to
   - Matches modern JavaScript best practices

3. **Consistency with modern JavaScript:**
   - Arrow functions are the standard in modern codebases
   - Aligns with React, Node.js, and TypeScript conventions
   - More commonly taught pattern

4. **Forces declaration order:**
   - Functions must be defined before use
   - Dependencies are explicit and visible
   - Code reads top-to-bottom naturally

5. **Easier refactoring:**
   - Moving arrow functions doesn't change behavior
   - Less risk of hoisting-related bugs
   - Consistent with `const` for immutability

### Why Not Function Keyword?

**Hoisting can cause subtle bugs:**
```typescript
// This works but is confusing - foo called before defined
const result = foo();

function foo() {
  return bar(); // bar not hoisted - ReferenceError!
}

const bar = () => "value";
```

**Dynamic `this` is error-prone:**
```typescript
function Counter() {
  this.count = 0;

  function increment() {
    this.count++; // 'this' is undefined in strict mode!
  }

  return { increment };
}
```

**Inconsistent with modern patterns:**
- Most modern TypeScript/JavaScript uses arrow functions
- React components use arrow functions
- Callbacks and promises use arrow functions

## Consequences

### Positive
- Predictable execution order (no hoisting surprises)
- Consistent `this` behavior across codebase
- Aligns with modern JavaScript practices
- Forces explicit dependency ordering

### Negative
- Cannot use function before its definition (but this is actually desired)
- Slightly longer syntax (`const foo = () => {}` vs `function foo() {}`)
- Stack traces show arrow functions as anonymous (minor debugging impact)

### Migration

**For existing code:**
1. Replace `function foo() {}` with `const foo = () => {}`
2. Ensure function is defined before first use
3. Update exports: `export function foo()` → `export const foo = () => {}`
4. Verify tests still pass

**Example migration:**
```typescript
// Before
export function parseChangedFiles(status: string): string[] {
  return parseLines(status);
}

function parseLines(status: string): string[] {
  return status.split('\n');
}

// After
const parseLines = (status: string): string[] => {
  return status.split('\n');
};

export const parseChangedFiles = (status: string): string[] => {
  return parseLines(status);
};
```

Note: Helper functions must be defined before functions that use them.

## Verification

Check for function declarations:
```bash
# Find function keyword usage (excluding class methods)
grep -n "^\s*function\s" api/src/**/*.ts
grep -n "^\s*export\s*function\s" api/src/**/*.ts
```

## References
- [MDN: Arrow functions](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Functions/Arrow_functions)
- [TypeScript Handbook: Functions](https://www.typescriptlang.org/docs/handbook/2/functions.html)
- [Airbnb JavaScript Style Guide: Prefer arrow callbacks](https://github.com/airbnb/javascript#arrow-functions)
- Modern JavaScript/TypeScript conventions (React, Next.js, Node.js)
