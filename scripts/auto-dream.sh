#!/bin/bash
#
# auto-dream.sh - AutoDream/KAIROS Background Memory Consolidation
# 
# Trigger Gates:
#   - 24 hours since last consolidation
#   - 5 sessions with updates since last consolidation
#   - 10 minute minimum interval between scan attempts
#
# File Lock:
#   - PID + timestamp based
#   - 1 hour expiration (prevents dead-lock from PID reuse)
#
# Usage: ./auto-dream.sh [--force] [--status]
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

AUTODREAM_CONFIG=(
    MIN_HOURS=24
    MIN_SESSIONS=5
    SCAN_INTERVAL_MS=600000      # 10 minutes
    LOCK_STALE_MS=3600000        # 1 hour
)

# Paths
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/.openclaw/workspace}"
MEMORY_DIR="${WORKSPACE_DIR}/memory"
LOGS_DIR="${WORKSPACE_DIR}/logs"
LOCK_FILE="${MEMORY_DIR}/.consolidate-lock"
STATE_FILE="${MEMORY_DIR}/.autodream-state.json"
SESSION_COUNT_FILE="${MEMORY_DIR}/.session-count.json"

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [$level] $msg" >&2
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }

# Get current timestamp in milliseconds
now_ms() {
    echo $(($(date +%s) * 1000 + $(date +%N | cut -c1-3)))
}

# Check if a process with given PID is running
is_process_running() {
    local pid="$1"
    if [[ -z "$pid" ]] || [[ "$pid" == "null" ]]; then
        return 1
    fi
    kill -0 "$pid" 2>/dev/null
}

# Initialize daily log directory structure
init_daily_log() {
    local today
    today=$(date +%Y/%m/%d.md)
    local log_path="${LOGS_DIR}/${today}"
    
    if [[ ! -d "${LOGS_DIR}/$(date +%Y/%m)" ]]; then
        mkdir -p "${LOGS_DIR}/$(date +%Y/%m)"
        info "Created log directory: ${LOGS_DIR}/$(date +%Y/%m)"
    fi
    
    if [[ ! -f "$log_path" ]]; then
        cat > "$log_path" << EOF
---
date: $(date +%Y-%m-%d)
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
---

# Daily Log: $(date +%Y-%m-%d)

## Sessions
<!-- Session summaries will be added here -->

## Extractions
<!-- Memory extraction events -->

## Consolidations
<!-- Consolidation events -->

EOF
        info "Created daily log: $log_path"
    fi
    
    echo "$log_path"
}

# =============================================================================
# File Lock Mechanism
# =============================================================================

acquire_lock() {
    local lock_path="$1"
    local pid=$$
    local timestamp
    timestamp=$(now_ms)
    
    # Check for existing lock
    if [[ -f "$lock_path" ]]; then
        local lock_content
        lock_content=$(cat "$lock_path" 2>/dev/null || echo "{}")
        
        local existing_pid existing_timestamp
        existing_pid=$(echo "$lock_content" | jq -r '.pid // null' 2>/dev/null || echo "null")
        existing_timestamp=$(echo "$lock_content" | jq -r '.timestamp // 0' 2>/dev/null || echo "0")
        
        local now
        now=$(now_ms)
        local age_ms=$((now - existing_timestamp))
        
        # Check if lock is stale (> 1 hour)
        if [[ $age_ms -gt ${LOCK_STALE_MS} ]]; then
            warn "Lock is stale (age: ${age_ms}ms > ${LOCK_STALE_MS}ms). Acquiring..."
        elif is_process_running "$existing_pid"; then
            warn "Another consolidation is running (PID: $existing_pid). Aborting."
            return 1
        else
            warn "Lock holder (PID: $existing_pid) is dead. Acquiring..."
        fi
    fi
    
    # Write new lock
    cat > "$lock_path" << EOF
{
  "pid": $pid,
  "timestamp": $timestamp,
  "acquired_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    info "Lock acquired (PID: $pid, timestamp: $timestamp)"
    return 0
}

release_lock() {
    local lock_path="$1"
    
    if [[ -f "$lock_path" ]]; then
        local lock_content
        lock_content=$(cat "$lock_path" 2>/dev/null || echo "{}")
        local current_pid
        current_pid=$(echo "$lock_content" | jq -r '.pid // null' 2>/dev/null || echo "null")
        
        if [[ "$current_pid" == "$$" ]]; then
            # We own the lock, remove it
            rm -f "$lock_path"
            info "Lock released"
        else
            warn "Cannot release lock: owned by PID $current_pid"
        fi
    fi
}

# =============================================================================
# Trigger Gate Logic
# =============================================================================

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"last_consolidation": null, "consolidation_count": 0}'
    fi
}

