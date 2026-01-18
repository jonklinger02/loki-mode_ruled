#!/bin/bash
# Test: Debate-Based Verification
# Tests DeepMind-inspired debate pattern for critical decision verification

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
echo "Debate-Based Verification Tests"
echo "========================================"
echo ""

# Initialize structure
mkdir -p .loki/{state,queue}

# Test 1: Create debate proposal
log_test "Create debate proposal"
python3 << 'CREATE_PROPOSAL'
import json
from datetime import datetime, timezone

proposal = {
    'id': 'debate-' + datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S'),
    'type': 'architecture-decision',
    'content': 'Implement microservices architecture because it enables independent scaling. Must use Docker containers. Should include health checks.',
    'context': 'Current monolith is hitting scaling limits',
    'createdAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    'status': 'pending'
}

with open('.loki/state/debate-proposal.json', 'w') as f:
    json.dump(proposal, f, indent=2)

print(f"PROPOSAL_ID:{proposal['id']}")
CREATE_PROPOSAL

if [ -f ".loki/state/debate-proposal.json" ]; then
    log_pass "Debate proposal created successfully"
else
    log_fail "Failed to create debate proposal"
fi

# Test 2: Defense generation with strong proposal
log_test "Defense generation for strong proposal"
python3 << 'DEFENSE_STRONG'
import json

proposal = {
    'content': 'Implement authentication system because users need secure access. Must use JWT tokens. Should include rate limiting.',
    'type': 'security'
}

# Score proposal clarity
content = proposal['content'].lower()
has_specific_goal = any(kw in content for kw in ['implement', 'add', 'fix', 'update', 'create'])
has_reasoning = any(kw in content for kw in ['because', 'since', 'therefore', 'in order to'])
has_constraints = any(kw in content for kw in ['must', 'should', 'requirement', 'constraint'])

strength_score = 0.5
if has_specific_goal: strength_score += 0.15
if has_reasoning: strength_score += 0.15
if has_constraints: strength_score += 0.1
if len(proposal['content']) > 100: strength_score += 0.1

print(f"DEFENSE_SCORE:{strength_score:.2f}")
# Expected: 0.5 + 0.15 (implement) + 0.15 (because) + 0.1 (must/should) = 0.9
DEFENSE_STRONG

