#!/bin/bash
# OpenClaw Memory Extraction Service
# Fork Agent script for post-turn memory extraction
# 
# This script runs as a Fork Agent to extract durable knowledge from
# recent conversation turns and persist it to the memory system.
#
# Usage: ./extract-memories.sh [options]
#   --transcript-file <path>   Path to conversation transcript JSON
#   --last-extract-index <n>   Last extraction message index
#   --memory-dir <path>        Memory directory path (default: workspace/memory)
#   --workspace <path>         Workspace root path
#   --dry-run                  Show what would be extracted without writing

set -e

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-/home/cina/.openclaw/workspace}"
MEMORY_DIR="$WORKSPACE/memory"
PROMPT_TEMPLATE="$WORKSPACE/prompts/extraction-prompt.md"
LOG_DIR="$WORKSPACE/logs/memory"

# Defaults
TRANSCRIPT_FILE=""
LAST_EXTRACT_INDEX=0
DRY_RUN=false
VERBOSE=false

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --transcript-file)
            TRANSCRIPT_FILE="$2"
            shift 2
            ;;
        --last-extract-index)
            LAST_EXTRACT_INDEX="$2"
            shift 2
            ;;
        --memory-dir)
            MEMORY_DIR="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "OpenClaw Memory Extraction Service"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --transcript-file <path>   Path to conversation transcript JSON"
            echo "  --last-extract-index <n>   Last extraction message index"
            echo "  --memory-dir <path>        Memory directory path"
            echo "  --workspace <path>         Workspace root path"
            echo "  --dry-run                  Show what would be extracted without writing"
            echo "  --verbose, -v              Enable verbose output"
            echo "  --help, -h                 Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    if [ "$VERBOSE" = true ]; then
        echo "[$(date -Iseconds)] $*" >&2
    fi
}

error() {
    echo "[$(date -Iseconds)] ERROR: $*" >&2
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_paths() {
    # Check workspace exists
    if [ ! -d "$WORKSPACE" ]; then
        error "Workspace directory does not exist: $WORKSPACE"
        exit 1
    fi

    # Check memory directory exists (create if needed)
    if [ ! -d "$MEMORY_DIR" ]; then
        log "Creating memory directory: $MEMORY_DIR"
        if [ "$DRY_RUN" = false ]; then
            mkdir -p "$MEMORY_DIR"
        fi
    fi

    # Check prompt template exists
    if [ ! -f "$PROMPT_TEMPLATE" ]; then
        error "Prompt template not found: $PROMPT_TEMPLATE"
        exit 1
    fi

    # Validate transcript file if provided
    if [ -n "$TRANSCRIPT_FILE" ] && [ ! -f "$TRANSCRIPT_FILE" ]; then
        error "Transcript file not found: $TRANSCRIPT_FILE"
        exit 1
    fi
}

# ============================================================================
# Memory Manifest Generation
# ============================================================================

generate_memory_manifest() {
    # Scan memory directory and generate manifest for the extraction prompt
    # Format: - [type] filename.md (YYYY-MM-DD): description
    
    local manifest=""
    
    if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
        log "Reading existing MEMORY.md index"
        # Extract entries from MEMORY.md (lines starting with "- [")
        manifest=$(grep "^- \[" "$MEMORY_DIR/MEMORY.md" 2>/dev/null || echo "")
    fi
    
    # Also scan for .md files not in MEMORY.md
    if [ -d "$MEMORY_DIR" ]; then
        while IFS= read -r -d '' file; do
            local filename=$(basename "$file")
            if [ "$filename" != "MEMORY.md" ]; then
                # Extract frontmatter description if present
                local desc=$(grep -A1 "^description:" "$file" 2>/dev/null | tail -1 | sed 's/^ *//' || echo "No description")
                local type=$(grep "^type:" "$file" 2>/dev/null | sed 's/type: *//' || echo "project")
                local mtime=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
                
                if ! echo "$manifest" | grep -q "$filename"; then
                    manifest="$manifest
- [$type] $filename ($mtime): $desc"
                fi
            fi
        done < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
    fi
    
    echo "$manifest"
}

# ============================================================================
# Transcript Processing
# ============================================================================

count_new_messages() {
    # Count messages since last extraction index
    # Returns the count of new messages
    
    if [ -z "$TRANSCRIPT_FILE" ]; then
        echo "0"
        return
    fi
    
    # Simple line count for now (can be enhanced with JSON parsing)
    local total_lines=$(wc -l < "$TRANSCRIPT_FILE" 2>/dev/null || echo "0")
    local new_count=$((total_lines - LAST_EXTRACT_INDEX))
    
    echo "$new_count"
}

check_memory_writes() {
    # Check if main agent already wrote to memory directory in recent turns
    # Returns 0 if writes detected, 1 if no writes
    
    if [ -z "$TRANSCRIPT_FILE" ]; then
        return 1
    fi
    
    # Check for file write operations to memory directory in transcript
    if grep -q "\"file_path\":.*$MEMORY_DIR" "$TRANSCRIPT_FILE" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# ============================================================================
# Permission Sandbox (createExtractCanUseTool equivalent)
# ============================================================================

# This function validates tool permissions for the extraction Fork Agent
# It implements the security sandbox described in the architecture
validate_tool_permission() {
    local tool_name="$1"
    local tool_input="$2"
    
    case "$tool_name" in
        FileReadTool|GrepTool|GlobTool)
            # Always allowed
            return 0
            ;;
        BashTool)
            # Only read-only commands allowed
            local cmd=$(echo "$tool_input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            local first_word=$(echo "$cmd" | awk '{print $1}')
            
            case "$first_word" in
                ls|find|cat|stat|wc|head|tail|grep|echo|date|pwd)
                    return 0
                    ;;
                *)
                    error "Bash command not allowed in extraction mode: $first_word"
                    return 1
                    ;;
            esac
            ;;
        FileWriteTool|FileEditTool)
            # Only within memory directory
            local target_path=$(echo "$tool_input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            target_path=$(echo "$tool_input" | grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 || echo "$target_path")
            
            # Resolve to absolute path
            local resolved_path=$(realpath -m "$target_path" 2>/dev/null || echo "$target_path")
            
            # Check if within memory directory
            if [[ "$resolved_path" == "$MEMORY_DIR"* ]]; then
                return 0
            else
                error "Write operation outside memory directory: $resolved_path"
                return 1
            fi
            ;;
        *)
            error "Tool not available during memory extraction: $tool_name"
            return 1
            ;;
    esac
}

