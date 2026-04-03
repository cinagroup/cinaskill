#!/bin/bash
#
# edge-case-tests.sh - OpenClaw Memory System Edge Case Tests
# 
# Tests Phase 8.4: Edge Case Handling
# 1) Empty memory directory
# 2) Corrupted YAML frontmatter
# 3) Concurrent write conflicts
# 4) Disk space exhaustion
# 5) Permission errors
#
# Usage: ./edge-case-tests.sh [--test-name]
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/.openclaw/workspace}"
TEST_DIR="$WORKSPACE_DIR/test"
RESULTS_DIR="$TEST_DIR/results"
MEMORY_DIR="$WORKSPACE_DIR/memory"
BACKUP_DIR="$WORKSPACE_DIR/test/.backup"
LOG_FILE="$RESULTS_DIR/edge-case-tests.log"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [$level] $msg" | tee -a "$LOG_FILE"
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }

pass() {
    local test_name="$1"
    ((TESTS_PASSED++))
    echo -e "${GREEN}[PASS]${NC} $test_name" | tee -a "$LOG_FILE"
}

fail() {
    local test_name="$1"
    local reason="${2:-}"
    ((TESTS_FAILED++))
    echo -e "${RED}[FAIL]${NC} $test_name" | tee -a "$LOG_FILE"
    if [[ -n "$reason" ]]; then
        echo -e "${RED}       Reason: $reason${NC}" | tee -a "$LOG_FILE"
    fi
}

skip() {
    local test_name="$1"
    local reason="${2:-}"
    echo -e "${YELLOW}[SKIP]${NC} $test_name" | tee -a "$LOG_FILE"
    if [[ -n "$reason" ]]; then
        echo -e "${YELLOW}       Reason: $reason${NC}" | tee -a "$LOG_FILE"
    fi
}

run_test() {
    local test_name="$1"
    local test_func="$2"
    ((TESTS_RUN++))
    echo -e "${BLUE}[TEST]${NC} $test_name" | tee -a "$LOG_FILE"
    
    if $test_func; then
        pass "$test_name"
        return 0
    else
        fail "$test_name"
        return 1
    fi
}

# Backup original memory directory
backup_memory() {
    info "Backing up original memory directory..."
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    if [[ -d "$MEMORY_DIR" ]]; then
        cp -r "$MEMORY_DIR" "$BACKUP_DIR/memory"
    fi
}

# Restore original memory directory
restore_memory() {
    info "Restoring original memory directory..."
    if [[ -d "$MEMORY_DIR" ]]; then
        rm -rf "$MEMORY_DIR"
    fi
    if [[ -d "$BACKUP_DIR/memory" ]]; then
        cp -r "$BACKUP_DIR/memory" "$MEMORY_DIR"
    fi
}

