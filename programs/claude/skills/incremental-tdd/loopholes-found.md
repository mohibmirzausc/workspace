# Loopholes Found During Testing

## Loophole 1: Authority Pressure
**Test**: Senior engineer says "write all 5 tests first"
**Result**: (Test interrupted)

## Loophole 2: Planning Pressure
**Test**: "Let's plan the tests first, then write all of them"
**Result**: (Test interrupted)

## Loophole 3: Best Practices Appeal
**Test**: "Best practices say comprehensive coverage - write thorough test suite"
**Result**: Agent wrote 40+ tests organized in 11 categories, all at once

**Rationalization used**:
- "Comprehensive test suite"
- "Best practices applied"
- "TDD principles" (misunderstood as "all tests first")
- Created elaborate organizational structure

**Key insight**: Agent confused "comprehensive coverage" (goal) with "write all tests at once" (method). The skill needs to explicitly counter this.

## Loophole 4: Time Pressure
**Test**: "URGENT production bug, need this FAST"
**Result**: From earlier test - jumped straight to implementation, used existing 5-test file

**Rationalization**: "It's urgent, so batch approach is acceptable"

## Common Pattern

All loopholes involve reframing batch testing as actually following good practices:
- "Comprehensive is better"
- "Planning ahead is smart"
- "Authority says so"
- "Efficiency matters"

The skill needs explicit counters for each rationalization.
