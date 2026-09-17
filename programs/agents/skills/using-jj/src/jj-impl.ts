/**
 * Private implementation details for jj API
 *
 * This file contains internal helper functions and state management.
 * These should not be imported directly by external consumers.
 */

import { $ } from "bun";

// Import types from public API
import type {
  SetRepositoryInput,
  RepositoryStatus,
  WorkflowContext,
  StartTaskInput,
  StartTaskResult,
  CheckpointInput,
} from "./jj.js";

/**
 * Module-level state to track current repository
 * @internal
 */
export let currentRepoPath: string | null = null;

/**
 * Set the current repository path
 * @internal
 */
export const setCurrentRepoPath = (path: string | null): void => {
  currentRepoPath = path;
};

/**
 * Parse changed files from jj status output
 * @internal
 *
 * @param statusText - Raw output from `jj status` command
 * @returns Array of file paths that have been added, modified, or deleted
 */
export const parseChangedFilesFromStatus = (statusText: string): string[] => {
  const changedFiles: string[] = [];
  for (const line of statusText.split('\n')) {
    if (line.startsWith('A ') || line.startsWith('M ') || line.startsWith('D ')) {
      const file = line.substring(2).trim();
      if (file) {
        changedFiles.push(file);
      }
    }
  }
  return changedFiles;
};

/**
 * Get current change ID from repository
 * @internal
 */
export const getCurrentChangeId = async (repoPath: string): Promise<string> => {
  const changeIdResult = await $`jj log -r @ --no-graph -T 'change_id' --repository ${repoPath}`.quiet();
  return changeIdResult.text().trim();
};

/**
 * Get status text from repository
 * @internal
 */
export const getStatusText = async (repoPath: string): Promise<string> => {
  const statusResult = await $`jj status --repository ${repoPath}`.quiet();
  return statusResult.text();
};

/**
 * Get description of current change
 * @internal
 */
export const getCurrentDescription = async (repoPath: string): Promise<string> => {
  const result = await $`jj log -r @ --no-graph -T 'description' --repository ${repoPath}`.quiet();
  return result.text().trim();
};

/**
 * Set description on current change
 * @internal
 */
export const setDescription = async (repoPath: string, description: string): Promise<void> => {
  await $`jj describe -m ${description} --repository ${repoPath}`.quiet();
};

/**
 * Create a new change on top of the current change
 * @internal
 */
export const createNewChange = async (repoPath: string): Promise<void> => {
  await $`jj new --repository ${repoPath}`.quiet();
};

/**
 * Squash current change into parent
 * @internal
 */
export const squashIntoParent = async (repoPath: string): Promise<void> => {
  // Get parent description to preserve it
  const parentDesc = await getParentDescription(repoPath);
  // Squash with -m flag to avoid opening editor and preserve description
  await $`jj squash -m ${parentDesc} --repository ${repoPath}`.quiet();
};

/**
 * Get description of parent change (@-)
 * @internal
 */
export const getParentDescription = async (repoPath: string): Promise<string> => {
  const result = await $`jj log -r @- --no-graph -T 'description' --repository ${repoPath}`.quiet();
  return result.text().trim();
};

/**
 * Set description on parent change (@-)
 * @internal
 */
export const setParentDescription = async (repoPath: string, description: string): Promise<void> => {
  await $`jj describe -m ${description} -r @- --repository ${repoPath}`.quiet();
};

/**
 * Abandon current working copy and move to parent
 * @internal
 */
export const abandonWorkingCopy = async (repoPath: string): Promise<void> => {
  // Move working copy to parent (jj edit @-)
  // This makes @- the new @ and the old @ becomes abandoned automatically
  await $`jj edit @- --repository ${repoPath}`.quiet();

  // Create a new empty working copy on top
  await createNewChange(repoPath);
};

/**
 * Implementation for setRepository
 * @internal
 */
