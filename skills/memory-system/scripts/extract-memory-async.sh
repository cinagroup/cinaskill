#!/bin/bash
# OpenClaw Async Memory Extractor
# Forked agent pattern inspired by Claude Code memdir
# Runs in background after conversation ends to update memory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/root/.openclaw/workspace"
MEMORY_DIR="$WORKSPACE_DIR/memory"
SCENE_DIR="/root/.openclaw/memory-tdai/scene_blocks"
LOG_FILE="$WORKSPACE_DIR/logs/memory-extract.log"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

# Initialize
init() {
    mkdir -p "$MEMORY_DIR" "$SCENE_DIR" "$(dirname "$LOG_FILE")"
    log "=========================================="
    log "Memory Extract Agent Started"
    log "=========================================="
}

# Analyze conversation and extract memories
extract_memories() {
    local session_key="$1"
    local conversation_file="$2"
    
    log "Analyzing conversation: $conversation_file"
    
    if [[ ! -f "$conversation_file" ]]; then
        warn "Conversation file not found: $conversation_file"
        return 1
    fi
    
    # Extract key information using AI
    # This would normally call an LLM API
    # For now, we'll do pattern-based extraction
    
    local today=$(date '+%Y-%m-%d')
    local daily_file="$MEMORY_DIR/$today.md"
    
    # Append to daily log
    cat >> "$daily_file" << EOF

## Session: $session_key
**Time**: $(date '+%Y-%m-%d %H:%M:%S')

### Summary
[AI-generated summary would go here]

### Key Decisions
- [Decision items extracted from conversation]

### Action Items
- [Tasks identified during conversation]

EOF
    
    success "Daily log updated: $daily_file"
}

# Update scene blocks based on content analysis
update_scene_blocks() {
    local topic="$1"
    local content="$2"
    
    log "Updating scene block: $topic"
    
    # Normalize topic to filename
    local filename=$(echo "$topic" | sed 's/[[:space:]]\+/-/g' | sed 's/[^a-zA-Z0-9-]//g')
    local scene_file="$SCENE_DIR/${filename}.md"
    
    # Check if scene file exists
    if [[ -f "$scene_file" ]]; then
        # Update existing file - append new info
        log "Appending to existing scene: $scene_file"
        # In production, this would use AI to merge intelligently
    else
        # Create new scene file with standardized frontmatter
        cat > "$scene_file" << EOF
-----META-START-----
created: $(date -Iseconds)
updated: $(date -Iseconds)
summary: [Auto-generated summary]
heat: 1
type: project
-----META-END-----

# $topic

[Content extracted from conversation]

EOF
        success "Created new scene: $scene_file"
    fi
}

# Update MEMORY.md index
update_memory_index() {
    log "Updating MEMORY.md index"
    
    local index_file="$WORKSPACE_DIR/MEMORY.md"
    
    if [[ ! -f "$index_file" ]]; then
        warn "MEMORY.md not found, skipping index update"
        return
    fi
    
    # Update the "Last Updated" timestamp
    sed -i "s/\*\*Last Updated\*\*: .*/\*\*Last Updated\*\*: $(date '+%Y-%m-%d')/" "$index_file"
    
    success "Index updated: $index_file"
}

# Cleanup old working files
cleanup_working() {
    local working_dir="$MEMORY_DIR/working"
    local max_age_days=7
    
    log "Cleaning up working files older than $max_age_days days"
    
    if [[ -d "$working_dir" ]]; then
        find "$working_dir" -type f -mtime +$max_age_days -delete 2>/dev/null || true
        success "Working directory cleaned"
    fi
}

# Main execution
main() {
    init
    
    local session_key="${1:-unknown}"
    local conversation_file="${2:-}"
    
    # Step 1: Extract memories from conversation
    if [[ -n "$conversation_file" ]] && [[ -f "$conversation_file" ]]; then
        extract_memories "$session_key" "$conversation_file"
    else
        log "No conversation file provided, skipping extraction"
    fi
    
    # Step 2: Update scene blocks (would be triggered by content analysis)
    # update_scene_blocks "Topic Name" "Extracted content"
    
    # Step 3: Update index
    update_memory_index
    
    # Step 4: Cleanup
    cleanup_working
    
    log "=========================================="
    log "Memory Extract Agent Complete"
    log "=========================================="
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
