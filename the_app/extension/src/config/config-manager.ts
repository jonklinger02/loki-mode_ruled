/**
 * Configuration manager for Autonomi VSCode Extension
 */

import * as vscode from 'vscode';
import { ConfidenceTier } from '../providers/types';
import { Logger } from '../utils/logger';

// Configuration keys
const CONFIG_SECTION = 'autonomi';
const SECRET_PREFIX = 'autonomi.apiKey.';

// Budget configuration interface
export interface BudgetConfig {
  taskBudget: number;
  sessionBudget: number;
  dailyBudget: number;
  warningThreshold: number;
}

// Approval gate configuration interface
export interface ApprovalGateConfig {
  productionDeploy: boolean;
  databaseMigration: boolean;
  securityChanges: boolean;
  newDependencies: boolean;
  fileDeletion: boolean;
  costThreshold: number;
}

// Default configurations
const DEFAULT_BUDGETS: BudgetConfig = {
  taskBudget: 5.00,
  sessionBudget: 50.00,
  dailyBudget: 100.00,
  warningThreshold: 0.80
};

const DEFAULT_APPROVAL_GATES: ApprovalGateConfig = {
  productionDeploy: true,
  databaseMigration: true,
  securityChanges: true,
  newDependencies: true,
  fileDeletion: true,
  costThreshold: 1.00
};

export class ConfigManager {
  private context: vscode.ExtensionContext;
  private config: vscode.WorkspaceConfiguration;
  private secretStorage: vscode.SecretStorage;

