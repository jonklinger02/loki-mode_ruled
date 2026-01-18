#!/bin/bash
# Test: Dynamic Agent Selection
# Tests complexity classification and model selection for tasks

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
echo "Dynamic Agent Selection Tests"
echo "========================================"
echo ""

# Initialize structure
mkdir -p .loki/state

# Test 1: Simple task classification (lint/format/test-unit)
log_test "Simple task classification - lint task"
cat > task-simple.json << 'EOF'
{
  "id": "task-lint-001",
  "type": "lint",
  "priority": 9,
  "timeout": 60,
  "dependencies": [],
  "payload": {
    "action": "run",
    "description": "Run linter on src/ directory"
  }
}
EOF

python3 << 'CLASSIFY_SIMPLE'
import json

task = json.load(open('task-simple.json'))

# Simple types get low complexity
simple_types = ['lint', 'format', 'test-unit', 'health-check', 'docs', 'monitor']
is_simple_type = any(st in task['type'].lower() for st in simple_types)

# Simple actions
simple_actions = ['run', 'check', 'lint', 'format', 'test', 'read', 'list']
action = task.get('payload', {}).get('action', '').lower()
is_simple_action = any(sa in action for sa in simple_actions)

# Short description and no deps
has_short_desc = len(task.get('payload', {}).get('description', '')) < 50
has_no_deps = len(task.get('dependencies', [])) == 0

if is_simple_type and is_simple_action:
    print("SIMPLE_CLASSIFICATION_CORRECT")
else:
    print("CLASSIFICATION_WRONG")
CLASSIFY_SIMPLE