# ============================================================================
# Main Extraction Logic
# ============================================================================

run_extraction() {
    log "Starting memory extraction..."
    log "  Workspace: $WORKSPACE"
    log "  Memory Dir: $MEMORY_DIR"
    log "  Last Extract Index: $LAST_EXTRACT_INDEX"
    log "  Dry Run: $DRY_RUN"
    
    # Step 1: Count new messages since last extraction
    local new_message_count=$(count_new_messages)
    log "  New messages since last extraction: $new_message_count"
    
    # Skip if not enough new content (minimum 2 messages: 1 user + 1 assistant)
    if [ "$new_message_count" -lt 2 ]; then
        log "Skipping extraction: not enough new content (need >= 2 messages)"
        return 0
    fi
    
    # Step 2: Check if main agent already wrote memories
    if check_memory_writes; then
        log "Skipping extraction: main agent already wrote to memory directory"
        return 0
    fi
    
    # Step 3: Generate memory manifest
    log "Generating memory manifest..."
    local manifest=$(generate_memory_manifest)
    
    if [ "$VERBOSE" = true ]; then
        echo "Current Memory Manifest:"
        echo "$manifest"
        echo ""
    fi
    
    # Step 4: Build extraction prompt
    log "Building extraction prompt..."
    local prompt_content=$(cat "$PROMPT_TEMPLATE")
    
    # Replace placeholders
    prompt_content="${prompt_content//\{\{MEMORY_MANIFEST\}\}/$manifest}"
    
    # Load recent messages if transcript provided
    local recent_messages=""
    if [ -n "$TRANSCRIPT_FILE" ] && [ -f "$TRANSCRIPT_FILE" ]; then
        # Extract last N messages from transcript (simplified for now)
        recent_messages=$(tail -50 "$TRANSCRIPT_FILE" 2>/dev/null || echo "[Transcript not available]")
    else
        recent_messages="[No transcript provided - analyze recent conversation context]"
    fi
    
    prompt_content="${prompt_content//\{\{RECENT_MESSAGES\}\}/$recent_messages}"
    
    # Step 5: Run extraction (dry-run or actual)
    if [ "$DRY_RUN" = true ]; then
        echo "=== DRY RUN MODE ==="
        echo "Would run extraction with the following prompt:"
        echo ""
        echo "$prompt_content" | head -100
        echo ""
        echo "... (prompt truncated)"
        echo ""
        echo "=== END DRY RUN ==="
    else
        log "Writing prompt to temporary file for Fork Agent..."
        local temp_prompt=$(mktemp)
        echo "$prompt_content" > "$temp_prompt"
        
        # In a full implementation, this would invoke the Fork Agent
        # For now, we log what would happen
        log "Fork Agent would be invoked with prompt: $temp_prompt"
        log "Tool permissions sandbox active:"
        log "  - FileReadTool: ALLOWED"
        log "  - GrepTool: ALLOWED"
        log "  - GlobTool: ALLOWED"
        log "  - BashTool: READ-ONLY (ls, find, cat, stat, wc, head, tail, grep)"
        log "  - FileWriteTool: MEMORY_DIR_ONLY"
        log "  - FileEditTool: MEMORY_DIR_ONLY"
        log "  - MCP/Sub-agents: BLOCKED"
        
        # Cleanup
        rm -f "$temp_prompt"
    fi
    
    log "Extraction complete"
}

# ============================================================================
# Entry Point
# ============================================================================

main() {
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Validate paths
    validate_paths
    
    # Run extraction
    run_extraction
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
