# Test Scenario: Batch Test Writing

## Pressure Scenario

**Context**: Agent is implementing a feature using TDD. They need to refactor a function to accept parameters.

**Prompt**:
```
We need to refactor renderDashboard() to accept an apps array instead of using hardcoded data. Use TDD to do this.
```

**Expected Violation** (without skill):
Agent writes multiple test cases at once (3-4 tests covering different scenarios) before implementing anything.

**Expected Behavior** (with skill):
Agent writes ONE simple test, implements minimal code to pass it, then considers next test.

## Baseline Test (RED Phase)

Run this with a subagent WITHOUT the incremental-tdd skill present.

**Setup**:
- Simple codebase with function that uses hardcoded data
- Agent knows TDD principles
- Task: Refactor to accept data parameter

**Document**:
- Did agent write multiple tests at once?
- What rationalizations did they use?
  - "comprehensive coverage"
  - "testing all scenarios"
  - "being thorough"
- Did they recognize the problem themselves?

## Success Criteria (GREEN Phase)

With skill present:
- Agent writes exactly ONE test
- Implements minimal code to pass it
- Only then considers next test
- Explicitly mentions incremental approach
