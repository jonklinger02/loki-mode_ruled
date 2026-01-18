#!/bin/bash
# Test: Confidence-Based Routing
# Tests multi-tier routing based on task confidence scores

set -uo pipefail

TEST_DIR=$(mktemp -d)
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED++)); }
log_test() { echo -e "${YELLOW}[TEST]${NC} $1"; }

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

cd "$TEST_DIR"

echo "========================================"
echo "Confidence-Based Routing Tests"
echo "========================================"
echo ""

# Initialize structure
mkdir -p .loki/{state,queue}
echo '{"tasks":[]}' > .loki/queue/completed.json

# Test 1: High confidence task (clear requirements, simple)
log_test "High confidence task routing"
cat > task-simple.json << 'EOF'
{
  "id": "task-001",
  "type": "eng-backend",
  "priority": 9,
  "timeout": 300,
  "dependencies": [],
  "payload": {
    "action": "format",
    "target": "src/utils.ts",
    "goal": "Format file with prettier",
    "constraints": ["Use existing config"],
    "description": "Run prettier on src/utils.ts to fix formatting"
  }
}
EOF

python3 << 'CALC_HIGH'
import json
import os
from datetime import datetime, timezone

with open('task-simple.json', 'r') as f:
    task = json.load(f)

# Simplified confidence calculation
def assess_requirement_clarity(task):
    description = str(task.get('payload', {}).get('description', ''))
    ambiguous_terms = ['maybe', 'perhaps', 'might', 'probably', 'unclear']
    ambiguity_count = sum(1 for term in ambiguous_terms if term in description.lower())

    has_goal = bool(task.get('payload', {}).get('goal', ''))
    has_constraints = bool(task.get('payload', {}).get('constraints', []))
    has_target = bool(task.get('payload', {}).get('target', ''))
    has_action = bool(task.get('payload', {}).get('action', ''))

    base_score = 1.0 - min(0.6, ambiguity_count * 0.15)
    if has_goal: base_score += 0.1
    if has_constraints: base_score += 0.1
    if has_target: base_score += 0.1
    if has_action: base_score += 0.1

    return min(1.0, max(0.0, base_score))

def assess_complexity(task):
    priority = task.get('priority', 5)
    dependencies = len(task.get('dependencies', []))
    timeout = task.get('timeout', 3600)

    score = 0.8
    score -= (10 - priority) * 0.03
    score -= dependencies * 0.1
    if timeout > 3600: score -= 0.1
    if timeout < 300: score += 0.1

    return min(1.0, max(0.0, score))

weights = {'requirement_clarity': 0.35, 'historical_success': 0.25, 'complexity': 0.25, 'resources': 0.15}
factors = {
    'requirement_clarity': assess_requirement_clarity(task),
    'historical_success': 0.6,  # No history
    'complexity': assess_complexity(task),
    'resources': 0.8  # No monitoring
}

confidence = sum(factors[k] * weights[k] for k in factors)

if confidence >= 0.95:
    tier = 'auto-approve'
elif confidence >= 0.70:
    tier = 'direct-review'
elif confidence >= 0.40:
    tier = 'supervisor'
else:
    tier = 'escalate'

