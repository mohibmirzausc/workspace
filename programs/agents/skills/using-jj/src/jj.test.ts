import { describe, test, expect } from "bun:test";
import { setRepository, getChangedFiles, getContext, cleanup, startTask, checkpoint, finishTask } from "./jj.js";
import { withJJ } from "./test-helpers.js";
import { resolve } from "node:path";
import { mkdirSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { execSync } from "child_process";

describe("setRepository", () => {
  describe("when repository path is invalid", () => {
    test("throws error when empty", async () => {
      await expect(
        setRepository({ repositoryPath: "" })
      ).rejects.toThrow("repositoryPath is required");
    });

    test("throws error when path doesn't exist", async () => {
      await expect(
        setRepository({ repositoryPath: "/nonexistent/path/to/repo" })
      ).rejects.toThrow("repository not found");
    });

    test("throws error when path exists but is not a jj repository", async () => {
      // Create a temporary directory that exists but has no .jj folder
      const tempDir = join(tmpdir(), `jj-test-not-repo-${Date.now()}`);
      mkdirSync(tempDir, { recursive: true });

      try {
        await expect(
          setRepository({ repositoryPath: tempDir })
        ).rejects.toThrow("repository not found");
      } finally {
        // Clean up
        rmSync(tempDir, { recursive: true, force: true });
      }
    });
  });

  describe("when repository path is valid", () => {
    test("returns currentChangeId from actual repository", async () => {
      // Use relative path from test file location to find the repository root
      const repoRoot = resolve(import.meta.dir, "..");

      const result = await setRepository({
        repositoryPath: repoRoot
      });

      expect(result).toHaveProperty("currentChangeId");
      expect(typeof result.currentChangeId).toBe("string");
      expect(result.currentChangeId.length).toBeGreaterThan(0);

      // Clean up after test to ensure isolation
      cleanup();
    });

    test("returns changedFiles array from actual repository", async () => {
      // Use relative path from test file location to find the repository root
      const repoRoot = resolve(import.meta.dir, "..");

      const result = await setRepository({
        repositoryPath: repoRoot
      });

      expect(result).toHaveProperty("changedFiles");
      expect(Array.isArray(result.changedFiles)).toBe(true);

      // Clean up after test to ensure isolation
      cleanup();
    });

    test("returns status with changeId and changedFiles from initialized repository", async () => {
      // Create a temporary directory
      const tempDir = join(tmpdir(), `jj-test-repo-${Date.now()}`);
      mkdirSync(tempDir, { recursive: true });

      try {
        // Initialize a real jj repo
        execSync(`jj git init "${tempDir}"`, { encoding: "utf8" });

        // Call setRepository
        const result = await setRepository({ repositoryPath: tempDir });

        // Verify the result
        expect(result).toBeDefined();
        expect(result.currentChangeId).toBeDefined();
        expect(typeof result.currentChangeId).toBe("string");
        expect(result.currentChangeId.length).toBeGreaterThan(0);
        expect(Array.isArray(result.changedFiles)).toBe(true);
      } finally {
        // Clean up
        rmSync(tempDir, { recursive: true, force: true });
      }
    });
  });
});

describe("getChangedFiles", () => {
  describe("when no repository is set", () => {
    test("throws error", async () => {
      // Ensure clean state
      cleanup();

      await expect(getChangedFiles()).rejects.toThrow("No repository set - call setRepository first");
    });
  });
});

describe("getContext", () => {
  describe("when no repository is set", () => {
    test("throws error", async () => {
      // Ensure clean state
      cleanup();

      await expect(getContext()).rejects.toThrow("No repository set - call setRepository first");
    });
  });

  describe("when repository is set", () => {
    test("returns current workflow state", async () => {
      const repoRoot = resolve(import.meta.dir, "..");

      // First set repository
      await setRepository({ repositoryPath: repoRoot });

      // Then get context
      const context = await getContext();

      // Should return current change ID
      expect(context).toBeDefined();
      expect(context.currentChangeId).toBeDefined();
      expect(typeof context.currentChangeId).toBe("string");

      // Clean up after test
      cleanup();
    });
  });
});

describe("cleanup", () => {
  describe("when called after setting repository", () => {
    test("clears the repository context", async () => {
      // Use relative path from test file location to find the repository root
      const repoRoot = resolve(import.meta.dir, "..");

      // First, set a repository
      await setRepository({
        repositoryPath: repoRoot
      });

      // Then cleanup
      cleanup();

      // Verify that getContext throws because repo is cleared
      await expect(getContext()).rejects.toThrow("No repository set - call setRepository first");
    });
  });
});

describe("startTask", () => {
  describe("when no repository is set", () => {
    test("throws error", async () => {
      cleanup();

      await expect(startTask({ description: "Test task" })).rejects.toThrow("No repository set - call setRepository first");
    });
  });

  describe("when repository is set", () => {
    describe("when current change has no description", () => {
      test("throws error when has changes", async () => {
        await withJJ(async (repoPath) => {
          // Add a file to create changes
          execSync(`touch "${repoPath}/test-file.txt"`, { encoding: "utf8" });

          await expect(startTask({ description: "Test task" })).rejects.toThrow("Current change has no description");
        });
      });

      test("describes current change when empty", async () => {
        await withJJ(async (repoPath) => {
          // Fresh jj repo: no description, no changes
          const result = await startTask({ description: "Test task" });

          // Should describe current change and create new working copy
          expect(result.changeId).toBeDefined();
          expect(result.wasEmpty).toBe(true);

          // Current change should be empty working copy
          const currentDesc = execSync(
            `jj log -r @ --no-graph -T 'description' --repository "${repoPath}"`,
            { encoding: "utf8" }
          ).trim();
          expect(currentDesc).toBe("");

          // Parent should have the task description
          const parentDesc = execSync(
            `jj log -r @- --no-graph -T 'description' --repository "${repoPath}"`,
            { encoding: "utf8" }
          ).trim();
          expect(parentDesc).toBe("Test task");
        });
      });
    });

    describe("when current change has description", () => {
    test("returns changeId", async () => {
      await withJJ(async (repoPath) => {
        execSync(`jj describe -m "Initial work" --repository "${repoPath}"`, { encoding: "utf8" });

        const result = await startTask({ description: "Test task" });

        expect(result.changeId).toBeDefined();
        expect(typeof result.changeId).toBe("string");
        expect(result.changeId.length).toBeGreaterThan(0);
      });
    });

    test("returns wasEmpty as boolean", async () => {
      await withJJ(async (repoPath) => {
        execSync(`jj describe -m "Initial work" --repository "${repoPath}"`, { encoding: "utf8" });

        const result = await startTask({ description: "Test task" });

        expect(typeof result.wasEmpty).toBe("boolean");
      });
    });

    test("returns wasEmpty false when changed files exist", async () => {
      await withJJ(async (repoPath) => {
        execSync(`jj describe -m "Initial work" --repository "${repoPath}"`, { encoding: "utf8" });
        // Create a file to have changed files
        execSync(`touch "${repoPath}/test-file.txt"`, { encoding: "utf8" });

        const result = await startTask({ description: "Test task" });

        expect(result.wasEmpty).toBe(false);
      });
    });

    test("returns wasEmpty true when no changed files", async () => {
      await withJJ(async (repoPath) => {
        execSync(`jj describe -m "Initial work" --repository "${repoPath}"`, { encoding: "utf8" });

        // Clean repo should have no changed files
        const result = await startTask({ description: "Test task" });

        expect(result.wasEmpty).toBe(true);
      });
    });

    test("creates described change and new working copy", async () => {
      await withJJ(async (repoPath) => {
        execSync(`jj describe -m "Initial work" --repository "${repoPath}"`, { encoding: "utf8" });

        const initialChangeId = execSync(
          `jj log -r @ --no-graph -T 'change_id' --repository "${repoPath}"`,
          { encoding: "utf8" }
        ).trim();

        const description = "Implement feature X";
        const result = await startTask({ description });

        // Current change (@) should be empty and have no description
        const currentDesc = execSync(
          `jj log -r @ --no-graph -T 'description' --repository "${repoPath}"`,
          { encoding: "utf8" }
        ).trim();
        expect(currentDesc).toBe("");

        // Parent change (@-) should have our task description
        const parentDesc = execSync(
          `jj log -r @- --no-graph -T 'description' --repository "${repoPath}"`,
          { encoding: "utf8" }
        ).trim();
        expect(parentDesc).toBe(description);

        // Result should return the current (empty) change ID
        expect(result.changeId).toBeDefined();
        expect(result.changeId).not.toBe(initialChangeId);
      });
    });
    });
  });
});

describe("checkpoint", () => {
  describe("when no repository is set", () => {
    test("throws error", async () => {
      cleanup();

      await expect(checkpoint({ summary: "Test work" })).rejects.toThrow("No repository set - call setRepository first");
    });
  });

  describe("when repository is set", () => {
    test("squashes working change into parent", async () => {
      await withJJ(async (repoPath) => {
        // Set up task workflow: described change with empty working copy
        execSync(`jj describe -m "Initial work" --repository "${repoPath}"`, { encoding: "utf8" });
        await startTask({ description: "Test task" });

        // Add some work to the working copy
        execSync(`touch "${repoPath}/test-file.txt"`, { encoding: "utf8" });

        // Verify working copy has changes
        const beforeChanges = await getChangedFiles();
        expect(beforeChanges.length).toBeGreaterThan(0);

        // Checkpoint
        await checkpoint({ summary: "Added test file" });

        // Verify working copy is now empty
        const afterChanges = await getChangedFiles();
        expect(afterChanges.length).toBe(0);

        // Verify parent change has the work using diff
        const parentDiff = execSync(
          `jj diff --repository "${repoPath}" -r @-`,
          { encoding: "utf8" }
        );
        expect(parentDiff).toContain("test-file.txt");
      });
    });

    test("appends summary as bullet point to parent description", async () => {
      await withJJ(async (repoPath) => {
        execSync(`jj describe -m "Initial work" --repository "${repoPath}"`, { encoding: "utf8" });
        await startTask({ description: "Test task" });

        // Checkpoint with summary
        await checkpoint({ summary: "Implemented feature X" });

        // Verify parent description has the bullet point appended
        const parentDesc = execSync(
          `jj log -r @- --no-graph -T 'description' --repository "${repoPath}"`,
          { encoding: "utf8" }
        ).trim();

        expect(parentDesc).toContain("Test task");
        expect(parentDesc).toContain("- Implemented feature X");
      });
    });

    test("preserves parent description when squashing", async () => {
      await withJJ(async (repoPath) => {
        execSync(`jj describe -m "Initial work" --repository "${repoPath}"`, { encoding: "utf8" });
        await startTask({ description: "Test task" });

        // First checkpoint
        execSync(`touch "${repoPath}/file1.txt"`, { encoding: "utf8" });
        await checkpoint({ summary: "Added file1" });

        // Second checkpoint - should preserve all previous description
        execSync(`touch "${repoPath}/file2.txt"`, { encoding: "utf8" });
        await checkpoint({ summary: "Added file2" });

        // Verify parent has both checkpoints
        const parentDesc = execSync(
          `jj log -r @- --no-graph -T 'description' --repository "${repoPath}"`,
          { encoding: "utf8" }
        ).trim();

        expect(parentDesc).toContain("Test task");
        expect(parentDesc).toContain("- Added file1");
        expect(parentDesc).toContain("- Added file2");
      });
    });
  });
});

describe("finishTask", () => {
  describe("when no repository is set", () => {
    test("throws error", async () => {
      cleanup();

      await expect(finishTask()).rejects.toThrow("No repository set - call setRepository first");
    });
  });

  describe("when repository is set", () => {
    test("moves to described change and creates new empty working copy", async () => {
      await withJJ(async (repoPath) => {
        execSync(`jj describe -m "Initial work" --repository "${repoPath}"`, { encoding: "utf8" });
        await startTask({ description: "Test task" });

        // Add work and checkpoint
        execSync(`touch "${repoPath}/test-file.txt"`, { encoding: "utf8" });
        await checkpoint({ summary: "Added test file" });

        // Finish task
        await finishTask();

        // Current change should be empty with no description
        const currentDesc = execSync(
          `jj log -r @ --no-graph -T 'description' --repository "${repoPath}"`,
          { encoding: "utf8" }
        ).trim();
        expect(currentDesc).toBe("");

        // Parent should be the described change with work
        const parentDesc = execSync(
          `jj log -r @- --no-graph -T 'description' --repository "${repoPath}"`,
          { encoding: "utf8" }
        ).trim();
        expect(parentDesc).toContain("Test task");
        expect(parentDesc).toContain("- Added test file");

        // Parent should have the work
        const parentDiff = execSync(
          `jj diff --repository "${repoPath}" -r @-`,
          { encoding: "utf8" }
        );
        expect(parentDiff).toContain("test-file.txt");
      });
    });
  });
});
