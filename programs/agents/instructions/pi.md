## Mechanical Orchard security defaults

A safety baseline for Pi sessions on MO machines, carried over from mo-pi's managed block.

- Treat internet access as opt-in. Prefer local repository files, existing docs, and user-provided context before reaching for the network.
- Do not install packages or modify package manager state without explicit user confirmation. This includes `npm install`, `pnpm install`, `yarn add`, `pip install`, `pipx install`, `brew install`, `cargo install`, and similar commands.
- Do not use `curl | sh`, `wget | sh`, remote shell bootstrap scripts, or similar pipe-to-shell patterns. Download, inspect, and verify before executing anything fetched from the internet.
- Do not read credential or secret files unless the user explicitly asks and the need is clear. Examples include `.env`, `~/.ssh/*`, `~/.ai.env.toml`, `~/.secrets.nu`, and Pi auth files.
- Prefer small, reviewable changes over broad rewrites. If a command could affect files outside the current project, stop and ask first.
- If a tool or command unexpectedly asks for credentials, opens macOS Keychain, or prompts through a system credential helper, stop. That usually means the command was invoked through the wrong auth path.

These defaults are guardrails, not a substitute for thinking. If the user explicitly overrides one, follow their instruction for that task and keep the exception narrow.

## Subagents

When you launch subagents with pi-subagents:

- Run them in the background (`async: true`, the default). A foreground child runs inside your process
  without extensions: no shared memory and no guardrails.
- Name the agent type: `scout` for read-mostly reconnaissance (it returns a context summary), `worker` for
  implementation edits, `delegate` for a small general task. `claude-code`, `codex-exec` and `cursor-agent`
  run an external CLI outside Pi, its extensions and the shared memory: use them only when asked to.
- `scout`, `worker` and `delegate` can call `mem_log` and `mem_ask` (overrides in `home.nix`), but their
  prompts don't carry the memory guidance. When a child should record what it learns, say so in its task.
  Each child writes its own ledger file, linked to your session.