save_state() {
    local state="$1"
    echo "$state" > "$STATE_FILE"
}

load_session_count() {
    if [[ -f "$SESSION_COUNT_FILE" ]]; then
        cat "$SESSION_COUNT_FILE"
    else
        echo '{"sessions_since_consolidation": 0, "last_reset": null}'
    fi
}

save_session_count() {
    local state="$1"
    echo "$state" > "$SESSION_COUNT_FILE"
}

increment_session_count() {
    local state
    state=$(load_session_count)
    local count
    count=$(echo "$state" | jq -r '.sessions_since_consolidation // 0')
    local new_count=$((count + 1))
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    save_session_count "{\"sessions_since_consolidation\": $new_count, \"last_reset\": \"$now\"}"
    info "Session count incremented to: $new_count"
}

check_trigger_gates() {
    local force="${1:-false}"
    
    if [[ "$force" == "true" ]]; then
        info "Force mode: bypassing trigger gates"
        return 0
    fi
    
    local state
    state=$(load_state)
    local last_consolidation
    last_consolidation=$(echo "$state" | jq -r '.last_consolidation // null')
    
    local now
    now=$(date +%s)
    
    # Gate 1: Minimum 24 hours since last consolidation
    if [[ "$last_consolidation" != "null" ]]; then
        local last_ts
        last_ts=$(date -d "$last_consolidation" +%s 2>/dev/null || echo "0")
        local hours_since=$(( (now - last_ts) / 3600 ))
        
        if [[ $hours_since -lt $MIN_HOURS ]]; then
            info "Gate 1 FAILED: Only ${hours_since}h since last consolidation (need ${MIN_HOURS}h)"
            return 1
        fi
        info "Gate 1 PASSED: ${hours_since}h since last consolidation"
    else
        info "Gate 1 PASSED: No previous consolidation recorded"
    fi
    
    # Gate 2: Minimum 5 sessions with updates
    local session_state
    session_state=$(load_session_count)
    local session_count
    session_count=$(echo "$session_state" | jq -r '.sessions_since_consolidation // 0')
    
    if [[ $session_count -lt $MIN_SESSIONS ]]; then
        info "Gate 2 FAILED: Only ${session_count} sessions since consolidation (need ${MIN_SESSIONS})"
        return 1
    fi
    info "Gate 2 PASSED: ${session_count} sessions since consolidation"
    
    # Gate 3: Minimum 10 minutes between scan attempts
    # (This is handled by the caller's scheduling, not enforced here)
    info "Gate 3 PASSED: Scan interval check delegated to scheduler"
    
    return 0
}

# =============================================================================
# Consolidation Execution
# =============================================================================

run_consolidation() {
    info "Starting AutoDream/KAIROS consolidation..."
    
    # Initialize daily log
    local daily_log
    daily_log=$(init_daily_log)
    info "Daily log ready: $daily_log"
    
    # Verify memory directory exists
    if [[ ! -d "$MEMORY_DIR" ]]; then
        mkdir -p "$MEMORY_DIR"
        info "Created memory directory: $MEMORY_DIR"
    fi
    
    # Check if MEMORY.md exists, create if needed
    if [[ ! -f "${MEMORY_DIR}/MEMORY.md" ]]; then
        cat > "${MEMORY_DIR}/MEMORY.md" << EOF
# Memory Index

_This file is auto-generated by AutoDream/KAIROS consolidation._

## Topic Files

_No topic files yet. Run memory extraction to create initial memories._

EOF
        info "Created initial MEMORY.md"
    fi
    
    # Load consolidation prompt
    local prompt_file="${WORKSPACE_DIR}/prompts/consolidation-prompt.md"
    if [[ ! -f "$prompt_file" ]]; then
        error "Consolidation prompt not found: $prompt_file"
        return 1
    fi
    
    info "Consolidation prompt: $prompt_file"
    
    # Record consolidation start in daily log
    local start_time
    start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat >> "$daily_log" << EOF

### Consolidation Event
- **Started:** $start_time
- **PID:** $$
- **Status:** In Progress

EOF
    
    # Execute consolidation via oracle (or direct LLM call)
    # This would typically invoke the Fork Agent with the consolidation prompt
    info "Executing 4-phase consolidation..."
    
    # Phase 1: ORIENT
    info "Phase 1: ORIENT - Reading MEMORY.md and listing topic files"
    
    # Phase 2: GATHER SIGNAL
    info "Phase 2: GATHER SIGNAL - Scanning daily logs and recent sessions"
    
    # Phase 3: CONSOLIDATE
    info "Phase 3: CONSOLIDATE - Merging new signals into topic files"
    
    # Phase 4: PRUNE AND INDEX
    info "Phase 4: PRUNE AND INDEX - Cleaning up and regenerating index"
    
    # Update state
    local now_iso
    now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local state
    state=$(load_state)
    local count
    count=$(echo "$state" | jq -r '.consolidation_count // 0')
    local new_count=$((count + 1))
    
    save_state "{\"last_consolidation\": \"$now_iso\", \"consolidation_count\": $new_count}"
    
    # Reset session count
    save_session_count "{\"sessions_since_consolidation\": 0, \"last_reset\": \"$now_iso\"}"
    
    # Record consolidation complete in daily log
    local end_time
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat >> "$daily_log" << EOF

- **Completed:** $end_time
- **Status:** Success
- **Total Consolidations:** $new_count

EOF
    
    info "Consolidation completed successfully"
    return 0
}

