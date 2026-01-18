#!/bin/bash
#===============================================================================
# Loki Mode - Autonomous Runner
# Single script that handles prerequisites, setup, and autonomous execution
#
# Usage:
#   ./autonomy/run.sh [PRD_PATH]
#   ./autonomy/run.sh ./docs/requirements.md
#   ./autonomy/run.sh                          # Interactive mode
#
# Environment Variables:
#   LOKI_MAX_RETRIES    - Max retry attempts (default: 50)
#   LOKI_BASE_WAIT      - Base wait time in seconds (default: 60)
#   LOKI_MAX_WAIT       - Max wait time in seconds (default: 3600)
#   LOKI_SKIP_PREREQS   - Skip prerequisite checks (default: false)
#   LOKI_DASHBOARD      - Enable web dashboard (default: true)
#   LOKI_DASHBOARD_PORT - Dashboard port (default: 57374)
#
# Rules Configuration:
#   LOKI_RULES                 - Comma-separated list of rules to load (default: all)
#                                Example: "react,firebase-rules,clean-code"
#                                Searches: .cursor/rules, .claude/rules, ~/.cursor/rules, ~/.claude/rules
#   LOKI_INTERACTIVE_RULES     - Enable interactive rule selection via AskUserQuestion (default: false)
#
# Resource Monitoring (prevents system overload):
#   LOKI_RESOURCE_CHECK_INTERVAL - Check resources every N seconds (default: 300 = 5min)
#   LOKI_RESOURCE_CPU_THRESHOLD  - CPU % threshold to warn (default: 80)
#   LOKI_RESOURCE_MEM_THRESHOLD  - Memory % threshold to warn (default: 80)
#
# Security & Autonomy Controls (Enterprise):
#   LOKI_STAGED_AUTONOMY    - Require approval before execution (default: false)
#   LOKI_AUDIT_LOG          - Enable audit logging (default: false)
#   LOKI_MAX_PARALLEL_AGENTS - Limit concurrent agent spawning (default: 10)
#   LOKI_SANDBOX_MODE       - Run in sandboxed container (default: false, requires Docker)
#   LOKI_ALLOWED_PATHS      - Comma-separated paths agents can modify (default: all)
#   LOKI_BLOCKED_COMMANDS   - Comma-separated blocked shell commands (default: rm -rf /)
#
# SDLC Phase Controls (all enabled by default, set to 'false' to skip):
#   LOKI_PHASE_UNIT_TESTS      - Run unit tests (default: true)
#   LOKI_PHASE_API_TESTS       - Functional API testing (default: true)
#   LOKI_PHASE_E2E_TESTS       - E2E/UI testing with Playwright (default: true)
#   LOKI_PHASE_SECURITY        - Security scanning OWASP/auth (default: true)
#   LOKI_PHASE_INTEGRATION     - Integration tests SAML/OIDC/SSO (default: true)
#   LOKI_PHASE_CODE_REVIEW     - 3-reviewer parallel code review (default: true)
#   LOKI_PHASE_WEB_RESEARCH    - Competitor/feature gap research (default: true)
#   LOKI_PHASE_PERFORMANCE     - Load/performance testing (default: true)
#   LOKI_PHASE_ACCESSIBILITY   - WCAG compliance testing (default: true)
#   LOKI_PHASE_REGRESSION      - Regression testing (default: true)
#   LOKI_PHASE_UAT             - UAT simulation (default: true)
#
# Autonomous Loop Controls (Ralph Wiggum Mode):
#   LOKI_COMPLETION_PROMISE    - EXPLICIT stop condition text (default: none - runs forever)
#                                Example: "ALL TESTS PASSING 100%"
#                                Only stops when Claude outputs this EXACT text
#   LOKI_MAX_ITERATIONS        - Max loop iterations before exit (default: 1000)
#   LOKI_PERPETUAL_MODE        - Ignore ALL completion signals (default: false)
#                                Set to 'true' for truly infinite operation
#
# 2026 Research Enhancements:
#   LOKI_PROMPT_REPETITION     - Enable prompt repetition for Haiku agents (default: true)
#                                arXiv 2512.14982v1: Improves accuracy 4-5x on structured tasks
#   LOKI_CONFIDENCE_ROUTING    - Enable confidence-based routing (default: true)
#                                HN Production: 4-tier routing (auto-approve, direct, supervisor, escalate)
#   LOKI_AUTONOMY_MODE         - Autonomy level (default: perpetual)
#                                Options: perpetual, checkpoint, supervised
#                                Tim Dettmers: "Shorter bursts of autonomy with feedback loops"
#   LOKI_DEBATE_ENABLED        - Enable debate-based verification (default: true)
#                                DeepMind: Scalable AI Safety via Doubly-Efficient Debate
#   LOKI_DEBATE_MAX_ROUNDS     - Max debate rounds before escalation (default: 2)
#   LOKI_DEBATE_THRESHOLD      - Confidence below which debate triggers (default: 0.70)
#===============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

#===============================================================================
# Self-Copy Protection
# Bash reads scripts incrementally, so editing a running script corrupts execution.
# Solution: Copy ourselves to /tmp and run from there. The original can be safely edited.
#===============================================================================
if [[ -z "${LOKI_RUNNING_FROM_TEMP:-}" ]]; then
    TEMP_SCRIPT="/tmp/loki-run-$$.sh"
    cp "${BASH_SOURCE[0]}" "$TEMP_SCRIPT"
    chmod +x "$TEMP_SCRIPT"
    export LOKI_RUNNING_FROM_TEMP=1
    export LOKI_ORIGINAL_SCRIPT_DIR="$SCRIPT_DIR"
    export LOKI_ORIGINAL_PROJECT_DIR="$PROJECT_DIR"
    exec "$TEMP_SCRIPT" "$@"
fi

# Restore original paths when running from temp
SCRIPT_DIR="${LOKI_ORIGINAL_SCRIPT_DIR:-$SCRIPT_DIR}"
PROJECT_DIR="${LOKI_ORIGINAL_PROJECT_DIR:-$PROJECT_DIR}"

# Clean up temp script on exit
trap 'rm -f "${BASH_SOURCE[0]}" 2>/dev/null' EXIT

# Configuration
MAX_RETRIES=${LOKI_MAX_RETRIES:-50}
BASE_WAIT=${LOKI_BASE_WAIT:-60}
MAX_WAIT=${LOKI_MAX_WAIT:-3600}
SKIP_PREREQS=${LOKI_SKIP_PREREQS:-false}
ENABLE_DASHBOARD=${LOKI_DASHBOARD:-true}
DASHBOARD_PORT=${LOKI_DASHBOARD_PORT:-57374}
RESOURCE_CHECK_INTERVAL=${LOKI_RESOURCE_CHECK_INTERVAL:-300}  # Check every 5 minutes
RESOURCE_CPU_THRESHOLD=${LOKI_RESOURCE_CPU_THRESHOLD:-80}     # CPU % threshold
RESOURCE_MEM_THRESHOLD=${LOKI_RESOURCE_MEM_THRESHOLD:-80}     # Memory % threshold

# Security & Autonomy Controls
STAGED_AUTONOMY=${LOKI_STAGED_AUTONOMY:-false}           # Require plan approval
AUDIT_LOG_ENABLED=${LOKI_AUDIT_LOG:-false}               # Enable audit logging
MAX_PARALLEL_AGENTS=${LOKI_MAX_PARALLEL_AGENTS:-10}      # Limit concurrent agents
SANDBOX_MODE=${LOKI_SANDBOX_MODE:-false}                 # Docker sandbox mode
ALLOWED_PATHS=${LOKI_ALLOWED_PATHS:-""}                  # Empty = all paths allowed
BLOCKED_COMMANDS=${LOKI_BLOCKED_COMMANDS:-"rm -rf /,dd if=,mkfs,:(){ :|:& };:"}

STATUS_MONITOR_PID=""
DASHBOARD_PID=""
RESOURCE_MONITOR_PID=""

# SDLC Phase Controls (all enabled by default)
PHASE_UNIT_TESTS=${LOKI_PHASE_UNIT_TESTS:-true}
PHASE_API_TESTS=${LOKI_PHASE_API_TESTS:-true}
PHASE_E2E_TESTS=${LOKI_PHASE_E2E_TESTS:-true}
PHASE_SECURITY=${LOKI_PHASE_SECURITY:-true}
PHASE_INTEGRATION=${LOKI_PHASE_INTEGRATION:-true}
PHASE_CODE_REVIEW=${LOKI_PHASE_CODE_REVIEW:-true}
PHASE_WEB_RESEARCH=${LOKI_PHASE_WEB_RESEARCH:-true}
PHASE_PERFORMANCE=${LOKI_PHASE_PERFORMANCE:-true}
PHASE_ACCESSIBILITY=${LOKI_PHASE_ACCESSIBILITY:-true}
PHASE_REGRESSION=${LOKI_PHASE_REGRESSION:-true}
PHASE_UAT=${LOKI_PHASE_UAT:-true}

# Autonomous Loop Controls (Ralph Wiggum Mode)
# Default: No auto-completion - runs until max iterations or explicit promise
COMPLETION_PROMISE=${LOKI_COMPLETION_PROMISE:-""}
MAX_ITERATIONS=${LOKI_MAX_ITERATIONS:-1000}
ITERATION_COUNT=0
# Perpetual mode: never stop unless max iterations (ignores all completion signals)
PERPETUAL_MODE=${LOKI_PERPETUAL_MODE:-false}

# 2026 Research Enhancements (minimal additions)
PROMPT_REPETITION=${LOKI_PROMPT_REPETITION:-true}
CONFIDENCE_ROUTING=${LOKI_CONFIDENCE_ROUTING:-true}
AUTONOMY_MODE=${LOKI_AUTONOMY_MODE:-perpetual}  # perpetual|checkpoint|supervised

# Proactive Context Management (OpenCode/Sisyphus pattern, validated by Opus)
COMPACTION_INTERVAL=${LOKI_COMPACTION_INTERVAL:-25}  # Suggest compaction every N iterations

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

#===============================================================================
# Logging Functions
#===============================================================================

log_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} ${BOLD}$1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_warning() { log_warn "$@"; }  # Alias for backwards compatibility
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $*"; }

#===============================================================================
# Prerequisites Check
#===============================================================================

check_prerequisites() {
    log_header "Checking Prerequisites"

    local missing=()

    # Check Claude Code CLI
    log_step "Checking Claude Code CLI..."
    if command -v claude &> /dev/null; then
        local version=$(claude --version 2>/dev/null | head -1 || echo "unknown")
        log_info "Claude Code CLI: $version"
    else
        missing+=("claude")
        log_error "Claude Code CLI not found"
        log_info "Install: https://claude.ai/code or npm install -g @anthropic-ai/claude-code"
    fi

    # Check Python 3
    log_step "Checking Python 3..."
    if command -v python3 &> /dev/null; then
        local py_version=$(python3 --version 2>&1)
        log_info "Python: $py_version"
    else
        missing+=("python3")
        log_error "Python 3 not found"
    fi

    # Check Git
    log_step "Checking Git..."
    if command -v git &> /dev/null; then
        local git_version=$(git --version)
        log_info "Git: $git_version"
    else
        missing+=("git")
        log_error "Git not found"
    fi

    # Check Node.js (optional but recommended)
    log_step "Checking Node.js (optional)..."
    if command -v node &> /dev/null; then
        local node_version=$(node --version)
        log_info "Node.js: $node_version"
    else
        log_warn "Node.js not found (optional, needed for some builds)"
    fi

    # Check npm (optional)
    if command -v npm &> /dev/null; then
        local npm_version=$(npm --version)
        log_info "npm: $npm_version"
    fi

    # Check curl (for web fetches)
    log_step "Checking curl..."
    if command -v curl &> /dev/null; then
        log_info "curl: available"
    else
        missing+=("curl")
        log_error "curl not found"
    fi

    # Check jq (optional but helpful)
    log_step "Checking jq (optional)..."
    if command -v jq &> /dev/null; then
        log_info "jq: available"
    else
        log_warn "jq not found (optional, for JSON parsing)"
    fi

    # Summary
    echo ""
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Please install the missing tools and try again."
        return 1
    else
        log_info "All required prerequisites are installed!"
        return 0
    fi
}

#===============================================================================
# Skill Installation Check
#===============================================================================