  constructor(context: vscode.ExtensionContext) {
    this.context = context;
    this.config = vscode.workspace.getConfiguration(CONFIG_SECTION);
    this.secretStorage = context.secrets;

    // Listen for configuration changes
    vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration(CONFIG_SECTION)) {
        this.config = vscode.workspace.getConfiguration(CONFIG_SECTION);
        Logger.debug('Configuration updated');
      }
    });
  }

  /**
   * Get API key for a provider from secret storage
   */
  async getApiKey(provider: string): Promise<string | undefined> {
    const key = `${SECRET_PREFIX}${provider}`;
    return this.secretStorage.get(key);
  }

  /**
   * Set API key for a provider in secret storage
   */
  async setApiKey(provider: string, apiKey: string): Promise<void> {
    const key = `${SECRET_PREFIX}${provider}`;
    await this.secretStorage.store(key, apiKey);
    Logger.info(`API key stored for provider: ${provider}`);
  }

  /**
   * Delete API key for a provider
   */
  async deleteApiKey(provider: string): Promise<void> {
    const key = `${SECRET_PREFIX}${provider}`;
    await this.secretStorage.delete(key);
    Logger.info(`API key deleted for provider: ${provider}`);
  }

  /**
   * Check if API key exists for a provider
   */
  async hasApiKey(provider: string): Promise<boolean> {
    const key = await this.getApiKey(provider);
    return !!key;
  }

  /**
   * Get budget configuration
   */
  getBudgets(): BudgetConfig {
    return {
      taskBudget: this.config.get<number>('budgets.taskBudget', DEFAULT_BUDGETS.taskBudget),
      sessionBudget: this.config.get<number>('budgets.sessionBudget', DEFAULT_BUDGETS.sessionBudget),
      dailyBudget: this.config.get<number>('budgets.dailyBudget', DEFAULT_BUDGETS.dailyBudget),
      warningThreshold: this.config.get<number>('budgets.warningThreshold', DEFAULT_BUDGETS.warningThreshold)
    };
  }

  /**
   * Get approval gate configuration
   */
  getApprovalGates(): ApprovalGateConfig {
    return {
      productionDeploy: this.config.get<boolean>('approvalGates.productionDeploy', DEFAULT_APPROVAL_GATES.productionDeploy),
      databaseMigration: this.config.get<boolean>('approvalGates.databaseMigration', DEFAULT_APPROVAL_GATES.databaseMigration),
      securityChanges: this.config.get<boolean>('approvalGates.securityChanges', DEFAULT_APPROVAL_GATES.securityChanges),
      newDependencies: this.config.get<boolean>('approvalGates.newDependencies', DEFAULT_APPROVAL_GATES.newDependencies),
      fileDeletion: this.config.get<boolean>('approvalGates.fileDeletion', DEFAULT_APPROVAL_GATES.fileDeletion),
      costThreshold: this.config.get<number>('approvalGates.costThreshold', DEFAULT_APPROVAL_GATES.costThreshold)
    };
  }

  /**
   * Get preferred provider
   */
  getPreferredProvider(): string {
    return this.config.get<string>('provider.preferred', 'anthropic');
  }

  /**
   * Get fallback providers
   */
  getFallbackProviders(): string[] {
    return this.config.get<string[]>('provider.fallbacks', ['openai', 'google']);
  }

  /**
   * Get auto-approve confidence threshold
   */
  getAutoApproveThreshold(): number {
    return this.config.get<number>('autoApprove.confidenceThreshold', 0.90);
  }

  /**
   * Check if auto-approve is enabled
   */
  isAutoApproveEnabled(): boolean {
    return this.config.get<boolean>('autoApprove.enabled', false);
  }

  /**
   * Get max concurrent agents
   */
  getMaxConcurrentAgents(): number {
    return this.config.get<number>('agents.maxConcurrent', 4);
  }

  /**
   * Get confidence tier thresholds
   */
  getConfidenceTierThresholds(): Record<ConfidenceTier, number> {
    return {
      [ConfidenceTier.TIER_1]: this.config.get<number>('confidence.tier1Threshold', 0.90),
      [ConfidenceTier.TIER_2]: this.config.get<number>('confidence.tier2Threshold', 0.60),
      [ConfidenceTier.TIER_3]: this.config.get<number>('confidence.tier3Threshold', 0.30),
      [ConfidenceTier.TIER_4]: 0.0 // Anything below tier 3
    };
  }

  /**
   * Get memory configuration
   */
  getMemoryConfig(): { hotMemoryMaxSize: number; coldMemoryPath: string } {
    return {
      hotMemoryMaxSize: this.config.get<number>('memory.hotMaxSizeMB', 50) * 1024 * 1024,
      coldMemoryPath: this.config.get<string>('memory.coldPath', '.autonomi/memory/memory.db')
    };
  }

  /**
   * Get snapshot configuration
   */
  getSnapshotConfig(): { maxSnapshots: number; snapshotPath: string } {
    return {
      maxSnapshots: this.config.get<number>('snapshots.maxCount', 20),
      snapshotPath: this.config.get<string>('snapshots.path', '.autonomi/snapshots')
    };
  }

  /**
   * Get telemetry setting
   */
  isTelemetryEnabled(): boolean {
    return this.config.get<boolean>('telemetry.enabled', false);
  }

  /**
   * Get log level
   */
  getLogLevel(): string {
    return this.config.get<string>('logging.level', 'info');
  }

  /**
   * Get quality gate configuration
   */
  getQualityGateConfig(): Array<{ enabled: boolean; tiers: number[] }> {
    return [
      {
        enabled: this.config.get<boolean>('quality.staticAnalysis.enabled', true),
        tiers: this.config.get<number[]>('quality.staticAnalysis.tiers', [1, 2, 3])
      },
      {
        enabled: this.config.get<boolean>('quality.automatedTests.enabled', true),
        tiers: this.config.get<number[]>('quality.automatedTests.tiers', [2, 3])
      },
      {
        enabled: this.config.get<boolean>('quality.codeReview.enabled', true),
        tiers: this.config.get<number[]>('quality.codeReview.tiers', [3])
      },
      {
        enabled: this.config.get<boolean>('quality.securityScan.enabled', true),
        tiers: this.config.get<number[]>('quality.securityScan.tiers', [3])
      }
    ];
  }

  /**
   * Update a configuration value
   */
  async updateConfig<T>(key: string, value: T, global: boolean = false): Promise<void> {
    const target = global
      ? vscode.ConfigurationTarget.Global
      : vscode.ConfigurationTarget.Workspace;
    await this.config.update(key, value, target);
    Logger.info(`Configuration updated: ${key} = ${JSON.stringify(value)}`);
  }

  /**
   * Get all configuration as an object (excluding secrets)
   */
  getAllConfig(): Record<string, unknown> {
    return {
      budgets: this.getBudgets(),
      approvalGates: this.getApprovalGates(),
      provider: {
        preferred: this.getPreferredProvider(),
        fallbacks: this.getFallbackProviders()
      },
      autoApprove: {
        enabled: this.isAutoApproveEnabled(),
        threshold: this.getAutoApproveThreshold()
      },
      agents: {
        maxConcurrent: this.getMaxConcurrentAgents()
      },
      memory: this.getMemoryConfig(),
      snapshots: this.getSnapshotConfig(),
      telemetry: {
        enabled: this.isTelemetryEnabled()
      },
      logging: {
        level: this.getLogLevel()
      }
    };
  }
}
