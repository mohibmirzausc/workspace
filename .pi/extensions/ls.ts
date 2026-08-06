import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { promises as fs } from "node:fs";
import * as path from "node:path";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "ls",
    label: "List directory",
    description:
      "List the contents of a directory. Returns names with type indicators " +
      "(/ for directories, @ for symlinks). Use this for quick directory " +
      "inspection instead of running `bash` with `ls`.",
    promptSnippet:
      "List directory contents with type indicators (faster than bash ls).",
    parameters: Type.Object({
      path: Type.String({
        description:
          "Absolute or relative path to the directory to list. Defaults to '.'",
      }),
      all: Type.Optional(
        Type.Boolean({
          description: "Include dotfiles (entries starting with '.')",
        }),
      ),
    }),

    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const target = path.isAbsolute(params.path)
        ? params.path
        : path.resolve(ctx.cwd, params.path);

      let entries;
      try {
        entries = await fs.readdir(target, { withFileTypes: true });
      } catch (err) {
        return {
          content: [
            {
              type: "text" as const,
              text: `ls failed: ${(err as Error).message}`,
            },
          ],
          isError: true,
          details: { path: target },
        };
      }

      const filtered = params.all
        ? entries
        : entries.filter((e) => !e.name.startsWith("."));

      filtered.sort((a, b) => a.name.localeCompare(b.name));

      const lines = filtered.map((e) => {
        if (e.isDirectory()) return `${e.name}/`;
        if (e.isSymbolicLink()) return `${e.name}@`;
        return e.name;
      });

      const text =
        lines.length === 0
          ? `(empty directory: ${target})`
          : `${target}:\n${lines.join("\n")}`;

      return {
        content: [{ type: "text" as const, text }],
        details: {
          path: target,
          count: filtered.length,
          entries: lines,
        },
      };
    },
  });
}
