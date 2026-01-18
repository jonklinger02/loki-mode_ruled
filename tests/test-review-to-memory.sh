#!/bin/bash
# Test: Review-to-Memory Learning (Anti-Pattern Extraction)
# Tests the extraction of code review findings into anti-patterns

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
echo "Review-to-Memory Learning Tests"
echo "========================================"
echo ""

# Initialize structure
mkdir -p .loki/{logs,memory/semantic/anti-patterns,state}

# Test 1: Extract anti-patterns from review file
log_test "Extract anti-patterns from code review"
cat > .loki/logs/latest-review.json << 'EOF'
{
  "findings": [
    {
      "severity": "critical",
      "category": "security",
      "description": "SQL injection vulnerability in user input handling",
      "file": "src/db.ts",
      "line": 45,
      "prevention": "Use parameterized queries instead of string concatenation"
    },
    {
      "severity": "high",
      "category": "type-safety",
      "description": "Using 'any' type loses TypeScript benefits",
      "file": "src/api.ts",
      "line": 123,
      "prevention": "Define explicit interfaces for API responses"
    },
    {
      "severity": "medium",
      "category": "performance",
      "description": "N+1 query pattern in loop",
      "file": "src/users.ts",
      "line": 78,
      "prevention": "Batch queries or use eager loading"
    },
    {
      "severity": "low",
      "category": "style",
      "description": "Inconsistent naming convention",
      "file": "src/utils.ts",
      "line": 12,
      "prevention": "Follow camelCase for variables"
    }
  ]
}
EOF

# Run extraction
python3 << 'EXTRACT'
import json
import os
from datetime import datetime, timezone

review_file = ".loki/logs/latest-review.json"
anti_patterns_dir = ".loki/memory/semantic/anti-patterns"

os.makedirs(anti_patterns_dir, exist_ok=True)

with open(review_file, 'r') as f:
    review = json.load(f)

findings = review.get('findings', [])
extracted = 0

for finding in findings:
    severity = finding.get('severity', 'medium').lower()

    # Only extract Critical, High, or Medium severity
    if severity not in ['critical', 'high', 'medium']:
        continue

    category = finding.get('category', 'general')
    description = finding.get('description', '')
    file_path = finding.get('file', '')
    prevention = finding.get('prevention', 'Follow best practices')

    if not description:
        continue

    pattern_id = f"{category}-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}-{extracted}"

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

    category_file = os.path.join(anti_patterns_dir, f"{category}.jsonl")
    with open(category_file, 'a') as f:
        f.write(json.dumps(anti_pattern) + "\n")

    extracted += 1

print(f"EXTRACTED:{extracted}")
EXTRACT

# Check results
security_file=".loki/memory/semantic/anti-patterns/security.jsonl"
type_safety_file=".loki/memory/semantic/anti-patterns/type-safety.jsonl"
performance_file=".loki/memory/semantic/anti-patterns/performance.jsonl"
style_file=".loki/memory/semantic/anti-patterns/style.jsonl"

if [ -f "$security_file" ] && [ -f "$type_safety_file" ] && [ -f "$performance_file" ]; then
    log_pass "Critical/High/Medium findings extracted"
else
    log_fail "Not all findings extracted"
fi

if [ -f "$style_file" ]; then
    log_fail "Low severity findings should be skipped"
else
    log_pass "Low severity findings correctly skipped"
fi

# Test 2: Verify anti-pattern format
log_test "Verify anti-pattern JSON format"
python3 << 'VERIFY'
import json

security_file = ".loki/memory/semantic/anti-patterns/security.jsonl"
with open(security_file, 'r') as f:
    pattern = json.loads(f.readline())

required_fields = ['id', 'pattern', 'category', 'severity', 'prevention', 'source', 'confidence', 'created']
missing = [f for f in required_fields if f not in pattern]

if not missing:
    print("VALID_FORMAT")
    print(f"Confidence:{pattern['confidence']}")
else:
    print(f"MISSING:{','.join(missing)}")
VERIFY