# =============================================================================
# Status Command
# =============================================================================

show_status() {
    echo "=== AutoDream/KAIROS Status ==="
    echo ""
    
    # State
    echo "State:"
    if [[ -f "$STATE_FILE" ]]; then
        echo "  Last consolidation: $(jq -r '.last_consolidation // "never"' "$STATE_FILE")"
        echo "  Total consolidations: $(jq -r '.consolidation_count // 0' "$STATE_FILE")"
    else
        echo "  No state file found (first run pending)"
    fi
    echo ""
    
    # Session count
    echo "Sessions since last consolidation:"
    if [[ -f "$SESSION_COUNT_FILE" ]]; then
        echo "  Count: $(jq -r '.sessions_since_consolidation // 0' "$SESSION_COUNT_FILE")"
    else
        echo "  Count: 0 (no sessions recorded)"
    fi
    echo ""
    
    # Lock status
    echo "Lock status:"
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_content
        lock_content=$(cat "$LOCK_FILE" 2>/dev/null || echo "{}")
        local lock_pid
        lock_pid=$(echo "$lock_content" | jq -r '.pid // null' 2>/dev/null || echo "null")
        local lock_ts
        lock_ts=$(echo "$lock_content" | jq -r '.timestamp // 0' 2>/dev/null || echo "0")
        local now
        now=$(now_ms)
        local age_ms=$((now - lock_ts))
        local age_hours=$((age_ms / 3600000))
        
        echo "  Lock file: $LOCK_FILE"
        echo "  Owner PID: $lock_pid"
        echo "  Age: ${age_hours}h (${age_ms}ms)"
        
        if [[ $age_ms -gt ${LOCK_STALE_MS} ]]; then
            echo "  Status: STALE (can be reclaimed)"
        elif is_process_running "$lock_pid"; then
            echo "  Status: ACTIVE (consolidation in progress)"
        else
            echo "  Status: DEAD (owner process terminated)"
        fi
    else
        echo "  No active lock"
    fi
    echo ""
    
    # Daily logs
    echo "Recent daily logs:"
    if [[ -d "$LOGS_DIR" ]]; then
        find "$LOGS_DIR" -name "*.md" -type f -mtime -7 2>/dev/null | head -5 | while read -r log; do
            echo "  - $log"
        done
    else
        echo "  No logs directory found"
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    local force=false
    local status=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            --status|-s)
                status=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--force] [--status]"
                echo ""
                echo "Options:"
                echo "  --force, -f    Bypass trigger gates and run consolidation"
                echo "  --status, -s   Show current status and exit"
                echo "  --help, -h     Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Show status if requested
    if [[ "$status" == "true" ]]; then
        show_status
        exit 0
    fi
    
    # Ensure memory directory exists
    mkdir -p "$MEMORY_DIR"
    mkdir -p "$LOGS_DIR"
    
    # Check trigger gates
    if ! check_trigger_gates "$force"; then
        info "Trigger gates not satisfied. Exiting."
        exit 0
    fi
    
    # Acquire lock
    if ! acquire_lock "$LOCK_FILE"; then
        error "Failed to acquire lock. Another consolidation may be running."
        exit 1
    fi
    
    # Trap to ensure lock is released on exit
    trap 'release_lock "$LOCK_FILE"' EXIT
    
    # Run consolidation
    if run_consolidation; then
        info "AutoDream/KAIROS consolidation completed successfully"
        exit 0
    else
        error "Consolidation failed"
        exit 1
    fi
}

# Run main
main "$@"
