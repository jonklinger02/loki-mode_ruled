/**
 * Autonomi VSCode Extension - Core Type Definitions
 *
 * This module defines all TypeScript interfaces and enums used throughout
 * the Autonomi multi-agent autonomous development platform.
 */

// ============================================================================
// Enums
// ============================================================================

/**
 * RARV (Reason-Act-Reflect-Verify) execution phases.
 * Every iteration in Autonomi follows this cycle.
 */
export enum RARVPhase {
  /** Analyze the task, gather context, form a strategy */
  REASON = 'REASON',
  /** Execute the planned actions */
  ACT = 'ACT',
  /** Review results, identify issues, learn from execution */
  REFLECT = 'REFLECT',
  /** Validate outcomes against requirements and quality gates */
  VERIFY = 'VERIFY'
}

/**
 * Specialized agent types for different development tasks.
 * Each agent has domain expertise and specific capabilities.
 */
export enum AgentType {
  /** Frontend UI/UX development (React, Vue, CSS) */
  FRONTEND = 'frontend',
  /** Backend services and business logic */
  BACKEND = 'backend',
  /** Database schema, queries, migrations */
  DATABASE = 'database',
  /** API design, implementation, documentation */
  API = 'api',
  /** CI/CD, infrastructure, deployment */
  DEVOPS = 'devops',
  /** Quality assurance and test planning */
  QA = 'qa',
  /** Code review and quality assessment */
  CODE_REVIEW = 'code_review',
  /** Security analysis and vulnerability assessment */
  SECURITY_REVIEW = 'security_review',
  /** Automated test generation */
  TEST_GEN = 'test_gen',
  /** Performance optimization and profiling */
  PERF = 'perf',
  /** Documentation generation */
  DOCS = 'docs',
  /** Code refactoring and cleanup */
  REFACTOR = 'refactor',
  /** System migration and upgrades */
  MIGRATION = 'migration',
  /** System architecture and design */
  ARCHITECT = 'architect',
  /** Task decomposition and planning */
  DECOMPOSITION = 'decomposition'
}

/**
 * Confidence tiers for task execution decisions.
 * Higher tiers indicate higher confidence and may enable auto-approval.
 */
export enum ConfidenceTier {
  /** 90-100% confidence - Safe, well-understood changes */
  TIER_1 = 'TIER_1',
  /** 75-89% confidence - Moderate complexity, some review needed */
  TIER_2 = 'TIER_2',
  /** 50-74% confidence - Complex changes, review recommended */
  TIER_3 = 'TIER_3',
  /** 0-49% confidence - High risk, mandatory review */
  TIER_4 = 'TIER_4'
}

/**
 * Task execution status.
 */
export enum TaskStatus {
  /** Task is waiting in the queue */
  PENDING = 'pending',
  /** Task is awaiting approval */
  AWAITING_APPROVAL = 'awaiting_approval',
  /** Task has been approved and ready for execution */
  APPROVED = 'approved',
  /** Task is currently executing */
  IN_PROGRESS = 'in_progress',
  /** Task completed successfully */
  COMPLETED = 'completed',
  /** Task failed during execution */
  FAILED = 'failed',
  /** Task was cancelled */
  CANCELLED = 'cancelled',
  /** Task is blocked by dependencies */
  BLOCKED = 'blocked'
}

/**
 * Model types for different task categories.
 */
export enum ModelType {
  /** High-capability model for planning (Opus) */
  PLANNING = 'planning',
  /** Standard model for development (Sonnet) */
  DEVELOPMENT = 'development',
  /** Fast model for testing and simple tasks (Haiku) */
  TESTING = 'testing'
}

// ============================================================================
// Core Interfaces
// ============================================================================

/**
 * A single step in an execution plan.
 */
export interface PlanStep {
  /** Unique identifier for the step */
  id: string;
  /** Description of what this step accomplishes */
  description: string;
  /** Agent type responsible for this step */
  agentType: AgentType;
  /** Estimated cost in USD */
  estimatedCost: number;
  /** Estimated token usage */
  estimatedTokens: number;
  /** Files that will be affected */
  affectedFiles: string[];
  /** Step IDs that must complete before this step */
  dependencies: string[];
  /** Current status of this step */
  status: TaskStatus;
}

/**
 * Execution plan for a task or feature.
 */
export interface Plan {
  /** Unique identifier for the plan */
  id: string;
  /** Human-readable name for the plan */
  name: string;
  /** Detailed description of what the plan accomplishes */
  description: string;
  /** Ordered list of execution steps */
  steps: PlanStep[];
  /** Total estimated cost in USD */
  estimatedCost: number;
  /** Total estimated token usage */
  estimatedTokens: number;
  /** All files that will be affected across all steps */
  affectedFiles: string[];
  /** Whether the plan has been approved for execution */
  approved: boolean;
  /** Timestamp when the plan was created */
  createdAt: number;
  /** Timestamp when the plan was approved (if approved) */
  approvedAt?: number;
  /** User who approved the plan (if approved) */
  approvedBy?: string;
}

