/**
 * Command handlers for Autonomi Extension
 * Registers and implements all extension commands
 */

import * as vscode from 'vscode';
import { AutonomiTreeProvider } from './treeview/autonomi-tree-provider';
import { StatusBarController } from './status-bar';
import { AutonomiOutputChannel, LogLevel } from './output-channel';
import {
  showTaskInput,
  showDetailedTaskInput,
  showPlanApproval,
  showPlanDetails,
  showAgentSelection,
  showConfirmation
} from './quick-pick';
import {
  showError,
  showProgress,
  showCostWarning,
  showApprovalRequired,
  showLowConfidence
} from './notifications';
import { ExecutionState, Plan, Task, RARVPhase } from '../types/execution';
import { ConfidenceTier } from '../providers/types';

/**
 * Extension context interface for command handlers
 * This would typically be provided by the main extension class
 */
export interface AutonomiExtension {
  // Core components
  treeProvider: AutonomiTreeProvider;
  statusBar: StatusBarController;
  outputChannel: AutonomiOutputChannel;

  // State accessors
  getState(): ExecutionState;
  getCurrentPlan(): Plan | undefined;
  getCurrentTask(): Task | undefined;

  // Execution control
  start(task: string): Promise<void>;
  stop(): Promise<void>;
  pause(): Promise<void>;
  resume(): Promise<void>;

  // Plan operations
  generatePlan(task: string): Promise<Plan>;
  approvePlan(planId: string): Promise<void>;
  rejectPlan(planId: string): Promise<void>;

  // Task operations
  retryTask(taskId: string): Promise<void>;
  cancelTask(taskId: string): Promise<void>;
}

/**
 * Register all extension commands
 */
