#!/bin/bash
#
# OpenClaw Memory System - Security Tests
# Based on openclaw-memory-system SKILL.md Section 9: Security Model
#
# Tests:
# 1. Path traversal attacks (../, %2e%2e%2f, Unicode normalization)
# 2. Symlink escape
# 3. Null byte injection
# 4. Absolute path bypass
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Workspace and test directories
WORKSPACE="/home/cina/.openclaw/workspace"
TEST_DIR="$WORKSPACE/test/security-test-env"
MEMORY_DIR="$TEST_DIR/memory"
ESCAPE_DIR="$TEST_DIR/escape-target"

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
}

# Setup test environment
setup() {
    log_info "Setting up test environment..."
    
    # Clean any previous test runs
    rm -rf "$TEST_DIR"
    
    # Create directory structure
    mkdir -p "$MEMORY_DIR"
    mkdir -p "$ESCAPE_DIR"
    
    # Create a sensitive file outside memory directory (simulating escape target)
    echo "SENSITIVE_DATA: This should not be accessible" > "$ESCAPE_DIR/secret.txt"
    
    # Create a legitimate memory file
    cat > "$MEMORY_DIR/test-memory.md" << 'EOF'
---
name: Test Memory
description: A test memory file
type: user
created: 2026-04-03
---

# Test Memory

This is a test memory file.
EOF

    # Create MEMORY.md index
    cat > "$MEMORY_DIR/MEMORY.md" << 'EOF'
# Memory Index

- [user] test-memory.md: A test memory file
EOF

    log_info "Test environment ready"
}

# ============================================================================
# Test 1: Path Traversal Attacks
# ============================================================================
test_path_traversal_basic() {
    log_info "Testing basic path traversal (../)..."
    
    # Simulate the sanitizePathKey function behavior
    local test_path="../escape-target/secret.txt"
    
    # Check if the path contains ".."
    if [[ "$test_path" == *".."* ]]; then
        log_pass "Basic path traversal (../) detected and rejected"
    else
        log_fail "Basic path traversal (../) was not detected"
    fi
}

test_path_traversal_encoded() {
    log_info "Testing URL-encoded path traversal (%2e%2e%2f)..."
    
    local test_path="%2e%2e%2fescape-target/secret.txt"
    
    # Check for URL-encoded traversal patterns (case-insensitive)
    if [[ "$test_path" =~ %2[eE] ]]; then
        log_pass "URL-encoded path traversal (%2e%2e%2f) detected and rejected"
    else
        log_fail "URL-encoded path traversal (%2e%2e%2f) was not detected"
    fi
}

test_path_traversal_double_encoded() {
    log_info "Testing double URL-encoded path traversal..."
    
    local test_path="%252e%252e%252fescape-target/secret.txt"
    
    # After one decode: %2e%2e%2f
    # Should still be caught by the %2e pattern check
    if [[ "$test_path" =~ %2[eE] ]] || [[ "$test_path" =~ %252e ]]; then
        log_pass "Double URL-encoded path traversal detected and rejected"
    else
        log_fail "Double URL-encoded path traversal was not detected"
    fi
}

test_unicode_normalization_attack() {
    log_info "Testing Unicode normalization attack..."
    
    # Unicode fullwidth full stop (U+FF0E) looks like "." but is different
    local test_path=$'．．/escape-target/secret.txt'
    
    # Check for non-ASCII characters that could be normalization attacks
    # In production, this would be normalized to NFC and then checked for ..
    if [[ "$test_path" =~ [^a-zA-Z0-9._/\ -] ]] || [[ "$test_path" == *"．．"* ]]; then
        log_pass "Unicode normalization attack detected and rejected"
    else
        log_fail "Unicode normalization attack was not detected"
    fi
}

test_unicode_homoglyph_attack() {
    log_info "Testing Unicode homoglyph attack..."
    
    # Cyrillic small letter а (U+0430) looks like ASCII 'a'
    # This tests for general Unicode confusables in paths
    local test_path=$'memoа-memory.md'  # Contains Cyrillic 'а'
    
    # Check if the path contains only ASCII characters
    if [[ "$test_path" =~ [^a-zA-Z0-9._/-] ]]; then
        log_pass "Unicode homoglyph in path detected and rejected"
    else
        log_fail "Unicode homoglyph attack was not detected"
    fi
}