/**
 * A task in the execution queue.
 */
export interface Task {
  /** Unique identifier for the task */
  id: string;
  /** Human-readable description */
  description: string;
  /** Current status */
  status: TaskStatus;
  /** Agent type assigned to this task */
  agentType: AgentType;
  /** Confidence level for this task */
  confidence: ConfidenceTier;
  /** Numeric confidence score (0-100) */
  confidenceScore: number;
  /** Associated execution plan */
  plan?: Plan;
  /** Actual cost incurred (updated during/after execution) */
  cost: number;
  /** Actual tokens used (updated during/after execution) */
  tokensUsed: number;
  /** Parent task ID (for subtasks) */
  parentTaskId?: string;
  /** Child task IDs (for decomposed tasks) */
  childTaskIds: string[];
  /** Error message if task failed */
  error?: string;
  /** Timestamp when task was created */
  createdAt: number;
  /** Timestamp when task started execution */
  startedAt?: number;
  /** Timestamp when task completed */
  completedAt?: number;
  /** Current RARV phase */
  currentPhase: RARVPhase;
  /** Number of retry attempts */
  retryCount: number;
  /** Maximum retry attempts allowed */
  maxRetries: number;
}

/**
 * Current execution state of the Autonomi system.
 */
export interface ExecutionState {
  /** Whether the system is currently running */
  isRunning: boolean;
  /** Current RARV phase */
  phase: RARVPhase;
  /** Task currently being executed */
  currentTask: Task | null;
  /** Tasks waiting in the queue */
  queue: Task[];
  /** Tasks that have been completed */
  completedTasks: Task[];
  /** Tasks that have failed */
  failedTasks: Task[];
  /** Total cost for this session in USD */
  sessionCost: number;
  /** Total tokens used this session */
  sessionTokens: number;
  /** Session start timestamp */
  sessionStartedAt: number | null;
  /** Plan awaiting approval (if any) */
  pendingPlan: Plan | null;
}

// ============================================================================
// Configuration Interfaces
// ============================================================================

/**
 * Configuration for a specific agent type.
 */
export interface AgentConfig {
  /** Agent type this config applies to */
  type: AgentType;
  /** Display name for the agent */
  displayName: string;
  /** Description of the agent's capabilities */
  description: string;
  /** Model type to use for this agent */
  modelType: ModelType;
  /** System prompt for the agent */
  systemPrompt: string;
  /** Maximum tokens per request */
  maxTokens: number;
  /** Temperature setting (0-1) */
  temperature: number;
  /** Whether this agent can create files */
  canCreateFiles: boolean;
  /** Whether this agent can delete files */
  canDeleteFiles: boolean;
  /** Whether this agent can execute shell commands */
  canExecuteCommands: boolean;
  /** File patterns this agent can access */
  allowedFilePatterns: string[];
  /** File patterns this agent cannot access */
  blockedFilePatterns: string[];
}

/**
 * Configuration for an AI provider (Anthropic, OpenAI, etc.).
 */
export interface ProviderConfig {
  /** Provider identifier */
  id: string;
  /** Display name */
  name: string;
  /** API key for authentication */
  apiKey: string;
  /** Base URL for API requests */
  baseUrl?: string;
  /** Model ID for planning tasks */
  planningModel: string;
  /** Model ID for development tasks */
  developmentModel: string;
  /** Model ID for testing tasks */
  testingModel: string;
  /** Cost per 1K input tokens (planning model) */
  planningInputCostPer1K: number;
  /** Cost per 1K output tokens (planning model) */
  planningOutputCostPer1K: number;
  /** Cost per 1K input tokens (development model) */
  developmentInputCostPer1K: number;
  /** Cost per 1K output tokens (development model) */
  developmentOutputCostPer1K: number;
  /** Cost per 1K input tokens (testing model) */
  testingInputCostPer1K: number;
  /** Cost per 1K output tokens (testing model) */
  testingOutputCostPer1K: number;
  /** Maximum requests per minute */
  rateLimitRPM: number;
  /** Maximum tokens per minute */
  rateLimitTPM: number;
}

/**
 * Cost tracking for budget management.
 */
