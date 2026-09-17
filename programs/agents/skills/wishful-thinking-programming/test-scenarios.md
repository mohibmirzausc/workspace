# Test Scenarios for Wishful-Thinking Programming

## Scenario 1: Building API Integration with Unknown Client Library

**Context:**
You need to build a feature that fetches user data from an external API and transforms it for display. You've never used this API before, and you're not sure what client library exists or what the exact API shape is.

**Task:**
Implement a feature that:
1. Fetches user profile data from external API
2. Transforms it to internal format
3. Caches the result
4. Returns it to the controller

**Pressure:**
- Deadline: Feature demo tomorrow
- Don't know the API details yet
- Uncertainty about implementation approach

**What to observe:**
- Does agent start by researching the API first?
- Or do they write the ideal code and work backward?
- How do they handle uncertainty?

---

## Scenario 2: Payment Processing with Multiple Integrations

**Context:**
Build payment processing that needs to:
- Validate payment details
- Call payment gateway
- Handle webhooks
- Send confirmation emails
- Update order status

You don't know which payment gateway library to use or how email sending works in this codebase.

**Task:**
Implement the payment processing flow.

**Pressure:**
- Complex domain with many moving parts
- Multiple unknowns (gateway, email, etc.)
- Business logic is clear but infrastructure is not

**What to observe:**
- Do they get overwhelmed and research everything first?
- Or write the business logic as they wish it worked?
- How do they structure the work?

---

## Scenario 3: Data Pipeline with Uncertain Steps

**Context:**
Build a data processing pipeline:
1. Read data from source (CSV? DB? API?)
2. Validate and clean data
3. Transform to target format
4. Write to destination
5. Send notifications on completion

The business logic is clear but the technical details are uncertain.

**Task:**
Implement the pipeline.

**Pressure:**
- Middle step (transform) is well understood
- Edges (source/destination) are uncertain
- Need to start somewhere

**What to observe:**
- Where do they start? (beginning, middle, or end?)
- Do they write code before knowing source/destination?
- How do they handle the unknowns?

---

## Success Criteria

**With skill present, agent should:**
- ✓ Start from well-understood part (business logic, middle layer, or UX)
- ✓ Write code as if ideal utilities/APIs existed
- ✓ Use mocks to stand in for unknowns
- ✓ Let mocks define what collaborators should do
- ✓ Work outward from center of understanding
- ✓ Follow test-first approach (example-driven)

**Without skill, agent likely:**
- ✗ Starts by researching all unknowns first
- ✗ Gets blocked on infrastructure decisions
- ✗ Tries to make all decisions upfront
- ✗ Bottom-up instead of outside-in or middle-out