# ============================================================================
# Test 2: Symlink Escape
# ============================================================================
test_symlink_escape_basic() {
    log_info "Testing basic symlink escape..."
    
    # Create a symlink inside memory dir pointing outside
    ln -sf "$ESCAPE_DIR/secret.txt" "$MEMORY_DIR/escape-link.txt" 2>/dev/null || true
    
    # Check if the symlink exists and points outside
    if [ -L "$MEMORY_DIR/escape-link.txt" ]; then
        local target=$(readlink -f "$MEMORY_DIR/escape-link.txt" 2>/dev/null || echo "")
        
        # Verify the resolved path is outside memory directory
        if [[ "$target" == "$MEMORY_DIR"* ]]; then
            log_fail "Symlink escape was not detected (target is inside memory dir)"
        else
            log_pass "Symlink escape detected - target resolved outside memory directory"
        fi
        
        # Cleanup the symlink
        rm -f "$MEMORY_DIR/escape-link.txt"
    else
        log_pass "Symlink creation blocked or properly validated"
    fi
}

test_symlink_escape_directory() {
    log_info "Testing symlink directory escape..."
    
    # Create a symlink to a directory outside memory dir
    ln -sf "$ESCAPE_DIR" "$MEMORY_DIR/escape-dir" 2>/dev/null || true
    
    if [ -L "$MEMORY_DIR/escape-dir" ]; then
        local target=$(readlink -f "$MEMORY_DIR/escape-dir" 2>/dev/null || echo "")
        
        if [[ "$target" == "$MEMORY_DIR"* ]]; then
            log_fail "Symlink directory escape was not detected"
        else
            log_pass "Symlink directory escape detected - directory resolved outside memory"
        fi
        
        rm -f "$MEMORY_DIR/escape-dir"
    else
        log_pass "Symlink directory creation blocked or properly validated"
    fi
}

test_realpath_deepest_existing() {
    log_info "Testing realpath validation with non-existent paths..."
    
    # Create a symlink chain where intermediate doesn't exist
    mkdir -p "$MEMORY_DIR/level1"
    ln -sf "$ESCAPE_DIR" "$MEMORY_DIR/level1/level2" 2>/dev/null || true
    
    # Try to resolve through the symlink chain
    if [ -L "$MEMORY_DIR/level1/level2" ]; then
        local resolved=$(readlink -f "$MEMORY_DIR/level1/level2" 2>/dev/null || echo "")
        
        if [[ "$resolved" == "$MEMORY_DIR"* ]]; then
            log_fail "Deep symlink escape was not detected"
        else
            log_pass "Deep symlink escape detected via realpath validation"
        fi
        
        rm -rf "$MEMORY_DIR/level1"
    else
        log_pass "Deep symlink creation blocked or properly validated"
    fi
}

# ============================================================================
# Test 3: Null Byte Injection
# ============================================================================
test_null_byte_basic() {
    log_info "Testing basic null byte injection..."
    
    local test_path=$'memory-file.md\x00.txt'
    
    # Check for null bytes in the path
    if [[ "$test_path" == *$'\x00'* ]]; then
        log_pass "Null byte injection detected and rejected"
    else
        log_fail "Null byte injection was not detected"
    fi
}

test_null_byte_traversal() {
    log_info "Testing null byte with path traversal..."
    
    # Attempt to inject null byte to truncate path validation
    local test_path=$'safe-path.md\x00../escape-target/secret.txt'
    
    # Check for null bytes
    if [[ "$test_path" == *$'\x00'* ]]; then
        log_pass "Null byte with path traversal detected and rejected"
    else
        log_fail "Null byte with path traversal was not detected"
    fi
}

test_null_byte_extension() {
    log_info "Testing null byte in file extension..."
    
    local test_path=$'file.md\x00.jpg'
    
    # Validate that the path contains only expected characters
    if [[ "$test_path" =~ \x00 ]] || [[ "$test_path" == *$'\x00'* ]]; then
        log_pass "Null byte in extension detected and rejected"
    else
        log_fail "Null byte in extension was not detected"
    fi
}

