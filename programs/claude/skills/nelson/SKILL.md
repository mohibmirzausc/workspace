# Nelson

A structured workflow for orchestrating complex, parallelizable tasks through a naval command framework.

## Core Phases

**1. Sailing Orders** establish outcome, metrics, deadlines, constraints, and scope boundaries using the Admiralty Templates.

**2. Squadron Formation** selects execution mode—`single-session` for sequential work, `subagents` for parallel scouting, or `agent-team` for coordinated multi-agent work—sized 1 admiral + 3-6 captains (max 10 total).

**3. Battle Plan** decomposes the mission into independent tasks with explicit ownership, dependencies, and file assignments, keeping one active task per agent unless multitasking is required.

**4. Quarterdeck Rhythm** maintains fixed-cadence checkpoints tracking task state (`pending`, `in_progress`, `completed`), blockers, token burn, and metric drift.

**5. Action Stations** enforces quality gates requiring verification evidence, test output, failure modes, and red-cell review before task completion.

**6. Stand Down** archives sessions and produces a captain's log documenting decisions, artifacts, validation evidence, and reusable patterns.

The underlying doctrine prioritizes mission throughput over equal distribution, replaces stalled agents proactively, keeps coordination terse, and escalates uncertainty early.
