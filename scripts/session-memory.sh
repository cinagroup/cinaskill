#!/bin/bash
# Session Memory Management Script
# Implements threshold-based session memory initialization and updates
# Based on OpenClaw Memory System Architecture Phase 5

set -e

# Configuration (from architecture spec)
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/.openclaw/workspace}"
SESSION_MEMORY_DIR="${SESSION_MEMORY_DIR:-$WORKSPACE_DIR/session-memory}"

# Thresholds
MIN_TOKENS_TO_INIT=10000      # Initialize session memory at 10K tokens
MIN_TOKENS_TO_UPDATE=5000     # Update every 5K tokens after init
TOOL_CALLS_BETWEEN_UPDATES=3  # Force update after N tool calls
MAX_SECTION_LENGTH=2000       # Token limit per section

# State tracking file
STATE_FILE="${WORKSPACE_DIR}/memory/.session-memory-state.json"

# Logging
log() {
    echo "[$(date -Iseconds)] [session-memory] $*" >&2
}

# Initialize state file if not exists
init_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << 'EOF'
{
  "initialized": false,
  "lastUpdateTokens": 0,
  "lastUpdateToolCalls": 0,
  "currentSessionId": null,
  "sessionFile": null
}
EOF
        log "Initialized state file: $STATE_FILE"
    fi
}

# Read state from JSON
read_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        jq -r ".$key // null" "$STATE_FILE"
    else
        echo "null"
    fi
}

# Write state to JSON
write_state() {
    local key="$1"
    local value="$2"
    
    if [[ ! -f "$STATE_FILE" ]]; then
        init_state
    fi
    
    local tmp_file=$(mktemp)
    jq ".$key = $value" "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"
    log "Updated state: $key = $value"
}

# Generate session ID
generate_session_id() {
    echo "session-$(date +%Y%m%d-%H%M%S)-$$"
}

# Check if initialization threshold is met
should_init_session_memory() {
    local current_tokens="$1"
    local initialized=$(read_state "initialized")
    
    if [[ "$initialized" == "true" ]]; then
        return 1  # Already initialized
    fi
    
    if [[ "$current_tokens" -ge "$MIN_TOKENS_TO_INIT" ]]; then
        return 0  # Should initialize
    fi
    
    return 1  # Not yet
}

# Check if update threshold is met
should_update_session_memory() {
    local current_tokens="$1"
    local current_tool_calls="$2"
    
    local initialized=$(read_state "initialized")
    if [[ "$initialized" != "true" ]]; then
        return 1  # Not initialized yet
    fi
    
    local last_tokens=$(read_state "lastUpdateTokens")
    local last_tool_calls=$(read_state "lastUpdateToolCalls")
    
    # Check token delta
    local token_delta=$((current_tokens - last_tokens))
    if [[ "$token_delta" -ge "$MIN_TOKENS_TO_UPDATE" ]]; then
        return 0  # Should update based on tokens
    fi
    
    # Check tool call count
    local tool_call_delta=$((current_tool_calls - last_tool_calls))
    if [[ "$tool_call_delta" -ge "$TOOL_CALLS_BETWEEN_UPDATES" ]]; then
        return 0  # Should update based on tool calls
    fi
    
    return 1  # No update needed
}

# Initialize session memory file
init_session_memory() {
    local session_id="$1"
    local session_file="${SESSION_MEMORY_DIR}/${session_id}.md"
    
    # Copy template
    local template="${WORKSPACE_DIR}/memory/session-template.md"
    if [[ -f "$template" ]]; then
        cp "$template" "$session_file"
    else
        # Create minimal template inline
        cat > "$session_file" << 'EOF'
# Session Title
*5-10 word title describing the overall session goal*

# Current State
*Most critical section. Describes what is being done RIGHT NOW and the immediate next step.*

# Task Specification
*The original user request, preserved verbatim or paraphrased.*

# Files and Functions
*Key files touched, with brief notes on what was done.*

# Errors & Corrections
*Mistakes made and how they were resolved. Prevents repeating errors after compaction.*

# Learnings
*New knowledge gained during this session.*
EOF
    fi
    
    # Update state
    write_state "initialized" "true"
    write_state "currentSessionId" "\"$session_id\""
    write_state "sessionFile" "\"$session_file\""
    write_state "lastUpdateTokens" "0"
    write_state "lastUpdateToolCalls" "0"
    
    log "Initialized session memory: $session_file"
    echo "$session_file"
}

