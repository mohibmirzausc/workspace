# REFACTOR Phase - Loophole Analysis

## Loopholes to Check

### 1. "This is project-specific, not broadly reusable"

**Current guidance:** "Create something reusable across projects"

**Potential loophole:** Agent rationalizes that pattern is only useful in current project

**Fix needed?** YES - clarify that project-specific valuable patterns can go in CLAUDE.md or project docs

---

### 2. "I don't have bd / capture system"

**Current guidance:** Assumes bd exists for capture tasks

**Potential loophole:** Agent says "can't create bd task, so I'll just remember"

**Fix needed?** YES - provide fallback (markdown note, todo system, etc.)

---

### 3. "This is TOO simple/obvious"

**Current guidance:** "Simple techniques are EASIEST to forget"

**Potential loophole:** "But this is SO simple it's not worth documenting"

**Fix needed?** Maybe - add minimum threshold or emphasize that simple = MORE reason to document

---

### 4. "I'm not sure if this is skill-worthy"

**Current guidance:** Clear checklist of when to pause

**Potential loophole:** "I recognized something but not sure it meets criteria"

**Fix needed?** Maybe - add "when in doubt, create capture" rule

---

## Analysis from GREEN Tests

**Good news:** No new rationalizations emerged!

All three agents:
- Followed the decision rule
- Didn't find loopholes
- Complied with guidance

**This suggests the skill is robust for v1.**

## Recommendations

### Must Fix
1. Add fallback for no-bd situation
2. Clarify project-specific patterns (CLAUDE.md)

### Nice to Have
3. Add "when in doubt, capture" rule
4. Emphasize simple patterns MORE explicitly

### Not Needed
- The "too simple" rationalization is already addressed well
- Time estimates seem reasonable
- Urgency exception is clear

---

## Proposed Refinements

### Addition 1: Alternative Capture Mechanisms

Add to "Handling Multiple Discoveries" section:

```markdown
## Capture Mechanisms

**If using bd:**
```bash
bd create "Document [pattern-name] skill" -t task -p 1
```

**If not using bd:**
- Create markdown note with pattern details
- Add to project TODO.md
- Create GitHub/GitLab issue
- Use any task tracking system

**Key:** External capture that creates commitment.
```

### Addition 2: Project-Specific Patterns

Add to "When to Pause" section:

```markdown
**For project-specific patterns:**
- Broadly reusable → Create skill
- Project-specific → Document in CLAUDE.md or README
- Either way: PAUSE and capture now
```

### Addition 3: When in Doubt Rule

Add to "The Decision Rule" section:

```markdown
**Uncertain if skill-worthy?**
Create capture anyway. Takes 2 minutes. Better to capture and decide later than lose the insight.
```

---

## Testing Plan for Refinements

Would need to re-run scenarios with agents trying to use these loopholes:

1. "No bd system available"
2. "Pattern is project-specific"
3. "Not sure if worthy"

But given GREEN phase success, these are minor enhancements, not critical fixes.

**Decision:** Apply refinements to strengthen skill, but it's already functional.