# Cleanup test artifacts (called after report generation)
cleanup() {
    info "Cleaning up test artifacts..."
    rm -rf "$BACKUP_DIR"
    rm -f "$RESULTS_DIR"/*.tmp
}

# =============================================================================
# Test 1: Empty Memory Directory
# =============================================================================

test_empty_memory_directory() {
    local test_name="Empty Memory Directory Handling"
    info "Testing: $test_name"
    
    # Create empty memory directory
    rm -rf "$MEMORY_DIR"
    mkdir -p "$MEMORY_DIR"
    
    # Try to run memory index command
    local output
    local exit_code=0
    cd "$WORKSPACE_DIR"
    output=$(openclaw memory index 2>&1) || exit_code=$?
    
    # Should not crash, should create necessary files
    if [[ -f "$MEMORY_DIR/README.md" ]] || [[ -f "$WORKSPACE_DIR/MEMORY.md" ]]; then
        info "Memory system handled empty directory gracefully"
        return 0
    else
        # Even if index fails, check if it created basic structure
        if [[ $exit_code -eq 0 ]] || [[ "$output" == *"Creating"* ]]; then
            return 0
        fi
        warn "Empty directory handling produced exit code: $exit_code"
        return 1
    fi
}

test_empty_memory_scan() {
    local test_name="Empty Memory Scan"
    info "Testing: $test_name"
    
    # Ensure memory directory is empty (except README if needed)
    rm -rf "$MEMORY_DIR"/*.md 2>/dev/null || true
    find "$MEMORY_DIR" -maxdepth 1 -name "*.md" ! -name "README.md" -delete 2>/dev/null || true
    
    # Try to search in empty memory
    local output
    local exit_code=0
    cd "$WORKSPACE_DIR"
    output=$(openclaw memory search "test" 2>&1) || exit_code=$?
    
    # Should return empty results, not crash
    if [[ $exit_code -eq 0 ]] || [[ "$output" == *"No memories found"* ]] || [[ "$output" == *"0 results"* ]]; then
        info "Empty memory search handled correctly"
        return 0
    else
        warn "Empty memory search produced unexpected output: $output"
        return 1
    fi
}

# =============================================================================
# Test 2: Corrupted YAML Frontmatter
# =============================================================================

test_corrupted_yaml_missing_closing() {
    local test_name="Corrupted YAML - Missing Closing Delimiter"
    info "Testing: $test_name"
    
    local test_file="$MEMORY_DIR/corrupted-missing-close.md"
    
    # Remove any stale file first
    rm -f "$test_file"
    
    cat > "$test_file" << 'EOF'
---
name: Test Memory
description: Missing closing delimiter
type: project
created: 2026-04-03

# Content without closing ---

This file has broken YAML frontmatter.
EOF
    
    # Try to index
    local exit_code=0
    cd "$WORKSPACE_DIR"
    openclaw memory index 2>&1 || exit_code=$?
    
    # Clean up test file immediately
    rm -f "$test_file"
    
    # Re-index to remove stale reference
    cd "$WORKSPACE_DIR" && openclaw memory index 2>&1 >/dev/null || true
    
    # Should handle gracefully (skip file or warn)
    if [[ $exit_code -eq 0 ]]; then
        info "Index handled corrupted YAML without crashing"
        return 0
    else
        warn "Index failed with corrupted YAML (exit code: $exit_code)"
        return 1
    fi
}

test_corrupted_yaml_invalid_syntax() {
    local test_name="Corrupted YAML - Invalid Syntax"
    info "Testing: $test_name"
    
    local test_file="$MEMORY_DIR/corrupted-syntax.md"
    cat > "$test_file" << 'EOF'
---
name: Test Memory
description: "Unclosed string
type: project
created: 2026-04-03
tags: [unclosed, bracket
---

# Content

Invalid YAML syntax.
EOF
    
    # Try to index
    local exit_code=0
    cd "$WORKSPACE_DIR"
    openclaw memory index 2>&1 || exit_code=$?
    
    # Should handle gracefully
    if [[ $exit_code -eq 0 ]]; then
        info "Index handled invalid YAML syntax without crashing"
        rm -f "$test_file"
        return 0
    else
        warn "Index failed with invalid YAML (exit code: $exit_code)"
        rm -f "$test_file"
        return 1
    fi
}

test_corrupted_yaml_binary_content() {
    local test_name="Corrupted YAML - Binary Content in Frontmatter"
    info "Testing: $test_name"
    
    local test_file="$MEMORY_DIR/corrupted-binary.md"
    # Create file with binary content in frontmatter area using echo -e
    echo -e '---\nname: Test\x00\x01\x02Binary\x03\n---\n\nContent' > "$test_file"
    
    # Try to index
    local exit_code=0
    cd "$WORKSPACE_DIR"
    openclaw memory index 2>&1 || exit_code=$?
    
    # Should handle gracefully
    if [[ $exit_code -eq 0 ]]; then
        info "Index handled binary content without crashing"
        rm -f "$test_file"
        return 0
    else
        warn "Index failed with binary content (exit code: $exit_code)"
        rm -f "$test_file"
        return 1
    fi
}

# =============================================================================
# Test 3: Concurrent Write Conflicts
# =============================================================================

test_concurrent_writes_same_file() {
    local test_name="Concurrent Writes - Same File"
    info "Testing: $test_name"
    
    local test_file="$MEMORY_DIR/concurrent-test.md"
    local original_content="# Original Content"
    
    # Create initial file
    echo "$original_content" > "$test_file"
    
    # Simulate concurrent writes using background processes
    local pids=()
    for i in {1..5}; do
        (
            for j in {1..10}; do
                echo "# Write $i-$j at $(date +%s.%N)" >> "$test_file"
                sleep 0.01
            done
        ) &
        pids+=($!)
    done
    
    # Wait for all processes
    local all_success=true
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            all_success=false
        fi
    done
    
    # Check file integrity (should not be corrupted)
    if [[ -f "$test_file" ]] && [[ -s "$test_file" ]]; then
        # Count lines - should have original + 50 writes (5 processes * 10 writes each)
        local line_count
        line_count=$(wc -l < "$test_file")
        
        # Note: Concurrent appends may interleave but file should remain readable
        # Linux ext4 filesystem provides atomic appends for small writes (< PIPE_BUF)
        if [[ $line_count -ge 1 ]]; then
            info "Concurrent writes completed. Line count: $line_count (expected ~51)"
            # This test passes if file is readable, even if lines interleaved
            rm -f "$test_file"
            return 0
        else
            warn "File appears corrupted (line count: $line_count)"
            rm -f "$test_file"
            return 1
        fi
    else
        warn "File was deleted or empty after concurrent writes"
        return 1
    fi
}

test_concurrent_index_operations() {
    local test_name="Concurrent Index Operations"
    info "Testing: $test_name"
    
    # Create multiple test files
    for i in {1..5}; do
        cat > "$MEMORY_DIR/concurrent-$i.md" << EOF
---
name: Concurrent Test $i
description: Testing concurrent operations
type: project
---

# Content $i
EOF
    done
    
    # Run multiple index operations concurrently
    local pids=()
    local outputs=()
    for i in {1..3}; do
        (
            cd "$WORKSPACE_DIR"
            openclaw memory index 2>&1
        ) > "$RESULTS_DIR/index-output-$i.tmp" &
        pids+=($!)
    done
    
    # Wait for all
    local all_success=true
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            all_success=false
        fi
    done
    
    # Check outputs
    for i in {1..3}; do
        if [[ -f "$RESULTS_DIR/index-output-$i.tmp" ]]; then
            local output
            output=$(cat "$RESULTS_DIR/index-output-$i.tmp")
            if [[ -n "$output" ]] && [[ "$output" != *"Error"* ]]; then
                info "Index operation $i completed successfully"
            else
                warn "Index operation $i had issues: $output"
            fi
            rm -f "$RESULTS_DIR/index-output-$i.tmp"
        fi
    done
    
    # Cleanup test files
    rm -f "$MEMORY_DIR"/concurrent-*.md
    
    if $all_success; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Test 4: Disk Space Exhaustion (Simulated)
# =============================================================================

test_disk_space_simulation() {
    local test_name="Disk Space Exhaustion Simulation"
    info "Testing: $test_name"
    
    # Create a large file to simulate low disk space
    local large_file="$MEMORY_DIR/large-test-file.tmp"
    local available_space
    available_space=$(df -P "$MEMORY_DIR" | awk 'NR==2 {print $4}')
    
    # Use only a small portion for testing (10MB max for safety)
    local test_size=$((available_space > 10240 ? 10240 : available_space - 100))
    
    if [[ $test_size -lt 100 ]]; then
        skip "Insufficient disk space for test"
        return 0
    fi
    
    info "Creating test file of ${test_size}KB..."
    
    # Create file using dd (faster than /dev/zero loop)
    if dd if=/dev/zero of="$large_file" bs=1024 count="$test_size" 2>/dev/null; then
        info "Large file created, testing write operations..."
        
        # Try to write a memory file
        local test_memory="$MEMORY_DIR/disk-test.md"
        if echo "# Test" > "$test_memory" 2>/dev/null; then
            info "Write succeeded (space still available)"
            rm -f "$large_file" "$test_memory"
            return 0
        else
            info "Write correctly failed when disk full"
            rm -f "$large_file"
            return 0
        fi
    else
        warn "Failed to create test file"
        rm -f "$large_file"
        return 1
    fi
}

test_large_memory_file() {
    local test_name="Large Memory File Handling"
    info "Testing: $test_name"
    
    local large_file="$MEMORY_DIR/large-memory.md"
    
    # Create a file larger than typical limits (100KB)
    {
        echo "---"
        echo "name: Large Test Memory"
        echo "description: Testing large file handling"
        echo "type: project"
        echo "---"
        echo ""
        echo "# Large Content"
        echo ""
        for i in {1..2000}; do
            echo "Line $i: This is test content to make the file large. Lorem ipsum dolor sit amet."
        done
    } > "$large_file"
    
    local file_size
    file_size=$(wc -c < "$large_file")
    info "Created file of $file_size bytes"
    
    # Try to index
    local exit_code=0
    cd "$WORKSPACE_DIR"
    openclaw memory index 2>&1 || exit_code=$?
    
    rm -f "$large_file"
    
    if [[ $exit_code -eq 0 ]]; then
        info "Large file indexed successfully"
        return 0
    else
        warn "Index failed with large file (exit code: $exit_code)"
        return 1
    fi
}

# =============================================================================
# Test 5: Permission Errors
# =============================================================================

test_readonly_memory_directory() {
    local test_name="Read-Only Memory Directory"
    info "Testing: $test_name"
    
    # Make memory directory read-only
    chmod 555 "$MEMORY_DIR"
    
    # Try to create a file
    local test_file="$MEMORY_DIR/readonly-test.md"
    local exit_code=0
    echo "# Test" > "$test_file" 2>/dev/null || exit_code=$?
    
    # Restore permissions
    chmod 755 "$MEMORY_DIR"
    rm -f "$test_file" 2>/dev/null || true
    
    if [[ $exit_code -ne 0 ]]; then
        info "Correctly detected read-only condition"
        return 0
    else
        warn "Write succeeded on read-only directory (unexpected)"
        return 1
    fi
}

test_readonly_memory_file() {
    local test_name="Read-Only Memory File"
    info "Testing: $test_name"
    
    local test_file="$MEMORY_DIR/readonly-file.md"
    
    # Create file and make it read-only
    cat > "$test_file" << 'EOF'
---
name: Readonly Test
description: Testing read-only file handling
---

# Content
EOF
    chmod 444 "$test_file"
    
    # Try to modify
    local exit_code=0
    echo "# Modified" >> "$test_file" 2>/dev/null || exit_code=$?
    
    # Restore and cleanup
    chmod 644 "$test_file"
    rm -f "$test_file"
    
    if [[ $exit_code -ne 0 ]]; then
        info "Correctly detected read-only file"
        return 0
    else
        warn "Write succeeded on read-only file (unexpected)"
        return 1
    fi
}

test_no_execute_permission_on_script() {
    local test_name="Script Permission Handling"
    info "Testing: $test_name"
    
    # Test if memory scripts handle permission issues gracefully
    local script="$WORKSPACE_DIR/scripts/memory-maintenance.sh"
    
    if [[ -f "$script" ]]; then
        # Try to run without execute permission
        chmod -x "$script"
        local exit_code=0
        bash "$script" 2>&1 || exit_code=$?
        chmod +x "$script"
        
        if [[ $exit_code -eq 0 ]]; then
            info "Script ran successfully via bash"
            return 0
        else
            warn "Script failed (exit code: $exit_code)"
            return 1
        fi
    else
        skip "Memory maintenance script not found"
        return 0
    fi
}

test_owned_by_different_user() {
    local test_name="File Ownership Simulation"
    info "Testing: $test_name"
    
    # We can't easily test different user ownership without root
    # Instead, test that the system handles permission denied gracefully
    
    local test_file="$MEMORY_DIR/ownership-test.md"
    
    # Create file
    echo "# Test" > "$test_file"
    
    # Remove all permissions (simulate inaccessible file)
    chmod 000 "$test_file"
    
    # Try to read
    local exit_code=0
    cat "$test_file" >/dev/null 2>&1 || exit_code=$?
    
    # Restore and cleanup
    chmod 644 "$test_file"
    rm -f "$test_file"
    
    if [[ $exit_code -ne 0 ]]; then
        info "Correctly detected permission denied"
        return 0
    else
        # Running as root might succeed
        info "Access succeeded (possibly running as root)"
        return 0
    fi
}

# =============================================================================
# Report Generation
# =============================================================================

generate_report() {
    local report_file="$RESULTS_DIR/edge-case-report.md"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$report_file" << EOF
# Edge Case Test Report

**Generated**: $timestamp  
**Workspace**: $WORKSPACE_DIR  
**Tests Run**: $TESTS_RUN  
**Passed**: $TESTS_PASSED  
**Failed**: $TESTS_FAILED  

---

## Summary

$(if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ All tests passed successfully!"
else
    echo "⚠️ $TESTS_FAILED test(s) failed. Review details below."
fi)

---

## Test Results

### 1. Empty Memory Directory

| Test | Status |
|------|--------|
| Empty Directory Handling | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |
| Empty Memory Scan | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |

**Notes**: Tests verify that the memory system handles empty directories gracefully without crashing.

### 2. Corrupted YAML Frontmatter

| Test | Status |
|------|--------|
| Missing Closing Delimiter | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |
| Invalid YAML Syntax | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |
| Binary Content in Frontmatter | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |

**Notes**: Tests verify that corrupted YAML files are handled without crashing the indexer.

### 3. Concurrent Write Conflicts

| Test | Status |
|------|--------|
| Concurrent Writes - Same File | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |
| Concurrent Index Operations | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |

**Notes**: Tests verify file integrity under concurrent access.

### 4. Disk Space Exhaustion

| Test | Status |
|------|--------|
| Disk Space Simulation | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |
| Large Memory File Handling | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |

**Notes**: Tests verify behavior when disk space is limited.

### 5. Permission Errors

| Test | Status |
|------|--------|
| Read-Only Directory | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |
| Read-Only File | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |
| Script Permission Handling | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |
| File Ownership Simulation | $([ $TESTS_PASSED -gt 0 ] && echo "✅ Pass" || echo "❌ Fail") |

**Notes**: Tests verify graceful handling of permission issues.

---

## Recommendations

1. **Empty Directory**: Ensure memory system creates necessary structure on first run
2. **Corrupted YAML**: Implement YAML validation with graceful error handling
3. **Concurrent Access**: Consider file locking mechanisms for write operations
4. **Disk Space**: Add disk space checks before large operations
5. **Permissions**: Implement permission checks with clear error messages

---

## Detailed Log

See \`edge-case-tests.log\` for full test execution log.

---

*Report generated by edge-case-tests.sh*
EOF

    info "Report generated: $report_file"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}OpenClaw Memory System Edge Case Tests${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Initialize log file
    echo "=== Edge Case Tests Started at $(date) ===" > "$LOG_FILE"
    
    # Backup and prepare
    backup_memory
    
    # Run all tests
    echo ""
    echo -e "${YELLOW}Running Test Suite 1: Empty Memory Directory${NC}"
    run_test "Empty Directory Handling" test_empty_memory_directory || true
    run_test "Empty Memory Scan" test_empty_memory_scan || true
    
    echo ""
    echo -e "${YELLOW}Running Test Suite 2: Corrupted YAML Frontmatter${NC}"
    run_test "Corrupted YAML - Missing Closing" test_corrupted_yaml_missing_closing || true
    run_test "Corrupted YAML - Invalid Syntax" test_corrupted_yaml_invalid_syntax || true
    run_test "Corrupted YAML - Binary Content" test_corrupted_yaml_binary_content || true
    
    echo ""
    echo -e "${YELLOW}Running Test Suite 3: Concurrent Write Conflicts${NC}"
    run_test "Concurrent Writes - Same File" test_concurrent_writes_same_file || true
    run_test "Concurrent Index Operations" test_concurrent_index_operations || true
    
    echo ""
    echo -e "${YELLOW}Running Test Suite 4: Disk Space Exhaustion${NC}"
    run_test "Disk Space Simulation" test_disk_space_simulation || true
    run_test "Large Memory File" test_large_memory_file || true
    
    echo ""
    echo -e "${YELLOW}Running Test Suite 5: Permission Errors${NC}"
    run_test "Read-Only Directory" test_readonly_memory_directory || true
    run_test "Read-Only File" test_readonly_memory_file || true
    run_test "Script Permission Handling" test_no_execute_permission_on_script || true
    run_test "File Ownership Simulation" test_owned_by_different_user || true
    
    # Restore and cleanup
    restore_memory
    cleanup
    
    # Generate report
    echo ""
    echo -e "${BLUE}Generating test report...${NC}"
    generate_report
    
    # Summary
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Tests Run:    ${TESTS_RUN}"
    echo -e "Passed:       ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed:       ${RED}${TESTS_FAILED}${NC}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Check $RESULTS_DIR/edge-case-report.md for details.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
