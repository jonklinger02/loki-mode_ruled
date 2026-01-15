/**
 * Notification helpers for Autonomi Extension
 * Provides consistent notification patterns for cost warnings, approvals, completions, and errors
 */

import * as vscode from 'vscode';
import { Task, TaskResult, Plan, CostState } from '../types/execution';

// Notification configuration
interface NotificationConfig {
  showInStatusBar: boolean;
  autoHideMs?: number;
}

const DEFAULT_CONFIG: NotificationConfig = {
  showInStatusBar: true,
  autoHideMs: 5000
};

/**
 * Show cost warning notification
 * @param current Current cost
 * @param budget Budget limit
 * @param scope Cost scope (task, session, daily)
 */
export async function showCostWarning(
  current: number,
  budget: number,
  scope: 'task' | 'session' | 'daily' = 'session'
): Promise<void> {
  const percentage = Math.round((current / budget) * 100);
  const formattedCurrent = `$${current.toFixed(4)}`;
  const formattedBudget = `$${budget.toFixed(2)}`;

  const scopeLabel = scope.charAt(0).toUpperCase() + scope.slice(1);
  const message = `${scopeLabel} cost ${formattedCurrent} has reached ${percentage}% of budget (${formattedBudget})`;

  const action = await vscode.window.showWarningMessage(
    message,
    'View Details',
    'Adjust Budget',
    'Dismiss'
  );

  switch (action) {
    case 'View Details':
      vscode.commands.executeCommand('autonomi.showCostDetails');
      break;
    case 'Adjust Budget':
      vscode.commands.executeCommand('autonomi.configure');
      break;
  }
}

/**
 * Show budget exceeded notification (blocks execution)
 */
export async function showBudgetExceeded(
  current: number,
  budget: number,
  scope: 'task' | 'session' | 'daily' = 'task'
): Promise<'continue' | 'stop'> {
  const formattedCurrent = `$${current.toFixed(4)}`;
  const formattedBudget = `$${budget.toFixed(2)}`;

  const scopeLabel = scope.charAt(0).toUpperCase() + scope.slice(1);
  const message = `${scopeLabel} budget exceeded: ${formattedCurrent} / ${formattedBudget}. Execution paused.`;

  const action = await vscode.window.showErrorMessage(
    message,
    { modal: true },
    'Continue Anyway',
    'Stop Execution'
  );

  return action === 'Continue Anyway' ? 'continue' : 'stop';
}

/**
 * Show approval required notification
 */
export async function showApprovalRequired(
  task: Task,
  plan: Plan
): Promise<'approve' | 'reject' | 'modify'> {
  const costStr = `$${plan.totalEstimatedCost.toFixed(4)}`;
  const stepsStr = `${plan.steps.length} step${plan.steps.length !== 1 ? 's' : ''}`;

  const message = `Plan ready for "${task.title}": ${stepsStr}, est. ${costStr}`;

  const action = await vscode.window.showInformationMessage(
    message,
    { modal: false },
    'Approve',
    'View Plan',
    'Reject'
  );

  switch (action) {
    case 'Approve':
      return 'approve';
    case 'View Plan':
      // Show the plan details, then re-prompt for approval
      vscode.commands.executeCommand('autonomi.viewPlan');
      return 'modify';
    case 'Reject':
    default:
      return 'reject';
  }
}

/**
 * Show task completion notification
 */
export function showTaskComplete(
  task: Task,
  result: TaskResult
): void {
  const durationStr = formatDuration(result.duration);
  const costStr = result.cost !== undefined ? ` ($${result.cost.toFixed(4)})` : '';

  if (result.success) {
    const filesStr = result.filesModified?.length
      ? ` - ${result.filesModified.length} file${result.filesModified.length !== 1 ? 's' : ''} modified`
      : '';

    vscode.window.showInformationMessage(
      `Task completed: "${task.title}" in ${durationStr}${costStr}${filesStr}`,
      'View Changes',
      'Dismiss'
    ).then(action => {
      if (action === 'View Changes') {
        vscode.commands.executeCommand('autonomi.viewTaskResult', result.taskId);
      }
    });
  } else {
    vscode.window.showErrorMessage(
      `Task failed: "${task.title}" - ${result.error || 'Unknown error'}`,
      'View Details',
      'Retry',
      'Dismiss'
    ).then(action => {
      if (action === 'View Details') {
        vscode.commands.executeCommand('autonomi.viewTaskResult', result.taskId);
      } else if (action === 'Retry') {
        vscode.commands.executeCommand('autonomi.retryTask', task.id);
      }
    });
  }
}

/**
 * Show error notification
 */
export function showError(
  message: string,
  error?: Error,
  showReportOption: boolean = true
): void {
  const errorDetail = error?.message || '';
  const fullMessage = errorDetail
    ? `${message}: ${errorDetail}`
    : message;

  const actions: string[] = ['Dismiss'];
  if (showReportOption) {
    actions.unshift('Report Issue');
  }
  actions.unshift('Show Output');

  vscode.window.showErrorMessage(
    fullMessage,
    ...actions
  ).then(action => {
    switch (action) {
      case 'Show Output':
        vscode.commands.executeCommand('autonomi.showOutput');
        break;
      case 'Report Issue':
        // Open GitHub issues page
        vscode.env.openExternal(
          vscode.Uri.parse('https://github.com/asklokesh/autonomi-extension/issues/new')
        );
        break;
    }
  });
}

