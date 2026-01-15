/**
 * Main extension class for Autonomi VSCode Extension
 */

import * as vscode from 'vscode';
import { v4 as uuidv4 } from 'uuid';
import { StateManager } from './state/state-manager';
import { ConfigManager } from './config/config-manager';
import { Logger, LogLevel } from './utils/logger';
import { TaskQueue } from './utils/task-queue';
import {
  ExecutionState,
  Task,
  Plan,
  RARVPhase,
  AgentType,
  TaskStatus,
  PlanStep
} from './types/execution';
import { ConfidenceTier } from './providers/types';

// Forward declarations for components to be implemented
interface AgentOrchestrator {
  executeTask(task: Task, plan: Plan): Promise<void>;
  stop(): Promise<void>;
  dispose(): void;
}

interface ProviderManager {
  initialize(): Promise<void>;
  getPreferredProvider(): string;
  dispose(): void;
}

interface CostTracker {
  getSessionCost(): number;
  addCost(cost: number): void;
  checkBudget(): { exceeded: boolean; budget: string; current: number; limit: number };
  dispose(): void;
}

interface PlanGenerator {
  generatePlan(task: Task): Promise<Plan>;
  dispose(): void;
}

interface ApprovalManager {
  requiresApproval(plan: Plan): boolean;
  requestApproval(plan: Plan): Promise<boolean>;
  dispose(): void;
}

interface ConfidenceCalculator {
  calculate(task: Task): Promise<{ confidence: number; tier: ConfidenceTier }>;
  dispose(): void;
}

interface AutonomiTreeProvider extends vscode.TreeDataProvider<unknown> {
  refresh(): void;
  dispose(): void;
}

interface StatusBarController {
  update(state: ExecutionState): void;
  dispose(): void;
}

/**
 * Main Autonomi Extension class
 */
export class AutonomiExtension implements vscode.Disposable {
  private readonly context: vscode.ExtensionContext;
  private stateManager: StateManager;
  private configManager: ConfigManager;
  private taskQueue: TaskQueue;
  private outputChannel: vscode.OutputChannel;
  private disposables: vscode.Disposable[] = [];

  // Components (initialized lazily)
  private treeProvider: AutonomiTreeProvider | undefined;
  private statusBar: StatusBarController | undefined;
  private orchestrator: AgentOrchestrator | undefined;
  private providerManager: ProviderManager | undefined;
  private costTracker: CostTracker | undefined;
  private planGenerator: PlanGenerator | undefined;
  private approvalManager: ApprovalManager | undefined;
  private confidenceCalculator: ConfidenceCalculator | undefined;

  constructor(context: vscode.ExtensionContext) {
    this.context = context;
    this.outputChannel = vscode.window.createOutputChannel('Autonomi');
    this.stateManager = new StateManager(context);
    this.configManager = new ConfigManager(context);
    this.taskQueue = new TaskQueue();
    this.disposables.push(this.outputChannel);
  }

  /**
   * Initialize the extension
   */
  async initialize(): Promise<void> {
    // 1. Initialize logger
    const logLevel = this.getLogLevel();
    Logger.initialize(this.outputChannel, logLevel);
    Logger.info('Initializing Autonomi extension...');

    try {
      // 2. Restore state if resuming
      await this.stateManager.restore();

      // 3. Register commands
      this.registerCommands();

      // 4. Set up UI components
      await this.setupUI();

      // 5. Set up event listeners
      this.setupEventListeners();

      // 6. Initialize providers (lazy - will init when first task starts)
      Logger.info('Autonomi extension initialized successfully');
    } catch (error) {
      Logger.error('Failed to initialize extension', error as Error);
      throw error;
    }
  }

  /**
   * Get log level from configuration
   */
  private getLogLevel(): LogLevel {
    const level = this.configManager.getLogLevel();
    switch (level.toLowerCase()) {
      case 'debug': return LogLevel.DEBUG;
      case 'info': return LogLevel.INFO;
      case 'warn': return LogLevel.WARN;
      case 'error': return LogLevel.ERROR;
      default: return LogLevel.INFO;
    }
  }

