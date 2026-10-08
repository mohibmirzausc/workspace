# Global agent instructions

Every harness gets one global instructions file, assembled by Home Manager from
the files here (`agentInstructions` in `home.nix`):

| Harness     | Built from                 | Installed at           |
|-------------|----------------------------|------------------------|
| Claude Code | `shared.md` + `claude.md`  | `~/.claude/CLAUDE.md`  |
| Pi          | `shared.md` + `pi.md`      | `~/.pi/agent/AGENTS.md` |

- **`shared.md`**: rules for every agent, whatever the harness (cmux naming, `rg`).
- **`<harness>.md`**: rules for that harness only. `pi.md` has the Mechanical Orchard
  security defaults and how to launch subagents. `claude.md` is empty for now;
  an empty file adds nothing, so Claude gets exactly `shared.md`.

The shared part comes first, then the harness part, joined with a blank line, under a
one-line "generated, edit the sources" comment. Edit the files here and rebuild;
the installed files are read-only links into the Nix store.

To add a harness, write `<harness>.md` if it needs one and add a `home.file` entry
using `agentInstructions "<harness>"`.

Not here: instructions that belong to a tool. The memory system's Pi extension
carries its own guidance (in its tool definitions), so it is present exactly when
the extension is loaded.
