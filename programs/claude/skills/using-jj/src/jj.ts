/**
 * jj-tool TypeScript API
 *
 * Simple TypeScript wrapper around jj CLI commands.
 *
 * USAGE:
 * Import and call functions directly:
 *
 *   import * as jj from './src/jj';
 *
 *   const status = await jj.setRepository({repositoryPath: "/path/to/repo"});
 *   const context = await jj.getContext();
 *   const files = await jj.getChangedFiles();
 *   jj.cleanup();
 */

import {
  setRepositoryImpl,
  getContextImpl,
  getChangedFilesImpl,
  cleanupImpl,
  startTaskImpl,
  checkpointImpl,
  finishTaskImpl,
} from "./jj-impl.js";

/**
 * Type definitions
 */

export interface SetRepositoryInput {
  repositoryPath: string;
}

export interface RepositoryStatus {
  currentChangeId: string;
  changedFiles: string[];
}

export interface WorkflowContext {
  currentChangeId: string;
  phase?: string;
  description?: string;
}

export interface StartTaskInput {
  description: string;
}

export interface StartTaskResult {
  changeId: string;
  wasEmpty: boolean;
}

export interface CheckpointInput {
  summary: string;
}

/**
 * Set the repository context for jj operations
 *
 * Validates the repository and retrieves current change information.
 *
 * @param input - Repository configuration
 * @returns Repository status with current change ID and changed files
 * @throws Error if repository path is invalid or not found
 */
export const setRepository = async (
  input: SetRepositoryInput
): Promise<RepositoryStatus> => {
  return setRepositoryImpl(input);
};

/**
 * Get the current workflow context
 *
 * Returns information about the current jj change and workflow state.
 *
 * @returns Workflow context with current change ID and phase
 * @throws Error if no repository is set
 */
export const getContext = async (): Promise<WorkflowContext> => {
  return getContextImpl();
};

/**
 * Get list of changed files in the current repository
 *
 * Returns array of file paths that have been added, modified, or deleted.
 *
 * @returns Array of changed file paths
 * @throws Error if no repository is set
 */
export const getChangedFiles = async (): Promise<string[]> => {
  return getChangedFilesImpl();
};

/**
 * Clears the current repository context
 *
 * Resets the module-level currentRepoPath to null, allowing a new repository
 * to be set or preventing operations when no repository is active.
 */
export const cleanup = (): void => {
  return cleanupImpl();
};

/**
 * Start a new task
 *
 * Creates a described change for the task and an empty working copy.
 * If current change is empty with no description, describes it instead.
 *
 * @param input - Task configuration with description
 * @returns Task result with change ID and whether it was empty
 * @throws Error if no repository is set or current change has no description with changes
 */
export const startTask = async (input: StartTaskInput): Promise<StartTaskResult> => {
  return startTaskImpl(input);
};

/**
 * Checkpoint current work
 *
 * Appends summary as bullet point to parent description, then squashes
 * the current working change into its parent described change.
 *
 * @param input - Checkpoint configuration with summary
 * @throws Error if no repository is set
 */
export const checkpoint = async (input: CheckpointInput): Promise<void> => {
  return checkpointImpl(input);
};

/**
 * Finish current task
 *
 * Moves to the parent described change and creates a new empty working copy.
 * This completes the task lifecycle.
 *
 * @throws Error if no repository is set
 */
export const finishTask = async (): Promise<void> => {
  return finishTaskImpl();
};
