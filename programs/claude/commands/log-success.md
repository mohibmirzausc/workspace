# Log Success

You are helping the user log a success/win that occurred during agentic coding. Most people skip this - they only log failures. But understanding WHY things work is just as important as why they fail. Capture what went RIGHT.

## Logs Directory

All logs are stored in: `~/.claude/claude_accessible/agentic-practice-logs/`
- Successes: `/successes/success-XXX.md`
- Metadata (for ID tracking): `/metadata.json`

⚠️ **IMPORTANT: Privacy Considerations**
- DO NOT include sensitive information (API keys, passwords, credentials, personal data)
- Be mindful of private file paths that reveal sensitive system information

## Your Task

1. **First, review the recent conversation context** to understand what went notably well. Look for:
   - What task was accomplished smoothly
   - What approach was used that worked well
   - Any moments where something just clicked
   - Unusually fast completion
   - First-try successes
   - Elegant solutions
   - Minimal intervention needed
   - Good tool/command usage

2. **Ask 4-6 clarifying questions** to extract WHY it worked. Be SPECIFIC to what actually happened. Examples:
   - "That auth flow came together in under 20 minutes. What about the prompt setup made it work so smoothly?"
   - "You didn't have to correct me once during the refactor. Was that luck or did the context in CLAUDE.md help?"
   - "The solution I suggested was cleaner than what you initially had in mind. What made it click?"

   Questions should cover:
   - **What specifically went well:** Not generic "it worked" but precise win
   - **Why it worked:** The contributing factors
   - **The setup:** What context/prompt/approach was used
   - **Key ingredient:** What was the one thing that made the difference?
   - **Reproducibility:** Could you do this again? Should this become standard practice?

3. **Trace the triggering prompt**: After the interview, identify and quote the EXACT user prompt(s) that led to this success. This is critical for understanding what instruction produced the win. Ask the user to confirm or paste the exact prompt if you can't find it in context.

4. **After getting answers**, read metadata.json to get the next success ID, then create the log file.

5. **Update metadata.json** with the incremented counter.

6. **Commit and push the log**:
   - First, `cd ~/.claude/claude_accessible/agentic-practice-logs && git pull origin main` to get the latest state and avoid merge conflicts
   - Read metadata.json to get the next success ID
   - Create the success log file: `~/.claude/claude_accessible/agentic-practice-logs/successes/success-XXX.md`
   - Update metadata.json with incremented nextSuccessId, totalSuccesses, and current timestamp for lastUpdated
   - Use Bash tool to git add, commit with message: "Log success #XXX: [Short descriptive name]", and push to main
   - IMPORTANT: Do NOT initialize a new git repo - the repo should already exist with remote configured via home-manager
   - If push fails, the commit will remain local (silent failure - no warnings to user)

## Log Template

```markdown
# Success #[ID]: [Short Descriptive Name]

**Date:** [Date]
**Project/Context:** [What were you working on]

## What Went Well
[2-3 sentences - what succeeded specifically]

## Success Category
**Primary factor:** [Pick ONE or TWO]

### Prompt Excellence
- [ ] **Crystal clear instruction** - No ambiguity, single interpretation
- [ ] **Explicit constraints** - Specified what NOT to do upfront
- [ ] **Right level of detail** - Not too verbose, not too sparse
- [ ] **Requirements not reference** - Gave actionable requirements, not documentation dumps
- [ ] **Clear success criteria** - Defined what "done" looks like
- [ ] **Perfect abstraction level** - Matched the task complexity

### Context Excellence
- [ ] **Fresh context** - Conversation was /cleared at right time
- [ ] **Relevant context only** - No noise, all signal
- [ ] **Right amount of context** - Not too much, not too little
- [ ] **Well-structured CLAUDE.md** - Project context file helped
- [ ] **Good memory management** - Reminded Claude at right moments

### Harness Excellence
- [ ] **Right agent for job** - Chose specialized agent appropriately
- [ ] **Good guardrails** - Constrained behavior effectively
- [ ] **Smart parallelization** - Used parallel agents when appropriate
- [ ] **Proper validation** - Checked agent output appropriately
- [ ] **Context passed correctly** - Subagents received critical info

### Execution Excellence
- [ ] **Asked clarifying questions** - Caught issues early
- [ ] **Planned before implementing** - Used /plan or similar
- [ ] **Verified before claiming done** - Ran tests, checked output
- [ ] **Good tool selection** - Used right tools for the job

## The Triggering Prompt
```
[Exact prompt - verbatim]
```

## Why This Prompt Worked
[Be specific. What made this effective?]

## Key Ingredients
1. [What was the most important factor]
2. [What was the second most important factor]
3. [Any other critical elements]

## The Win
- **Expected outcome:** [What you hoped for]
- **Actual outcome:** [What you got]
- **Why it exceeded expectations:** [If it did]

## Impact
- **Time saved:** [X minutes compared to alternatives]
- **Quality improvement:** [Better than usual in what way]
- **Learning captured:** [What new insight emerged]

## Reproducibility - Action Items
1. [Specific thing to do again next time]
2. [Another repeatable action]
3. [Consider adding to personal CLAUDE.md or workflow template]

## Pattern Check
- **First time success?** [Yes/No - is this a new pattern to cultivate?]
- **Repeatable?** [Can you do this consistently?]
- **Should this become standard?** [Add to your regular workflow?]

## One-Line Win (for the USER)
[What you did right that you should keep doing]

---
*Logged on [timestamp]*
```

## Important

- Be SPECIFIC about what worked - vague praise is useless
- Focus on USER actions that led to success
- The goal is to make successes REPEATABLE
- Extract patterns that can become habits
- Help the user understand their own effectiveness