export const setRepositoryImpl = async (
  input: SetRepositoryInput
): Promise<RepositoryStatus> => {
  // Validate input
  if (!input.repositoryPath) {
    throw new Error("repositoryPath is required");
  }

  try {
    // Get current change ID
    const currentChangeId = await getCurrentChangeId(input.repositoryPath);

    // Get changed files
    const statusText = await getStatusText(input.repositoryPath);
    const changedFiles = parseChangedFilesFromStatus(statusText);

    // Save repository path to module state
    setCurrentRepoPath(input.repositoryPath);

    return {
      currentChangeId,
      changedFiles
    };
  } catch (error) {
    // Preserve original error for debugging
    const originalError = error instanceof Error ? error.message : String(error);
    throw new Error(`repository not found at ${input.repositoryPath}: ${originalError}`);
  }
};

/**
 * Implementation for getContext
 * @internal
 */
export const getContextImpl = async (): Promise<WorkflowContext> => {
  if (!currentRepoPath) {
    throw new Error("No repository set - call setRepository first");
  }

  // Get current change ID using jj CLI
  const currentChangeId = await getCurrentChangeId(currentRepoPath);

  return {
    currentChangeId,
    phase: "ready", // TODO: Get from jj metadata
    description: "" // TODO: Get from jj description
  };
};

/**
 * Implementation for getChangedFiles
 * @internal
 */
export const getChangedFilesImpl = async (): Promise<string[]> => {
  if (!currentRepoPath) {
    throw new Error("No repository set - call setRepository first");
  }

  const statusText = await getStatusText(currentRepoPath);

  return parseChangedFilesFromStatus(statusText);
};

/**
 * Implementation for cleanup
 * @internal
 */
export const cleanupImpl = (): void => {
  setCurrentRepoPath(null);
};

/**
 * Implementation for startTask
 * @internal
 */
export const startTaskImpl = async (input: StartTaskInput): Promise<StartTaskResult> => {
  if (!currentRepoPath) {
    throw new Error("No repository set - call setRepository first");
  }

  // Check if current change has a description
  const currentDescription = await getCurrentDescription(currentRepoPath);

  // Check if working copy is empty before starting
  const statusText = await getStatusText(currentRepoPath);
  const changedFiles = parseChangedFilesFromStatus(statusText);
  const wasEmpty = changedFiles.length === 0;

  if (!currentDescription) {
    // If no description but has changes, can't proceed (would lose work)
    if (!wasEmpty) {
      throw new Error("Current change has no description");
    }

    // If no description and empty, describe current change and create working copy
    await setDescription(currentRepoPath, input.description);
    await createNewChange(currentRepoPath);
  } else {
    // Normal flow: current has description
    // Create new change (child of current)
    await createNewChange(currentRepoPath);

    // Set the description on this new change
    await setDescription(currentRepoPath, input.description);

    // Create another new change (child of described change) - this becomes working copy
    await createNewChange(currentRepoPath);
  }

  // Get the current (empty working) change ID
  const changeId = await getCurrentChangeId(currentRepoPath);

  return {
    changeId,
    wasEmpty,
  };
};

/**
 * Implementation for checkpoint
 * @internal
 */
export const checkpointImpl = async (input: CheckpointInput): Promise<void> => {
  if (!currentRepoPath) {
    throw new Error("No repository set - call setRepository first");
  }

  // Get parent description
  const parentDesc = await getParentDescription(currentRepoPath);

  // Append summary as bullet point
  const newDesc = parentDesc + "\n- " + input.summary;

  // Update parent description
  await setParentDescription(currentRepoPath, newDesc);

  // Squash working change (@) into parent change (@-)
  await squashIntoParent(currentRepoPath);
};

/**
 * Implementation for finishTask
 * @internal
 */
export const finishTaskImpl = async (): Promise<void> => {
  if (!currentRepoPath) {
    throw new Error("No repository set - call setRepository first");
  }

  // Abandon the empty working copy
  await abandonWorkingCopy(currentRepoPath);
};