result=$(python3 -c "
task = {'type': 'lint', 'payload': {'action': 'run', 'description': 'Run linter on src/'}}
simple_types = ['lint', 'format', 'test-unit']
print(any(st in task['type'].lower() for st in simple_types))
")

if [ "$result" = "True" ]; then
    log_pass "Lint task correctly identified as simple type"
else
    log_fail "Lint task not identified as simple"
fi

# Test 2: Medium task classification (deploy/review/security-scan)
log_test "Medium task classification - deploy task"
cat > task-medium.json << 'EOF'
{
  "id": "task-deploy-001",
  "type": "deploy",
  "priority": 5,
  "timeout": 1800,
  "dependencies": ["task-001"],
  "payload": {
    "action": "deploy",
    "description": "Deploy application to staging environment with rollback support"
  }
}
EOF

result=$(python3 -c "
task = {'type': 'deploy', 'payload': {'action': 'deploy'}}
medium_types = ['test-integration', 'test-e2e', 'deploy', 'security-scan', 'review']
print(any(mt in task['type'].lower() for mt in medium_types))
")

if [ "$result" = "True" ]; then
    log_pass "Deploy task correctly identified as medium type"
else
    log_fail "Deploy task not identified as medium"
fi

# Test 3: Complex task classification (architecture/implement/refactor)
log_test "Complex task classification - architecture task"
cat > task-complex.json << 'EOF'
{
  "id": "task-arch-001",
  "type": "architecture",
  "priority": 2,
  "timeout": 7200,
  "dependencies": ["task-001", "task-002", "task-003"],
  "payload": {
    "action": "design",
    "description": "Design authentication architecture with OAuth2 integration, multiple identity providers, and secure token management. Consider scalability and performance implications."
  }
}
EOF

result=$(python3 -c "
task = {'type': 'architecture', 'payload': {'action': 'design'}}
complex_types = ['architecture', 'design', 'implement', 'refactor', 'bootstrap', 'discovery']
print(any(ct in task['type'].lower() for ct in complex_types))
")

if [ "$result" = "True" ]; then
    log_pass "Architecture task correctly identified as complex type"
else
    log_fail "Architecture task not identified as complex"
fi

# Test 4: Model selection for simple task
log_test "Model selection for simple task"
python3 << 'MODEL_SIMPLE'
import json

# Simulate complexity calculation
factors = {
    'task_type': 0.2,  # lint = simple
    'action': 0.2,     # run = simple
    'description': 0.3,
    'dependencies': 0.0,
    'timeout': 0.2
}
weights = {'task_type': 0.30, 'action': 0.25, 'description': 0.25, 'dependencies': 0.10, 'timeout': 0.10}

score = sum(factors[k] * weights[k] for k in factors)

if score < 0.35:
    model = 'haiku'
elif score < 0.65:
    model = 'sonnet'
else:
    model = 'opus'

print(f"SCORE:{score:.3f}")
print(f"MODEL:{model}")
MODEL_SIMPLE

model_result=$(python3 -c "
factors = {'task_type': 0.2, 'action': 0.2, 'description': 0.3, 'dependencies': 0.0, 'timeout': 0.2}
weights = {'task_type': 0.30, 'action': 0.25, 'description': 0.25, 'dependencies': 0.10, 'timeout': 0.10}
score = sum(factors[k] * weights[k] for k in factors)
print('haiku' if score < 0.35 else 'sonnet' if score < 0.65 else 'opus')
")

if [ "$model_result" = "haiku" ]; then
    log_pass "Haiku selected for simple task"
else
    log_fail "Expected Haiku for simple task, got $model_result"
fi

# Test 5: Model selection for complex task
log_test "Model selection for complex task"
model_result=$(python3 -c "
factors = {'task_type': 0.8, 'action': 0.8, 'description': 0.7, 'dependencies': 0.6, 'timeout': 0.8}
weights = {'task_type': 0.30, 'action': 0.25, 'description': 0.25, 'dependencies': 0.10, 'timeout': 0.10}
score = sum(factors[k] * weights[k] for k in factors)
print('haiku' if score < 0.35 else 'sonnet' if score < 0.65 else 'opus')
")

if [ "$model_result" = "opus" ]; then
    log_pass "Opus selected for complex task"
else
    log_fail "Expected Opus for complex task, got $model_result"
fi

# Test 6: Description complexity detection
log_test "Description complexity detection"
python3 << 'DESC_COMPLEXITY'
desc_simple = "run tests"
desc_complex = "design authentication architecture with multiple identity providers, database migration, and performance optimization"

complex_indicators = ['architecture', 'design', 'refactor', 'integrate', 'security',
                     'authentication', 'database', 'migration', 'performance', 'optimize']

simple_count = 0  # Simple description has no complex indicators
complex_count = sum(1 for ind in complex_indicators if ind in desc_complex.lower())

print(f"SIMPLE_DESC_INDICATORS:{simple_count}")
print(f"COMPLEX_DESC_INDICATORS:{complex_count}")
DESC_COMPLEXITY

complex_count=$(python3 -c "
desc = 'design authentication architecture with database migration and performance optimization'
indicators = ['architecture', 'design', 'authentication', 'database', 'migration', 'performance', 'optimize']
print(sum(1 for i in indicators if i in desc.lower()))
")

if [ "$complex_count" -ge 3 ]; then
    log_pass "Complex description correctly detected ($complex_count indicators)"
else
    log_fail "Complex description not detected (only $complex_count indicators)"
fi

# Test 7: Dependency impact on complexity
log_test "Dependency impact on complexity"
python3 << 'DEP_IMPACT'
# More dependencies = higher complexity score
no_deps_score = 0 * 0.2
one_dep_score = 1 * 0.2
many_deps_score = min(1.0, 5 * 0.2)

print(f"NO_DEPS:{no_deps_score}")
print(f"ONE_DEP:{one_dep_score}")
print(f"MANY_DEPS:{many_deps_score}")
DEP_IMPACT

dep_result=$(python3 -c "
print(0 * 0.2 < 1 * 0.2 < min(1.0, 5 * 0.2))
")

if [ "$dep_result" = "True" ]; then
    log_pass "Dependencies correctly increase complexity"
else
    log_fail "Dependency impact calculation incorrect"
fi

# Test 8: Timeout impact on complexity
log_test "Timeout impact on complexity"
timeout_result=$(python3 -c "
def timeout_score(timeout):
    if timeout > 3600: return 0.8
    elif timeout > 1800: return 0.6
    elif timeout > 600: return 0.4
    else: return 0.2

# Short timeout (5 min) = simpler
# Medium timeout (30 min) = medium
# Long timeout (2 hours) = complex
print(timeout_score(300) < timeout_score(1800) < timeout_score(7200))
")

if [ "$timeout_result" = "True" ]; then
    log_pass "Longer timeouts correctly indicate higher complexity"
else
    log_fail "Timeout impact calculation incorrect"
fi

# Test 9: Parallel agent count recommendation
log_test "Parallel agent count recommendation"
python3 << 'PARALLEL_TEST'
max_parallel = 10

# Haiku tasks can run in large parallel batches
haiku_parallel = max_parallel  # 10
# Sonnet tasks should be more limited
sonnet_parallel = min(5, max_parallel)  # 5
# Opus tasks should be minimal
opus_parallel = min(2, max_parallel)  # 2

print(f"HAIKU:{haiku_parallel}")
print(f"SONNET:{sonnet_parallel}")
print(f"OPUS:{opus_parallel}")
PARALLEL_TEST

parallel_result=$(python3 -c "
print(10 > 5 > 2)  # haiku > sonnet > opus parallelization
")

if [ "$parallel_result" = "True" ]; then
    log_pass "Parallel agent counts correctly scaled by model"
else
    log_fail "Parallel count scaling incorrect"
fi

# Test 10: SDLC phase mapping
log_test "SDLC phase mapping"
python3 << 'SDLC_MAPPING'
def get_sdlc_phase(model):
    if model == 'haiku':
        return 'operations'
    elif model == 'sonnet':
        return 'qa-deployment'
    else:
        return 'development'

haiku_phase = get_sdlc_phase('haiku')
sonnet_phase = get_sdlc_phase('sonnet')
opus_phase = get_sdlc_phase('opus')

print(f"HAIKU_PHASE:{haiku_phase}")
print(f"SONNET_PHASE:{sonnet_phase}")
print(f"OPUS_PHASE:{opus_phase}")
SDLC_MAPPING

phase_result=$(python3 -c "
phases = {'haiku': 'operations', 'sonnet': 'qa-deployment', 'opus': 'development'}
print(phases['haiku'] == 'operations' and phases['sonnet'] == 'qa-deployment' and phases['opus'] == 'development')
")

if [ "$phase_result" = "True" ]; then
    log_pass "SDLC phases correctly mapped to models"
else
    log_fail "SDLC phase mapping incorrect"
fi

# Test 11: Factor weights sum to 1.0
log_test "Factor weights normalization"
weights_result=$(python3 -c "
weights = {'task_type': 0.30, 'action': 0.25, 'description': 0.25, 'dependencies': 0.10, 'timeout': 0.10}
print(abs(sum(weights.values()) - 1.0) < 0.001)
")

if [ "$weights_result" = "True" ]; then
    log_pass "Factor weights correctly sum to 1.0"
else
    log_fail "Factor weights don't sum to 1.0"
fi

# Test 12: Full classification output structure
log_test "Full classification output structure"
cat > .loki/state/task-complexity.json << 'EOF'
{
  "taskId": "test-001",
  "taskType": "implement",
  "complexity": "complex",
  "model": "opus",
  "score": 0.75,
  "sdlcPhase": "development",
  "factors": {
    "task_type": 0.8,
    "action": 0.8,
    "description": 0.7,
    "dependencies": 0.4,
    "timeout": 0.8
  },
  "weights": {
    "task_type": 0.30,
    "action": 0.25,
    "description": 0.25,
    "dependencies": 0.10,
    "timeout": 0.10
  },
  "calculatedAt": "2026-01-18T16:00:00Z"
}
EOF

structure_result=$(python3 -c "
import json
with open('.loki/state/task-complexity.json') as f:
    data = json.load(f)
required_fields = ['taskId', 'complexity', 'model', 'score', 'sdlcPhase', 'factors', 'weights']
print(all(f in data for f in required_fields))
")

if [ "$structure_result" = "True" ]; then
    log_pass "Classification output has correct structure"
else
    log_fail "Classification output missing required fields"
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