/**
 * Show progress notification with cancel option
 */
export async function showProgress<T>(
  title: string,
  task: (
    progress: vscode.Progress<{ message?: string; increment?: number }>,
    token: vscode.CancellationToken
  ) => Promise<T>,
  options: { cancellable?: boolean; location?: vscode.ProgressLocation } = {}
): Promise<T | undefined> {
  const { cancellable = true, location = vscode.ProgressLocation.Notification } = options;

  return vscode.window.withProgress(
    {
      title,
      location,
      cancellable
    },
    task
  );
}

/**
 * Show gate triggered notification
 */
export async function showGateTriggered(
  gateName: string,
  reason: string
): Promise<'override' | 'wait'> {
  const message = `Approval gate triggered: ${gateName}\n${reason}`;

  const action = await vscode.window.showWarningMessage(
    message,
    { modal: true },
    'Override (Admin)',
    'Wait for Approval'
  );

  return action === 'Override (Admin)' ? 'override' : 'wait';
}

/**
 * Show low confidence notification
 */
export async function showLowConfidence(
  confidence: number,
  taskTitle: string
): Promise<'proceed' | 'abort' | 'clarify'> {
  const percentage = Math.round(confidence * 100);
  const message = `Low confidence (${percentage}%) for task: "${taskTitle}". The system may need additional guidance.`;

  const action = await vscode.window.showWarningMessage(
    message,
    { modal: true },
    'Proceed Anyway',
    'Provide Clarification',
    'Abort Task'
  );

  switch (action) {
    case 'Proceed Anyway':
      return 'proceed';
    case 'Provide Clarification':
      return 'clarify';
    default:
      return 'abort';
  }
}

/**
 * Show session summary notification
 */
export function showSessionSummary(
  tasksCompleted: number,
  tasksFailed: number,
  totalCost: number,
  duration: number
): void {
  const costStr = `$${totalCost.toFixed(4)}`;
  const durationStr = formatDuration(duration);
  const successRate = tasksCompleted + tasksFailed > 0
    ? Math.round((tasksCompleted / (tasksCompleted + tasksFailed)) * 100)
    : 0;

  vscode.window.showInformationMessage(
    `Session complete: ${tasksCompleted} tasks completed, ${tasksFailed} failed (${successRate}% success) | Cost: ${costStr} | Duration: ${durationStr}`,
    'View Details',
    'Dismiss'
  ).then(action => {
    if (action === 'View Details') {
      vscode.commands.executeCommand('autonomi.openDashboard');
    }
  });
}

/**
 * Show agent handoff notification
 */
export function showAgentHandoff(
  fromAgent: string,
  toAgent: string,
  reason: string
): void {
  vscode.window.showInformationMessage(
    `Agent handoff: ${formatAgentName(fromAgent)} -> ${formatAgentName(toAgent)} (${reason})`,
    'View Details'
  ).then(action => {
    if (action === 'View Details') {
      vscode.commands.executeCommand('autonomi.showOutput');
    }
  });
}

/**
 * Show quality gate failure notification
 */
export async function showQualityGateFailure(
  gateName: string,
  issues: string[]
): Promise<'fix' | 'skip' | 'abort'> {
  const issueList = issues.slice(0, 3).join(', ');
  const moreCount = issues.length > 3 ? ` (+${issues.length - 3} more)` : '';

  const message = `Quality gate "${gateName}" failed: ${issueList}${moreCount}`;

  const action = await vscode.window.showErrorMessage(
    message,
    { modal: true },
    'Auto-Fix',
    'Skip Gate',
    'Abort Task'
  );

  switch (action) {
    case 'Auto-Fix':
      return 'fix';
    case 'Skip Gate':
      return 'skip';
    default:
      return 'abort';
  }
}

/**
 * Show secret detected warning
 */
export async function showSecretDetected(
  fileName: string,
  secretType: string
): Promise<'remove' | 'ignore' | 'abort'> {
  const message = `Potential secret detected in ${fileName}: ${secretType}`;

  const action = await vscode.window.showErrorMessage(
    message,
    { modal: true },
    'Remove Secret',
    'Ignore (Not a Secret)',
    'Abort Changes'
  );

  switch (action) {
    case 'Remove Secret':
      return 'remove';
    case 'Ignore (Not a Secret)':
      return 'ignore';
    default:
      return 'abort';
  }
}

// Utility functions

function formatDuration(ms: number): string {
  if (ms < 1000) {
    return `${ms}ms`;
  }
  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) {
    return `${seconds}s`;
  }
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return `${minutes}m ${remainingSeconds}s`;
  }
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return `${hours}h ${remainingMinutes}m`;
}

function formatAgentName(agentType: string): string {
  return agentType
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}
