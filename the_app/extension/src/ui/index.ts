/**
 * Autonomi Extension UI Layer
 * Exports all UI components for the VSCode extension
 */

// TreeView components
export {
  AutonomiTreeProvider,
  registerTreeView
} from './treeview/autonomi-tree-provider';

export {
  AutonomiTreeItem,
  StatusItem,
  QueueCategoryItem,
  TaskItem,
  ActionItem,
  AgentItem,
  TreeItemType
} from './treeview/tree-items';

// Status bar
export { StatusBarController } from './status-bar';

// Output channel
export {
  AutonomiOutputChannel,
  LogLevel,
  createOutputChannel
} from './output-channel';

// Commands
export {
  registerCommands,
  getRegisteredCommands,
  AutonomiExtension
} from './commands';

// Quick pick dialogs
export {
  showTaskInput,
  showDetailedTaskInput,
  showPlanApproval,
  showPlanDetails,
  showAgentSelection,
  showConfirmation,
  showModelSelection
} from './quick-pick';

// Notifications
export {
  showCostWarning,
  showBudgetExceeded,
  showApprovalRequired,
  showTaskComplete,
  showError,
  showProgress,
  showGateTriggered,
  showLowConfidence,
  showSessionSummary,
  showAgentHandoff,
  showQualityGateFailure,
  showSecretDetected
} from './notifications';
