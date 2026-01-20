# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Loki Mode is a Claude Code skill that orchestrates 37 specialized AI agent types across 6 swarms to autonomously build, test, deploy, and scale complete startups from a PRD. Zero human intervention required.

## Commands

### Running Loki Mode
```bash
# Autonomous mode (recommended)
./autonomy/run.sh ./path/to/prd.md

# Manual mode
claude --dangerously-skip-permissions
> Loki Mode with PRD at ./path/to/prd.md

# With specific rules
> Loki Mode with rules react,firebase-rules
```

### Testing
```bash
# Run all tests
./tests/run-all-tests.sh

# Run individual test suites
./tests/test-bootstrap.sh           # Directory structure, state init
./tests/test-task-queue.sh          # Queue operations, priorities
./tests/test-circuit-breaker.sh     # Failure handling, recovery
./tests/test-agent-timeout.sh       # Timeout, stuck process handling
./tests/test-state-recovery.sh      # Checkpoints, recovery
./tests/test-confidence-routing.sh  # 4-tier routing system
./tests/test-debate-verification.sh # DeepMind debate pattern
./tests/test-review-to-memory.sh    # Learning from code reviews
./tests/test-rules-integration.sh   # Rules discovery and loading
./tests/test-vibe-kanban-export.sh  # Vibe Kanban SQLite sync
```

### Benchmarks
```bash
# HumanEval benchmark
./benchmarks/run-benchmarks.sh humaneval --execute              # Direct Claude (baseline)
./benchmarks/run-benchmarks.sh humaneval --execute --loki       # Multi-agent RARV mode
./benchmarks/run-benchmarks.sh humaneval --execute --limit 10   # First 10 problems only

# SWE-bench benchmark
./benchmarks/run-benchmarks.sh swebench --execute --loki
```

### Environment Variables
```bash
# Retry/timeout settings
LOKI_MAX_RETRIES=50         # Max retry attempts (default: 50)
LOKI_BASE_WAIT=60           # Base wait time in seconds
LOKI_MAX_WAIT=3600          # Max wait time (1 hour)

# Verification settings
LOKI_DEBATE_ENABLED=true    # Enable debate verification
LOKI_DEBATE_THRESHOLD=0.70  # Confidence threshold for debate

# Rules integration (v2.37.1+loki_ruled.2)
LOKI_RULES=react,firebase   # Comma-separated rules to load (optional)
LOKI_INTERACTIVE_RULES=true # Enable interactive rule selection prompt
```

## Architecture

### Key Files
| File | Purpose |
|------|---------|
| `SKILL.md` | Main skill definition (~1350 lines) - read this first |
| `references/` | Detailed documentation loaded progressively |
| `autonomy/run.sh` | Autonomous wrapper script with rate limit handling |
| `benchmarks/run-benchmarks.sh` | HumanEval and SWE-bench benchmark runner |

### Runtime State (`.loki/` directory)
```
.loki/
  CONTINUITY.md           # Working memory - read/update every turn
  specs/openapi.yaml      # API spec - source of truth
  queue/*.json            # Task queue (pending, in-progress, completed, dead-letter)
  state/orchestrator.json # Master state (phase, metrics)
  memory/                 # Episodic, semantic, and procedural memory
  metrics/                # Efficiency tracking and reward signals
```

### RARV Cycle
Every iteration follows: **R**eason -> **A**ct -> **R**eflect -> **V**erify

1. Read `.loki/CONTINUITY.md` including "Mistakes & Learnings"
2. Execute task, commit atomically
3. Update CONTINUITY.md with progress
4. Run tests, verify against spec, retry on failure

### Model Selection by SDLC Phase
- **Opus**: Bootstrap, Discovery, Architecture, Development (planning, implementation)
- **Sonnet**: QA, Deployment (testing, release automation)
- **Haiku**: Operations, monitoring, unit tests (use extensively in parallel)

### Quality Gates (7 total)
1. Input Guardrails - scope validation
2. Static Analysis - CodeQL, ESLint
3. Blind Review - 3 parallel reviewers
4. Anti-Sycophancy - devil's advocate on unanimous approval
5. Output Guardrails - spec compliance, no secrets
6. Severity Blocking - Critical/High/Medium = BLOCK
7. Test Coverage - Unit: >80%, 100% pass

### Confidence-Based Routing
| Confidence | Tier | Behavior |
|------------|------|----------|
| >= 0.95 | Auto-Approve | Direct execution |
| 0.70-0.95 | Direct + Review | Execute then validate |
| 0.40-0.70 | Supervisor | Full coordination |
| < 0.40 | Escalate | Requires human decision |

## Development Guidelines

### When Modifying SKILL.md
- Keep under 500 lines (reference detailed docs in `references/` instead)
- Update version in header AND footer
- Update CHANGELOG.md with new version entry

### Version Numbering
Current: v2.37.1+loki_ruled.2

### Code Style
- No emojis in code or documentation
- Clear, concise comments only when necessary
- Follow existing patterns in codebase
- Additional rules in `.cursor/rules/clean-code.md`

### Protected Files (Do Not Edit While Running)
| File | Reason |
|------|--------|
| `autonomy/run.sh` | Currently executing bash script |
| `.loki/dashboard/*` | Served by active HTTP server |

If bugs found, document in `.loki/CONTINUITY.md` under "Pending Fixes".

### Rules Integration
Rules are auto-discovered from (priority order):
1. `.cursor/rules/` (project-local, highest priority)
2. `.claude/rules/` (project-local)
3. `~/.cursor/rules/` (global)
4. `~/.claude/rules/` (global, lowest priority)

Loaded rules index written to `.loki/rules/INDEX.md`.

## Research Foundation

Built on 2025 research patterns:
- **OpenAI**: Agents SDK (guardrails, tripwires, handoffs)
- **DeepMind**: Scalable Oversight via Debate, SIMA 2
- **Anthropic**: Constitutional AI, Explore-Plan-Code
- **Academic**: CONSENSAGENT, GoalAct, ToolOrchestra, MAR

See `references/` for detailed implementation patterns.