# Update session memory via extraction
update_session_memory() {
    local current_tokens="$1"
    local current_tool_calls="$2"
    local session_file=$(read_state "sessionFile")
    
    if [[ -z "$session_file" || "$session_file" == "null" ]]; then
        log "ERROR: No session file found"
        return 1
    fi
    
    if [[ ! -f "$session_file" ]]; then
        log "ERROR: Session file not found: $session_file"
        return 1
    fi
    
    log "Updating session memory (tokens: $current_tokens, tool_calls: $current_tool_calls)"
    
    # Update state
    write_state "lastUpdateTokens" "$current_tokens"
    write_state "lastUpdateToolCalls" "$current_tool_calls"
    
    # Touch the file to update mtime
    touch "$session_file"
    
    log "Session memory updated successfully"
    echo "$session_file"
}

# Get current session file path
get_session_file() {
    local session_file=$(read_state "sessionFile")
    if [[ -n "$session_file" && "$session_file" != "null" && -f "$session_file" ]]; then
        echo "$session_file"
    else
        echo ""
    fi
}

# Cleanup old session files (optional maintenance)
cleanup_old_sessions() {
    local max_age_days="${1:-7}"
    log "Cleaning up session files older than $max_age_days days"
    
    find "$SESSION_MEMORY_DIR" -name "*.md" -type f -mtime "+$max_age_days" -delete 2>/dev/null || true
    
    # Reset state if session file was deleted
    local session_file=$(read_state "sessionFile")
    if [[ -n "$session_file" && "$session_file" != "null" && ! -f "$session_file" ]]; then
        log "Previous session file no longer exists, resetting state"
        write_state "initialized" "false"
        write_state "currentSessionId" "null"
        write_state "sessionFile" "null"
    fi
}

# Main entry point for token threshold check
check_and_trigger() {
    local current_tokens="${1:-0}"
    local current_tool_calls="${2:-0}"
    local action="${3:-auto}"  # auto, init, update, status
    
    init_state
    
    case "$action" in
        init)
            if should_init_session_memory "$current_tokens"; then
                local session_id=$(generate_session_id)
                init_session_memory "$session_id"
                echo "INITIALIZED"
            else
                echo "NOT_READY"
            fi
            ;;
        update)
            if should_update_session_memory "$current_tokens" "$current_tool_calls"; then
                update_session_memory "$current_tokens" "$current_tool_calls"
                echo "UPDATED"
            else
                echo "NO_UPDATE_NEEDED"
            fi
            ;;
        auto)
            # Automatic mode: check both init and update
            if should_init_session_memory "$current_tokens"; then
                local session_id=$(generate_session_id)
                init_session_memory "$session_id"
                echo "INITIALIZED"
            elif should_update_session_memory "$current_tokens" "$current_tool_calls"; then
                update_session_memory "$current_tokens" "$current_tool_calls"
                echo "UPDATED"
            else
                echo "NO_ACTION"
            fi
            ;;
        status)
            echo "Initialized: $(read_state 'initialized')"
            echo "Session ID: $(read_state 'currentSessionId')"
            echo "Session File: $(read_state 'sessionFile')"
            echo "Last Update Tokens: $(read_state 'lastUpdateTokens')"
            echo "Last Update Tool Calls: $(read_state 'lastUpdateToolCalls')"
            ;;
        *)
            echo "Usage: $0 check_and_trigger <tokens> <tool_calls> [auto|init|update|status]"
            exit 1
            ;;
    esac
}

# Command-line interface
case "${1:-}" in
    init-state)
        init_state
        ;;
    generate-id)
        generate_session_id
        ;;
    check)
        shift
        check_and_trigger "$@"
        ;;
    get-file)
        get_session_file
        ;;
    cleanup)
        cleanup_old_sessions "${2:-7}"
        ;;
    help|--help|-h)
        cat << EOF
Session Memory Management Script

Usage: $0 <command> [options]

Commands:
  init-state              Initialize the state file
  generate-id             Generate a new session ID
  check <tokens> <calls> [action]  Check thresholds and trigger actions
                          Actions: auto (default), init, update, status
  get-file                Get current session file path
  cleanup [days]          Clean up old session files (default: 7 days)
  help                    Show this help message

Environment Variables:
  SESSION_MEMORY_DIR      Directory for session memory files
  WORKSPACE_DIR           OpenClaw workspace directory

Thresholds:
  MIN_TOKENS_TO_INIT      $MIN_TOKENS_TO_INIT tokens
  MIN_TOKENS_TO_UPDATE    $MIN_TOKENS_TO_UPDATE tokens
  TOOL_CALLS_BETWEEN_UPDATES  $TOOL_CALLS_BETWEEN_UPDATES calls

Examples:
  $0 check 12000 0 auto        # Initialize if over 10K tokens
  $0 check 18000 5 update      # Update if thresholds met
  $0 status                    # Show current state
  $0 cleanup 14                # Clean sessions older than 14 days
EOF
        ;;
    *)
        echo "Unknown command: ${1:-}"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac
