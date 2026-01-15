/**
 * State management for Autonomi VSCode Extension
 */

import * as vscode from 'vscode';
import {
  ExecutionState,
  RARVPhase,
  Task,
  Plan,
  QueueState,
  CostState,
  ActiveAgent
} from '../types/execution';
import { ConfidenceTier } from '../providers/types';
import { Logger } from '../utils/logger';

const STATE_KEY = 'autonomi.executionState';

// Initial state
function createInitialState(): ExecutionState {
  return {
    phase: 'idle',
    isRunning: false,
    isPaused: false,
    currentTask: undefined,
    currentPlan: undefined,
    activeAgents: [],
    queue: {
      pending: [],
      inProgress: [],
      completed: [],
      failed: []
    },
    confidence: 0,
    confidenceTier: ConfidenceTier.TIER_4,
    cost: {
      sessionCost: 0,
      taskCost: 0,
      dailyCost: 0,
      budgetTask: 5.00,
      budgetSession: 50.00,
      budgetDaily: 100.00
    },
    sessionId: '',
    sessionStartedAt: Date.now(),
    lastUpdatedAt: Date.now()
  };
}

export type StateListener = (state: ExecutionState) => void;

export class StateManager {
  private context: vscode.ExtensionContext;
  private state: ExecutionState;
  private listeners: Set<StateListener> = new Set();
  private saveDebounceTimer: ReturnType<typeof setTimeout> | undefined;
  private readonly saveDebounceMs: number = 1000;

  constructor(context: vscode.ExtensionContext) {
    this.context = context;
    this.state = createInitialState();
  }

  /**
   * Get the current state
   */
  getState(): ExecutionState {
    return { ...this.state };
  }

  /**
   * Update state with partial updates
   */
  setState(updates: Partial<ExecutionState>): void {
    this.state = { ...this.state, ...updates, lastUpdatedAt: Date.now() };

    // Notify listeners
    this.notifyListeners();

    // Debounced save to persistence
    this.debouncedSave();

    Logger.debug('State updated', { changes: Object.keys(updates) });
  }

  /**
   * Set current phase
   */
  setPhase(phase: RARVPhase): void {
    this.setState({ phase });
  }

  /**
   * Set current task
   */
  setCurrentTask(task: Task | undefined): void {
    this.setState({ currentTask: task });
  }

  /**
   * Set current plan
   */
  setCurrentPlan(plan: Plan | undefined): void {
    this.setState({ currentPlan: plan });
  }

  /**
   * Add task to queue
   */
  addToQueue(task: Task): void {
    const queue: QueueState = { ...this.state.queue };
    queue.pending = [...queue.pending, task];
    this.setState({ queue });
  }

  /**
   * Remove task from queue
   */
  removeFromQueue(taskId: string): void {
    const queue: QueueState = { ...this.state.queue };
    queue.pending = queue.pending.filter((t: Task) => t.id !== taskId);
    this.setState({ queue });
  }

  /**
   * Clear the queue
   */
  clearQueue(): void {
    const queue: QueueState = {
      pending: [],
      inProgress: [],
      completed: this.state.queue.completed,
      failed: this.state.queue.failed
    };
    this.setState({ queue });
  }

  /**
   * Mark task as completed
   */
  completeTask(task: Task): void {
    const queue: QueueState = { ...this.state.queue };
    queue.completed = [...queue.completed, task];
    queue.inProgress = queue.inProgress.filter((t: Task) => t.id !== task.id);
    // Keep only last 100 completed tasks
    if (queue.completed.length > 100) {
      queue.completed = queue.completed.slice(-100);
    }
    this.setState({
      currentTask: undefined,
      queue
    });
  }

  /**
   * Mark task as failed
   */
  failTask(task: Task, error: string): void {
    const queue: QueueState = { ...this.state.queue };
    const failedTask: Task = { ...task, status: 'failed' };
    queue.failed = [...queue.failed, failedTask];
    queue.inProgress = queue.inProgress.filter((t: Task) => t.id !== task.id);
    // Keep only last 50 failed tasks
    if (queue.failed.length > 50) {
      queue.failed = queue.failed.slice(-50);
    }
    this.setState({
      currentTask: undefined,
      queue
    });
    Logger.warn(`Task failed: ${task.id} - ${error}`);
  }

  /**
   * Update session cost
   */
  updateCost(cost: number): void {
    const costState: CostState = {
      ...this.state.cost,
      sessionCost: this.state.cost.sessionCost + cost,
      taskCost: this.state.cost.taskCost + cost,
      dailyCost: this.state.cost.dailyCost + cost
    };
    this.setState({ cost: costState });
  }

  /**
   * Add active agent
   */
  addActiveAgent(agent: ActiveAgent): void {
    if (!this.state.activeAgents.find((a: ActiveAgent) => a.id === agent.id)) {
      const activeAgents = [...this.state.activeAgents, agent];
      this.setState({ activeAgents });
    }
  }

  /**
   * Remove active agent
   */
  removeActiveAgent(agentId: string): void {
    const activeAgents = this.state.activeAgents.filter((a: ActiveAgent) => a.id !== agentId);
    this.setState({ activeAgents });
  }

  /**
   * Start execution
   */
  startExecution(): void {
    this.setState({
      isRunning: true,
      isPaused: false,
      sessionStartedAt: Date.now(),
      cost: {
        ...this.state.cost,
        taskCost: 0
      }
    });
  }

  /**
   * Stop execution
   */
  stopExecution(): void {
    this.setState({
      isRunning: false,
      isPaused: false,
      phase: 'idle',
      currentTask: undefined,
      currentPlan: undefined,
      activeAgents: []
    });
  }

  /**
   * Pause execution
   */
  pauseExecution(): void {
    this.setState({ isPaused: true });
  }

  /**
   * Resume execution
   */
  resumeExecution(): void {
    this.setState({ isPaused: false });
  }

  /**
   * Approve pending plan
   */
  approvePlan(): void {
    if (this.state.currentPlan) {
      const plan: Plan = {
        ...this.state.currentPlan,
        approved: true,
        approvedAt: Date.now()
      };
      this.setState({ currentPlan: plan });
    }
  }

  /**
   * Reject pending plan
   */
  rejectPlan(): void {
    this.setState({ currentPlan: undefined });
  }

  /**
   * Reset state to initial
   */
  reset(): void {
    this.state = createInitialState();
    this.notifyListeners();
    this.save();
  }

  /**
   * Save state to persistent storage
   */
  async save(): Promise<void> {
    try {
      await this.context.workspaceState.update(STATE_KEY, this.state);
      Logger.debug('State saved to workspace storage');
    } catch (error) {
      Logger.error('Failed to save state', error as Error);
    }
  }

  /**
   * Debounced save to avoid excessive writes
   */
  private debouncedSave(): void {
    if (this.saveDebounceTimer) {
      clearTimeout(this.saveDebounceTimer);
    }
    this.saveDebounceTimer = setTimeout(() => {
      this.save();
    }, this.saveDebounceMs);
  }

  /**
   * Restore state from persistent storage
   */
  async restore(): Promise<ExecutionState | undefined> {
    try {
      const savedState = this.context.workspaceState.get<ExecutionState>(STATE_KEY);
      if (savedState) {
        // Merge with initial state to handle any new fields
        this.state = { ...createInitialState(), ...savedState };
        // Reset running state on restore (extension was restarted)
        this.state.isRunning = false;
        this.state.isPaused = false;
        this.state.activeAgents = [];
        this.state.phase = 'idle';
        Logger.info('State restored from workspace storage');
        return this.state;
      }
    } catch (error) {
      Logger.error('Failed to restore state', error as Error);
    }
    return undefined;
  }

  /**
   * Subscribe to state changes
   */
  subscribe(listener: StateListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /**
   * Notify all listeners of state change
   */
  private notifyListeners(): void {
    const stateCopy = this.getState();
    this.listeners.forEach(listener => {
      try {
        listener(stateCopy);
      } catch (error) {
        Logger.error('State listener error', error as Error);
      }
    });
  }

  /**
   * Get task by ID from queue or completed
   */
  getTaskById(taskId: string): Task | undefined {
    if (this.state.currentTask?.id === taskId) {
      return this.state.currentTask;
    }
    const allTasks = [
      ...this.state.queue.pending,
      ...this.state.queue.inProgress,
      ...this.state.queue.completed,
      ...this.state.queue.failed
    ];
    return allTasks.find((t: Task) => t.id === taskId);
  }

  /**
   * Dispose of the state manager
   */
  dispose(): void {
    if (this.saveDebounceTimer) {
      clearTimeout(this.saveDebounceTimer);
    }
    // Save final state
    this.save();
    this.listeners.clear();
  }
}