export function registerCommands(
  context: vscode.ExtensionContext,
  extension: AutonomiExtension
): void {
  // Core execution commands
  registerCommand(context, 'autonomi.start', async () => {
    const taskInput = await showDetailedTaskInput();
    if (!taskInput) {
      return;
    }

    try {
      await showProgress(
        'Starting Autonomi...',
        async (progress, token) => {
          progress.report({ message: 'Analyzing task...' });
          await extension.start(taskInput.description);
        },
        { cancellable: true }
      );
    } catch (error) {
      showError('Failed to start task', error as Error);
    }
  });

  registerCommand(context, 'autonomi.stop', async () => {
    const state = extension.getState();
    if (!state.isRunning) {
      vscode.window.showInformationMessage('Autonomi is not currently running');
      return;
    }

    const confirmed = await showConfirmation(
      'Stop all running tasks? This cannot be undone.',
      'Stop',
      'Cancel'
    );

    if (confirmed) {
      try {
        await extension.stop();
        extension.outputChannel.info('Execution stopped by user', 'Command');
        vscode.window.showInformationMessage('Autonomi stopped');
      } catch (error) {
        showError('Failed to stop execution', error as Error);
      }
    }
  });

  registerCommand(context, 'autonomi.pause', async () => {
    const state = extension.getState();
    if (!state.isRunning || state.isPaused) {
      vscode.window.showInformationMessage('Nothing to pause');
      return;
    }

    try {
      await extension.pause();
      extension.outputChannel.info('Execution paused by user', 'Command');
      vscode.window.showInformationMessage('Autonomi paused');
    } catch (error) {
      showError('Failed to pause execution', error as Error);
    }
  });

  registerCommand(context, 'autonomi.resume', async () => {
    const state = extension.getState();
    if (!state.isPaused) {
      vscode.window.showInformationMessage('Nothing to resume');
      return;
    }

    try {
      await extension.resume();
      extension.outputChannel.info('Execution resumed by user', 'Command');
      vscode.window.showInformationMessage('Autonomi resumed');
    } catch (error) {
      showError('Failed to resume execution', error as Error);
    }
  });

  // Plan commands
  registerCommand(context, 'autonomi.plan', async (taskDescription?: string) => {
    const task = taskDescription || await showTaskInput();
    if (!task) {
      return;
    }

    try {
      const plan = await showProgress(
        'Generating execution plan...',
        async (progress, token) => {
          progress.report({ message: 'Analyzing task requirements...' });
          return extension.generatePlan(task);
        },
        { cancellable: true }
      );

      if (plan) {
        // Show plan approval dialog
        const approved = await showPlanApproval(plan);
        if (approved) {
          await extension.approvePlan(plan.id);
          extension.outputChannel.info(`Plan approved: ${plan.id}`, 'Plan');
        } else {
          await extension.rejectPlan(plan.id);
          extension.outputChannel.info(`Plan rejected: ${plan.id}`, 'Plan');
        }
      }
    } catch (error) {
      showError('Failed to generate plan', error as Error);
    }
  });

  registerCommand(context, 'autonomi.approve', async () => {
    const plan = extension.getCurrentPlan();
    if (!plan) {
      vscode.window.showInformationMessage('No plan awaiting approval');
      return;
    }

    try {
      await extension.approvePlan(plan.id);
      extension.outputChannel.info(`Plan approved: ${plan.id}`, 'Command');
    } catch (error) {
      showError('Failed to approve plan', error as Error);
    }
  });

  registerCommand(context, 'autonomi.reject', async () => {
    const plan = extension.getCurrentPlan();
    if (!plan) {
      vscode.window.showInformationMessage('No plan to reject');
      return;
    }

    try {
      await extension.rejectPlan(plan.id);
      extension.outputChannel.info(`Plan rejected: ${plan.id}`, 'Command');
      vscode.window.showInformationMessage('Plan rejected');
    } catch (error) {
      showError('Failed to reject plan', error as Error);
    }
  });

  registerCommand(context, 'autonomi.viewPlan', async () => {
    const plan = extension.getCurrentPlan();
    if (!plan) {
      vscode.window.showInformationMessage('No active plan to view');
      return;
    }

    await showPlanDetails(plan);
  });

  // Configuration and settings
  registerCommand(context, 'autonomi.configure', async () => {
    vscode.commands.executeCommand(
      'workbench.action.openSettings',
      '@ext:autonomi'
    );
  });

  // Output and logging
  registerCommand(context, 'autonomi.showOutput', () => {
    extension.outputChannel.show(true);
  });

  registerCommand(context, 'autonomi.clearOutput', () => {
    extension.outputChannel.clear();
    vscode.window.showInformationMessage('Output cleared');
  });

  // Dashboard and views
  registerCommand(context, 'autonomi.openDashboard', () => {
    // This would open the WebView dashboard
    // For now, focus the TreeView
    vscode.commands.executeCommand('autonomiPanel.focus');
    vscode.window.showInformationMessage('Dashboard: Coming soon');
  });

  // Task-specific commands
  registerCommand(context, 'autonomi.showTaskDetails', async (taskId: string) => {
    extension.outputChannel.info(`Showing details for task: ${taskId}`, 'Command');
    // This would show task details in a WebView
    vscode.window.showInformationMessage(`Task details for ${taskId}: Coming soon`);
  });

  registerCommand(context, 'autonomi.viewTaskResult', async (taskId: string) => {
    extension.outputChannel.info(`Viewing result for task: ${taskId}`, 'Command');
    // This would show task result in a WebView
    vscode.window.showInformationMessage(`Task result for ${taskId}: Coming soon`);
  });

  registerCommand(context, 'autonomi.retryTask', async (taskId: string) => {
    try {
      await extension.retryTask(taskId);
      extension.outputChannel.info(`Retrying task: ${taskId}`, 'Command');
    } catch (error) {
      showError('Failed to retry task', error as Error);
    }
  });

  registerCommand(context, 'autonomi.cancelTask', async (taskId: string) => {
    const confirmed = await showConfirmation(
      'Cancel this task?',
      'Cancel Task',
      'Keep Running'
    );

    if (confirmed) {
      try {
        await extension.cancelTask(taskId);
        extension.outputChannel.info(`Task cancelled: ${taskId}`, 'Command');
      } catch (error) {
        showError('Failed to cancel task', error as Error);
      }
    }
  });

  // Agent selection
  registerCommand(context, 'autonomi.selectAgent', async () => {
    const agentType = await showAgentSelection();
    if (agentType) {
      vscode.window.showInformationMessage(`Selected agent: ${agentType}`);
      // This would be used when manually selecting an agent for a task
    }
  });

  // Cost and confidence details
  registerCommand(context, 'autonomi.showCostDetails', () => {
    const state = extension.getState();
    const cost = state.cost;

    const message = [
      `Task Cost: $${cost.taskCost.toFixed(4)} / $${cost.budgetTask.toFixed(2)}`,
      `Session Cost: $${cost.sessionCost.toFixed(4)} / $${cost.budgetSession.toFixed(2)}`,
      `Daily Cost: $${cost.dailyCost.toFixed(4)} / $${cost.budgetDaily.toFixed(2)}`
    ].join('\n');

    vscode.window.showInformationMessage(message, 'Adjust Budgets').then(action => {
      if (action === 'Adjust Budgets') {
        vscode.commands.executeCommand('autonomi.configure');
      }
    });
  });

  registerCommand(context, 'autonomi.showConfidenceDetails', () => {
    const state = extension.getState();
    const percentage = Math.round(state.confidence * 100);

    const tierDescriptions: Record<ConfidenceTier, string> = {
      [ConfidenceTier.TIER_1]: 'Auto-execute (simple tasks, >= 90%)',
      [ConfidenceTier.TIER_2]: 'Execute with validation (60-90%)',
      [ConfidenceTier.TIER_3]: 'Execute with full review (30-60%)',
      [ConfidenceTier.TIER_4]: 'Requires guidance (< 30%)'
    };

    const message = [
      `Confidence: ${percentage}%`,
      `Tier: ${state.confidenceTier}`,
      `Routing: ${tierDescriptions[state.confidenceTier]}`
    ].join('\n');

    vscode.window.showInformationMessage(message);
  });

  // Refresh TreeView
  registerCommand(context, 'autonomi.refresh', () => {
    extension.treeProvider.refresh();
  });

  // Quick task from selection
  registerCommand(context, 'autonomi.taskFromSelection', async () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showInformationMessage('No active editor');
      return;
    }

    const selection = editor.document.getText(editor.selection);
    if (!selection) {
      vscode.window.showInformationMessage('No text selected');
      return;
    }

    const task = await vscode.window.showInputBox({
      title: 'Task for Selection',
      prompt: 'What would you like to do with this code?',
      placeHolder: 'e.g., Refactor, Add tests, Explain, Optimize...',
      ignoreFocusOut: true
    });

    if (task) {
      const fullTask = `${task}:\n\`\`\`\n${selection}\n\`\`\``;
      vscode.commands.executeCommand('autonomi.plan', fullTask);
    }
  });

  // Register context menu command
  registerCommand(context, 'autonomi.contextMenu', async (uri: vscode.Uri) => {
    const items = [
      { label: 'Analyze File', command: 'autonomi.analyzeFile' },
      { label: 'Generate Tests', command: 'autonomi.generateTests' },
      { label: 'Add Documentation', command: 'autonomi.addDocs' },
      { label: 'Refactor', command: 'autonomi.refactorFile' }
    ];

    const selected = await vscode.window.showQuickPick(items, {
      title: 'Autonomi Actions',
      placeHolder: 'Select an action'
    });

    if (selected) {
      vscode.commands.executeCommand(selected.command, uri);
    }
  });

  // File-specific commands
  registerCommand(context, 'autonomi.analyzeFile', async (uri?: vscode.Uri) => {
    const filePath = uri?.fsPath || vscode.window.activeTextEditor?.document.uri.fsPath;
    if (!filePath) {
      vscode.window.showInformationMessage('No file to analyze');
      return;
    }

    vscode.commands.executeCommand('autonomi.plan', `Analyze and explain the code in ${filePath}`);
  });

  registerCommand(context, 'autonomi.generateTests', async (uri?: vscode.Uri) => {
    const filePath = uri?.fsPath || vscode.window.activeTextEditor?.document.uri.fsPath;
    if (!filePath) {
      vscode.window.showInformationMessage('No file selected');
      return;
    }

    vscode.commands.executeCommand('autonomi.plan', `Generate comprehensive unit tests for ${filePath}`);
  });

  registerCommand(context, 'autonomi.addDocs', async (uri?: vscode.Uri) => {
    const filePath = uri?.fsPath || vscode.window.activeTextEditor?.document.uri.fsPath;
    if (!filePath) {
      vscode.window.showInformationMessage('No file selected');
      return;
    }

    vscode.commands.executeCommand('autonomi.plan', `Add comprehensive JSDoc/documentation to ${filePath}`);
  });

  registerCommand(context, 'autonomi.refactorFile', async (uri?: vscode.Uri) => {
    const filePath = uri?.fsPath || vscode.window.activeTextEditor?.document.uri.fsPath;
    if (!filePath) {
      vscode.window.showInformationMessage('No file selected');
      return;
    }

    vscode.commands.executeCommand('autonomi.plan', `Refactor and improve code quality in ${filePath}`);
  });
}