  /**
   * Register extension commands
   */
  private registerCommands(): void {
    const commands = [
      { id: 'autonomi.startTask', handler: () => this.promptAndStartTask() },
      { id: 'autonomi.stopTask', handler: () => this.stopTask() },
      { id: 'autonomi.approvePlan', handler: () => this.approvePlan() },
      { id: 'autonomi.rejectPlan', handler: () => this.rejectPlan() },
      { id: 'autonomi.showOutput', handler: () => this.outputChannel.show() },
      { id: 'autonomi.configureApiKeys', handler: () => this.configureApiKeys() },
      { id: 'autonomi.showStatus', handler: () => this.showStatus() },
      { id: 'autonomi.clearQueue', handler: () => this.clearQueue() },
      { id: 'autonomi.openSettings', handler: () => vscode.commands.executeCommand('workbench.action.openSettings', 'autonomi') }
    ];

    for (const { id, handler } of commands) {
      const disposable = vscode.commands.registerCommand(id, handler);
      this.disposables.push(disposable);
    }

    Logger.debug(`Registered ${commands.length} commands`);
  }

  /**
   * Set up UI components
   */
  private async setupUI(): Promise<void> {
    // Create status bar item
    const statusBarItem = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Left,
      100
    );
    statusBarItem.command = 'autonomi.showStatus';
    statusBarItem.text = '$(circuit-board) Autonomi: Ready';
    statusBarItem.tooltip = 'Click to show Autonomi status';
    statusBarItem.show();
    this.disposables.push(statusBarItem);

    // Subscribe to state changes to update status bar
    this.stateManager.subscribe((state) => {
      this.updateStatusBar(statusBarItem, state);
    });