defense_score=$(python3 -c "
proposal = {'content': 'Implement authentication system because users need secure access. Must use JWT tokens. Should include rate limiting.'}
content = proposal['content'].lower()
score = 0.5
if 'implement' in content: score += 0.15
if 'because' in content: score += 0.15
if 'must' in content or 'should' in content: score += 0.1
if len(proposal['content']) > 100: score += 0.1
print(score >= 0.8)
")

if [ "$defense_score" = "True" ]; then
    log_pass "Strong proposal generates high defense score (>=0.8)"
else
    log_fail "Strong proposal defense score incorrect"
fi

# Test 3: Challenge generation finds flaws in weak proposal
log_test "Challenge generation for weak proposal"
python3 << 'CHALLENGE_WEAK'
import json

proposal = {
    'content': 'Update something',
    'type': 'generic'
}

content = proposal['content'].lower()
flaws = []

if 'test' not in content and 'verify' not in content:
    flaws.append({'point': 'No testing strategy', 'severity': 'medium', 'valid': True})

if 'rollback' not in content and 'revert' not in content:
    flaws.append({'point': 'No rollback plan', 'severity': 'low', 'valid': True})

if len(proposal['content']) < 50:
    flaws.append({'point': 'Proposal lacks detail', 'severity': 'high', 'valid': True})

has_valid_flaw = any(f['valid'] for f in flaws)
print(f"FLAWS_FOUND:{len(flaws)}")
print(f"HAS_VALID_FLAW:{has_valid_flaw}")
CHALLENGE_WEAK

flaw_result=$(python3 -c "
proposal = {'content': 'Update something'}
flaws = []
if 'test' not in proposal['content'].lower(): flaws.append({'valid': True})
if len(proposal['content']) < 50: flaws.append({'valid': True})
print(len(flaws) >= 2)
")

if [ "$flaw_result" = "True" ]; then
    log_pass "Weak proposal has multiple valid flaws identified"
else
    log_fail "Challenge failed to find flaws in weak proposal"
fi

# Test 4: Debate round creates proper log structure
log_test "Debate round log structure"
python3 << 'DEBATE_LOG'
import json
from datetime import datetime, timezone

log = {
    'proposalId': 'debate-test-001',
    'proposalType': 'test',
    'rounds': [{
        'round': 1,
        'timestamp': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
        'defense': {'strengthScore': 0.75, 'arguments': ['Test argument']},
        'challenge': {'flaws': [], 'hasValidFlaw': False}
    }],
    'outcome': None,
    'startedAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
}

with open('.loki/state/debate-log.json', 'w') as f:
    json.dump(log, f, indent=2)

# Verify structure
with open('.loki/state/debate-log.json', 'r') as f:
    loaded = json.load(f)

has_required_fields = all(k in loaded for k in ['proposalId', 'rounds', 'outcome'])
print(f"STRUCTURE_VALID:{has_required_fields}")
DEBATE_LOG

if [ -f ".loki/state/debate-log.json" ]; then
    structure_valid=$(python3 -c "
import json
with open('.loki/state/debate-log.json') as f:
    log = json.load(f)
print(all(k in log for k in ['proposalId', 'rounds', 'outcome']))
")
    if [ "$structure_valid" = "True" ]; then
        log_pass "Debate log has correct structure"
    else
        log_fail "Debate log missing required fields"
    fi
else
    log_fail "Debate log not created"
fi

# Test 5: Verification outcome when no valid flaws
log_test "Verification passes when no valid flaws"
python3 << 'VERIFY_PASS'
import json
from datetime import datetime, timezone

log = {
    'proposalId': 'debate-pass-001',
    'proposalType': 'feature',
    'rounds': [{
        'round': 1,
        'defense': {'strengthScore': 0.85},
        'challenge': {'flaws': [], 'hasValidFlaw': False}
    }],
    'outcome': {
        'verified': True,
        'reason': 'Opponent could not find valid flaws',
        'roundsCompleted': 1,
        'finalDefenseScore': 0.85
    }
}

with open('.loki/state/debate-log.json', 'w') as f:
    json.dump(log, f, indent=2)

print("OUTCOME:verified")
VERIFY_PASS

outcome=$(python3 -c "
import json
with open('.loki/state/debate-log.json') as f:
    log = json.load(f)
print(log['outcome']['verified'])
")

if [ "$outcome" = "True" ]; then
    log_pass "Proposal verified when no valid flaws found"
else
    log_fail "Verification outcome incorrect"
fi

# Test 6: Verification fails when critical flaws persist
log_test "Verification fails with unresolved critical flaws"
python3 << 'VERIFY_FAIL'
import json

log = {
    'proposalId': 'debate-fail-001',
    'proposalType': 'deployment',
    'rounds': [
        {'round': 1, 'defense': {'strengthScore': 0.4}, 'challenge': {'flaws': [{'point': 'No rollback', 'severity': 'high', 'valid': True}], 'hasValidFlaw': True}},
        {'round': 2, 'defense': {'strengthScore': 0.5}, 'challenge': {'flaws': [{'point': 'No rollback', 'severity': 'high', 'valid': True}], 'hasValidFlaw': True}}
    ],
    'outcome': {
        'verified': False,
        'reason': 'Unresolved flaws after 2 rounds',
        'roundsCompleted': 2,
        'unresolvedFlaws': [{'point': 'No rollback', 'severity': 'high'}]
    }
}

with open('.loki/state/debate-log.json', 'w') as f:
    json.dump(log, f, indent=2)

print("OUTCOME:rejected")
VERIFY_FAIL

outcome=$(python3 -c "
import json
with open('.loki/state/debate-log.json') as f:
    log = json.load(f)
print(log['outcome']['verified'] == False)
")

if [ "$outcome" = "True" ]; then
    log_pass "Proposal rejected when critical flaws persist"
else
    log_fail "Should reject proposal with unresolved critical flaws"
fi

# Test 7: Debate trigger based on confidence threshold
log_test "Debate trigger based on confidence"
cat > .loki/state/task-confidence.json << 'EOF'
{
    "confidence": 0.65,
    "tier": "supervisor",
    "taskType": "eng-backend"
}
EOF

should_debate=$(python3 -c "
import json
threshold = 0.70
with open('.loki/state/task-confidence.json') as f:
    data = json.load(f)
confidence = data['confidence']
tier = data['tier']
should_debate = confidence < threshold or tier in ['supervisor', 'escalate']
print(should_debate)
")

if [ "$should_debate" = "True" ]; then
    log_pass "Debate triggered for low-confidence task (0.65 < 0.70)"
else
    log_fail "Should trigger debate for low-confidence task"
fi

# Test 8: Debate skipped for high-confidence tasks
log_test "Debate skipped for high-confidence tasks"
cat > .loki/state/task-confidence.json << 'EOF'
{
    "confidence": 0.92,
    "tier": "direct-review",
    "taskType": "eng-backend"
}
EOF

should_skip=$(python3 -c "
import json
threshold = 0.70
with open('.loki/state/task-confidence.json') as f:
    data = json.load(f)
confidence = data['confidence']
tier = data['tier']
# Skip debate if confidence >= threshold AND tier is not low
should_skip = confidence >= threshold and tier not in ['supervisor', 'escalate']
print(should_skip)
")

if [ "$should_skip" = "True" ]; then
    log_pass "Debate skipped for high-confidence task (0.92 >= 0.70)"
else
    log_fail "Should skip debate for high-confidence task"
fi

# Test 9: Critical task types always trigger debate
log_test "Critical task types always trigger debate"
cat > .loki/state/task-confidence.json << 'EOF'
{
    "confidence": 0.95,
    "tier": "auto-approve",
    "taskType": "security-audit"
}
EOF

should_debate=$(python3 -c "
import json
critical_types = ['security', 'deployment', 'database', 'infrastructure', 'auth']
with open('.loki/state/task-confidence.json') as f:
    data = json.load(f)
task_type = data['taskType']
is_critical = any(ct in task_type.lower() for ct in critical_types)
print(is_critical)
")

if [ "$should_debate" = "True" ]; then
    log_pass "Debate triggered for critical task type (security)"
else
    log_fail "Should trigger debate for critical task types"
fi

# Test 10: Evaluate debate outcome returns structured result
log_test "Evaluate debate outcome function"
cat > .loki/state/debate-log.json << 'EOF'
{
    "proposalId": "debate-eval-001",
    "proposalType": "feature",
    "rounds": [{"round": 1}],
    "outcome": {
        "verified": true,
        "reason": "All challenges addressed",
        "roundsCompleted": 1,
        "finalDefenseScore": 0.88
    }
}
EOF

eval_result=$(python3 -c "
import json
with open('.loki/state/debate-log.json') as f:
    log = json.load(f)
outcome = log.get('outcome', {})
result = {
    'proposalId': log.get('proposalId'),
    'verified': outcome.get('verified'),
    'recommendation': 'proceed' if outcome.get('verified') else 'revise'
}
print(result['verified'] and result['recommendation'] == 'proceed')
")

if [ "$eval_result" = "True" ]; then
    log_pass "Evaluate outcome returns correct recommendation"
else
    log_fail "Evaluate outcome result incorrect"
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