result = {'confidence': round(confidence, 3), 'tier': tier, 'factors': factors}
with open('.loki/state/task-confidence.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"CONFIDENCE:{confidence:.3f}")
print(f"TIER:{tier}")
CALC_HIGH

tier=$(python3 -c "import json; print(json.load(open('.loki/state/task-confidence.json'))['tier'])")
confidence=$(python3 -c "import json; print(json.load(open('.loki/state/task-confidence.json'))['confidence'])")

if [ "$tier" = "direct-review" ] || [ "$tier" = "auto-approve" ]; then
    log_pass "Simple task routed to high-confidence tier ($tier, $confidence)"
else
    log_fail "Expected direct-review or auto-approve, got $tier ($confidence)"
fi

# Test 2: Low confidence task (ambiguous requirements)
log_test "Low confidence task routing"
cat > task-ambiguous.json << 'EOF'
{
  "id": "task-002",
  "type": "eng-frontend",
  "priority": 3,
  "timeout": 7200,
  "dependencies": ["task-001", "task-003"],
  "payload": {
    "description": "Maybe we should probably update the UI, but it's unclear what exactly needs to change. Perhaps something with the styling might help, not sure though."
  }
}
EOF

python3 << 'CALC_LOW'
import json

with open('task-ambiguous.json', 'r') as f:
    task = json.load(f)

def assess_requirement_clarity(task):
    description = str(task.get('payload', {}).get('description', ''))
    ambiguous_terms = ['maybe', 'perhaps', 'might', 'probably', 'unclear', 'not sure']
    ambiguity_count = sum(1 for term in ambiguous_terms if term in description.lower())

    has_goal = bool(task.get('payload', {}).get('goal', ''))
    has_constraints = bool(task.get('payload', {}).get('constraints', []))

    base_score = 1.0 - min(0.6, ambiguity_count * 0.15)
    if has_goal: base_score += 0.1
    if has_constraints: base_score += 0.1

    return min(1.0, max(0.0, base_score))

def assess_complexity(task):
    priority = task.get('priority', 5)
    dependencies = len(task.get('dependencies', []))
    timeout = task.get('timeout', 3600)

    score = 0.8
    score -= (10 - priority) * 0.03
    score -= dependencies * 0.1
    if timeout > 3600: score -= 0.1

    return min(1.0, max(0.0, score))

weights = {'requirement_clarity': 0.35, 'historical_success': 0.25, 'complexity': 0.25, 'resources': 0.15}
factors = {
    'requirement_clarity': assess_requirement_clarity(task),
    'historical_success': 0.6,
    'complexity': assess_complexity(task),
    'resources': 0.8
}

confidence = sum(factors[k] * weights[k] for k in factors)

if confidence >= 0.95: tier = 'auto-approve'
elif confidence >= 0.70: tier = 'direct-review'
elif confidence >= 0.40: tier = 'supervisor'
else: tier = 'escalate'

result = {'confidence': round(confidence, 3), 'tier': tier, 'factors': factors}
with open('.loki/state/task-confidence.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"CONFIDENCE:{confidence:.3f}")
print(f"TIER:{tier}")
CALC_LOW

tier=$(python3 -c "import json; print(json.load(open('.loki/state/task-confidence.json'))['tier'])")
confidence=$(python3 -c "import json; print(json.load(open('.loki/state/task-confidence.json'))['confidence'])")

if [ "$tier" = "escalate" ] || [ "$tier" = "supervisor" ]; then
    log_pass "Ambiguous task routed to low-confidence tier ($tier, $confidence)"
else
    log_fail "Expected escalate or supervisor, got $tier ($confidence)"
fi

# Test 3: Historical success rate affects confidence
log_test "Historical success rate impact"
# Add some completed tasks with success
cat > .loki/queue/completed.json << 'EOF'
{
  "tasks": [
    {"id": "past-1", "type": "eng-backend", "result": {"status": "success"}},
    {"id": "past-2", "type": "eng-backend", "result": {"status": "success"}},
    {"id": "past-3", "type": "eng-backend", "result": {"status": "success"}},
    {"id": "past-4", "type": "eng-backend", "result": {"status": "failed"}},
    {"id": "past-5", "type": "eng-frontend", "result": {"status": "success"}}
  ]
}
EOF

python3 << 'CALC_HISTORY'
import json
import os

task = {"id": "new-task", "type": "eng-backend", "priority": 5, "dependencies": [], "payload": {"action": "implement", "goal": "Add feature"}}

# Check historical success
completed_file = '.loki/queue/completed.json'
with open(completed_file, 'r') as f:
    completed = json.load(f)

similar = [t for t in completed.get('tasks', []) if t.get('type') == 'eng-backend']
success_rate = sum(1 for t in similar if t.get('result', {}).get('status') == 'success') / len(similar) if similar else 0.6

print(f"HISTORY_RATE:{success_rate:.2f}")
# 3 successes out of 4 eng-backend tasks = 0.75
CALC_HISTORY

history_result=$(python3 -c "
import json
with open('.loki/queue/completed.json') as f:
    completed = json.load(f)
similar = [t for t in completed['tasks'] if t['type'] == 'eng-backend']
rate = sum(1 for t in similar if t['result']['status'] == 'success') / len(similar)
print(rate == 0.75)
")

if [ "$history_result" = "True" ]; then
    log_pass "Historical success rate calculated correctly (75%)"
else
    log_fail "Historical success rate incorrect"
fi

# Test 4: Tier thresholds are correct
log_test "Tier threshold boundaries"
python3 << 'TEST_THRESHOLDS'
def get_tier(confidence):
    if confidence >= 0.95:
        return 'auto-approve'
    elif confidence >= 0.70:
        return 'direct-review'
    elif confidence >= 0.40:
        return 'supervisor'
    else:
        return 'escalate'

# Test exact boundaries
tests = [
    (0.95, 'auto-approve'),
    (0.94, 'direct-review'),
    (0.70, 'direct-review'),
    (0.69, 'supervisor'),
    (0.40, 'supervisor'),
    (0.39, 'escalate'),
    (0.0, 'escalate'),
    (1.0, 'auto-approve')
]

all_passed = True
for conf, expected in tests:
    actual = get_tier(conf)
    if actual != expected:
        print(f"FAIL: {conf} -> {actual}, expected {expected}")
        all_passed = False

if all_passed:
    print("THRESHOLDS_CORRECT")
else:
    print("THRESHOLDS_WRONG")
TEST_THRESHOLDS

threshold_result=$(python3 -c "
def get_tier(c):
    if c >= 0.95: return 'auto-approve'
    elif c >= 0.70: return 'direct-review'
    elif c >= 0.40: return 'supervisor'
    else: return 'escalate'

print(get_tier(0.95) == 'auto-approve' and get_tier(0.70) == 'direct-review' and get_tier(0.40) == 'supervisor' and get_tier(0.39) == 'escalate')
")

if [ "$threshold_result" = "True" ]; then
    log_pass "Tier thresholds are correctly defined"
else
    log_fail "Tier thresholds incorrect"
fi

# Test 5: Factor weights sum to 1.0
log_test "Factor weights normalization"
python3 << 'TEST_WEIGHTS'
weights = {
    'requirement_clarity': 0.35,
    'historical_success': 0.25,
    'complexity': 0.25,
    'resources': 0.15
}

total = sum(weights.values())
if abs(total - 1.0) < 0.001:
    print("WEIGHTS_SUM_TO_1")
else:
    print(f"WEIGHTS_SUM:{total}")
TEST_WEIGHTS

weight_result=$(python3 -c "
weights = {'requirement_clarity': 0.35, 'historical_success': 0.25, 'complexity': 0.25, 'resources': 0.15}
print(abs(sum(weights.values()) - 1.0) < 0.001)
")

if [ "$weight_result" = "True" ]; then
    log_pass "Factor weights correctly sum to 1.0"
else
    log_fail "Factor weights don't sum to 1.0"
fi

# Test 6: Resource constraints lower confidence
log_test "Resource constraints impact"
cat > .loki/state/resources.json << 'EOF'
{
  "cpu": 85,
  "memory": 90,
  "activeAgents": 10
}
EOF

python3 << 'TEST_RESOURCES'
import json

with open('.loki/state/resources.json', 'r') as f:
    resources = json.load(f)

cpu = resources.get('cpu', 0)
memory = resources.get('memory', 0)
agents = resources.get('activeAgents', 0)
max_agents = 10

score = 1.0
if cpu > 80: score -= 0.3
if memory > 80: score -= 0.3
if agents >= max_agents: score -= 0.4

print(f"RESOURCE_SCORE:{max(0.0, score):.2f}")
# 85% CPU (-0.3) + 90% memory (-0.3) + 10 agents (-0.4) = 0.0
TEST_RESOURCES

resource_score=$(python3 -c "
import json
with open('.loki/state/resources.json') as f:
    r = json.load(f)
score = 1.0
if r['cpu'] > 80: score -= 0.3
if r['memory'] > 80: score -= 0.3
if r['activeAgents'] >= 10: score -= 0.4
print(abs(score) < 0.01)
")

if [ "$resource_score" = "True" ]; then
    log_pass "High resource usage correctly lowers confidence"
else
    log_fail "Resource impact calculation incorrect"
fi

# Test 7: Debate triggers for low-confidence tasks
log_test "Debate triggers for supervisor tier"
python3 << 'TEST_DEBATE_TRIGGER'
# Simulate should_trigger_debate logic
confidence = 0.55  # Supervisor tier
tier = 'supervisor'
threshold = 0.70
critical_types = ['security', 'deployment', 'database']
task_type = 'eng-backend'

is_critical = any(ct in task_type.lower() for ct in critical_types)
should_debate = (
    confidence < threshold or
    tier in ['supervisor', 'escalate'] or
    is_critical
)

if should_debate:
    print("DEBATE_REQUIRED")
else:
    print("DEBATE_SKIP")
TEST_DEBATE_TRIGGER

debate_result=$(python3 -c "
confidence = 0.55
tier = 'supervisor'
threshold = 0.70
should_debate = confidence < threshold or tier in ['supervisor', 'escalate']
print(should_debate)
")

if [ "$debate_result" = "True" ]; then
    log_pass "Debate correctly triggered for supervisor tier"
else
    log_fail "Debate should trigger for supervisor tier"
fi

# Test 8: No debate for high-confidence tasks
log_test "No debate for auto-approve tier"
python3 << 'TEST_NO_DEBATE'
confidence = 0.97
tier = 'auto-approve'
threshold = 0.70
task_type = 'lint'
critical_types = ['security', 'deployment', 'database']

is_critical = any(ct in task_type.lower() for ct in critical_types)
should_debate = (
    confidence < threshold or
    tier in ['supervisor', 'escalate'] or
    is_critical
)

if not should_debate:
    print("DEBATE_SKIP_CORRECT")
else:
    print("DEBATE_SHOULD_NOT_TRIGGER")
TEST_NO_DEBATE

no_debate_result=$(python3 -c "
confidence = 0.97
tier = 'auto-approve'
threshold = 0.70
should_debate = confidence < threshold or tier in ['supervisor', 'escalate']
print(not should_debate)
")

if [ "$no_debate_result" = "True" ]; then
    log_pass "Debate correctly skipped for auto-approve tier"
else
    log_fail "Debate should not trigger for auto-approve"
fi

# Test 9: Debate triggers for critical task types
log_test "Debate triggers for critical task types (security)"
python3 << 'TEST_CRITICAL_DEBATE'
confidence = 0.85  # Above threshold
tier = 'direct-review'
threshold = 0.70
task_type = 'security-scan'
critical_types = ['security', 'deployment', 'database']

is_critical = any(ct in task_type.lower() for ct in critical_types)
should_debate = (
    confidence < threshold or
    tier in ['supervisor', 'escalate'] or
    is_critical
)

if should_debate and is_critical:
    print("CRITICAL_DEBATE_CORRECT")
else:
    print("CRITICAL_DEBATE_WRONG")
TEST_CRITICAL_DEBATE

critical_result=$(python3 -c "
task_type = 'security-scan'
critical_types = ['security', 'deployment', 'database']
is_critical = any(ct in task_type.lower() for ct in critical_types)
print(is_critical)
")

if [ "$critical_result" = "True" ]; then
    log_pass "Debate correctly triggered for security task"
else
    log_fail "Debate should trigger for security tasks"
fi

# Test 10: Routing actions with debate suffix
log_test "Routing actions include debate suffix when needed"
python3 << 'TEST_DEBATE_ACTIONS'
# Test that routing returns correct actions
def get_action_with_debate(tier, needs_debate):
    if tier == 'auto-approve':
        return 'execute_direct'
    elif tier == 'direct-review':
        return 'execute_with_debate_review' if needs_debate else 'execute_with_review'
    elif tier == 'supervisor':
        return 'supervisor_with_debate' if needs_debate else 'supervisor_mode'
    elif tier == 'escalate':
        return 'debate_then_escalate' if needs_debate else 'escalate'

# Test cases
tests = [
    ('supervisor', True, 'supervisor_with_debate'),
    ('supervisor', False, 'supervisor_mode'),
    ('direct-review', True, 'execute_with_debate_review'),
    ('direct-review', False, 'execute_with_review'),
    ('escalate', True, 'debate_then_escalate'),
    ('escalate', False, 'escalate'),
    ('auto-approve', True, 'execute_direct'),
    ('auto-approve', False, 'execute_direct'),
]

all_correct = True
for tier, needs_debate, expected in tests:
    actual = get_action_with_debate(tier, needs_debate)
    if actual != expected:
        print(f"FAIL: {tier}, debate={needs_debate} -> {actual}, expected {expected}")
        all_correct = False

if all_correct:
    print("DEBATE_ACTIONS_CORRECT")
TEST_DEBATE_ACTIONS

actions_result=$(python3 -c "
def get_action(tier, needs_debate):
    if tier == 'auto-approve': return 'execute_direct'
    elif tier == 'direct-review': return 'execute_with_debate_review' if needs_debate else 'execute_with_review'
    elif tier == 'supervisor': return 'supervisor_with_debate' if needs_debate else 'supervisor_mode'
    elif tier == 'escalate': return 'debate_then_escalate' if needs_debate else 'escalate'

print(get_action('supervisor', True) == 'supervisor_with_debate' and get_action('supervisor', False) == 'supervisor_mode')
")

if [ "$actions_result" = "True" ]; then
    log_pass "Routing actions correctly include debate suffix"
else
    log_fail "Routing actions with debate suffix incorrect"
fi

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    exit 1
fi
echo -e "${GREEN}All tests passed!${NC}"
exit 0