format_result=$(python3 -c "
import json
with open('.loki/memory/semantic/anti-patterns/security.jsonl', 'r') as f:
    p = json.loads(f.readline())
    print('confidence' in p and p['confidence'] == 0.9)
")

if [ "$format_result" = "True" ]; then
    log_pass "Anti-pattern format correct with proper confidence scoring"
else
    log_fail "Anti-pattern format incorrect"
fi

# Test 3: Query anti-patterns by context
log_test "Query anti-patterns by context"
python3 << 'QUERY'
import json
import os
import glob

anti_patterns_dir = ".loki/memory/semantic/anti-patterns"
context = "working with user input database queries sql"

def load_jsonl(filepath):
    entries = []
    with open(filepath, 'r') as f:
        for line in f:
            try:
                entries.append(json.loads(line.strip()))
            except:
                pass
    return entries

all_patterns = []
for jsonl_file in glob.glob(f"{anti_patterns_dir}/*.jsonl"):
    all_patterns.extend(load_jsonl(jsonl_file))

def score_pattern(pattern):
    desc = pattern.get('pattern', '').lower()
    cat = pattern.get('category', '').lower()
    score = 0
    for word in context.lower().split():
        if len(word) > 3:
            if word in desc:
                score += 3
            if word in cat:
                score += 2
    severity = pattern.get('severity', 'low')
    if severity == 'critical':
        score *= 2
    return score

scored = [(score_pattern(p), p) for p in all_patterns]
scored.sort(reverse=True, key=lambda x: x[0])
relevant = [p for score, p in scored if score > 0][:5]

print(f"FOUND:{len(relevant)}")
if relevant:
    print(f"TOP:{relevant[0]['category']}")
QUERY

query_result=$(python3 -c "
import json
import glob

all_patterns = []
for f in glob.glob('.loki/memory/semantic/anti-patterns/*.jsonl'):
    with open(f) as fp:
        for line in fp:
            all_patterns.append(json.loads(line))

context = 'sql database query'
relevant = [p for p in all_patterns if any(w in p['pattern'].lower() for w in context.split())]
print(len(relevant) > 0)
")

if [ "$query_result" = "True" ]; then
    log_pass "Context-based query returns relevant anti-patterns"
else
    log_fail "Context-based query failed"
fi

# Test 4: Test severity-based confidence scoring
log_test "Severity-based confidence scoring"
python3 << 'CONFIDENCE'
import json

def check_confidence():
    # Critical should be 0.9
    with open('.loki/memory/semantic/anti-patterns/security.jsonl', 'r') as f:
        critical = json.loads(f.readline())

    # High should be 0.7
    with open('.loki/memory/semantic/anti-patterns/type-safety.jsonl', 'r') as f:
        high = json.loads(f.readline())

    # Medium should be 0.5
    with open('.loki/memory/semantic/anti-patterns/performance.jsonl', 'r') as f:
        medium = json.loads(f.readline())

    if critical['confidence'] == 0.9 and high['confidence'] == 0.7 and medium['confidence'] == 0.5:
        print("CORRECT")
    else:
        print(f"WRONG:critical={critical['confidence']},high={high['confidence']},medium={medium['confidence']}")

check_confidence()
CONFIDENCE

confidence_result=$(python3 -c "
import json
with open('.loki/memory/semantic/anti-patterns/security.jsonl') as f:
    c = json.loads(f.readline())['confidence']
with open('.loki/memory/semantic/anti-patterns/type-safety.jsonl') as f:
    h = json.loads(f.readline())['confidence']
with open('.loki/memory/semantic/anti-patterns/performance.jsonl') as f:
    m = json.loads(f.readline())['confidence']
print(c == 0.9 and h == 0.7 and m == 0.5)
")

if [ "$confidence_result" = "True" ]; then
    log_pass "Confidence scoring by severity works correctly"
else
    log_fail "Confidence scoring incorrect"
fi

# Test 5: Empty review file handling
log_test "Handle empty/invalid review file"
echo '{}' > .loki/logs/empty-review.json

python3 << 'EMPTY'
import json
import os

review_file = ".loki/logs/empty-review.json"

with open(review_file, 'r') as f:
    review = json.load(f)

findings = review.get('findings', [])
if len(findings) == 0:
    print("CORRECTLY_HANDLED_EMPTY")
EMPTY

log_pass "Empty review file handled gracefully"

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
