## Mechanical Orchard security defaults

A safety baseline for Pi sessions on MO machines, carried over from mo-pi's managed block.

- Treat internet access as opt-in. Prefer local repository files, existing docs, and user-provided context before reaching for the network.
- Do not install packages or modify package manager state without explicit user confirmation. This includes `npm install`, `pnpm install`, `yarn add`, `pip install`, `pipx install`, `brew install`, `cargo install`, and similar commands.
- Do not use `curl | sh`, `wget | sh`, remote shell bootstrap scripts, or similar pipe-to-shell patterns. Download, inspect, and verify before executing anything fetched from the internet.
- Do not read credential or secret files unless the user explicitly asks and the need is clear. Examples include `.env`, `~/.ssh/*`, `~/.ai.env.toml`, `~/.secrets.nu`, and Pi auth files.
- Prefer small, reviewable changes over broad rewrites. If a command could affect files outside the current project, stop and ask first.
- If a tool or command unexpectedly asks for credentials, opens macOS Keychain, or prompts through a system credential helper, stop. That usually means the command was invoked through the wrong auth path.

These defaults are guardrails, not a substitute for thinking. If the user explicitly overrides one, follow their instruction for that task and keep the exception narrow.

## Don't trip the permission gate

pi-guardrails' permission gate stops any bash command it considers dangerous and waits for me to press a key.
For a hosted or unattended agent, that wait can last hours, because nobody is watching its window. A child
subagent has no window at all, so its command is simply blocked. Write commands that don't trigger it:

- **Never `rm -rf`, `rm -fr` or `rm -r -f`.** Any `rm` with both recursive and force flags triggers it, even on
  `/tmp`. Don't clean up scratch files at all: put them in `mktemp -d` or `/tmp` and leave them, since macOS clears
  them. If a delete is really needed, use `rm -r <path>` without `-f`, as its own command.
- Don't type `sudo` in a command: the gate stops it before my Touch ID prompt ever appears. Root work goes through a
  script I've approved that calls sudo itself, such as `install.sh`. Run it in the background (`run_background`, or
  `nohup … &`) and tell me to expect a Touch ID prompt. sudo uses Touch ID here, including inside tmux.
- Don't chain cleanup onto a check with `;` or `&&`. One flagged word in a long compound command blocks the
  whole thing.

If a command you need is flagged anyway, say so and ask me, rather than finding a way around the gate.

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
