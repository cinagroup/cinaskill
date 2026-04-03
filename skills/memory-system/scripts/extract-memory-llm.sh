#!/bin/bash
# OpenClaw LLM-Powered Memory Extractor
# Uses local LLM for intelligent memory extraction
# Inspired by Claude Code's Forked Agent pattern

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/root/.openclaw/workspace"
MEMORY_DIR="$WORKSPACE_DIR/memory"
SCENE_DIR="/root/.openclaw/memory-tdai/scene_blocks"
LOG_FILE="$WORKSPACE_DIR/logs/memory-extract-llm.log"

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

# Extract memories using LLM
extract_with_llm() {
    local conversation_text="$1"
    local output_file="$2"
    
    log "Starting LLM-powered memory extraction..."
    
    # Build extraction prompt
    local prompt=$(cat << 'PROMPT'
You are analyzing a conversation to extract lasting memories for OpenClaw.

## Memory Types
- **user**: User preferences, habits, personality traits
- **feedback**: Rules, corrections, "should/should not" statements
- **project**: Project decisions, architecture, incidents, goals
- **reference**: API docs, tool links, external resources

## Extraction Rules
1. Only extract PERSISTENT information (not temporary task details)
2. Merge with existing knowledge when possible
3. Be specific - include exact values (IDs, paths, timestamps)
4. DO NOT extract: code content, temporary states, sensitive credentials

## Output Format (JSON)
{
  "memories": [
    {
      "file": "scene_blocks/topic-name.md",
      "type": "user|feedback|project|reference",
      "action": "create|update",
      "summary": "One-line summary",
      "content": "Full markdown content"
    }
  ],
  "daily_log": {
    "date": "YYYY-MM-DD",
    "summary": "Session summary",
    "decisions": ["Decision 1", "Decision 2"],
    "action_items": ["Task 1", "Task 2"]
  }
}

## Conversation to Analyze
PROMPT
)
    
    prompt="$prompt"$'\n\n'"$conversation_text"
    
    # Call LLM API (using OpenClaw's default model)
    # This is a placeholder - in production, integrate with actual LLM
    log "Calling LLM API for extraction..."
    
    # Simulated LLM response (replace with actual API call)
    local llm_response='{"memories": [], "daily_log": {"date": "'$(date '+%Y-%m-%d')'", "summary": "Session analyzed", "decisions": [], "action_items": []}}'
    
    echo "$llm_response"
    success "LLM extraction complete"
}

# Update scene block with merge logic
update_scene_with_merge() {
    local scene_file="$1"
    local new_content="$2"
    local memory_type="$3"
    
    log "Updating scene with merge: $scene_file"
    
    if [[ -f "$scene_file" ]]; then
        # Read existing content
        local existing_content=$(cat "$scene_file")
        
        # Check if frontmatter exists
        if grep -q "^-----META-START-----$" "$scene_file"; then
            # Update timestamp and merge content
            local updated_time=$(date -Iseconds)
            
            # Extract existing summary
            local existing_summary=$(sed -n '/^-----META-START-----$/,/^-----META-END-----$/p' "$scene_file" | grep "^summary:" | cut -d':' -f2- | xargs)
            
            # Create merged content (append new info to end)
            cat > "$scene_file" << EOF
$(sed -n '/^-----META-START-----$/,/^-----META-END-----$/p' "$scene_file" | sed "s/^updated:.*/updated: $updated_time/")

$(sed -n '/^-----META-END-----$/,$ p' "$scene_file" | tail -n +2)

---

## Update: $(date '+%Y-%m-%d %H:%M')
$new_content
EOF
            success "Merged update: $scene_file"
        else
            # No frontmatter, create new
            create_scene_file "$scene_file" "$new_content" "$memory_type"
        fi
    else
        # Create new scene file
        create_scene_file "$scene_file" "$new_content" "$memory_type"
    fi
    
    # Increment heat score
    increment_heat "$scene_file"
}