/**
 * Helper to register a command with error handling
 */
function registerCommand(
  context: vscode.ExtensionContext,
  commandId: string,
  handler: (...args: unknown[]) => void | Promise<void>
): void {
  const wrappedHandler = async (...args: unknown[]) => {
    try {
      await handler(...args);
    } catch (error) {
      console.error(`Command ${commandId} failed:`, error);
      showError(`Command failed: ${commandId}`, error as Error);
    }
  };

  context.subscriptions.push(
    vscode.commands.registerCommand(commandId, wrappedHandler)
  );
}

/**
 * Get all registered command IDs
 */
export function getRegisteredCommands(): string[] {
  return [
    // Core execution
    'autonomi.start',
    'autonomi.stop',
    'autonomi.pause',
    'autonomi.resume',
    // Plan operations
    'autonomi.plan',
    'autonomi.approve',
    'autonomi.reject',
    'autonomi.viewPlan',
    // Configuration
    'autonomi.configure',
    // Output
    'autonomi.showOutput',
    'autonomi.clearOutput',
    // Dashboard
    'autonomi.openDashboard',
    // Task operations
    'autonomi.showTaskDetails',
    'autonomi.viewTaskResult',
    'autonomi.retryTask',
    'autonomi.cancelTask',
    // Agent
    'autonomi.selectAgent',
    // Details
    'autonomi.showCostDetails',
    'autonomi.showConfidenceDetails',
    // UI
    'autonomi.refresh',
    // Selection/context
    'autonomi.taskFromSelection',
    'autonomi.contextMenu',
    // File actions
    'autonomi.analyzeFile',
    'autonomi.generateTests',
    'autonomi.addDocs',
    'autonomi.refactorFile'
  ];
}
