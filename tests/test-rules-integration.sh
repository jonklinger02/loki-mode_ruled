#!/bin/bash
# Test: Global Rules Integration
# Tests the rules discovery and loading functionality

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
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

# Source the run.sh to get access to functions
# We need to extract just the functions we want to test
extract_functions() {
    # Extract functions from run.sh
    sed -n '/^discover_rules()/,/^}$/p' "$PROJECT_DIR/autonomy/run.sh"
    sed -n '/^find_rule_source()/,/^}$/p' "$PROJECT_DIR/autonomy/run.sh"
    sed -n '/^generate_rules_index()/,/^}$/p' "$PROJECT_DIR/autonomy/run.sh"
    sed -n '/^load_rules()/,/^}$/p' "$PROJECT_DIR/autonomy/run.sh"
}

# Create a minimal version of required dependencies
log_header() { echo "=== $1 ==="; }
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }

# Evaluate the functions in this shell
eval "$(extract_functions)"

cd "$TEST_DIR"

echo "========================================"
echo "Loki Mode Rules Integration Tests"
echo "========================================"
echo "Test directory: $TEST_DIR"
echo ""

# Test 1: discover_rules with no rules directories
# Override HOME to prevent picking up real global rules
log_test "discover_rules with no rules directories"
result=$(HOME="$TEST_DIR" discover_rules)
if [ -z "$result" ]; then
    log_pass "Returns empty when no rules found"
else
    log_fail "Expected empty, got: $result"
fi

# Test 2: discover_rules with project rules
log_test "discover_rules with project .cursor/rules"
mkdir -p .cursor/rules
echo "test content" > .cursor/rules/react.mdc
echo "test content" > .cursor/rules/clean-code.md
result=$(discover_rules)
if [[ "$result" == *"react"* ]] && [[ "$result" == *"clean-code"* ]]; then
    log_pass "Found project rules: $result"
else
    log_fail "Expected react and clean-code, got: $result"
fi

# Test 3: find_rule_source returns correct path
log_test "find_rule_source returns correct path"
source_path=$(find_rule_source "react")
if [ "$source_path" = ".cursor/rules/react.mdc" ]; then
    log_pass "Correct path returned: $source_path"
else
    log_fail "Expected .cursor/rules/react.mdc, got: $source_path"
fi

# Test 4: find_rule_source returns 1 for missing rule
log_test "find_rule_source returns 1 for missing rule"
if ! find_rule_source "nonexistent" >/dev/null 2>&1; then
    log_pass "Returns failure for missing rule"
else
    log_fail "Should have returned 1 for missing rule"
fi

# Test 5: discover_rules deduplicates rules from multiple directories
log_test "discover_rules deduplicates rules"
mkdir -p .claude/rules
echo "duplicate content" > .claude/rules/react.mdc
result=$(discover_rules)
# Count occurrences of "react"
count=$(echo "$result" | tr ',' '\n' | grep -c "^react$" || true)
if [ "$count" -eq 1 ]; then
    log_pass "Rule names deduplicated correctly"
else
    log_fail "Expected 1 occurrence of react, got: $count (result: $result)"
fi

# Test 6: Priority order - project rules before global
log_test "find_rule_source priority order"
# .cursor/rules should take priority over .claude/rules
echo "cursor version" > .cursor/rules/priority-test.mdc
echo "claude version" > .claude/rules/priority-test.mdc
source_path=$(find_rule_source "priority-test")
if [ "$source_path" = ".cursor/rules/priority-test.mdc" ]; then
    log_pass ".cursor/rules takes priority over .claude/rules"
else
    log_fail "Expected .cursor/rules path, got: $source_path"
fi

# Test 7: load_rules creates .loki/rules directory and copies files
log_test "load_rules copies files to .loki/rules"
mkdir -p .loki/rules .loki/config
load_rules >/dev/null 2>&1
if [ -f ".loki/rules/react.mdc" ] && [ -f ".loki/rules/clean-code.md" ]; then
    log_pass "Rules copied to .loki/rules/"
else
    log_fail "Rules not copied correctly"
    ls -la .loki/rules/ 2>/dev/null || echo "Directory not created"
fi

# Test 8: generate_rules_index creates INDEX.md
log_test "generate_rules_index creates INDEX.md"
if [ -f ".loki/rules/INDEX.md" ]; then
    if grep -q "react.mdc" .loki/rules/INDEX.md; then
        log_pass "INDEX.md created with rule listing"
    else
        log_fail "INDEX.md missing rule listing"
    fi
else
    log_fail "INDEX.md not created"
fi

# Test 9: LOKI_RULES env var filters rules
log_test "LOKI_RULES env var filters rules"
rm -rf .loki/rules .loki/config
mkdir -p .loki/rules .loki/config
LOKI_RULES="react" load_rules >/dev/null 2>&1
if [ -f ".loki/rules/react.mdc" ] && [ ! -f ".loki/rules/clean-code.md" ]; then
    log_pass "LOKI_RULES correctly filters rules"
else
    log_fail "LOKI_RULES filtering not working"
    ls -la .loki/rules/
fi

# Test 10: Saved rules.txt is used on subsequent runs
log_test "Saved rules.txt is used"
rm -rf .loki/rules
mkdir -p .loki/rules .loki/config
echo "clean-code" > .loki/config/rules.txt
unset LOKI_RULES
load_rules >/dev/null 2>&1
if [ -f ".loki/rules/clean-code.md" ] && [ ! -f ".loki/rules/react.mdc" ]; then
    log_pass "Saved rules.txt selection used"
else
    log_fail "Saved rules.txt not used correctly"
    ls -la .loki/rules/
fi

echo ""
echo "========================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "========================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
exit 0
