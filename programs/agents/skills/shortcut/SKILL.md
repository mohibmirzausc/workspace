---
name: shortcut
description: Use when reading or updating Shortcut stories, epics, iterations or comments - fetch a story, search with Shortcut query syntax, list your open work, comment, or move a story to started. Use the `sc` CLI rather than a Shortcut MCP server.
---

# Shortcut

Use the `sc` CLI. It authenticates itself from the encrypted secrets store —
you do not need a token and must not ask the user for one.

```bash
sc me                      # current member (name, mention_name, id)
sc story <id>              # one story
sc search '<query>'        # Shortcut query syntax
sc mine                    # your stories that are not done
sc comment <id> '<text>'   # add a comment
sc start <id>              # move to the workflow's started state
sc raw <METHOD> <PATH>     # any API v3 call, e.g. sc raw GET /workflows
```

Output is JSON. Pipe to `jq` and select only the fields you need — story
objects are large, so requesting everything wastes context:

```bash
sc story 126509 | jq '{name, app_url, workflow_state_id}'
sc mine | jq '.data[] | {id, name}'
sc search 'owner:mohib.mirza state:"In Progress"' | jq '.data[].name'
```

`search` and `mine` return `{total, data: [...]}`; `story` returns the object
directly.

## Why a CLI and not MCP

The Shortcut MCP server registers ~45 tool definitions, which cost roughly
11k–29k tokens in *every* request whether or not Shortcut is used. This skill
plus `sc` costs a few hundred tokens and is only read when relevant.

## Notes

- Mutating commands (`comment`, `start`) change real stories. Confirm the
  story id before running them.
- For anything the subcommands do not cover, use `sc raw`. The API reference
  is at <https://developer.shortcut.com/api/rest/v3>.
