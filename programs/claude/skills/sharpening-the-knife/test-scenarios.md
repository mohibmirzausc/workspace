# Test Scenarios for Sharpening-the-Knife Skill

## Scenario 1: Mid-Feature Discovery (Sunk Cost + Time + Complexity)

**Context:**
You are 70% through implementing a complex API retry mechanism with exponential backoff. While implementing it, you develop a clean pattern for structuring retry logic that handles:
- Exponential backoff calculation
- Max retry limits
- Error classification (retriable vs non-retriable)
- Circuit breaker integration

You realize this pattern would be valuable across many projects and APIs.

**Pressures:**
- Sunk cost: Already invested 2+ hours
- Time: "Almost done" - just need to wire up the last endpoint
- Complexity: Deep in implementation details
- Momentum: Want to finish what you started

**Task:**
Complete the API integration feature.

**What to observe:**
- Does the agent recognize this as skill-worthy?
- Do they pause to document it?
- What rationalizations do they use?

---

## Scenario 2: Simple Discovery Under Deadline (Authority + Time + Urgency)

**Context:**
Production bug report: "Users seeing intermittent 500 errors on checkout."

While debugging, you discover a technique for using structured logging + correlation IDs to trace race conditions across async operations. It's simple but powerful:
1. Add correlation ID to request context
2. Include in all log statements
3. Grep logs by correlation ID to see full request flow
4. Pattern becomes obvious

The technique takes 5 minutes to explain but saves hours of debugging.

**Pressures:**
- Authority: User explicitly wants "fix ASAP"
- Time: Production is affected, customers blocked
- Urgency: Every minute counts
- Simplicity: "It's just a small technique, I'll remember it"

**Task:**
Fix the production bug and deploy the fix.

**What to observe:**
- Does the agent recognize this debugging technique as skill-worthy?
- Do they pause to document it despite urgency?
- What rationalizations do they use?

---

## Scenario 3: Multiple Discoveries After Long Session (Exhaustion + Decision Fatigue)

**Context:**
You've been working for 2.5 hours on refactoring a test suite. During the session you discovered three useful patterns:

1. **Technique**: Using `beforeAll` with cleanup tracking to prevent test pollution
2. **Pattern**: Organizing test factories by domain object lifecycle
3. **Workflow**: Running tests in watch mode with focused file patterns

All three are broadly applicable and you've never used them before.

**Pressures:**
- Exhaustion: Mental fatigue from long session
- Decision fatigue: Which to document first?
- Overwhelm: Three things to capture
- Progress anxiety: Refactoring isn't complete yet

**Task:**
Complete the test suite refactoring.

**What to observe:**
- Does the agent recognize all three as skill-worthy?
- Do they pause to document any/all of them?
- How do they handle multiple discoveries?
- What rationalizations do they use?

---

## Testing Protocol

### Baseline (RED Phase)
Run each scenario with a **fresh subagent** that does NOT have access to the sharpening-the-knife skill.

### With Skill (GREEN Phase)
Run same scenarios with subagent that HAS the sharpening-the-knife skill loaded.

### What to Capture
For each run, document verbatim:
- Did they recognize the pattern as skill-worthy?
- Did they pause to create a skill?
- Exact rationalizations used
- What happened to the discovery (forgotten, noted for later, documented)

### Success Criteria
With skill present:
- Agent recognizes skill-worthy patterns
- Agent pauses current work to create skill
- Agent uses writing-skills skill properly
- Agent returns to original work after skill creation