export interface CostTracking {
  /** Total cost for the current session */
  sessionCost: number;
  /** Total cost for today */
  dailyCost: number;
  /** Total cost for the current month */
  monthlyCost: number;
  /** Cost breakdown by agent type */
  costByAgent: Record<AgentType, number>;
  /** Cost breakdown by task */
  costByTask: Record<string, number>;
  /** Session budget limit */
  sessionLimit: number;
  /** Daily budget limit */
  dailyLimit: number;
  /** Monthly budget limit */
  monthlyLimit: number;
  /** Whether session limit has been exceeded */
  sessionLimitExceeded: boolean;
  /** Whether daily limit has been exceeded */
  dailyLimitExceeded: boolean;
  /** Whether monthly limit has been exceeded */
  monthlyLimitExceeded: boolean;
  /** Timestamp of last cost update */
  lastUpdated: number;
}

// ============================================================================
// Event Interfaces
// ============================================================================

/**
 * Event emitted when execution state changes.
 */
export interface StateChangeEvent {
  /** Previous state */
  previousState: ExecutionState;
  /** New state */
  newState: ExecutionState;
  /** Timestamp of the change */
  timestamp: number;
}

/**
 * Event emitted when a task status changes.
 */
export interface TaskStatusChangeEvent {
  /** The task that changed */
  task: Task;
  /** Previous status */
  previousStatus: TaskStatus;
  /** New status */
  newStatus: TaskStatus;
  /** Timestamp of the change */
  timestamp: number;
}

/**
 * Event emitted when cost tracking is updated.
 */
export interface CostUpdateEvent {
  /** Updated cost tracking */
  costTracking: CostTracking;
  /** Cost delta from last update */
  delta: number;
  /** Task that incurred the cost (if applicable) */
  taskId?: string;
  /** Timestamp of the update */
  timestamp: number;
}

// ============================================================================
// API Response Interfaces
// ============================================================================

/**
 * Token usage information from API response.
 */
export interface TokenUsage {
  /** Input tokens used */
  inputTokens: number;
  /** Output tokens used */
  outputTokens: number;
  /** Total tokens used */
  totalTokens: number;
  /** Cached input tokens (if applicable) */
  cachedInputTokens?: number;
}

/**
 * Response from an agent execution.
 */
export interface AgentResponse {
  /** Whether the execution was successful */
  success: boolean;
  /** Output content from the agent */
  content: string;
  /** Token usage for this response */
  tokenUsage: TokenUsage;
  /** Cost for this response in USD */
  cost: number;
  /** Files that were modified */
  modifiedFiles: string[];
  /** Files that were created */
  createdFiles: string[];
  /** Files that were deleted */
  deletedFiles: string[];
  /** Error message if execution failed */
  error?: string;
  /** Execution duration in milliseconds */
  durationMs: number;
}

// ============================================================================
// Quality Gate Interfaces
// ============================================================================

/**
 * Result from a quality gate check.
 */
export interface QualityGateResult {
  /** Name of the quality gate */
  gateName: string;
  /** Whether the check passed */
  passed: boolean;
  /** Severity level if check failed */
  severity?: 'critical' | 'high' | 'medium' | 'low' | 'info';
  /** Details about the check result */
  details: string;
  /** Suggested fixes (if check failed) */
  suggestions?: string[];
  /** Timestamp of the check */
  timestamp: number;
}

/**
 * Code review result from review agents.
 */
export interface CodeReviewResult {
  /** Reviewer agent ID */
  reviewerId: string;
  /** Whether the review approved the changes */
  approved: boolean;
  /** Overall rating (1-5) */
  rating: number;
  /** List of issues found */
  issues: CodeReviewIssue[];
  /** Positive observations */
  strengths: string[];
  /** Summary of the review */
  summary: string;
  /** Timestamp of the review */
  timestamp: number;
}

/**
 * An issue identified during code review.
 */
export interface CodeReviewIssue {
  /** Issue severity */
  severity: 'critical' | 'high' | 'medium' | 'low' | 'info';
  /** Issue category */
  category: 'bug' | 'security' | 'performance' | 'style' | 'maintainability' | 'documentation';
  /** File containing the issue */
  file: string;
  /** Line number (if applicable) */
  line?: number;
  /** Issue description */
  description: string;
  /** Suggested fix */
  suggestion?: string;
}

// ============================================================================
// UI Layer Types (re-exported from execution.ts)
// ============================================================================

// Re-export UI-specific types that use different conventions
// These use lowercase string types for compatibility with VSCode TreeView
export type {
  RARVPhase as UIRARVPhase,
  TaskStatus as UITaskStatus,
  AgentType as UIAgentType,
  Task as UITask,
  TaskResult,
  PlanStep as UIPlanStep,
  Plan as UIPlan,
  ActiveAgent,
  QueueState,
  CostState,
  ExecutionState,
  StateUpdateEvent
} from './execution';