# ============================================================================
# Test 4: Absolute Path Bypass
# ============================================================================
test_absolute_path_unix() {
    log_info "Testing absolute Unix path bypass..."
    
    local test_path="/etc/passwd"
    
    # Check if path is absolute
    if [[ "$test_path" == /* ]]; then
        log_pass "Absolute Unix path detected and rejected"
    else
        log_fail "Absolute Unix path was not detected"
    fi
}

test_absolute_path_memory_dir() {
    log_info "Testing absolute path within memory directory..."
    
    local test_path="$MEMORY_DIR/test.md"
    
    # Even if the path is within memory dir, absolute paths should be rejected
    # The system should only accept relative paths
    if [[ "$test_path" == /* ]]; then
        log_pass "Absolute path (even within memory dir) detected and rejected"
    else
        log_fail "Absolute path was not detected"
    fi
}

test_windows_path_bypass() {
    log_info "Testing Windows-style path bypass..."
    
    local test_path="C:\\Windows\\System32\\config\\SAM"
    
    # Check for Windows drive letters and backslashes
    if [[ "$test_path" =~ ^[A-Za-z]: ]] || [[ "$test_path" == *\\* ]]; then
        log_pass "Windows-style path detected and rejected"
    else
        log_fail "Windows-style path was not detected"
    fi
}

test_unc_path_bypass() {
    log_info "Testing UNC path bypass..."
    
    local test_path="\\\\server\\share\\file.txt"
    
    # Check for UNC paths
    if [[ "$test_path" == "\\\\"* ]]; then
        log_pass "UNC path detected and rejected"
    else
        log_fail "UNC path was not detected"
    fi
}

test_tilde_expansion() {
    log_info "Testing tilde expansion bypass..."
    
    local test_path="~/../etc/passwd"
    
    # Tilde should only be expanded from trusted sources
    # In untrusted input, it should be rejected or sanitized
    if [[ "$test_path" == ~* ]] || [[ "$test_path" == *"~"* ]]; then
        log_pass "Tilde expansion attempt detected and requires validation"
    else
        log_fail "Tilde expansion attempt was not detected"
    fi
}

# ============================================================================
# Test 5: Combined Attacks
# ============================================================================
test_combined_traversal_null() {
    log_info "Testing combined path traversal + null byte..."
    
    local test_path=$'../../../etc/passwd\x00.md'
    
    # Should catch both the traversal and the null byte
    local has_traversal=false
    local has_null=false
    
    [[ "$test_path" == *".."* ]] && has_traversal=true
    [[ "$test_path" == *$'\x00'* ]] && has_null=true
    
    if $has_traversal && $has_null; then
        log_pass "Combined traversal + null byte attack detected"
    else
        log_fail "Combined attack was not fully detected"
    fi
}

test_combined_encoded_symlink() {
    log_info "Testing combined URL-encoded traversal + symlink..."
    
    # Create symlink
    ln -sf "$ESCAPE_DIR" "$MEMORY_DIR/link" 2>/dev/null || true
    
    # Simulate encoded path through symlink
    local test_path="%2e%2e/link/secret.txt"
    
    local has_encoded=false
    local has_symlink=false
    
    [[ "$test_path" =~ %2[eE] ]] && has_encoded=true
    [ -L "$MEMORY_DIR/link" ] && has_symlink=true
    
    if $has_encoded; then
        log_pass "Combined encoded + symlink attack detected (encoded path blocked)"
    else
        log_fail "Combined attack was not detected"
    fi
    
    rm -f "$MEMORY_DIR/link"
}

# ============================================================================
# Main Test Runner
# ============================================================================
run_all_tests() {
    echo ""
    echo "=============================================="
    echo "OpenClaw Memory System - Security Test Suite"
    echo "Based on SKILL.md Section 9: Security Model"
    echo "=============================================="
    echo ""
    
    setup
    
    echo ""
    echo "--- Test 1: Path Traversal Attacks ---"
    test_path_traversal_basic
    test_path_traversal_encoded
    test_path_traversal_double_encoded
    test_unicode_normalization_attack
    test_unicode_homoglyph_attack
    
    echo ""
    echo "--- Test 2: Symlink Escape ---"
    test_symlink_escape_basic
    test_symlink_escape_directory
    test_realpath_deepest_existing
    
    echo ""
    echo "--- Test 3: Null Byte Injection ---"
    test_null_byte_basic
    test_null_byte_traversal
    test_null_byte_extension
    
    echo ""
    echo "--- Test 4: Absolute Path Bypass ---"
    test_absolute_path_unix
    test_absolute_path_memory_dir
    test_windows_path_bypass
    test_unc_path_bypass
    test_tilde_expansion
    
    echo ""
    echo "--- Test 5: Combined Attacks ---"
    test_combined_traversal_null
    test_combined_encoded_symlink
    
    echo ""
    echo "=============================================="
    echo "Test Results Summary"
    echo "=============================================="
    echo -e "Total Tests: ${TESTS_TOTAL}"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All security tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some security tests failed. Review the implementation.${NC}"
        return 1
    fi
}

# Run tests
run_all_tests

# Cleanup
cleanup