check_skill_installed() {
    log_header "Checking Loki Mode Skill"

    local skill_locations=(
        "$HOME/.claude/skills/loki-mode/SKILL.md"
        ".claude/skills/loki-mode/SKILL.md"
        "$PROJECT_DIR/SKILL.md"
    )

    for loc in "${skill_locations[@]}"; do
        if [ -f "$loc" ]; then
            log_info "Skill found: $loc"
            return 0
        fi
    done

    log_warn "Loki Mode skill not found in standard locations"
    log_info "The skill will be used from: $PROJECT_DIR/SKILL.md"

    if [ -f "$PROJECT_DIR/SKILL.md" ]; then
        log_info "Using skill from project directory"
        return 0
    else
        log_error "SKILL.md not found!"
        return 1
    fi
}

#===============================================================================
# Initialize Loki Directory
#===============================================================================

init_loki_dir() {
    log_header "Initializing Loki Mode Directory"

    mkdir -p .loki/{state,queue,messages,logs,config,prompts,artifacts,scripts}
    mkdir -p .loki/queue
    mkdir -p .loki/state/checkpoints
    mkdir -p .loki/artifacts/{releases,reports,backups}
    mkdir -p .loki/memory/{ledgers,handoffs,learnings,episodic,semantic,skills}
    mkdir -p .loki/metrics/{efficiency,rewards}
    mkdir -p .loki/rules
    mkdir -p .loki/signals

    # Initialize queue files if they don't exist
    for queue in pending in-progress completed failed dead-letter; do
        if [ ! -f ".loki/queue/${queue}.json" ]; then
            echo "[]" > ".loki/queue/${queue}.json"
        fi
    done

    # Initialize orchestrator state if it doesn't exist
    if [ ! -f ".loki/state/orchestrator.json" ]; then
        cat > ".loki/state/orchestrator.json" << EOF
{
    "version": "$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "2.2.0")",
    "currentPhase": "BOOTSTRAP",
    "startedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "agents": {},
    "metrics": {
        "tasksCompleted": 0,
        "tasksFailed": 0,
        "retries": 0
    }
}
EOF
    fi

    log_info "Loki directory initialized: .loki/"
}

#===============================================================================
# Global Rules Discovery and Loading
#===============================================================================

discover_rules() {
    local rules_found=()
    local search_dirs=(
        ".cursor/rules"
        ".claude/rules"
        "$HOME/.cursor/rules"
        "$HOME/.claude/rules"
    )

    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            for rule_file in "$dir"/*.mdc "$dir"/*.md; do
                if [ -f "$rule_file" ]; then
                    local rule_name=$(basename "$rule_file" | sed 's/\.\(mdc\|md\)$//')
                    if [[ ! " ${rules_found[*]} " =~ " ${rule_name} " ]]; then
                        rules_found+=("$rule_name")
                    fi
                fi
            done
        fi
    done

    local IFS=','
    echo "${rules_found[*]}"
}

find_rule_source() {
    local rule_name="$1"
    local search_dirs=(
        ".cursor/rules"
        ".claude/rules"
        "$HOME/.cursor/rules"
        "$HOME/.claude/rules"
    )

    for dir in "${search_dirs[@]}"; do
        if [ -f "$dir/${rule_name}.mdc" ]; then
            echo "$dir/${rule_name}.mdc"
            return 0
        elif [ -f "$dir/${rule_name}.md" ]; then
            echo "$dir/${rule_name}.md"
            return 0
        fi
    done
    return 1
}

generate_rules_index() {
    local index_file=".loki/rules/INDEX.md"

    cat > "$index_file" << 'EOF'
# Loaded Rules Index

These rules have been loaded for this Loki Mode session.

## Available Rules

EOF

    for rule_file in .loki/rules/*.mdc .loki/rules/*.md; do
        if [ -f "$rule_file" ] && [ "$(basename "$rule_file")" != "INDEX.md" ]; then
            local rule_name=$(basename "$rule_file")
            local description=$(grep -A1 "^description:" "$rule_file" 2>/dev/null | tail -1 | sed 's/^description: *//' || echo "")
            echo "- **$rule_name**: $description" >> "$index_file"
        fi
    done
}

load_rules() {
    log_header "Loading Project Rules"

    local available_rules=$(discover_rules)

    if [ -z "$available_rules" ]; then
        log_info "No rules found in any rules directory"
        return 0
    fi

    log_info "Available rules: $available_rules"

    local rules_to_load=""

    if [ -n "${LOKI_RULES:-}" ]; then
        rules_to_load="$LOKI_RULES"
        log_info "Using LOKI_RULES from environment: $rules_to_load"
    elif [ -f ".loki/config/rules.txt" ]; then
        rules_to_load=$(cat ".loki/config/rules.txt")
        log_info "Using saved rule selection: $rules_to_load"
    elif [ "${LOKI_INTERACTIVE_RULES:-}" = "true" ]; then
        log_info "Interactive rule selection enabled - will be handled by skill"
        echo "$available_rules" > ".loki/state/available-rules.txt"
        return 0
    else
        rules_to_load="$available_rules"
        log_info "Loading all available rules"
    fi

    local loaded_count=0
    IFS=',' read -ra RULE_ARRAY <<< "$rules_to_load"
    for rule in "${RULE_ARRAY[@]}"; do
        rule=$(echo "$rule" | xargs)
        local source_path=$(find_rule_source "$rule")

        if [ -n "$source_path" ]; then
            cp "$source_path" ".loki/rules/"
            log_info "  Loaded: $rule"
            ((loaded_count++))
        else
            log_warn "  Rule not found: $rule"
        fi
    done

    echo "$rules_to_load" > ".loki/config/rules.txt"
    generate_rules_index
    log_info "Loaded $loaded_count rules to .loki/rules/"
}

#===============================================================================
# Task Status Monitor
#===============================================================================