    Logger.debug('UI components set up');
  }

  /**
   * Update status bar based on state
   */
  private updateStatusBar(
    statusBarItem: vscode.StatusBarItem,
    state: ExecutionState
  ): void {
    if (!state.isRunning) {
      statusBarItem.text = '$(circuit-board) Autonomi: Ready';
      statusBarItem.backgroundColor = undefined;
    } else if (state.currentPlan && !state.currentPlan.approved) {
      statusBarItem.text = '$(question) Autonomi: Awaiting Approval';
      statusBarItem.backgroundColor = new vscode.ThemeColor(
        'statusBarItem.warningBackground'
      );
    } else if (state.phase && state.phase !== 'idle') {
      const phaseIcons: Record<RARVPhase, string> = {
        'idle': '$(circle-outline)',
        'reason': '$(lightbulb)',
        'act': '$(play)',
        'reflect': '$(mirror)',
        'verify': '$(check)'
      };
      const icon = phaseIcons[state.phase] || '$(sync~spin)';
      statusBarItem.text = `${icon} Autonomi: ${state.phase.toUpperCase()} | $${state.cost.sessionCost.toFixed(2)}`;
      statusBarItem.backgroundColor = undefined;
    } else {
      statusBarItem.text = `$(sync~spin) Autonomi: Running | $${state.cost.sessionCost.toFixed(2)}`;
      statusBarItem.backgroundColor = undefined;
    }
  }

  /**
   * Set up event listeners
   */
  private setupEventListeners(): void {
    // Listen for configuration changes
    const configDisposable = vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration('autonomi')) {
        Logger.info('Configuration changed, reloading...');
        // Update log level if changed
        const newLevel = this.getLogLevel();
        Logger.setLevel(newLevel);
      }
    });
    this.disposables.push(configDisposable);
  }

  /**
   * Prompt user for task description and start task
   */
  private async promptAndStartTask(): Promise<void> {
    const description = await vscode.window.showInputBox({
      prompt: 'Enter task description',
      placeHolder: 'e.g., Add a login form to the homepage',
      ignoreFocusOut: true
    });

    if (description) {
      await this.startTask(description);
    }
  }

  /**
   * Start a new task
   */
  async startTask(description: string): Promise<void> {
    Logger.info(`Starting task: ${description}`);

    const state = this.stateManager.getState();
    if (state.isRunning && state.currentTask) {
      // Queue the task if already running
      const task = this.createTask(description);
      this.taskQueue.enqueue(task);
      this.stateManager.addToQueue(task);
      vscode.window.showInformationMessage(`Task queued: ${description}`);
      Logger.info(`Task queued: ${task.id}`);
      return;
    }

    // Create and execute task
    const task = this.createTask(description);
    await this.executeTask(task);
  }

  /**
   * Create a new task
   */
  private createTask(description: string, priority: number = 1): Task {
    return {
      id: uuidv4(),
      title: description.slice(0, 50),
      description,
      status: 'pending' as TaskStatus,
      priority,
      createdAt: Date.now()
    };
  }

  /**
   * Execute a task through the RARV cycle
   */
  private async executeTask(task: Task): Promise<void> {
    try {
      // Start execution
      this.stateManager.startExecution();
      this.stateManager.setCurrentTask(task);

      // 1. Calculate confidence
      const confidence = await this.calculateConfidence(task);
      task.confidence = confidence.confidence;
      task.confidenceTier = confidence.tier;
      Logger.info(`Task confidence: ${confidence.confidence.toFixed(2)} (Tier ${confidence.tier})`);

      // 2. Generate plan
      this.stateManager.setPhase('reason');
      const plan = await this.generatePlan(task);
      Logger.info(`Plan generated: ${plan.id} with ${plan.steps.length} steps`);

      // 3. Request approval if needed
      const autoApprove = this.configManager.isAutoApproveEnabled();
      const threshold = this.configManager.getAutoApproveThreshold();
      const requiresApproval = !autoApprove || confidence.confidence < threshold;

      if (requiresApproval) {
        this.stateManager.setCurrentPlan(plan);
        task.status = 'pending';

        vscode.window.showInformationMessage(
          `Plan ready for review. Estimated cost: $${plan.totalEstimatedCost.toFixed(2)}`,
          'Approve',
          'Reject'
        ).then(action => {
          if (action === 'Approve') {
            this.approvePlan();
          } else if (action === 'Reject') {
            this.rejectPlan();
          }
        });
        return; // Wait for user action
      }

      // 4. Execute RARV cycle (auto-approved)
      plan.approved = true;
      plan.approvedAt = Date.now();
      await this.executeRARVCycle(task, plan);

    } catch (error) {
      Logger.error('Task execution failed', error as Error);
      task.status = 'failed';
      this.stateManager.failTask(task, (error as Error).message);
      vscode.window.showErrorMessage(`Task failed: ${(error as Error).message}`);
    }
  }

  /**
   * Calculate confidence for a task
   */
  private async calculateConfidence(task: Task): Promise<{ confidence: number; tier: ConfidenceTier }> {
    // Placeholder implementation
    // TODO: Implement actual confidence calculation using ConfidenceCalculator
    const complexity = this.estimateComplexity(task.description);
    const confidence = Math.max(0.1, 1.0 - complexity * 0.2);

    const thresholds = this.configManager.getConfidenceTierThresholds();
    let tier: ConfidenceTier;
    if (confidence >= thresholds[ConfidenceTier.TIER_1]) {
      tier = ConfidenceTier.TIER_1;
    } else if (confidence >= thresholds[ConfidenceTier.TIER_2]) {
      tier = ConfidenceTier.TIER_2;
    } else if (confidence >= thresholds[ConfidenceTier.TIER_3]) {
      tier = ConfidenceTier.TIER_3;
    } else {
      tier = ConfidenceTier.TIER_4;
    }

    return { confidence, tier };
  }

  /**
   * Estimate task complexity based on description
   */
  private estimateComplexity(description: string): number {
    const words = description.toLowerCase();
    let complexity = 0;

    // Simple heuristics
    if (words.includes('refactor')) complexity += 1;
    if (words.includes('migrate')) complexity += 2;
    if (words.includes('architecture')) complexity += 2;
    if (words.includes('database')) complexity += 1;
    if (words.includes('security')) complexity += 1;
    if (words.includes('authentication')) complexity += 1;
    if (words.includes('api')) complexity += 0.5;
    if (words.includes('test')) complexity -= 0.5;
    if (words.includes('simple')) complexity -= 1;
    if (words.includes('fix')) complexity -= 0.5;

    return Math.max(0, Math.min(4, complexity));
  }

  /**
   * Generate execution plan for a task
   */
  private async generatePlan(task: Task): Promise<Plan> {
    // Placeholder implementation
    // TODO: Implement actual plan generation using PlanGenerator
    const description = task.description.toLowerCase();

    // Determine agent type based on description
    let primaryAgent: AgentType = 'backend';
    if (description.includes('frontend') || description.includes('ui') || description.includes('css')) {
      primaryAgent = 'frontend';
    } else if (description.includes('database') || description.includes('sql')) {
      primaryAgent = 'database';
    } else if (description.includes('api') || description.includes('endpoint')) {
      primaryAgent = 'api';
    } else if (description.includes('test')) {
      primaryAgent = 'qa';
    }

    const steps: PlanStep[] = [
      {
        id: uuidv4(),
        description: 'Analyze requirements and context',
        agentType: 'architect',
        estimatedTokens: 1000,
        estimatedCost: 0.01,
        estimatedDuration: 5000,
        dependencies: [],
        filesAffected: []
      },
      {
        id: uuidv4(),
        description: 'Implement changes',
        agentType: primaryAgent,
        estimatedTokens: 3000,
        estimatedCost: 0.03,
        estimatedDuration: 15000,
        dependencies: [],
        filesAffected: []
      },
      {
        id: uuidv4(),
        description: 'Run tests and verify',
        agentType: 'qa',
        estimatedTokens: 1000,
        estimatedCost: 0.01,
        estimatedDuration: 5000,
        dependencies: [],
        filesAffected: []
      }
    ];

    const plan: Plan = {
      id: uuidv4(),
      taskId: task.id,
      title: `Plan: ${task.title}`,
      description: `Execution plan for: ${task.description}`,
      steps,
      totalEstimatedTokens: 5000,
      totalEstimatedCost: 0.05,
      totalEstimatedDuration: 25000,
      createdAt: Date.now(),
      approved: false
    };

    return plan;
  }

  /**
   * Execute the RARV cycle for a task
   */
  private async executeRARVCycle(task: Task, plan: Plan): Promise<void> {
    task.status = 'in_progress';
    task.startedAt = Date.now();

    // REASON phase
    this.stateManager.setPhase('reason');
    Logger.info('REASON phase: Analyzing task...');
    await this.delay(500); // Placeholder

    // ACT phase
    this.stateManager.setPhase('act');
    Logger.info('ACT phase: Executing plan...');
    for (const step of plan.steps) {
      Logger.info(`Executing step: ${step.description}`);
      await this.delay(500); // Placeholder
    }

    // REFLECT phase
    this.stateManager.setPhase('reflect');
    Logger.info('REFLECT phase: Analyzing results...');
    await this.delay(500); // Placeholder

    // VERIFY phase
    this.stateManager.setPhase('verify');
    Logger.info('VERIFY phase: Running verification...');
    await this.delay(500); // Placeholder

    // Complete task
    task.status = 'completed';
    task.completedAt = Date.now();

    this.stateManager.updateCost(plan.totalEstimatedCost);
    this.stateManager.completeTask(task);
    this.stateManager.stopExecution();

    Logger.info(`Task completed: ${task.id}`);
    vscode.window.showInformationMessage(`Task completed: ${task.description}`);

    // Process next task in queue
    await this.processNextTask();
  }

  /**
   * Process next task in queue
   */
  private async processNextTask(): Promise<void> {
    const nextTask = this.taskQueue.dequeue();
    if (nextTask) {
      this.stateManager.removeFromQueue(nextTask.id);
      Logger.info(`Processing next task from queue: ${nextTask.id}`);
      await this.executeTask(nextTask);
    }
  }

  /**
   * Stop current task execution
   */
  async stopTask(): Promise<void> {
    const state = this.stateManager.getState();
    if (!state.isRunning) {
      vscode.window.showInformationMessage('No task is currently running');
      return;
    }

    Logger.info('Stopping current task...');

    if (state.currentTask) {
      state.currentTask.status = 'cancelled';
      this.stateManager.failTask(state.currentTask, 'Cancelled by user');
    }

    this.stateManager.stopExecution();
    vscode.window.showInformationMessage('Task stopped');
  }

  /**
   * Approve a pending plan
   */
  async approvePlan(): Promise<void> {
    const state = this.stateManager.getState();
    const plan = state.currentPlan;

    if (!plan) {
      vscode.window.showErrorMessage('No pending plan to approve');
      return;
    }

    Logger.info(`Plan approved: ${plan.id}`);
    plan.approved = true;
    plan.approvedAt = Date.now();
    this.stateManager.approvePlan();

    // Continue execution
    const task = state.currentTask;
    if (task) {
      await this.executeRARVCycle(task, plan);
    }
  }

  /**
   * Reject a pending plan
   */
  async rejectPlan(): Promise<void> {
    const state = this.stateManager.getState();
    const plan = state.currentPlan;

    if (!plan) {
      vscode.window.showErrorMessage('No pending plan to reject');
      return;
    }

    Logger.info(`Plan rejected: ${plan.id}`);
    this.stateManager.rejectPlan();

    // Cancel current task
    if (state.currentTask) {
      state.currentTask.status = 'cancelled';
      this.stateManager.failTask(state.currentTask, 'Plan rejected by user');
    }

    this.stateManager.stopExecution();
    vscode.window.showInformationMessage('Plan rejected');

    // Process next task
    await this.processNextTask();
  }

  /**
   * Configure API keys
   */
  private async configureApiKeys(): Promise<void> {
    const providers = ['anthropic', 'openai', 'google'];
    const provider = await vscode.window.showQuickPick(providers, {
      placeHolder: 'Select provider to configure'
    });

    if (!provider) return;

    const apiKey = await vscode.window.showInputBox({
      prompt: `Enter API key for ${provider}`,
      password: true,
      ignoreFocusOut: true
    });

    if (apiKey) {
      await this.configManager.setApiKey(provider, apiKey);
      vscode.window.showInformationMessage(`API key configured for ${provider}`);
    }
  }

  /**
   * Show current status
   */
  private showStatus(): void {
    const state = this.stateManager.getState();
    const lines: string[] = [
      '=== Autonomi Status ===',
      `Running: ${state.isRunning}`,
      `Phase: ${state.phase || 'None'}`,
      `Session Cost: $${state.cost.sessionCost.toFixed(2)}`,
      `Queue Size: ${state.queue.pending.length}`,
      `Active Agents: ${state.activeAgents.length}`,
      ''
    ];

    if (state.currentTask) {
      lines.push('Current Task:');
      lines.push(`  ID: ${state.currentTask.id}`);
      lines.push(`  Description: ${state.currentTask.description}`);
      lines.push(`  Status: ${state.currentTask.status}`);
      lines.push(`  Confidence: ${state.currentTask.confidence?.toFixed(2) || 'N/A'}`);
    }

    if (state.currentPlan) {
      lines.push('');
      lines.push('Current Plan:');
      lines.push(`  ID: ${state.currentPlan.id}`);
      lines.push(`  Steps: ${state.currentPlan.steps.length}`);
      lines.push(`  Est. Cost: $${state.currentPlan.totalEstimatedCost.toFixed(2)}`);
      lines.push(`  Approved: ${state.currentPlan.approved}`);
    }

    this.outputChannel.clear();
    this.outputChannel.appendLine(lines.join('\n'));
    this.outputChannel.show();
  }

  /**
   * Clear task queue
   */
  private clearQueue(): void {
    this.taskQueue.clear();
    this.stateManager.clearQueue();
    vscode.window.showInformationMessage('Task queue cleared');
  }

  /**
   * Get current execution state
   */
  getState(): ExecutionState {
    return this.stateManager.getState();
  }

  /**
   * Utility delay function
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Dispose of all resources
   */
  dispose(): void {
    Logger.info('Disposing Autonomi extension...');

    // Dispose state manager
    this.stateManager.dispose();

    // Dispose all registered disposables
    this.disposables.forEach(d => d.dispose());
    this.disposables = [];

    // Dispose optional components
    this.treeProvider?.dispose();
    this.statusBar?.dispose();
    this.orchestrator?.dispose();
    this.providerManager?.dispose();
    this.costTracker?.dispose();
    this.planGenerator?.dispose();
    this.approvalManager?.dispose();
    this.confidenceCalculator?.dispose();

    Logger.info('Autonomi extension disposed');
    Logger.dispose();
  }
}
