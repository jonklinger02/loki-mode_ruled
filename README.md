# Loki Mode

**Multi-Agent Autonomous Startup System for Claude Code**

[![Claude Code](https://img.shields.io/badge/Claude-Code-orange)](https://claude.ai)
[![Agents](https://img.shields.io/badge/Agents-37-blue)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> Transform a PRD into a fully deployed, revenue-generating product with zero human intervention.

## What is Loki Mode?

Loki Mode is a Claude Code skill that orchestrates 37 specialized AI agents across 6 swarms to autonomously build, deploy, and operate a complete startup. Just say **"Loki Mode"** and provide a PRD.

```
PRD → Competitive Research → Architecture → Development → Testing → Deployment → Marketing → Revenue
```

## Features

| Category | Capabilities |
|----------|-------------|
| **Multi-Agent System** | 37 agents across Engineering, Operations, Business, Data, Product, and Growth swarms |
| **Parallel Code Review** | 3 specialized reviewers (code, business, security) running simultaneously |
| **Quality Gates** | 14 automated gates including security scans, load tests, accessibility |
| **Deployment** | AWS, GCP, Azure, Vercel, Railway with blue-green and canary strategies |
| **Business Ops** | Marketing, Sales, HR, Legal, Finance, Investor Relations agents |
| **Reliability** | Circuit breakers, dead letter queues, exponential backoff, state recovery |
| **Observability** | External alerting (Slack, PagerDuty), backup/restore, log rotation |

## Agent Swarms

<img width="5309" height="979" alt="image" src="https://github.com/user-attachments/assets/7d18635d-a606-401f-8d9f-430e6e4ee689" />


### Engineering (8)
`eng-frontend` `eng-backend` `eng-database` `eng-mobile` `eng-api` `eng-qa` `eng-perf` `eng-infra`

### Operations (8)
`ops-devops` `ops-sre` `ops-security` `ops-monitor` `ops-incident` `ops-release` `ops-cost` `ops-compliance`

### Business (8)
`biz-marketing` `biz-sales` `biz-finance` `biz-legal` `biz-support` `biz-hr` `biz-investor` `biz-partnerships`

### Data (3)
`data-ml` `data-eng` `data-analytics`

### Product (3)
`prod-pm` `prod-design` `prod-techwriter`

### Growth (4)
`growth-hacker` `growth-community` `growth-success` `growth-lifecycle`

### Review (3)
`review-code` `review-business` `review-security`

## Installation

### Claude Code (Recommended)

```bash
# Copy to your skills directory
git clone https://github.com/asklokesh/claudeskill-loki-mode.git ~/.claude/skills/loki-mode
```

### Manual Installation

1. Download this repository
2. Copy to `~/.claude/skills/loki-mode/` (personal) or `.claude/skills/loki-mode/` (project)

## Usage

```bash
# Launch Claude Code with autonomous permissions
claude --dangerously-skip-permissions

# Then say:
> Loki Mode

# Or with a specific PRD:
> Loki Mode with PRD at ./docs/requirements.md
```

## How It Works

### Phase Execution

| Phase | Description |
|-------|-------------|
| **0. Bootstrap** | Create `.loki/` directory structure, initialize state |
| **1. Discovery** | Parse PRD, competitive research via web search |
| **2. Architecture** | Tech stack selection with self-reflection |
| **3. Infrastructure** | Provision cloud, CI/CD, monitoring |
| **4. Development** | Implement with TDD, parallel code review |
| **5. QA** | 14 quality gates, security audit, load testing |
| **6. Deployment** | Blue-green deploy, auto-rollback on errors |
| **7. Business** | Marketing, sales, legal, support setup |
| **8. Growth** | Continuous optimization, A/B testing, feedback loops |

### Parallel Code Review Pattern

Every task goes through 3 reviewers simultaneously:

```
IMPLEMENT → REVIEW (3 parallel) → AGGREGATE → FIX → RE-REVIEW → COMPLETE
                │
                ├─ code-reviewer (opus)
                ├─ business-logic-reviewer (opus)
                └─ security-reviewer (opus)
```

### Severity-Based Issue Handling

| Severity | Action |
|----------|--------|
| Critical/High/Medium | Block. Fix immediately. Re-review. |
| Low | Add `// TODO(review): ...` comment, continue |
| Cosmetic | Add `// FIXME(nitpick): ...` comment, continue |

## Directory Structure

When running, Loki Mode creates:

```
.loki/
├── state/          # Orchestrator and agent states
├── queue/          # Task queue (pending, in-progress, completed, dead-letter)
├── messages/       # Inter-agent communication
├── logs/           # Audit logs
├── config/         # Configuration files
├── prompts/        # Agent role prompts
├── artifacts/      # Releases, reports, backups
└── scripts/        # Helper scripts
```

## Configuration

### Circuit Breakers

```yaml
# .loki/config/circuit-breakers.yaml
defaults:
  failureThreshold: 5
  cooldownSeconds: 300
```

### External Alerting

```yaml
# .loki/config/alerting.yaml
channels:
  slack:
    webhook_url: "${SLACK_WEBHOOK_URL}"
    severity: [critical, high]
```

## Example PRDs for Testing

Test the skill with these pre-built PRDs in the `examples/` directory:

| PRD | Complexity | Time | Description |
|-----|------------|------|-------------|
| `simple-todo-app.md` | Low | ~10 min | Basic todo app - tests core functionality |
| `api-only.md` | Low | ~10 min | REST API only - tests backend agents |
| `static-landing-page.md` | Low | ~5 min | HTML/CSS only - tests frontend/marketing |
| `full-stack-demo.md` | Medium | ~30-60 min | Complete bookmark manager - full test |

```bash
# Example: Test with simple todo app
claude --dangerously-skip-permissions
> Loki Mode with PRD at examples/simple-todo-app.md
```

## Running Tests

The skill includes a comprehensive test suite:

```bash
# Run all tests
./tests/run-all-tests.sh

# Run individual test suites
./tests/test-bootstrap.sh        # Directory structure, state init
./tests/test-task-queue.sh       # Queue operations, priorities
./tests/test-circuit-breaker.sh  # Failure handling, recovery
./tests/test-agent-timeout.sh    # Timeout, stuck process handling
./tests/test-state-recovery.sh   # Checkpoints, recovery
```

## Requirements

- Claude Code with `--dangerously-skip-permissions` flag
- Internet access for competitive research and deployment
- Cloud provider credentials (for deployment phase)
- Python 3 (for test suite)

## Comparison

| Feature | Basic Skills | Loki Mode |
|---------|-------------|-----------|
| Agents | 1 | 37 |
| Swarms | - | 6 |
| Code Review | Manual | Parallel 3-reviewer |
| Deployment | None | Multi-cloud |
| Business Ops | None | Full stack |
| State Recovery | None | Checkpoint/resume |
| Alerting | None | Slack/PagerDuty |

## Contributing

Contributions welcome! Please read the skill and open issues for bugs or feature requests.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [LerianStudio/ring](https://github.com/LerianStudio/ring) subagent-driven-development pattern
- Built for the [Claude Code](https://claude.ai) ecosystem

---

**Keywords:** claude-code, claude-skills, ai-agents, autonomous-development, multi-agent-system, sdlc-automation, startup-automation, devops, mlops, deployment-automation