update_status_file() {
    # Create a human-readable status file
    local status_file=".loki/STATUS.txt"

    # Get current phase
    local current_phase="UNKNOWN"
    if [ -f ".loki/state/orchestrator.json" ]; then
        current_phase=$(python3 -c "import json; print(json.load(open('.loki/state/orchestrator.json')).get('currentPhase', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
    fi

    # Count tasks in each queue
    local pending=0 in_progress=0 completed=0 failed=0
    [ -f ".loki/queue/pending.json" ] && pending=$(python3 -c "import json; print(len(json.load(open('.loki/queue/pending.json'))))" 2>/dev/null || echo "0")
    [ -f ".loki/queue/in-progress.json" ] && in_progress=$(python3 -c "import json; print(len(json.load(open('.loki/queue/in-progress.json'))))" 2>/dev/null || echo "0")
    [ -f ".loki/queue/completed.json" ] && completed=$(python3 -c "import json; print(len(json.load(open('.loki/queue/completed.json'))))" 2>/dev/null || echo "0")
    [ -f ".loki/queue/failed.json" ] && failed=$(python3 -c "import json; print(len(json.load(open('.loki/queue/failed.json'))))" 2>/dev/null || echo "0")

    cat > "$status_file" << EOF
╔════════════════════════════════════════════════════════════════╗
║                    LOKI MODE STATUS                            ║
╚════════════════════════════════════════════════════════════════╝

Updated: $(date)

Phase: $current_phase

Tasks:
  ├─ Pending:     $pending
  ├─ In Progress: $in_progress
  ├─ Completed:   $completed
  └─ Failed:      $failed

Monitor: watch -n 2 cat .loki/STATUS.txt
EOF
}

start_status_monitor() {
    log_step "Starting status monitor..."

    # Initial update
    update_status_file
    update_agents_state

    # Background update loop
    (
        while true; do
            update_status_file
            update_agents_state
            sleep 5
        done
    ) &
    STATUS_MONITOR_PID=$!

    log_info "Status monitor started"
    log_info "Monitor progress: ${CYAN}watch -n 2 cat .loki/STATUS.txt${NC}"
}

stop_status_monitor() {
    if [ -n "$STATUS_MONITOR_PID" ]; then
        kill "$STATUS_MONITOR_PID" 2>/dev/null || true
        wait "$STATUS_MONITOR_PID" 2>/dev/null || true
    fi
    stop_resource_monitor
}

#===============================================================================
# Web Dashboard
#===============================================================================

generate_dashboard() {
    # Generate HTML dashboard with Anthropic design language + Agent Monitoring
    cat > .loki/dashboard/index.html << 'DASHBOARD_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Loki Mode Dashboard</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Söhne', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #FAF9F6;
            color: #1A1A1A;
            padding: 24px;
            min-height: 100vh;
        }
        .header {
            text-align: center;
            padding: 32px 20px;
            margin-bottom: 32px;
        }
        .header h1 {
            color: #D97757;
            font-size: 28px;
            font-weight: 600;
            letter-spacing: -0.5px;
            margin-bottom: 8px;
        }
        .header .subtitle {
            color: #666;
            font-size: 14px;
            font-weight: 400;
        }
        .header .phase {
            display: inline-block;
            margin-top: 16px;
            padding: 8px 16px;
            background: #FFF;
            border: 1px solid #E5E3DE;
            border-radius: 20px;
            font-size: 13px;
            color: #1A1A1A;
            font-weight: 500;
        }
        .stats {
            display: flex;
            justify-content: center;
            gap: 16px;
            margin-bottom: 40px;
            flex-wrap: wrap;
        }
        .stat {
            background: #FFF;
            border: 1px solid #E5E3DE;
            border-radius: 12px;
            padding: 20px 32px;
            text-align: center;
            min-width: 140px;
            transition: box-shadow 0.2s ease;
        }
        .stat:hover { box-shadow: 0 4px 12px rgba(0,0,0,0.06); }
        .stat .number { font-size: 36px; font-weight: 600; margin-bottom: 4px; }
        .stat .label { font-size: 12px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; }
        .stat.pending .number { color: #D97757; }
        .stat.progress .number { color: #5B8DEF; }
        .stat.completed .number { color: #2E9E6E; }
        .stat.failed .number { color: #D44F4F; }
        .stat.agents .number { color: #9B6DD6; }
        .section-header {
            text-align: center;
            font-size: 16px;
            font-weight: 600;
            color: #666;
            margin: 40px 0 20px 0;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .agents-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 16px;
            max-width: 1400px;
            margin: 0 auto 40px auto;
        }
        .agent-card {
            background: #FFF;
            border: 1px solid #E5E3DE;
            border-radius: 12px;
            padding: 16px;
            transition: box-shadow 0.2s ease, border-color 0.2s ease;
        }
        .agent-card:hover {
            box-shadow: 0 4px 12px rgba(0,0,0,0.06);
            border-color: #9B6DD6;
        }
        .agent-card .agent-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 12px;
        }
        .agent-card .agent-id {
            font-size: 11px;
            color: #999;
            font-family: monospace;
        }
        .agent-card .model-badge {
            padding: 4px 10px;
            border-radius: 6px;
            font-size: 10px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .agent-card .model-badge.sonnet {
            background: #E8F0FD;
            color: #5B8DEF;
        }
        .agent-card .model-badge.haiku {
            background: #FFF4E6;
            color: #F59E0B;
        }
        .agent-card .model-badge.opus {
            background: #F3E8FF;
            color: #9B6DD6;
        }
        .agent-card .agent-type {
            font-size: 14px;
            font-weight: 600;
            color: #1A1A1A;
            margin-bottom: 8px;
        }
        .agent-card .agent-status {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 10px;
            font-weight: 500;
            margin-bottom: 12px;
        }
        .agent-card .agent-status.active {
            background: #E6F5EE;
            color: #2E9E6E;
        }
        .agent-card .agent-status.completed {
            background: #F0EFEA;
            color: #666;
        }
        .agent-card .agent-work {
            font-size: 12px;
            color: #666;
            line-height: 1.5;
            margin-bottom: 8px;
        }
        .agent-card .agent-meta {
            display: flex;
            gap: 12px;
            font-size: 11px;
            color: #999;
            margin-top: 8px;
            padding-top: 8px;
            border-top: 1px solid #F0EFEA;
        }
        .agent-card .agent-meta span {
            display: flex;
            align-items: center;
            gap: 4px;
        }
        .columns {
            display: flex;
            gap: 20px;
            overflow-x: auto;
            padding-bottom: 24px;
            max-width: 1400px;
            margin: 0 auto;
        }
        .column {
            flex: 1;
            min-width: 300px;
            max-width: 350px;
            background: #FFF;
            border: 1px solid #E5E3DE;
            border-radius: 12px;
            padding: 20px;
        }
        .column h2 {
            font-size: 13px;
            font-weight: 600;
            color: #666;
            margin-bottom: 16px;
            display: flex;
            align-items: center;
            gap: 10px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .column h2 .count {
            background: #F0EFEA;
            padding: 3px 10px;
            border-radius: 12px;
            font-size: 11px;
            color: #1A1A1A;
        }
        .column.pending h2 .count { background: #FCEEE8; color: #D97757; }
        .column.progress h2 .count { background: #E8F0FD; color: #5B8DEF; }
        .column.completed h2 .count { background: #E6F5EE; color: #2E9E6E; }
        .column.failed h2 .count { background: #FCE8E8; color: #D44F4F; }
        .task {
            background: #FAF9F6;
            border: 1px solid #E5E3DE;
            border-radius: 8px;
            padding: 14px;
            margin-bottom: 12px;
            transition: border-color 0.2s ease;
        }
        .task:hover { border-color: #D97757; }
        .task .id { font-size: 10px; color: #999; margin-bottom: 6px; font-family: monospace; }
        .task .type {
            display: inline-block;
            background: #FCEEE8;
            color: #D97757;
            padding: 3px 10px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 500;
            margin-bottom: 8px;
        }
        .task .title { font-size: 13px; color: #1A1A1A; line-height: 1.5; }
        .task .error {
            font-size: 11px;
            color: #D44F4F;
            margin-top: 10px;
            padding: 10px;
            background: #FCE8E8;
            border-radius: 6px;
            font-family: monospace;
        }
        .refresh {
            position: fixed;
            bottom: 24px;
            right: 24px;
            background: #D97757;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            transition: background 0.2s ease;
            box-shadow: 0 4px 12px rgba(217, 119, 87, 0.3);
        }
        .refresh:hover { background: #C56747; }
        .updated {
            text-align: center;
            color: #999;
            font-size: 12px;
            margin-top: 24px;
        }
        .empty {
            color: #999;
            font-size: 13px;
            text-align: center;
            padding: 24px;
            font-style: italic;
        }
        .powered-by {
            text-align: center;
            margin-top: 40px;
            padding-top: 24px;
            border-top: 1px solid #E5E3DE;
            color: #999;
            font-size: 12px;
        }
        .powered-by span { color: #D97757; font-weight: 500; }
    </style>
</head>
<body>
    <div class="header">
        <h1>LOKI MODE</h1>
        <div class="subtitle">Autonomous Multi-Agent Startup System</div>
        <div class="phase" id="phase">Loading...</div>
    </div>
    <div class="stats">
        <div class="stat agents"><div class="number" id="agents-count">-</div><div class="label">Active Agents</div></div>
        <div class="stat pending"><div class="number" id="pending-count">-</div><div class="label">Pending</div></div>
        <div class="stat progress"><div class="number" id="progress-count">-</div><div class="label">In Progress</div></div>
        <div class="stat completed"><div class="number" id="completed-count">-</div><div class="label">Completed</div></div>
        <div class="stat failed"><div class="number" id="failed-count">-</div><div class="label">Failed</div></div>
    </div>
    <div class="section-header">Active Agents</div>
    <div class="agents-grid" id="agents-grid"></div>
    <div class="section-header">Task Queue</div>
    <div class="columns">
        <div class="column pending"><h2>Pending <span class="count" id="pending-badge">0</span></h2><div id="pending-tasks"></div></div>
        <div class="column progress"><h2>In Progress <span class="count" id="progress-badge">0</span></h2><div id="progress-tasks"></div></div>
        <div class="column completed"><h2>Completed <span class="count" id="completed-badge">0</span></h2><div id="completed-tasks"></div></div>
        <div class="column failed"><h2>Failed <span class="count" id="failed-badge">0</span></h2><div id="failed-tasks"></div></div>
    </div>
    <div class="updated" id="updated">Last updated: -</div>
    <div class="powered-by">Powered by <span>Claude</span></div>
    <button class="refresh" onclick="loadData()">Refresh</button>
    <script>
        async function loadJSON(path) {
            try {
                const res = await fetch(path + '?t=' + Date.now());
                if (!res.ok) return [];
                const text = await res.text();
                if (!text.trim()) return [];
                const data = JSON.parse(text);
                return Array.isArray(data) ? data : (data.tasks || data.agents || []);
            } catch { return []; }
        }
        function getModelClass(model) {
            if (!model) return 'sonnet';
            const m = model.toLowerCase();
            if (m.includes('haiku')) return 'haiku';
            if (m.includes('opus')) return 'opus';
            return 'sonnet';
        }
        function formatDuration(isoDate) {
            if (!isoDate) return 'Unknown';
            const start = new Date(isoDate);
            const now = new Date();
            const seconds = Math.floor((now - start) / 1000);
            if (seconds < 60) return seconds + 's';
            if (seconds < 3600) return Math.floor(seconds / 60) + 'm';
            return Math.floor(seconds / 3600) + 'h ' + Math.floor((seconds % 3600) / 60) + 'm';
        }
        function renderAgent(agent) {
            const modelClass = getModelClass(agent.model);
            const modelName = agent.model || 'Sonnet 4.5';
            const agentType = agent.agent_type || 'general-purpose';
            const status = agent.status === 'completed' ? 'completed' : 'active';
            const currentTask = agent.current_task || (agent.tasks_completed && agent.tasks_completed.length > 0
                ? 'Completed: ' + agent.tasks_completed.join(', ')
                : 'Initializing...');
            const duration = formatDuration(agent.spawned_at);
            const tasksCount = agent.tasks_completed ? agent.tasks_completed.length : 0;

            return `
                <div class="agent-card">
                    <div class="agent-header">
                        <div class="agent-id">${agent.agent_id || 'Unknown'}</div>
                        <div class="model-badge ${modelClass}">${modelName}</div>
                    </div>
                    <div class="agent-type">${agentType}</div>
                    <div class="agent-status ${status}">${status}</div>
                    <div class="agent-work">${currentTask}</div>
                    <div class="agent-meta">
                        <span>⏱ ${duration}</span>
                        <span>✓ ${tasksCount} tasks</span>
                    </div>
                </div>
            `;
        }
        function renderTask(task) {
            const payload = task.payload || {};
            const title = payload.description || payload.action || task.type || 'Task';
            const error = task.lastError ? `<div class="error">${task.lastError}</div>` : '';
            return `<div class="task"><div class="id">${task.id}</div><span class="type">${task.type || 'general'}</span><div class="title">${title}</div>${error}</div>`;
        }
        async function loadData() {
            const [pending, progress, completed, failed, agents] = await Promise.all([
                loadJSON('../queue/pending.json'),
                loadJSON('../queue/in-progress.json'),
                loadJSON('../queue/completed.json'),
                loadJSON('../queue/failed.json'),
                loadJSON('../state/agents.json')
            ]);

            // Agent stats
            document.getElementById('agents-count').textContent = agents.length;
            document.getElementById('agents-grid').innerHTML = agents.length
                ? agents.map(renderAgent).join('')
                : '<div class="empty">No active agents</div>';

            // Task stats
            document.getElementById('pending-count').textContent = pending.length;
            document.getElementById('progress-count').textContent = progress.length;
            document.getElementById('completed-count').textContent = completed.length;
            document.getElementById('failed-count').textContent = failed.length;
            document.getElementById('pending-badge').textContent = pending.length;
            document.getElementById('progress-badge').textContent = progress.length;
            document.getElementById('completed-badge').textContent = completed.length;
            document.getElementById('failed-badge').textContent = failed.length;
            document.getElementById('pending-tasks').innerHTML = pending.length ? pending.map(renderTask).join('') : '<div class="empty">No pending tasks</div>';
            document.getElementById('progress-tasks').innerHTML = progress.length ? progress.map(renderTask).join('') : '<div class="empty">No tasks in progress</div>';
            document.getElementById('completed-tasks').innerHTML = completed.length ? completed.slice(-10).reverse().map(renderTask).join('') : '<div class="empty">No completed tasks</div>';
            document.getElementById('failed-tasks').innerHTML = failed.length ? failed.map(renderTask).join('') : '<div class="empty">No failed tasks</div>';

            try {
                const state = await fetch('../state/orchestrator.json?t=' + Date.now()).then(r => r.json());
                document.getElementById('phase').textContent = 'Phase: ' + (state.currentPhase || 'UNKNOWN');
            } catch { document.getElementById('phase').textContent = 'Phase: UNKNOWN'; }
            document.getElementById('updated').textContent = 'Last updated: ' + new Date().toLocaleTimeString();
        }
        loadData();
        setInterval(loadData, 3000);
    </script>
</body>
</html>
DASHBOARD_HTML
}

update_agents_state() {
    # Aggregate agent information from .agent/sub-agents/*.json into .loki/state/agents.json
    local agents_dir=".agent/sub-agents"
    local output_file=".loki/state/agents.json"

    # Initialize empty array if no agents directory
    if [ ! -d "$agents_dir" ]; then
        echo "[]" > "$output_file"
        return
    fi

    # Find all agent JSON files and aggregate them
    local agents_json="["
    local first=true

    for agent_file in "$agents_dir"/*.json; do
        # Skip if no JSON files exist
        [ -e "$agent_file" ] || continue

        # Read agent JSON
        local agent_data=$(cat "$agent_file" 2>/dev/null)
        if [ -n "$agent_data" ]; then
            # Add comma separator for all but first entry
            if [ "$first" = true ]; then
                first=false
            else
                agents_json="${agents_json},"
            fi
            agents_json="${agents_json}${agent_data}"
        fi
    done

    agents_json="${agents_json}]"

    # Write aggregated data
    echo "$agents_json" > "$output_file"
}

#===============================================================================
# Resource Monitoring
#===============================================================================

check_system_resources() {
    # Check CPU and memory usage and write status to .loki/state/resources.json
    local output_file=".loki/state/resources.json"

    # Get CPU usage (average across all cores)
    local cpu_usage=0
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: get CPU idle from top header, calculate usage = 100 - idle
        local idle=$(top -l 2 -n 0 | grep "CPU usage" | tail -1 | awk -F'[:,]' '{for(i=1;i<=NF;i++) if($i ~ /idle/) print $(i)}' | awk '{print int($1)}')
        cpu_usage=$((100 - ${idle:-0}))
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux: use top or mpstat
        cpu_usage=$(top -bn2 | grep "Cpu(s)" | tail -1 | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print int(100 - $1)}')
    else
        cpu_usage=0
    fi

    # Get memory usage
    local mem_usage=0
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: use vm_stat
        local page_size=$(pagesize)
        local vm_stat=$(vm_stat)
        local pages_free=$(echo "$vm_stat" | awk '/Pages free/ {print $3}' | tr -d '.')
        local pages_active=$(echo "$vm_stat" | awk '/Pages active/ {print $3}' | tr -d '.')
        local pages_inactive=$(echo "$vm_stat" | awk '/Pages inactive/ {print $3}' | tr -d '.')
        local pages_speculative=$(echo "$vm_stat" | awk '/Pages speculative/ {print $3}' | tr -d '.')
        local pages_wired=$(echo "$vm_stat" | awk '/Pages wired down/ {print $4}' | tr -d '.')

        local total_pages=$((pages_free + pages_active + pages_inactive + pages_speculative + pages_wired))
        local used_pages=$((pages_active + pages_wired))
        mem_usage=$((used_pages * 100 / total_pages))
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux: use free
        mem_usage=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
    else
        mem_usage=0
    fi

    # Determine status
    local cpu_status="ok"
    local mem_status="ok"
    local overall_status="ok"
    local warning_message=""

    if [ "$cpu_usage" -ge "$RESOURCE_CPU_THRESHOLD" ]; then
        cpu_status="high"
        overall_status="warning"
        warning_message="CPU usage is ${cpu_usage}% (threshold: ${RESOURCE_CPU_THRESHOLD}%). Consider reducing parallel agent count or pausing non-critical tasks."
    fi

    if [ "$mem_usage" -ge "$RESOURCE_MEM_THRESHOLD" ]; then
        mem_status="high"
        overall_status="warning"
        if [ -n "$warning_message" ]; then
            warning_message="${warning_message} Memory usage is ${mem_usage}% (threshold: ${RESOURCE_MEM_THRESHOLD}%)."
        else
            warning_message="Memory usage is ${mem_usage}% (threshold: ${RESOURCE_MEM_THRESHOLD}%). Consider reducing parallel agent count or cleaning up resources."
        fi
    fi

    # Write JSON status
    cat > "$output_file" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cpu": {
    "usage_percent": $cpu_usage,
    "threshold_percent": $RESOURCE_CPU_THRESHOLD,
    "status": "$cpu_status"
  },
  "memory": {
    "usage_percent": $mem_usage,
    "threshold_percent": $RESOURCE_MEM_THRESHOLD,
    "status": "$mem_status"
  },
  "overall_status": "$overall_status",
  "warning_message": "$warning_message"
}
EOF

    # Log warning if resources are high
    if [ "$overall_status" = "warning" ]; then
        log_warn "RESOURCE WARNING: $warning_message"
    fi
}

start_resource_monitor() {
    log_step "Starting resource monitor (checks every ${RESOURCE_CHECK_INTERVAL}s)..."

    # Initial check
    check_system_resources

    # Background monitoring loop
    (
        while true; do
            sleep "$RESOURCE_CHECK_INTERVAL"
            check_system_resources
        done
    ) &
    RESOURCE_MONITOR_PID=$!

    log_info "Resource monitor started (CPU threshold: ${RESOURCE_CPU_THRESHOLD}%, Memory threshold: ${RESOURCE_MEM_THRESHOLD}%)"
    log_info "Check status: ${CYAN}cat .loki/state/resources.json${NC}"
}

stop_resource_monitor() {
    if [ -n "$RESOURCE_MONITOR_PID" ]; then
        kill "$RESOURCE_MONITOR_PID" 2>/dev/null || true
        wait "$RESOURCE_MONITOR_PID" 2>/dev/null || true
    fi
}

#===============================================================================
# Audit Logging (Enterprise Security)
#===============================================================================

audit_log() {
    # Log security-relevant events for enterprise compliance
    local event_type="$1"
    local event_data="$2"
    local audit_file=".loki/logs/audit-$(date +%Y%m%d).jsonl"

    if [ "$AUDIT_LOG_ENABLED" != "true" ]; then
        return
    fi

    mkdir -p .loki/logs

    local log_entry=$(cat << EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","event":"$event_type","data":"$event_data","user":"$(whoami)","pid":$$}
EOF
)
    echo "$log_entry" >> "$audit_file"
}

check_staged_autonomy() {
    # In staged autonomy mode, write plan and wait for approval
    local plan_file="$1"

    if [ "$STAGED_AUTONOMY" != "true" ]; then
        return 0
    fi

    log_info "STAGED AUTONOMY: Waiting for plan approval..."
    log_info "Review plan at: $plan_file"
    log_info "Create .loki/signals/PLAN_APPROVED to continue"

    audit_log "STAGED_AUTONOMY_WAIT" "plan=$plan_file"

    # Wait for approval signal
    while [ ! -f ".loki/signals/PLAN_APPROVED" ]; do
        sleep 5
    done

    rm -f ".loki/signals/PLAN_APPROVED"
    audit_log "STAGED_AUTONOMY_APPROVED" "plan=$plan_file"
    log_success "Plan approved, continuing execution..."
}

check_command_allowed() {
    # Check if a command is in the blocked list
    local command="$1"

    IFS=',' read -ra BLOCKED_ARRAY <<< "$BLOCKED_COMMANDS"
    for blocked in "${BLOCKED_ARRAY[@]}"; do
        if [[ "$command" == *"$blocked"* ]]; then
            audit_log "BLOCKED_COMMAND" "command=$command,pattern=$blocked"
            log_error "SECURITY: Blocked dangerous command: $command"
            return 1
        fi
    done

    return 0
}

#===============================================================================
# Cross-Project Learnings Database
#===============================================================================

init_learnings_db() {
    # Initialize the cross-project learnings database
    local learnings_dir="${HOME}/.loki/learnings"
    mkdir -p "$learnings_dir"

    # Create database files if they don't exist
    if [ ! -f "$learnings_dir/patterns.jsonl" ]; then
        echo '{"version":"1.0","created":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "$learnings_dir/patterns.jsonl"
    fi

    if [ ! -f "$learnings_dir/mistakes.jsonl" ]; then
        echo '{"version":"1.0","created":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "$learnings_dir/mistakes.jsonl"
    fi

    if [ ! -f "$learnings_dir/successes.jsonl" ]; then
        echo '{"version":"1.0","created":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "$learnings_dir/successes.jsonl"
    fi

    log_info "Learnings database initialized at: $learnings_dir"
}

save_learning() {
    # Save a learning to the cross-project database
    local learning_type="$1"  # pattern, mistake, success
    local category="$2"
    local description="$3"
    local project="${4:-$(basename "$(pwd)")}"

    local learnings_dir="${HOME}/.loki/learnings"
    local target_file="$learnings_dir/${learning_type}s.jsonl"

    if [ ! -d "$learnings_dir" ]; then
        init_learnings_db
    fi

    local learning_entry=$(cat << EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","project":"$project","category":"$category","description":"$description"}
EOF
)
    echo "$learning_entry" >> "$target_file"
    log_info "Saved $learning_type: $category"
}

get_relevant_learnings() {
    # Get learnings relevant to the current context
    local context="$1"
    local learnings_dir="${HOME}/.loki/learnings"
    local output_file=".loki/state/relevant-learnings.json"

    if [ ! -d "$learnings_dir" ]; then
        echo '{"patterns":[],"mistakes":[],"successes":[]}' > "$output_file"
        return
    fi

    # Simple grep-based relevance (can be enhanced with embeddings)
    # Pass context via environment variable to avoid quote escaping issues
    export LOKI_CONTEXT="$context"
    python3 << 'LEARNINGS_SCRIPT'
import json
import os

learnings_dir = os.path.expanduser("~/.loki/learnings")
context = os.environ.get("LOKI_CONTEXT", "").lower()

def load_jsonl(filepath):
    entries = []
    try:
        with open(filepath, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    if 'description' in entry:
                        entries.append(entry)
                except:
                    continue
    except:
        pass
    return entries

def filter_relevant(entries, context, limit=5):
    scored = []
    for e in entries:
        desc = e.get('description', '').lower()
        cat = e.get('category', '').lower()
        score = sum(1 for word in context.split() if word in desc or word in cat)
        if score > 0:
            scored.append((score, e))
    scored.sort(reverse=True, key=lambda x: x[0])
    return [e for _, e in scored[:limit]]

patterns = load_jsonl(f"{learnings_dir}/patterns.jsonl")
mistakes = load_jsonl(f"{learnings_dir}/mistakes.jsonl")
successes = load_jsonl(f"{learnings_dir}/successes.jsonl")

result = {
    "patterns": filter_relevant(patterns, context),
    "mistakes": filter_relevant(mistakes, context),
    "successes": filter_relevant(successes, context)
}

with open(".loki/state/relevant-learnings.json", 'w') as f:
    json.dump(result, f, indent=2)
LEARNINGS_SCRIPT

    log_info "Loaded relevant learnings to: $output_file"
}

extract_learnings_from_session() {
    # Extract learnings from completed session
    local continuity_file=".loki/CONTINUITY.md"

    if [ ! -f "$continuity_file" ]; then
        return
    fi

    log_info "Extracting learnings from session..."

    # Parse CONTINUITY.md for Mistakes & Learnings section
    python3 << EXTRACT_SCRIPT
import re
import json
import os
from datetime import datetime, timezone

continuity_file = ".loki/CONTINUITY.md"
learnings_dir = os.path.expanduser("~/.loki/learnings")

if not os.path.exists(continuity_file):
    exit(0)

with open(continuity_file, 'r') as f:
    content = f.read()

# Find Mistakes & Learnings section
mistakes_match = re.search(r'## Mistakes & Learnings\n(.*?)(?=\n## |\Z)', content, re.DOTALL)
if mistakes_match:
    mistakes_text = mistakes_match.group(1)
    # Extract bullet points
    bullets = re.findall(r'[-*]\s+(.+)', mistakes_text)
    for bullet in bullets:
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "project": os.path.basename(os.getcwd()),
            "category": "session",
            "description": bullet.strip()
        }
        with open(f"{learnings_dir}/mistakes.jsonl", 'a') as f:
            f.write(json.dumps(entry) + "\n")
        print(f"Extracted: {bullet[:50]}...")

print("Learning extraction complete")
EXTRACT_SCRIPT
}

extract_anti_patterns_from_review() {
    # Extract anti-patterns from code review findings (Review-to-Memory Learning)
    # Called after every code review cycle to prevent repeat mistakes
    local review_file="${1:-.loki/logs/latest-review.json}"
    local anti_patterns_dir=".loki/memory/semantic/anti-patterns"

    mkdir -p "$anti_patterns_dir"

    if [ ! -f "$review_file" ]; then
        log_info "No review file found at $review_file"
        return 0
    fi

    log_info "Extracting anti-patterns from code review..."

    python3 << ANTIPATTERN_SCRIPT
import json
import os
from datetime import datetime, timezone

review_file = "$review_file"
anti_patterns_dir = "$anti_patterns_dir"

if not os.path.exists(review_file):
    exit(0)

try:
    with open(review_file, 'r') as f:
        review = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    print("Could not parse review file")
    exit(0)

# Extract findings from review (expecting format: {findings: [{severity, category, description, file, line}]})
findings = review.get('findings', [])
if isinstance(review, list):
    findings = review

extracted = 0
for finding in findings:
    severity = finding.get('severity', 'medium').lower()

    # Only extract Critical, High, or Medium severity findings
    if severity not in ['critical', 'high', 'medium']:
        continue

    category = finding.get('category', 'general')
    description = finding.get('description', finding.get('message', ''))
    file_path = finding.get('file', '')
    prevention = finding.get('prevention', finding.get('fix', 'Follow best practices'))

    if not description:
        continue

    # Generate anti-pattern ID
    pattern_id = f"{category}-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}"

    anti_pattern = {
        "id": pattern_id,
        "pattern": description,
        "category": category,
        "severity": severity,
        "prevention": prevention,
        "source": f"review-{datetime.now(timezone.utc).strftime('%Y-%m-%d')}",
        "file": file_path,
        "confidence": 0.9 if severity == 'critical' else 0.7 if severity == 'high' else 0.5,
        "created": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    }

    # Save to category-specific file
    category_file = os.path.join(anti_patterns_dir, f"{category}.jsonl")
    with open(category_file, 'a') as f:
        f.write(json.dumps(anti_pattern) + "\\n")

    extracted += 1
    print(f"Extracted: [{severity}] {description[:60]}...")

# Also save to global anti-patterns index
if extracted > 0:
    index_file = os.path.join(anti_patterns_dir, "INDEX.json")
    index = {"lastUpdated": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "count": 0}
    if os.path.exists(index_file):
        try:
            with open(index_file, 'r') as f:
                index = json.load(f)
        except:
            pass
    index["count"] = index.get("count", 0) + extracted
    index["lastUpdated"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    with open(index_file, 'w') as f:
        json.dump(index, f, indent=2)

print(f"Extracted {extracted} anti-patterns to {anti_patterns_dir}")
ANTIPATTERN_SCRIPT
}

query_anti_patterns() {
    # Query anti-patterns before implementation to avoid repeat mistakes
    local context="$1"
    local anti_patterns_dir=".loki/memory/semantic/anti-patterns"
    local output_file=".loki/state/relevant-anti-patterns.json"

    if [ ! -d "$anti_patterns_dir" ]; then
        echo '{"antiPatterns":[]}' > "$output_file"
        return 0
    fi

    python3 << QUERY_SCRIPT
import json
import os
import glob

anti_patterns_dir = "$anti_patterns_dir"
context = """$context""".lower()
output_file = "$output_file"

def load_jsonl(filepath):
    entries = []
    if not os.path.exists(filepath):
        return entries
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('{'):
                continue
            try:
                entries.append(json.loads(line))
            except:
                pass
    return entries

# Load all anti-patterns from all category files
all_patterns = []
for jsonl_file in glob.glob(f"{anti_patterns_dir}/*.jsonl"):
    all_patterns.extend(load_jsonl(jsonl_file))

# Score patterns by relevance to context
def score_pattern(pattern):
    desc = pattern.get('pattern', '').lower()
    cat = pattern.get('category', '').lower()
    prevention = pattern.get('prevention', '').lower()

    score = 0
    for word in context.split():
        if len(word) > 3:  # Skip short words
            if word in desc:
                score += 3
            if word in cat:
                score += 2
            if word in prevention:
                score += 1

    # Boost by severity
    severity = pattern.get('severity', 'low')
    if severity == 'critical':
        score *= 2
    elif severity == 'high':
        score *= 1.5

    return score

# Filter and sort by relevance
scored = [(score_pattern(p), p) for p in all_patterns]
scored.sort(reverse=True, key=lambda x: x[0])
relevant = [p for score, p in scored if score > 0][:10]

result = {"antiPatterns": relevant, "count": len(relevant)}
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

if relevant:
    print(f"Found {len(relevant)} relevant anti-patterns")
else:
    print("No relevant anti-patterns found")
QUERY_SCRIPT
}

#===============================================================================
# Confidence-Based Routing
#===============================================================================
# Multi-tier routing based on task confidence scores
# Tier 1 (>=0.95): Auto-approve - execute immediately
# Tier 2 (>=0.70): Direct with review - execute then review
# Tier 3 (>=0.40): Supervisor mode - full orchestration
# Tier 4 (<0.40): Escalate - too uncertain, needs guidance

calculate_task_confidence() {
    # Calculate confidence score (0.0-1.0) for a task
    local task_file="$1"
    local output_file="${2:-.loki/state/task-confidence.json}"

    if [ ! -f "$task_file" ]; then
        echo '{"confidence":0.5,"tier":"supervisor","factors":{}}' > "$output_file"
        return 0
    fi

    python3 << CONFIDENCE_SCRIPT
import json
import os
import re
from datetime import datetime, timezone

task_file = "$task_file"
output_file = "$output_file"

with open(task_file, 'r') as f:
    task = json.load(f)

# Factor 1: Requirement Clarity (0.0-1.0)
def assess_requirement_clarity(task):
    """Score based on how clear and specific the requirements are."""
    description = str(task.get('payload', {}).get('description', task.get('description', '')))

    # Check for ambiguous language
    ambiguous_terms = ['maybe', 'perhaps', 'might', 'probably', 'unclear', 'not sure', 'possibly', 'could be']
    ambiguity_count = sum(1 for term in ambiguous_terms if term in description.lower())

    # Check for concrete elements
    has_goal = bool(task.get('payload', {}).get('goal', ''))
    has_constraints = bool(task.get('payload', {}).get('constraints', []))
    has_target = bool(task.get('payload', {}).get('target', ''))
    has_action = bool(task.get('payload', {}).get('action', ''))

    # Calculate score
    base_score = 1.0 - min(0.6, ambiguity_count * 0.15)
    if has_goal: base_score += 0.1
    if has_constraints: base_score += 0.1
    if has_target: base_score += 0.1
    if has_action: base_score += 0.1

    return min(1.0, max(0.0, base_score))

# Factor 2: Historical Success (0.0-1.0)
def check_historical_success(task):
    """Score based on similar task outcomes."""
    task_type = task.get('type', 'unknown')
    category = task.get('payload', {}).get('category', task_type)

    # Load completed tasks
    completed_file = '.loki/queue/completed.json'
    if not os.path.exists(completed_file):
        return 0.6  # Neutral if no history

    try:
        with open(completed_file, 'r') as f:
            completed = json.load(f)

        similar = [t for t in completed.get('tasks', [])
                   if t.get('type') == task_type]

        if not similar:
            return 0.6  # Neutral if no similar tasks

        success_count = sum(1 for t in similar
                            if t.get('result', {}).get('status') == 'success')
        return success_count / len(similar)
    except:
        return 0.6

# Factor 3: Complexity Assessment (0.0-1.0)
def assess_complexity(task):
    """Score inversely proportional to task complexity."""
    priority = task.get('priority', 5)
    dependencies = len(task.get('dependencies', []))
    timeout = task.get('timeout', 3600)

    # Higher priority often = simpler task
    # More dependencies = more complex
    # Shorter timeout = expected to be simpler

    score = 0.8
    score -= (10 - priority) * 0.03  # Priority 10 = simple, 1 = complex
    score -= dependencies * 0.1       # Each dependency reduces confidence
    if timeout > 3600: score -= 0.1   # Long timeout = complex
    if timeout < 300: score += 0.1    # Short timeout = simple

    return min(1.0, max(0.0, score))

# Factor 4: Resource Availability (0.0-1.0)
def check_resources():
    """Score based on current system resources."""
    resources_file = '.loki/state/resources.json'
    if not os.path.exists(resources_file):
        return 0.8  # Assume good if no monitoring

    try:
        with open(resources_file, 'r') as f:
            resources = json.load(f)

        cpu = resources.get('cpu', 0)
        memory = resources.get('memory', 0)
        agents = resources.get('activeAgents', 0)
        max_agents = 10  # MAX_PARALLEL_AGENTS

        # Lower score if resources are strained
        score = 1.0
        if cpu > 80: score -= 0.3
        elif cpu > 60: score -= 0.1
        if memory > 80: score -= 0.3
        elif memory > 60: score -= 0.1
        if agents >= max_agents: score -= 0.4
        elif agents > max_agents * 0.7: score -= 0.2

        return max(0.0, score)
    except:
        return 0.8

# Calculate weighted confidence
weights = {
    'requirement_clarity': 0.35,
    'historical_success': 0.25,
    'complexity': 0.25,
    'resources': 0.15
}

factors = {
    'requirement_clarity': assess_requirement_clarity(task),
    'historical_success': check_historical_success(task),
    'complexity': assess_complexity(task),
    'resources': check_resources()
}

confidence = sum(factors[k] * weights[k] for k in factors)
confidence = round(confidence, 3)

# Determine tier
if confidence >= 0.95:
    tier = 'auto-approve'
elif confidence >= 0.70:
    tier = 'direct-review'
elif confidence >= 0.40:
    tier = 'supervisor'
else:
    tier = 'escalate'

result = {
    'confidence': confidence,
    'tier': tier,
    'factors': {k: round(v, 3) for k, v in factors.items()},
    'weights': weights,
    'taskId': task.get('id', 'unknown'),
    'taskType': task.get('type', 'unknown'),
    'calculatedAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
}

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"CONFIDENCE:{confidence}")
print(f"TIER:{tier}")
CONFIDENCE_SCRIPT
}

route_task_by_confidence() {
    # Route a task based on its confidence score
    local task_file="$1"
    local action=""

    # Calculate confidence if not already done
    if [ ! -f ".loki/state/task-confidence.json" ]; then
        calculate_task_confidence "$task_file"
    fi

    local confidence_file=".loki/state/task-confidence.json"
    local tier=$(python3 -c "import json; print(json.load(open('$confidence_file'))['tier'])")
    local confidence=$(python3 -c "import json; print(json.load(open('$confidence_file'))['confidence'])")

    log_info "Task confidence: $confidence (tier: $tier)"

    case "$tier" in
        "auto-approve")
            log_info "Auto-approving task (high confidence)"
            action="execute_direct"
            ;;
        "direct-review")
            log_info "Executing with post-review (medium-high confidence)"
            action="execute_with_review"
            ;;
        "supervisor")
            log_info "Full supervisor orchestration (medium confidence)"
            action="supervisor_mode"
            ;;
        "escalate")
            log_warn "Task escalated - confidence too low"
            action="escalate"
            ;;
    esac

    echo "$action"
}

get_routing_recommendation() {
    # Get routing recommendation for a task without executing
    local task_file="$1"

    calculate_task_confidence "$task_file" ".loki/state/task-confidence.json"

    python3 << RECOMMEND_SCRIPT
import json

with open('.loki/state/task-confidence.json', 'r') as f:
    result = json.load(f)

tier_descriptions = {
    'auto-approve': 'Execute immediately without review (very high confidence)',
    'direct-review': 'Execute then run automated review (high confidence)',
    'supervisor': 'Use full supervisor orchestration (moderate confidence)',
    'escalate': 'Seek clarification before proceeding (low confidence)'
}

print(f"Confidence: {result['confidence']:.1%}")
print(f"Tier: {result['tier']}")
print(f"Recommendation: {tier_descriptions[result['tier']]}")
print()
print("Factor breakdown:")
for factor, score in result['factors'].items():
    weight = result['weights'][factor]
    contribution = score * weight
    print(f"  {factor}: {score:.1%} (weight: {weight:.0%}, contribution: {contribution:.3f})")
RECOMMEND_SCRIPT
}

#===============================================================================
# Debate-Based Verification (DeepMind Pattern)
# Based on "Scalable AI Safety via Doubly-Efficient Debate"
# Uses proponent/opponent debate to verify proposals for critical decisions
#===============================================================================

DEBATE_ENABLED=${LOKI_DEBATE_ENABLED:-true}
DEBATE_MAX_ROUNDS=${LOKI_DEBATE_MAX_ROUNDS:-2}
DEBATE_THRESHOLD=${LOKI_DEBATE_THRESHOLD:-0.70}  # Confidence below this triggers debate

create_debate_proposal() {
    # Create a proposal file for debate
    local proposal_type="$1"
    local proposal_content="$2"
    local context="${3:-}"
    local output_file="${4:-.loki/state/debate-proposal.json}"

    python3 << PROPOSAL_SCRIPT
import json
from datetime import datetime, timezone

proposal = {
    'id': 'debate-' + datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S'),
    'type': "$proposal_type",
    'content': '''$proposal_content''',
    'context': '''$context''',
    'createdAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    'status': 'pending'
}

with open("$output_file", 'w') as f:
    json.dump(proposal, f, indent=2)

print(f"PROPOSAL_ID:{proposal['id']}")
PROPOSAL_SCRIPT
}

run_debate_round() {
    # Execute one round of debate between proponent and opponent
    local proposal_file="$1"
    local round_number="$2"
    local debate_log="${3:-.loki/state/debate-log.json}"

    python3 << DEBATE_ROUND_SCRIPT
import json
from datetime import datetime, timezone

proposal_file = "$proposal_file"
round_num = int("$round_number")
debate_log = "$debate_log"

# Load proposal
with open(proposal_file, 'r') as f:
    proposal = json.load(f)

# Load or initialize debate log
try:
    with open(debate_log, 'r') as f:
        log = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    log = {
        'proposalId': proposal['id'],
        'proposalType': proposal['type'],
        'rounds': [],
        'outcome': None,
        'startedAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    }

# Simulate proponent defense based on proposal strength
def generate_defense(proposal, round_num, previous_challenges):
    """Generate defense arguments for the proposal."""
    content = proposal.get('content', '')
    context = proposal.get('context', '')

    # Score proposal clarity and completeness
    has_specific_goal = any(kw in content.lower() for kw in ['implement', 'add', 'fix', 'update', 'create'])
    has_reasoning = any(kw in content.lower() for kw in ['because', 'since', 'therefore', 'in order to'])
    has_constraints = any(kw in content.lower() for kw in ['must', 'should', 'requirement', 'constraint'])

    strength_score = 0.5
    if has_specific_goal: strength_score += 0.15
    if has_reasoning: strength_score += 0.15
    if has_constraints: strength_score += 0.1
    if len(content) > 100: strength_score += 0.1

    # Address previous challenges
    addressed_challenges = []
    for challenge in previous_challenges:
        if challenge.get('valid', False):
            addressed_challenges.append({
                'challenge': challenge.get('point', ''),
                'response': f"This is addressed by: {proposal['type']} scope"
            })

    return {
        'strengthScore': min(1.0, strength_score),
        'arguments': [
            f"The proposal is clear and actionable: {proposal['type']}",
            f"Implementation follows established patterns",
            f"Risk is mitigated by existing tests"
        ],
        'addressedChallenges': addressed_challenges
    }

def generate_challenge(proposal, defense, round_num):
    """Generate opponent challenges to find flaws."""
    content = proposal.get('content', '')
    defense_score = defense.get('strengthScore', 0.5)

    # Identify potential weaknesses
    flaws = []

    # Check for missing elements
    if 'test' not in content.lower() and 'verify' not in content.lower():
        flaws.append({
            'point': 'No testing strategy mentioned',
            'severity': 'medium',
            'valid': True
        })

    if 'rollback' not in content.lower() and 'revert' not in content.lower():
        flaws.append({
            'point': 'No rollback plan specified',
            'severity': 'low',
            'valid': defense_score < 0.7
        })

    if len(content) < 50:
        flaws.append({
            'point': 'Proposal lacks sufficient detail',
            'severity': 'high',
            'valid': True
        })

    # If defense is strong, challenges are weaker
    if defense_score >= 0.8:
        for flaw in flaws:
            flaw['valid'] = False
            flaw['reason'] = 'Defense adequately addressed this concern'

    return {
        'flaws': flaws,
        'hasValidFlaw': any(f.get('valid', False) for f in flaws),
        'criticalFlawCount': sum(1 for f in flaws if f.get('valid') and f.get('severity') == 'high')
    }

# Get previous challenges from log
previous_challenges = []
for r in log.get('rounds', []):
    previous_challenges.extend(r.get('challenge', {}).get('flaws', []))

# Run debate round
defense = generate_defense(proposal, round_num, previous_challenges)
challenge = generate_challenge(proposal, defense, round_num)

round_result = {
    'round': round_num,
    'timestamp': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    'defense': defense,
    'challenge': challenge
}

log['rounds'].append(round_result)

# Determine if debate should continue
if not challenge['hasValidFlaw']:
    log['outcome'] = {
        'verified': True,
        'reason': 'Opponent could not find valid flaws',
        'roundsCompleted': round_num,
        'finalDefenseScore': defense['strengthScore']
    }
elif round_num >= int("$DEBATE_MAX_ROUNDS"):
    log['outcome'] = {
        'verified': False,
        'reason': f"Unresolved flaws after {round_num} rounds",
        'roundsCompleted': round_num,
        'unresolvedFlaws': [f for f in challenge['flaws'] if f.get('valid', False)]
    }

log['lastUpdated'] = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

with open(debate_log, 'w') as f:
    json.dump(log, f, indent=2)

# Output result
if log.get('outcome'):
    print(f"DEBATE_COMPLETE:{'verified' if log['outcome']['verified'] else 'rejected'}")
else:
    print(f"DEBATE_CONTINUE:round_{round_num + 1}")
print(f"HAS_VALID_FLAW:{challenge['hasValidFlaw']}")
print(f"DEFENSE_SCORE:{defense['strengthScore']:.2f}")
DEBATE_ROUND_SCRIPT
}

debate_verification() {
    # Main debate verification function
    # Returns: "verified" or "rejected" or "escalate"
    local proposal_type="$1"
    local proposal_content="$2"
    local context="${3:-}"

    if [ "$DEBATE_ENABLED" != "true" ]; then
        log_info "Debate verification disabled, auto-approving"
        echo "verified"
        return 0
    fi

    log_header "Running Debate-Based Verification"
    log_info "Proposal type: $proposal_type"
    log_info "Max rounds: $DEBATE_MAX_ROUNDS"

    # Create proposal
    create_debate_proposal "$proposal_type" "$proposal_content" "$context"

    local proposal_file=".loki/state/debate-proposal.json"
    local debate_log=".loki/state/debate-log.json"

    # Initialize fresh debate log
    rm -f "$debate_log"

    # Run debate rounds
    local round=1
    local outcome=""

    while [ $round -le $DEBATE_MAX_ROUNDS ]; do
        log_step "Debate round $round of $DEBATE_MAX_ROUNDS"

        local result=$(run_debate_round "$proposal_file" "$round" "$debate_log")

        # Check if debate is complete
        if echo "$result" | grep -q "DEBATE_COMPLETE"; then
            if echo "$result" | grep -q "DEBATE_COMPLETE:verified"; then
                outcome="verified"
                log_info "Proposal verified (no valid flaws found)"
            else
                outcome="rejected"
                log_warn "Proposal rejected (unresolved flaws)"
            fi
            break
        fi

        ((round++))
    done

    # If max rounds reached without resolution
    if [ -z "$outcome" ]; then
        log_warn "Debate inconclusive after $DEBATE_MAX_ROUNDS rounds"
        outcome="escalate"
    fi

    # Log outcome
    echo "$outcome"
}

evaluate_debate_outcome() {
    # Analyze debate log and return structured result
    local debate_log="${1:-.loki/state/debate-log.json}"

    if [ ! -f "$debate_log" ]; then
        echo '{"verified":false,"reason":"No debate log found"}'
        return 1
    fi

    python3 << EVAL_SCRIPT
import json

with open("$debate_log", 'r') as f:
    log = json.load(f)

outcome = log.get('outcome', {})
rounds = log.get('rounds', [])

result = {
    'proposalId': log.get('proposalId', 'unknown'),
    'verified': outcome.get('verified', False),
    'reason': outcome.get('reason', 'Unknown'),
    'roundsCompleted': len(rounds),
    'finalDefenseScore': outcome.get('finalDefenseScore', 0),
    'unresolvedFlaws': outcome.get('unresolvedFlaws', []),
    'recommendation': 'proceed' if outcome.get('verified') else 'revise'
}

print(json.dumps(result, indent=2))
EVAL_SCRIPT
}

should_trigger_debate() {
    # Determine if a task should go through debate verification
    local task_file="$1"
    local confidence_file=".loki/state/task-confidence.json"

    # Calculate confidence if not available
    if [ ! -f "$confidence_file" ]; then
        calculate_task_confidence "$task_file" "$confidence_file"
    fi

    python3 << TRIGGER_SCRIPT
import json

confidence_file = "$confidence_file"
threshold = float("$DEBATE_THRESHOLD")

try:
    with open(confidence_file, 'r') as f:
        data = json.load(f)

    confidence = data.get('confidence', 0.5)
    tier = data.get('tier', 'supervisor')

    # Trigger debate if:
    # 1. Confidence is below threshold
    # 2. Tier is 'supervisor' or 'escalate'
    # 3. Task type is critical (security, deployment, database)
    task_type = data.get('taskType', 'unknown')
    critical_types = ['security', 'deployment', 'database', 'infrastructure', 'auth']
    is_critical = any(ct in task_type.lower() for ct in critical_types)

    should_debate = (
        confidence < threshold or
        tier in ['supervisor', 'escalate'] or
        is_critical
    )

    if should_debate:
        print("DEBATE_REQUIRED")
        print(f"REASON:confidence={confidence:.2f},tier={tier},critical={is_critical}")
    else:
        print("DEBATE_SKIP")
        print(f"REASON:confidence={confidence:.2f} above threshold")

except Exception as e:
    print("DEBATE_SKIP")
    print(f"REASON:error={str(e)}")
TRIGGER_SCRIPT
}

start_dashboard() {
    log_header "Starting Loki Dashboard"

    # Create dashboard directory
    mkdir -p .loki/dashboard

    # Generate HTML
    generate_dashboard

    # Kill any existing process on the dashboard port
    if lsof -i :$DASHBOARD_PORT &>/dev/null; then
        log_step "Killing existing process on port $DASHBOARD_PORT..."
        lsof -ti :$DASHBOARD_PORT | xargs kill -9 2>/dev/null || true
        sleep 1
    fi

    # Start Python HTTP server from .loki/ root so it can serve queue/ and state/
    log_step "Starting dashboard server..."
    (
        cd .loki
        python3 -m http.server $DASHBOARD_PORT --bind 127.0.0.1 2>&1 | while read line; do
            echo "[dashboard] $line" >> logs/dashboard.log
        done
    ) &
    DASHBOARD_PID=$!

    sleep 1

    if kill -0 $DASHBOARD_PID 2>/dev/null; then
        log_info "Dashboard started (PID: $DASHBOARD_PID)"
        log_info "Dashboard: ${CYAN}http://127.0.0.1:$DASHBOARD_PORT/dashboard/index.html${NC}"

        # Open in browser (macOS)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            open "http://127.0.0.1:$DASHBOARD_PORT/dashboard/index.html" 2>/dev/null || true
        fi
        return 0
    else
        log_warn "Dashboard failed to start"
        DASHBOARD_PID=""
        return 1
    fi
}

stop_dashboard() {
    if [ -n "$DASHBOARD_PID" ]; then
        kill "$DASHBOARD_PID" 2>/dev/null || true
        wait "$DASHBOARD_PID" 2>/dev/null || true
    fi
}

#===============================================================================
# Calculate Exponential Backoff
#===============================================================================

calculate_wait() {
    local retry="$1"
    local wait_time=$((BASE_WAIT * (2 ** retry)))

    # Add jitter (0-30 seconds)
    local jitter=$((RANDOM % 30))
    wait_time=$((wait_time + jitter))

    # Cap at max wait
    if [ $wait_time -gt $MAX_WAIT ]; then
        wait_time=$MAX_WAIT
    fi

    echo $wait_time
}

#===============================================================================
# Rate Limit Detection
#===============================================================================

# Detect rate limit from log and calculate wait time until reset
# Returns: seconds to wait, or 0 if no rate limit detected
detect_rate_limit() {
    local log_file="$1"

    # Look for rate limit message like "resets 4am" or "resets 10pm"
    local reset_time=$(grep -o "resets [0-9]\+[ap]m" "$log_file" 2>/dev/null | tail -1 | grep -o "[0-9]\+[ap]m")

    if [ -z "$reset_time" ]; then
        echo 0
        return
    fi

    # Parse the reset time
    local hour=$(echo "$reset_time" | grep -o "[0-9]\+")
    local ampm=$(echo "$reset_time" | grep -o "[ap]m")

    # Convert to 24-hour format
    if [ "$ampm" = "pm" ] && [ "$hour" -ne 12 ]; then
        hour=$((hour + 12))
    elif [ "$ampm" = "am" ] && [ "$hour" -eq 12 ]; then
        hour=0
    fi

    # Get current time
    local current_hour=$(date +%H)
    local current_min=$(date +%M)
    local current_sec=$(date +%S)

    # Calculate seconds until reset
    local current_secs=$((current_hour * 3600 + current_min * 60 + current_sec))
    local reset_secs=$((hour * 3600))

    local wait_secs=$((reset_secs - current_secs))

    # If reset time is in the past, it means tomorrow
    if [ $wait_secs -le 0 ]; then
        wait_secs=$((wait_secs + 86400))  # Add 24 hours
    fi

    # Add 2 minute buffer to ensure limit is actually reset
    wait_secs=$((wait_secs + 120))

    echo $wait_secs
}

# Format seconds into human-readable time
format_duration() {
    local secs="$1"
    local hours=$((secs / 3600))
    local mins=$(((secs % 3600) / 60))

    if [ $hours -gt 0 ]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

#===============================================================================
# Check Completion
#===============================================================================

is_completed() {
    # Check orchestrator state
    if [ -f ".loki/state/orchestrator.json" ]; then
        if command -v python3 &> /dev/null; then
            local phase=$(python3 -c "import json; print(json.load(open('.loki/state/orchestrator.json')).get('currentPhase', ''))" 2>/dev/null || echo "")
            # Accept various completion states
            if [ "$phase" = "COMPLETED" ] || [ "$phase" = "complete" ] || [ "$phase" = "finalized" ] || [ "$phase" = "growth-loop" ]; then
                return 0
            fi
        fi
    fi

    # Check for completion marker
    if [ -f ".loki/COMPLETED" ]; then
        return 0
    fi

    return 1
}

# Check if completion promise is fulfilled in log output
check_completion_promise() {
    local log_file="$1"

    # Check for the completion promise phrase in recent log output
    if grep -q "COMPLETION PROMISE FULFILLED" "$log_file" 2>/dev/null; then
        return 0
    fi

    # Check for custom completion promise text
    if [ -n "$COMPLETION_PROMISE" ] && grep -qF "$COMPLETION_PROMISE" "$log_file" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Check if max iterations reached
check_max_iterations() {
    if [ $ITERATION_COUNT -ge $MAX_ITERATIONS ]; then
        log_warn "Max iterations ($MAX_ITERATIONS) reached. Stopping."
        return 0
    fi
    return 1
}

# Check if context clear was requested by agent
check_context_clear_signal() {
    if [ -f ".loki/signals/CONTEXT_CLEAR_REQUESTED" ]; then
        log_info "Context clear signal detected from agent"
        rm -f ".loki/signals/CONTEXT_CLEAR_REQUESTED"
        return 0
    fi
    return 1
}

# Load latest ledger content for context injection
load_ledger_context() {
    local ledger_content=""

    # Find most recent ledger
    local latest_ledger=$(ls -t .loki/memory/ledgers/LEDGER-*.md 2>/dev/null | head -1)

    if [ -n "$latest_ledger" ] && [ -f "$latest_ledger" ]; then
        ledger_content=$(cat "$latest_ledger" | head -100)
        echo "$ledger_content"
    fi
}

# Load recent handoffs for context
load_handoff_context() {
    local handoff_content=""

    # Find most recent handoff (last 24 hours)
    local recent_handoff=$(find .loki/memory/handoffs -name "*.md" -mtime -1 2>/dev/null | head -1)

    if [ -n "$recent_handoff" ] && [ -f "$recent_handoff" ]; then
        handoff_content=$(cat "$recent_handoff" | head -80)
        echo "$handoff_content"
    fi
}

# Load relevant learnings
load_learnings_context() {
    local learnings=""

    # Get recent learnings (last 7 days)
    for learning in $(find .loki/memory/learnings -name "*.md" -mtime -7 2>/dev/null | head -5); do
        learnings+="$(head -30 "$learning")\n---\n"
    done

    echo -e "$learnings"
}

#===============================================================================
# Save/Load Wrapper State
#===============================================================================

save_state() {
    local retry_count="$1"
    local status="$2"
    local exit_code="$3"

    cat > ".loki/autonomy-state.json" << EOF
{
    "retryCount": $retry_count,
    "status": "$status",
    "lastExitCode": $exit_code,
    "lastRun": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "prdPath": "${PRD_PATH:-}",
    "pid": $$,
    "maxRetries": $MAX_RETRIES,
    "baseWait": $BASE_WAIT
}
EOF
}

load_state() {
    if [ -f ".loki/autonomy-state.json" ]; then
        if command -v python3 &> /dev/null; then
            RETRY_COUNT=$(python3 -c "import json; print(json.load(open('.loki/autonomy-state.json')).get('retryCount', 0))" 2>/dev/null || echo "0")
        else
            RETRY_COUNT=0
        fi
    else
        RETRY_COUNT=0
    fi
}

#===============================================================================
# Build Resume Prompt
#===============================================================================

build_prompt() {
    local retry="$1"
    local prd="$2"
    local iteration="$3"

    # Build SDLC phases configuration
    local phases=""
    [ "$PHASE_UNIT_TESTS" = "true" ] && phases="${phases}UNIT_TESTS,"
    [ "$PHASE_API_TESTS" = "true" ] && phases="${phases}API_TESTS,"
    [ "$PHASE_E2E_TESTS" = "true" ] && phases="${phases}E2E_TESTS,"
    [ "$PHASE_SECURITY" = "true" ] && phases="${phases}SECURITY,"
    [ "$PHASE_INTEGRATION" = "true" ] && phases="${phases}INTEGRATION,"
    [ "$PHASE_CODE_REVIEW" = "true" ] && phases="${phases}CODE_REVIEW,"
    [ "$PHASE_WEB_RESEARCH" = "true" ] && phases="${phases}WEB_RESEARCH,"
    [ "$PHASE_PERFORMANCE" = "true" ] && phases="${phases}PERFORMANCE,"
    [ "$PHASE_ACCESSIBILITY" = "true" ] && phases="${phases}ACCESSIBILITY,"
    [ "$PHASE_REGRESSION" = "true" ] && phases="${phases}REGRESSION,"
    [ "$PHASE_UAT" = "true" ] && phases="${phases}UAT,"
    phases="${phases%,}"  # Remove trailing comma

    # Ralph Wiggum Mode - Reason-Act-Reflect-VERIFY cycle with self-verification loop (Boris Cherny pattern)
    local rarv_instruction="RALPH WIGGUM MODE ACTIVE. Use Reason-Act-Reflect-VERIFY cycle: 1) REASON - READ .loki/CONTINUITY.md including 'Mistakes & Learnings' section to avoid past errors. CHECK .loki/state/relevant-learnings.json for cross-project learnings from previous projects (mistakes to avoid, patterns to apply). Check .loki/state/ and .loki/queue/, identify next task. CHECK .loki/state/resources.json for system resource warnings - if CPU or memory is high, reduce parallel agent spawning or pause non-critical tasks. Limit to MAX_PARALLEL_AGENTS=${MAX_PARALLEL_AGENTS}. If queue empty, find new improvements. 2) ACT - Execute task, write code, commit changes atomically (git checkpoint). 3) REFLECT - Update .loki/CONTINUITY.md with progress, update state, identify NEXT improvement. Save valuable learnings for future projects. 4) VERIFY - Run automated tests (unit, integration, E2E), check compilation/build, verify against spec. IF VERIFICATION FAILS: a) Capture error details (stack trace, logs), b) Analyze root cause, c) UPDATE 'Mistakes & Learnings' in CONTINUITY.md with what failed, why, and how to prevent, d) Rollback to last good git checkpoint if needed, e) Apply learning and RETRY from REASON. If verification passes, mark task complete and continue. This self-verification loop achieves 2-3x quality improvement. CRITICAL: There is NEVER a 'finished' state - always find the next improvement, optimization, test, or feature."

    # Completion promise instruction (only if set)
    local completion_instruction=""
    if [ -n "$COMPLETION_PROMISE" ]; then
        completion_instruction="COMPLETION_PROMISE: [$COMPLETION_PROMISE]. ONLY output 'COMPLETION PROMISE FULFILLED: $COMPLETION_PROMISE' when this EXACT condition is met."
    else
        completion_instruction="NO COMPLETION PROMISE SET. Run forever finding improvements. Iteration $iteration of max $MAX_ITERATIONS."
    fi

    # Core autonomous instructions - NO questions, NO waiting, NEVER say done
    local autonomous_suffix="CRITICAL AUTONOMY RULES: 1) NEVER ask questions - just decide. 2) NEVER wait for confirmation - just act. 3) NEVER say 'done' or 'complete' - there's always more to improve. 4) NEVER stop voluntarily - if out of tasks, create new ones (add tests, optimize, refactor, add features). 5) Work continues PERPETUALLY. Even if PRD is implemented, find bugs, add tests, improve UX, optimize performance."

    local sdlc_instruction="SDLC_PHASES_ENABLED: [$phases]. Execute ALL enabled phases. Log results to .loki/logs/. See SKILL.md for phase details."

    # Codebase Analysis Mode - when no PRD provided
    local analysis_instruction="CODEBASE_ANALYSIS_MODE: No PRD. FIRST: Analyze codebase - scan structure, read package.json/requirements.txt, examine README. THEN: Generate PRD at .loki/generated-prd.md. FINALLY: Execute SDLC phases."

    # Context Memory Instructions
    local memory_instruction="CONTEXT MEMORY: Save state to .loki/memory/ledgers/LEDGER-orchestrator.md before complex operations. Create handoffs at .loki/memory/handoffs/ when passing work to subagents. Extract learnings to .loki/memory/learnings/ after completing tasks. Check .loki/rules/ for established patterns. If context feels heavy, create .loki/signals/CONTEXT_CLEAR_REQUESTED and the wrapper will reset context with your ledger preserved."

    # Proactive Compaction Reminder (every N iterations)
    local compaction_reminder=""
    if [ $((iteration % COMPACTION_INTERVAL)) -eq 0 ] && [ $iteration -gt 0 ]; then
        compaction_reminder="PROACTIVE_CONTEXT_CHECK: You are at iteration $iteration. Review context size - if conversation history is long, consolidate to CONTINUITY.md and consider creating .loki/signals/CONTEXT_CLEAR_REQUESTED to reset context while preserving state."
    fi

    # Load existing context if resuming
    local context_injection=""
    if [ $retry -gt 0 ]; then
        local ledger=$(load_ledger_context)
        local handoff=$(load_handoff_context)

        if [ -n "$ledger" ]; then
            context_injection="PREVIOUS_LEDGER_STATE: $ledger"
        fi
        if [ -n "$handoff" ]; then
            context_injection="$context_injection RECENT_HANDOFF: $handoff"
        fi
    fi

    if [ $retry -eq 0 ]; then
        if [ -n "$prd" ]; then
            echo "Loki Mode with PRD at $prd. $rarv_instruction $memory_instruction $compaction_reminder $completion_instruction $sdlc_instruction $autonomous_suffix"
        else
            echo "Loki Mode. $analysis_instruction $rarv_instruction $memory_instruction $compaction_reminder $completion_instruction $sdlc_instruction $autonomous_suffix"
        fi
    else
        if [ -n "$prd" ]; then
            echo "Loki Mode - Resume iteration #$iteration (retry #$retry). PRD: $prd. $context_injection $rarv_instruction $memory_instruction $compaction_reminder $completion_instruction $sdlc_instruction $autonomous_suffix"
        else
            echo "Loki Mode - Resume iteration #$iteration (retry #$retry). $context_injection Use .loki/generated-prd.md if exists. $rarv_instruction $memory_instruction $compaction_reminder $completion_instruction $sdlc_instruction $autonomous_suffix"
        fi
    fi
}

#===============================================================================
# Main Autonomous Loop
#===============================================================================

run_autonomous() {
    local prd_path="$1"

    log_header "Starting Autonomous Execution"

    # Auto-detect PRD if not provided
    if [ -z "$prd_path" ]; then
        log_step "No PRD provided, searching for existing PRD files..."
        local found_prd=""

        # Search common PRD file patterns
        for pattern in "PRD.md" "prd.md" "REQUIREMENTS.md" "requirements.md" "SPEC.md" "spec.md" \
                       "docs/PRD.md" "docs/prd.md" "docs/REQUIREMENTS.md" "docs/requirements.md" \
                       "docs/SPEC.md" "docs/spec.md" ".github/PRD.md" "PROJECT.md" "project.md"; do
            if [ -f "$pattern" ]; then
                found_prd="$pattern"
                break
            fi
        done

        if [ -n "$found_prd" ]; then
            log_info "Found existing PRD: $found_prd"
            prd_path="$found_prd"
        elif [ -f ".loki/generated-prd.md" ]; then
            log_info "Using previously generated PRD: .loki/generated-prd.md"
            prd_path=".loki/generated-prd.md"
        else
            log_info "No PRD found - will analyze codebase and generate one"
        fi
    fi

    log_info "PRD: ${prd_path:-Codebase Analysis Mode}"
    log_info "Max retries: $MAX_RETRIES"
    log_info "Max iterations: $MAX_ITERATIONS"
    log_info "Completion promise: $COMPLETION_PROMISE"
    log_info "Base wait: ${BASE_WAIT}s"
    log_info "Max wait: ${MAX_WAIT}s"
    log_info "Autonomy mode: $AUTONOMY_MODE"
    log_info "Prompt repetition (Haiku): $PROMPT_REPETITION"
    log_info "Confidence routing: $CONFIDENCE_ROUTING"
    echo ""

    load_state
    local retry=$RETRY_COUNT

    # Check max iterations before starting
    if check_max_iterations; then
        log_error "Max iterations already reached. Reset with: rm .loki/autonomy-state.json"
        return 1
    fi

    while [ $retry -lt $MAX_RETRIES ]; do
        # Increment iteration count
        ((ITERATION_COUNT++))

        # Check max iterations
        if check_max_iterations; then
            save_state $retry "max_iterations_reached" 0
            return 0
        fi

        local prompt=$(build_prompt $retry "$prd_path" $ITERATION_COUNT)

        echo ""
        log_header "Attempt $((retry + 1)) of $MAX_RETRIES"
        log_info "Prompt: $prompt"
        echo ""

        save_state $retry "running" 0

        # Run Claude Code with live output
        local start_time=$(date +%s)
        local log_file=".loki/logs/autonomy-$(date +%Y%m%d).log"

        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  CLAUDE CODE OUTPUT (live)${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        # Log start time
        echo "=== Session started at $(date) ===" >> "$log_file"
        echo "=== Prompt: $prompt ===" >> "$log_file"

        set +e
        # Run Claude with stream-json for real-time output
        # Parse JSON stream, display formatted output, and track agents
        claude --dangerously-skip-permissions -p "$prompt" \
            --output-format stream-json --verbose 2>&1 | \
            tee -a "$log_file" | \
            python3 -u -c '
import sys
import json
import os
from datetime import datetime, timezone

# ANSI colors
CYAN = "\033[0;36m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
MAGENTA = "\033[0;35m"
DIM = "\033[2m"
NC = "\033[0m"

# Agent tracking
AGENTS_FILE = ".loki/state/agents.json"
QUEUE_IN_PROGRESS = ".loki/queue/in-progress.json"
active_agents = {}  # tool_id -> agent_info
orchestrator_id = "orchestrator-main"
session_start = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def init_orchestrator():
    """Initialize the main orchestrator agent (always visible)."""
    active_agents[orchestrator_id] = {
        "agent_id": orchestrator_id,
        "tool_id": orchestrator_id,
        "agent_type": "orchestrator",
        "model": "sonnet",
        "current_task": "Initializing...",
        "status": "active",
        "spawned_at": session_start,
        "tasks_completed": [],
        "tool_count": 0
    }
    save_agents()

def update_orchestrator_task(tool_name, description=""):
    """Update orchestrator current task based on tool usage."""
    if orchestrator_id in active_agents:
        active_agents[orchestrator_id]["tool_count"] = active_agents[orchestrator_id].get("tool_count", 0) + 1
        if description:
            active_agents[orchestrator_id]["current_task"] = f"{tool_name}: {description[:80]}"
        else:
            active_agents[orchestrator_id]["current_task"] = f"Using {tool_name}..."
        save_agents()

def load_agents():
    """Load existing agents from file."""
    try:
        if os.path.exists(AGENTS_FILE):
            with open(AGENTS_FILE, "r") as f:
                data = json.load(f)
                return {a.get("tool_id", a.get("agent_id")): a for a in data if isinstance(a, dict)}
    except:
        pass
    return {}

def save_agents():
    """Save agents to file for dashboard."""
    try:
        os.makedirs(os.path.dirname(AGENTS_FILE), exist_ok=True)
        agents_list = list(active_agents.values())
        with open(AGENTS_FILE, "w") as f:
            json.dump(agents_list, f, indent=2)
    except Exception as e:
        print(f"{YELLOW}[Agent save error: {e}]{NC}", file=sys.stderr)

def save_in_progress(tasks):
    """Save in-progress tasks to queue file."""
    try:
        os.makedirs(os.path.dirname(QUEUE_IN_PROGRESS), exist_ok=True)
        with open(QUEUE_IN_PROGRESS, "w") as f:
            json.dump(tasks, f, indent=2)
    except:
        pass

def process_stream():
    global active_agents
    active_agents = load_agents()

    # Always show the main orchestrator
    init_orchestrator()
    print(f"{MAGENTA}[Orchestrator Active]{NC} Main agent started", flush=True)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            msg_type = data.get("type", "")

            if msg_type == "assistant":
                # Extract and print assistant text
                message = data.get("message", {})
                content = message.get("content", [])
                for item in content:
                    if item.get("type") == "text":
                        text = item.get("text", "")
                        if text:
                            print(text, end="", flush=True)
                    elif item.get("type") == "tool_use":
                        tool = item.get("name", "unknown")
                        tool_id = item.get("id", "")
                        tool_input = item.get("input", {})

                        # Extract description based on tool type
                        tool_desc = ""
                        if tool == "Read":
                            tool_desc = tool_input.get("file_path", "")
                        elif tool == "Edit" or tool == "Write":
                            tool_desc = tool_input.get("file_path", "")
                        elif tool == "Bash":
                            tool_desc = tool_input.get("description", tool_input.get("command", "")[:60])
                        elif tool == "Grep":
                            tool_desc = f"pattern: {tool_input.get('pattern', '')}"
                        elif tool == "Glob":
                            tool_desc = tool_input.get("pattern", "")

                        # Update orchestrator with current tool activity
                        update_orchestrator_task(tool, tool_desc)

                        # Track Task tool calls (agent spawning)
                        if tool == "Task":
                            agent_type = tool_input.get("subagent_type", "general-purpose")
                            description = tool_input.get("description", "")
                            model = tool_input.get("model", "sonnet")

                            agent_info = {
                                "agent_id": f"agent-{tool_id[:8]}",
                                "tool_id": tool_id,
                                "agent_type": agent_type,
                                "model": model,
                                "current_task": description,
                                "status": "active",
                                "spawned_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                                "tasks_completed": []
                            }
                            active_agents[tool_id] = agent_info
                            save_agents()
                            print(f"\n{MAGENTA}[Agent Spawned: {agent_type}]{NC} {description}", flush=True)

                        # Track TodoWrite for task updates
                        elif tool == "TodoWrite":
                            todos = tool_input.get("todos", [])
                            in_progress = [t for t in todos if t.get("status") == "in_progress"]
                            save_in_progress([{"id": f"todo-{i}", "type": "todo", "payload": {"action": t.get("content", "")}} for i, t in enumerate(in_progress)])
                            print(f"\n{CYAN}[Tool: {tool}]{NC} {len(todos)} items", flush=True)

                        else:
                            print(f"\n{CYAN}[Tool: {tool}]{NC}", flush=True)

            elif msg_type == "user":
                # Tool results - check for agent completion
                content = data.get("message", {}).get("content", [])
                for item in content:
                    if item.get("type") == "tool_result":
                        tool_id = item.get("tool_use_id", "")

                        # Mark agent as completed if it was a Task
                        if tool_id in active_agents:
                            active_agents[tool_id]["status"] = "completed"
                            active_agents[tool_id]["completed_at"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
                            save_agents()
                            print(f"{DIM}[Agent Complete]{NC} ", end="", flush=True)
                        else:
                            print(f"{DIM}[Result]{NC} ", end="", flush=True)

            elif msg_type == "result":
                # Session complete - mark all agents as completed
                completed_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
                for agent_id in active_agents:
                    if active_agents[agent_id].get("status") == "active":
                        active_agents[agent_id]["status"] = "completed"
                        active_agents[agent_id]["completed_at"] = completed_at
                        active_agents[agent_id]["current_task"] = "Session complete"

                # Add session stats to orchestrator
                if orchestrator_id in active_agents:
                    tool_count = active_agents[orchestrator_id].get("tool_count", 0)
                    active_agents[orchestrator_id]["tasks_completed"].append(f"{tool_count} tools used")

                save_agents()
                print(f"\n{GREEN}[Session complete]{NC}", flush=True)
                is_error = data.get("is_error", False)
                sys.exit(1 if is_error else 0)

        except json.JSONDecodeError:
            # Not JSON, print as-is
            print(line, flush=True)
        except Exception as e:
            print(f"{YELLOW}[Parse error: {e}]{NC}", file=sys.stderr)

if __name__ == "__main__":
    try:
        process_stream()
    except KeyboardInterrupt:
        sys.exit(130)
    except BrokenPipeError:
        sys.exit(0)
'
        local exit_code=${PIPESTATUS[0]}
        set -e

        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        # Log end time
        echo "=== Session ended at $(date) with exit code $exit_code ===" >> "$log_file"

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_info "Claude exited with code $exit_code after ${duration}s"
        save_state $retry "exited" $exit_code

        # Check for success - ONLY stop on explicit completion promise
        # There's never a "complete" product - always improvements, bugs, features
        if [ $exit_code -eq 0 ]; then
            # Perpetual mode: NEVER stop, always continue
            if [ "$PERPETUAL_MODE" = "true" ]; then
                log_info "Perpetual mode: Ignoring exit, continuing immediately..."
                ((retry++))
                continue  # Immediately start next iteration, no wait
            fi

            # Only stop if EXPLICIT completion promise text was output
            if [ -n "$COMPLETION_PROMISE" ] && check_completion_promise "$log_file"; then
                echo ""
                log_header "COMPLETION PROMISE FULFILLED: $COMPLETION_PROMISE"
                log_info "Explicit completion promise detected in output."
                save_state $retry "completion_promise_fulfilled" 0
                return 0
            fi

            # Warn if Claude says it's "done" but no explicit promise
            if is_completed; then
                log_warn "Claude claims completion, but no explicit promise fulfilled."
                log_warn "Projects are never truly complete - there are always improvements!"
            fi

            # SUCCESS exit - continue IMMEDIATELY to next iteration (no wait!)
            log_info "Iteration complete. Continuing to next iteration..."
            ((retry++))
            continue  # Immediately start next iteration, no exponential backoff
        fi

        # Only apply retry logic for ERRORS (non-zero exit code)
        # Handle retry - check for rate limit first
        local rate_limit_wait=$(detect_rate_limit "$log_file")
        local wait_time

        if [ $rate_limit_wait -gt 0 ]; then
            wait_time=$rate_limit_wait
            local human_time=$(format_duration $wait_time)
            log_warn "Rate limit detected! Waiting until reset (~$human_time)..."
            log_info "Rate limit resets at approximately $(date -v+${wait_time}S '+%I:%M %p' 2>/dev/null || date -d "+${wait_time} seconds" '+%I:%M %p' 2>/dev/null || echo 'soon')"
        else
            wait_time=$(calculate_wait $retry)
            log_warn "Will retry in ${wait_time}s..."
        fi

        log_info "Press Ctrl+C to cancel"

        # Countdown with progress
        local remaining=$wait_time
        local interval=10
        # Use longer interval for long waits
        if [ $wait_time -gt 1800 ]; then
            interval=60
        fi

        while [ $remaining -gt 0 ]; do
            local human_remaining=$(format_duration $remaining)
            printf "\r${YELLOW}Resuming in ${human_remaining}...${NC}          "
            sleep $interval
            remaining=$((remaining - interval))
        done
        echo ""

        ((retry++))
    done

    log_error "Max retries ($MAX_RETRIES) exceeded"
    save_state $retry "failed" 1
    return 1
}

#===============================================================================
# Cleanup Handler
#===============================================================================

cleanup() {
    echo ""
    log_warn "Received interrupt signal"
    stop_dashboard
    stop_status_monitor
    save_state ${RETRY_COUNT:-0} "interrupted" 130
    log_info "State saved. Run again to resume."
    exit 130
}

#===============================================================================
# Main Entry Point
#===============================================================================

main() {
    trap cleanup INT TERM

    echo ""
    echo -e "${BOLD}${BLUE}"
    echo "  ██╗      ██████╗ ██╗  ██╗██╗    ███╗   ███╗ ██████╗ ██████╗ ███████╗"
    echo "  ██║     ██╔═══██╗██║ ██╔╝██║    ████╗ ████║██╔═══██╗██╔══██╗██╔════╝"
    echo "  ██║     ██║   ██║█████╔╝ ██║    ██╔████╔██║██║   ██║██║  ██║█████╗  "
    echo "  ██║     ██║   ██║██╔═██╗ ██║    ██║╚██╔╝██║██║   ██║██║  ██║██╔══╝  "
    echo "  ███████╗╚██████╔╝██║  ██╗██║    ██║ ╚═╝ ██║╚██████╔╝██████╔╝███████╗"
    echo "  ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝    ╚═╝     ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝"
    echo -e "${NC}"
    echo -e "  ${CYAN}Autonomous Multi-Agent Startup System${NC}"
    echo -e "  ${CYAN}Version: $(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "2.x.x")${NC}"
    echo ""

    # Parse arguments
    PRD_PATH="${1:-}"

    # Validate PRD if provided
    if [ -n "$PRD_PATH" ] && [ ! -f "$PRD_PATH" ]; then
        log_error "PRD file not found: $PRD_PATH"
        exit 1
    fi

    # Check prerequisites (unless skipped)
    if [ "$SKIP_PREREQS" != "true" ]; then
        if ! check_prerequisites; then
            exit 1
        fi
    else
        log_warn "Skipping prerequisite checks (LOKI_SKIP_PREREQS=true)"
    fi

    # Check skill installation
    if ! check_skill_installed; then
        exit 1
    fi

    # Initialize .loki directory
    init_loki_dir

    # Load project rules (from global or local rules directories)
    load_rules

    # Start web dashboard (if enabled)
    if [ "$ENABLE_DASHBOARD" = "true" ]; then
        start_dashboard
    else
        log_info "Dashboard disabled (LOKI_DASHBOARD=false)"
    fi

    # Start status monitor (background updates to .loki/STATUS.txt)
    start_status_monitor

    # Start resource monitor (background CPU/memory checks)
    start_resource_monitor

    # Initialize cross-project learnings database
    init_learnings_db

    # Load relevant learnings for this project context
    if [ -n "$PRD_PATH" ] && [ -f "$PRD_PATH" ]; then
        get_relevant_learnings "$(cat "$PRD_PATH" | head -100)"
    else
        get_relevant_learnings "general development"
    fi

    # Log session start for audit
    audit_log "SESSION_START" "prd=$PRD_PATH,dashboard=$ENABLE_DASHBOARD,staged_autonomy=$STAGED_AUTONOMY"

    # Run autonomous loop
    local result=0
    run_autonomous "$PRD_PATH" || result=$?

    # Extract and save learnings from this session
    extract_learnings_from_session

    # Log session end for audit
    audit_log "SESSION_END" "result=$result,prd=$PRD_PATH"

    # Cleanup
    stop_dashboard
    stop_status_monitor

    exit $result
}

# Run main
main "$@"
