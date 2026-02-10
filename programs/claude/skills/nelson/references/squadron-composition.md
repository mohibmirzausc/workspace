# Squadron Composition Reference

Use this file to choose execution mode and team size.

## Mode Selection

Choose the first condition that matches.

1. If work is sequential, tightly coupled, or mostly in the same files, use `single-session`.
2. If work is parallel but each worker only needs to report to admiral, use `subagents`.
3. If workers must coordinate directly across task boundaries, use `agent-team`.

## Decision Matrix

| Condition | Preferred Mode | Why |
| --- | --- | --- |
| Single critical path, low ambiguity | `single-session` | Lowest coordination overhead |
| Parallel discovery, synthesis by admiral | `subagents` | Fast throughput without peer chatter |
| Parallel implementation with dependencies | `agent-team` | Supports teammate-to-teammate coordination |
| High threat or high blast radius | `agent-team` + red-cell navigator | Adds explicit control points |

## Team Sizing (up to 10 total)

- Small mission: `1 admiral + 2-3 captains`.
- Medium mission: `1 admiral + 4-5 captains`.
- Large mission: `1 admiral + 6-7 captains`.
- Add `1 red-cell navigator` at medium/high threat.
- Keep one admiral only.

## Role Guide

- `admiral`: Defines sailing orders, delegates, tracks dependencies, resolves blockers, final synthesis.
- `captain`: Owns assigned task and artifacts.
- `red-cell navigator`: Challenges assumptions, validates outputs, checks rollback readiness.

## Anti-Patterns

- Creating teams for work that is mostly linear.
- Splitting one file across multiple captains.
- Letting red cell become a ticket queue.
- Adding agents without reducing critical path length.