# Create new scene file
create_scene_file() {
    local scene_file="$1"
    local content="$2"
    local memory_type="$3"
    
    local filename=$(basename "$scene_file" .md)
    local now=$(date -Iseconds)
    
    cat > "$scene_file" << EOF
-----META-START-----
created: $now
updated: $now
summary: [Auto-generated] $(echo "$content" | head -1 | cut -c1-80)
heat: 1
type: $memory_type
-----META-END-----

# $filename

$content
EOF
    success "Created scene: $scene_file"
}

# Increment heat score
increment_heat() {
    local scene_file="$1"
    
    if [[ -f "$scene_file" ]]; then
        local current_heat=$(grep "^heat:" "$scene_file" 2>/dev/null | cut -d':' -f2 | xargs || echo "0")
        local new_heat=$((current_heat + 1))
        
        # Update heat in frontmatter
        sed -i "s/^heat:.*/heat: $new_heat/" "$scene_file"
        
        log "Heat incremented: $(basename "$scene_file") ($current_heat → $new_heat)"
    fi
}

# Apply time decay to all scene files
apply_heat_decay() {
    log "Applying heat decay (aging)..."
    
    local today=$(date +%s)
    
    for scene_file in "$SCENE_DIR"/*.md; do
        if [[ -f "$scene_file" ]]; then
            local updated=$(grep "^updated:" "$scene_file" | cut -d':' -f2- | xargs)
            local updated_ts=$(date -d "$updated" +%s 2>/dev/null || echo "$today")
            local age_days=$(( (today - updated_ts) / 86400 ))
            
            if [[ $age_days -gt 7 ]]; then
                # Decay heat by 1 for each week old
                local decay=$((age_days / 7))
                local current_heat=$(grep "^heat:" "$scene_file" | cut -d':' -f2 | xargs || echo "1")
                local new_heat=$((current_heat - decay))
                [[ $new_heat -lt 1 ]] && new_heat=1
                
                sed -i "s/^heat:.*/heat: $new_heat/" "$scene_file"
                log "Heat decayed: $(basename "$scene_file") (age: $age_days days, decay: -$decay)"
            fi
        fi
    done
    
    success "Heat decay applied"
}

# Update daily log
update_daily_log() {
    local date="$1"
    local summary="$2"
    local decisions="$3"
    local action_items="$4"
    
    local daily_file="$MEMORY_DIR/$date.md"
    
    cat >> "$daily_file" << EOF

---

## Session: $(date '+%Y-%m-%d %H:%M:%S')

### Summary
$summary

### Decisions
$(echo "$decisions" | jq -r '.[]' 2>/dev/null | sed 's/^/- /' || echo "- None recorded")

### Action Items
$(echo "$action_items" | jq -r '.[]' 2>/dev/null | sed 's/^/- /' || echo "- None recorded")

EOF
    success "Daily log updated: $daily_file"
}

# Update MEMORY.md index
update_memory_index() {
    local index_file="$WORKSPACE_DIR/MEMORY.md"
    
    if [[ -f "$index_file" ]]; then
        sed -i "s/\*\*Last Updated\*\*: .*/\*\*Last Updated\*\*: $(date '+%Y-%m-%d')/" "$index_file"
        
        # Update scene block table
        log "Updating MEMORY.md scene index..."
        
        # This would parse scene files and update the table
        # For now, just update timestamp
        success "Index updated"
    fi
}

# Main execution
main() {
    mkdir -p "$MEMORY_DIR" "$SCENE_DIR" "$(dirname "$LOG_FILE")"
    
    log "=========================================="
    log "LLM Memory Extract Agent Started"
    log "=========================================="
    
    # Step 1: Apply heat decay (weekly maintenance)
    apply_heat_decay
    
    # Step 2: Extract memories from conversation (if provided)
    local conversation_file="$1"
    if [[ -n "$conversation_file" ]] && [[ -f "$conversation_file" ]]; then
        local conversation_text=$(cat "$conversation_file")
        local extraction_result=$(extract_with_llm "$conversation_text")
        
        # Parse and apply extraction results
        # (In production, this would process the JSON response)
        log "Extraction results processed"
    else
        log "No conversation file provided, skipping extraction"
    fi
    
    # Step 3: Update index
    update_memory_index
    
    log "=========================================="
    log "LLM Memory Extract Agent Complete"
    log "=========================================="
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
