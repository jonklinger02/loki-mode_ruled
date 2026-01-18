# PRD: Global Rules Integration for Loki Mode

**Version:** 1.1
**Status:** Implemented
**Author:** Jon Klinger
**Date:** 2026-01-18

---

## Overview

Add support for loading coding rules/guidelines from multiple global and project-local directories into Loki Mode sessions. Rules are `.mdc` or `.md` files containing coding standards, best practices, and project-specific guidelines that agents should follow during development.

---

## Problem Statement

Loki Mode operates autonomously but lacks awareness of project-specific coding standards and best practices. Users maintain rules in `.cursor/rules/` or `.claude/rules/` directories (both globally in `~/.cursor/rules/` and per-project), but Loki Mode doesn't discover or apply these rules during autonomous operation.

**Pain Points:**
1. Agents generate code that doesn't follow established project patterns
2. Users must manually copy rules or repeat guidelines in PRDs
3. No mechanism to select which rules apply to a specific session
4. Rules scattered across multiple locations aren't consolidated

---

## Goals

1. **Automatic Discovery** - Find rules in global (`~/`) and project-local directories
2. **Flexible Selection** - Support env vars, interactive multiselect, and saved preferences
3. **Agent Accessibility** - Load selected rules to `.loki/rules/` with an index for easy agent reference
4. **Zero Config Default** - Work out-of-the-box by loading all available rules
5. **Convergence & Completion** - Support "Definition of Done" rules to help agents recognize when a task is finished and prevent infinite optimization loops
---

## Non-Goals

- Rule validation or linting
- Rule conflict resolution (later rules override earlier ones)
- Dynamic rule reloading during a session
- Rule enforcement (agents are guided, not constrained)

---

## Technical Requirements

### 1. Rule Discovery

**Search Directories (Priority Order):**
```
1. .cursor/rules/       (project-local, highest priority)
2. .claude/rules/       (project-local)
3. ~/.cursor/rules/     (global)
4. ~/.claude/rules/     (global, lowest priority)
```

**Supported File Extensions:**
- `.mdc` (Cursor/Claude rule format)
- `.md` (standard markdown)

**Rule File Format (Optional Frontmatter):**
```yaml
---
description: Brief description of what this rule covers
globs: **/*.tsx, **/*.jsx    # File patterns this rule applies to
alwaysApply: false           # Whether to always include this rule
---

# Rule Title

Rule content in markdown...
```

### 2. Rule Selection Methods

**Method A: Environment Variable**
```bash
LOKI_RULES="react,firebase-rules,clean-code" ./autonomy/run.sh
```

**Method B: Interactive Selection**
```bash
LOKI_INTERACTIVE_RULES=true ./autonomy/run.sh
```
- Triggers AskUserQuestion with multiselect
- Presents discovered rules with descriptions
- Saves selection for future runs

**Method C: Saved Preferences**
- Selection persisted to `.loki/config/rules.txt`
- Automatically used on subsequent runs
- Overridden by env var if set

**Method D: Default (All Rules)**
- When no selection method specified
- Loads all discovered rules
- Good for projects with curated rule sets

### 3. Rule Loading

**Output Location:** `.loki/rules/`

**Index File:** `.loki/rules/INDEX.md`
```markdown
# Loaded Rules Index

## Available Rules

- **react.mdc**: React best practices and patterns
- **firebase-rules.mdc**: Firebase integration guidelines
- **clean-code.mdc**: General clean code principles

## Usage

Before implementing features, check if any rules apply...
```

### 4. New Invocation Patterns

```
Loki Mode                                    # Load all available rules
Loki Mode with PRD at path/to/prd            # Load all rules + PRD
Loki Mode with rules                         # Interactive rule selection
Loki Mode with rules react,firebase-rules    # Load specific rules only
```

---

## Implementation Guide

### File: `autonomy/run.sh`

#### 1. Add Environment Variables (Header Section ~Line 50)

```bash
# Rules Configuration:
#   LOKI_RULES                 - Comma-separated list of rules to load (default: all)
#                                Example: "react,firebase-rules,clean-code"
#                                Searches: .cursor/rules, .claude/rules, ~/.cursor/rules, ~/.claude/rules
#   LOKI_INTERACTIVE_RULES     - Enable interactive rule selection via AskUserQuestion (default: false)
```

#### 2. Add Functions (After `init_loki_dir`, ~Line 325)

```bash
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
            log_info "  ✓ Loaded: $rule"
            ((loaded_count++))
        else
            log_warn "  ✗ Rule not found: $rule"
        fi
    done

    echo "$rules_to_load" > ".loki/config/rules.txt"
    generate_rules_index
    log_info "Loaded $loaded_count rules to .loki/rules/"
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
```

#### 3. Call `load_rules` in Main (After `init_loki_dir`)

```bash
# Initialize .loki directory
init_loki_dir

# Load project rules (from global or local rules directories)
load_rules
```

### File: `SKILL.md`

#### Update Invocation Section (~Line 1242)

Add the new invocation patterns and rules documentation as shown in the Technical Requirements section above.

---

## Testing

### Test Cases

1. **No rules exist anywhere** - Should log "No rules found" and continue
2. **Project rules only** - Should discover and load from `.cursor/rules/` or `.claude/rules/`
3. **Global rules only** - Should discover and load from `~/.cursor/rules/` or `~/.claude/rules/`
4. **Mixed global + project** - Project rules take priority, no duplicates
5. **LOKI_RULES env var** - Should load only specified rules
6. **Saved selection exists** - Should use `.loki/config/rules.txt`
7. **Rule not found** - Should warn but continue with other rules

### Manual Test Commands

```bash
# Test discovery
cd /path/to/project
./autonomy/run.sh  # Should list discovered rules

# Test specific rules
LOKI_RULES="react,clean-code" ./autonomy/run.sh

# Test interactive (requires skill integration)
LOKI_INTERACTIVE_RULES=true ./autonomy/run.sh

# Verify loaded rules
cat .loki/rules/INDEX.md
ls -la .loki/rules/
```

---

## Example Rule Files

### `~/.cursor/rules/react.mdc`

```markdown
---
description: React best practices and patterns for modern web applications
globs: **/*.tsx, **/*.jsx, components/**/*
alwaysApply: false
---

# React Best Practices

## Component Structure
- Use functional components over class components
- Keep components small and focused
- Extract reusable logic into custom hooks

## Hooks
- Follow the Rules of Hooks
- Use custom hooks for reusable logic
- Use appropriate dependency arrays in useEffect
```

### `~/.cursor/rules/clean-code.mdc`

```markdown
---
description: General clean code principles and patterns
globs: **/*
alwaysApply: true
---

# Clean Code Principles

## Naming
- Use meaningful, descriptive names
- Avoid abbreviations unless universally understood
- Use consistent naming conventions

## Functions
- Keep functions small and focused (single responsibility)
- Limit function parameters (max 3-4)
- Avoid side effects where possible
```

---

## Migration Notes

For users upgrading from a fork without this feature:

1. Copy the new functions to `autonomy/run.sh`
2. Add the `load_rules` call after `init_loki_dir`
3. Update `SKILL.md` with new invocation patterns
4. Existing `.loki/` directories will work - rules just add to them

---

## Future Enhancements

- [ ] Rule conflict detection and resolution
- [ ] Glob-based auto-selection (apply rules matching current file types)
- [ ] Rule versioning and updates
- [ ] Integration with MCP rule servers
- [ ] Rule effectiveness tracking (which rules prevent issues)
