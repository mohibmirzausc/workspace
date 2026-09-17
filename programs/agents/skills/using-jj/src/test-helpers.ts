/**
 * Test helper utilities for jj-tool tests
 */

import { mkdirSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { execSync } from "child_process";
import { setRepository, cleanup } from "./jj.js";

/**
 * Create a temporary jj repository and run a test function within its context
 *
 * Automatically handles:
 * - Creating temp directory
 * - Initializing jj repo
 * - Setting repository context
 * - Cleaning up temp directory and context after test
 *
 * @param testFn - Test function that receives the temp repo path
 *
 * @example
 * ```typescript
 * await withJJ(async (repoPath) => {
 *   const result = await startTask({ description: "Test" });
 *   expect(result.changeId).toBeDefined();
 * });
 * ```
 */
export const withJJ = async (
  testFn: (repoPath: string) => Promise<void>
): Promise<void> => {
  const tempDir = join(tmpdir(), `jj-test-repo-${Date.now()}`);
  mkdirSync(tempDir, { recursive: true });

  try {
    // Initialize a jj repository
    execSync(`jj git init "${tempDir}"`, { encoding: "utf8" });

    // Set repository context
    await setRepository({ repositoryPath: tempDir });

    // Run the test function
    await testFn(tempDir);

    // Clean up repository context
    cleanup();
  } finally {
    // Always clean up temp directory
    rmSync(tempDir, { recursive: true, force: true });
  }
};
