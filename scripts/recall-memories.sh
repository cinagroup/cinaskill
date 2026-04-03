#!/bin/bash
#
# recall-memories.sh - Memory Recall Engine for OpenClaw
# 
# Implements Phase 3 of the OpenClaw Memory System:
# 1) scanMemoryFiles - Scan memory directory for .md files
# 2) formatMemoryManifest - Format memory headers into a manifest string
# 3) selectRelevantMemories - AI-driven selection algorithm
# 4) Tool-aware filtering logic
# 5) Staleness warnings
#
# Usage: ./recall-memories.sh <query> [memory_dir] [recent_tools...]
#

set -euo pipefail

# Configuration constants (from SKILL.md)
MAX_MEMORY_FILES=200
FRONTMATTER_MAX_LINES=30
MAX_RECALLED_FILES=5

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Function: scanMemoryFiles
# Scans a memory directory for .md files and extracts frontmatter metadata
#
# Args:
#   $1 - memory_dir: Path to the memory directory
#
# Output:
#   JSON array of memory headers (filename, filePath, mtimeMs, description, type)
#------------------------------------------------------------------------------
scanMemoryFiles() {
    local memory_dir="$1"
    
    if [[ ! -d "$memory_dir" ]]; then
        echo "[]"
        return 0
    fi
    
    local headers=()
    local count=0
    
    # Find all .md files, excluding MEMORY.md, sorted by mtime (newest first)
    while IFS= read -r -d '' file; do
        if [[ $count -ge $MAX_MEMORY_FILES ]]; then
            break
        fi
        
        local filename=$(basename "$file")
        
        # Skip MEMORY.md
        if [[ "$filename" == "MEMORY.md" ]]; then
            continue
        fi
        
        # Get modification time in milliseconds
        local mtime_sec=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
        local mtime_ms=$((mtime_sec * 1000))
        
        # Extract frontmatter (first 30 lines)
        local frontmatter=$(head -n $FRONTMATTER_MAX_LINES "$file" 2>/dev/null || echo "")
        
        # Parse YAML frontmatter
        local description=""
        local type="project"
        
        # Extract description from frontmatter
        if [[ "$frontmatter" =~ description:[[:space:]]*(.+) ]]; then
            description="${BASH_REMATCH[1]}"
            # Clean up the description
            description=$(echo "$description" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
        
        # Extract type from frontmatter
        if [[ "$frontmatter" =~ type:[[:space:]]*(.+) ]]; then
            type="${BASH_REMATCH[1]}"
            type=$(echo "$type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
        
        # Get relative path from memory_dir
        local rel_path="${file#$memory_dir/}"
        
        # Build JSON object
        headers+=("{\"filename\":\"$rel_path\",\"filePath\":\"$file\",\"mtimeMs\":$mtime_ms,\"description\":\"$description\",\"type\":\"$type\"}")
        
        ((count++))
    done < <(find "$memory_dir" -name "*.md" -type f ! -name "MEMORY.md" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | tr '\n' '\0')
    
    # Output JSON array
    if [[ ${#headers[@]} -eq 0 ]]; then
        echo "[]"
    else
        local IFS=','
        echo "[${headers[*]}]"
    fi
}

#------------------------------------------------------------------------------
# Function: formatMemoryManifest
# Formats memory headers into a human-readable manifest string for LLM consumption
#
# Args:
#   $1 - headers_json: JSON array of memory headers
#
# Output:
#   Formatted manifest string
#------------------------------------------------------------------------------
formatMemoryManifest() {
    local headers_json="$1"
    
    if [[ "$headers_json" == "[]" ]] || [[ -z "$headers_json" ]]; then
        echo "(No memory files found)"
        return 0
    fi
    
    local manifest=""
    
    # Parse JSON and format each entry
    # Using a simple approach with grep/sed for portability
    echo "$headers_json" | grep -oP '\{[^}]+\}' | while read -r entry; do
        local filename=$(echo "$entry" | grep -oP '"filename"\s*:\s*"\K[^"]+')
        local mtime_ms=$(echo "$entry" | grep -oP '"mtimeMs"\s*:\s*\K[0-9]+')
        local description=$(echo "$entry" | grep -oP '"description"\s*:\s*"\K[^"]*')
        local type=$(echo "$entry" | grep -oP '"type"\s*:\s*"\K[^"]+')
        
        # Convert mtime_ms to ISO date
        local mtime_sec=$((mtime_ms / 1000))
        local iso_date=$(date -d "@$mtime_sec" -Iseconds 2>/dev/null || date -r "$mtime_sec" +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || echo "unknown")
        local date_only=$(echo "$iso_date" | cut -d'T' -f1)
        
        echo "- [$type] $filename ($date_only): $description"
    done
}

#------------------------------------------------------------------------------
# Function: memoryFreshnessText
# Generates staleness warning for a memory file based on its age
#
# Args:
#   $1 - mtime_ms: Modification time in milliseconds
#
# Output:
#   Warning string (empty if file is fresh)
#------------------------------------------------------------------------------
memoryFreshnessText() {
    local mtime_ms="$1"
    local mtime_sec=$((mtime_ms / 1000))
    local now_sec=$(date +%s)
    local age_days=$(( (now_sec - mtime_sec) / 86400 ))
    
    if [[ $age_days -le 1 ]]; then
        echo ""
    else
        echo "⚠️ This memory is $age_days days old. Code references (line numbers, function names) may have drifted. Always verify against the current codebase before acting on this information."
    fi
}

#------------------------------------------------------------------------------
# Function: selectRelevantMemories
# AI-driven selection of relevant memories using LLM
#
# Args:
#   $1 - query: User's current query
#   $2 - manifest: Formatted memory manifest
#   $3 - recent_tools: Comma-separated list of recently used tools (optional)
#   $4 - already_surfaced: Comma-separated list of already shown file paths (optional)
#
# Output:
#   JSON array of selected filenames (max 5)
#------------------------------------------------------------------------------
selectRelevantMemories() {
    local query="$1"
    local manifest="$2"
    local recent_tools="${3:-}"
    local already_surfaced="${4:-}"
    
    # Build the system prompt
    local system_prompt="You are a memory recall assistant. Given a user's current query and a list of available memory files, select the most relevant memories that would help answer the query.

Rules:
- Return at most 5 filenames.
- If you are unsure whether a memory is relevant, do NOT include it.
- Do NOT select memories that are API usage references for tools currently being used (the conversation already has that context).
- DO select memories about known issues, gotchas, or corrections for those tools.
- Prefer newer memories over older ones when relevance is similar.

Output format: JSON object with key \"selected_memories\" containing an array of filenames.

Example output: {\"selected_memories\": [\"api-patterns.md\", \"user-preferences.md\"]}"

    # Add tool-aware filtering context
    if [[ -n "$recent_tools" ]]; then
        system_prompt="$system_prompt

Recent tools in use: $recent_tools
- Suppress: API docs/usage guides for these tools (already in context)
- Prioritize: Known issues, gotchas, workarounds for these tools"
    fi

    # Add already surfaced files context
    if [[ -n "$already_surfaced" ]]; then
        system_prompt="$system_prompt

Already shown in this conversation: $already_surfaced
- Avoid re-selecting these files unless highly relevant"
    fi

    # Build the user prompt
    local user_prompt="Current Query: $query

Available Memory Files:
$manifest

Select the most relevant memories for this query."

    # Call LLM for selection (using OpenClaw's model or fallback)
    # This is a placeholder - in production, this would call the actual LLM API
    local response=""
    
    # Check if we have access to an LLM via openclaw or other means
    if command -v openclaw &> /dev/null; then
        # Use OpenClaw's side query mechanism
        response=$(openclaw side-query --system "$system_prompt" --user "$user_prompt" 2>/dev/null || echo '{"selected_memories": []}')
    else
        # Fallback: simple keyword matching (for testing/development)
        response=$(keywordBasedSelection "$query" "$manifest")
    fi
    
    echo "$response"
}

#------------------------------------------------------------------------------
# Function: keywordBasedSelection
# Fallback selection algorithm using keyword matching (when LLM unavailable)
#
# Args:
#   $1 - query: User's query
#   $2 - manifest: Memory manifest
#
# Output:
#   JSON array of selected filenames
#------------------------------------------------------------------------------
keywordBasedSelection() {
    local query="$1"
    local manifest="$2"
    
    # Extract keywords from query (simple approach)
    local keywords=$(echo "$query" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{3,}\b' | sort -u | head -10)
    
    local selected=()
    local scores=()
    
    # Score each memory file
    while IFS= read -r line; do
        if [[ ! "$line" =~ ^-.*\.md ]]; then
            continue
        fi
        
        local filename=$(echo "$line" | grep -oP '\] \K[^ ]+(?= \()')
        local description=$(echo "$line" | grep -oP ': \K.*$')
        local combined="$filename $description"
        local combined_lower=$(echo "$combined" | tr '[:upper:]' '[:lower:]')
        
        local score=0
        for keyword in $keywords; do
            if [[ "$combined_lower" == *"$keyword"* ]]; then
                ((score++))
            fi
        done
        
        if [[ $score -gt 0 ]]; then
            selected+=("$filename")
            scores+=("$score")
        fi
    done <<< "$manifest"
    
    # Sort by score and take top 5
    local result=()
    if [[ ${#selected[@]} -gt 0 ]]; then
        # Simple selection (in production, would sort by score)
        for i in "${!selected[@]}"; do
            if [[ $i -lt $MAX_RECALLED_FILES ]]; then
                result+=("\"${selected[$i]}\"")
            fi
        done
    fi
    
    if [[ ${#result[@]} -eq 0 ]]; then
        echo '{"selected_memories": []}'
    else
        local IFS=','
        echo "{\"selected_memories\": [${result[*]}]}"
    fi
}

#------------------------------------------------------------------------------
# Function: filterByTools
# Applies tool-aware filtering to memory headers
#
# Args:
#   $1 - headers_json: JSON array of memory headers
#   $2 - recent_tools: Comma-separated list of recent tools
#
# Output:
#   Filtered JSON array
#------------------------------------------------------------------------------
filterByTools() {
    local headers_json="$1"
    local recent_tools="$2"
    
    if [[ -z "$recent_tools" ]] || [[ "$headers_json" == "[]" ]]; then
        echo "$headers_json"
        return 0
    fi
    
    # In production, this would filter out API reference files for active tools
    # while prioritizing known issues/gotchas for those tools
    # For now, pass through unchanged
    echo "$headers_json"
}

#------------------------------------------------------------------------------
# Function: findRelevantMemories
# Main entry point - orchestrates the full recall pipeline
#
# Args:
#   $1 - query: User's query
#   $2 - memory_dir: Path to memory directory
#   $3 - recent_tools: Comma-separated recent tools (optional)
#   $4 - already_surfaced: Comma-separated surfaced files (optional)
#
# Output:
#   JSON array of relevant memory objects with path and staleness warnings
#------------------------------------------------------------------------------
findRelevantMemories() {
    local query="$1"
    local memory_dir="$2"
    local recent_tools="${3:-}"
    local already_surfaced="${4:-}"
    
    # Step 1: Scan memory files
    local headers_json=$(scanMemoryFiles "$memory_dir")
    
    if [[ "$headers_json" == "[]" ]]; then
        echo '{"memories": [], "message": "No memory files found"}'
        return 0
    fi
    
    # Step 2: Apply tool-aware filtering
    local filtered_json=$(filterByTools "$headers_json" "$recent_tools")
    
    # Step 3: Format manifest for LLM
    local manifest=$(formatMemoryManifest "$filtered_json")
    
    # Step 4: AI-driven selection
    local selection=$(selectRelevantMemories "$query" "$manifest" "$recent_tools" "$already_surfaced")
    
    # Step 5: Map selected filenames back to full paths with staleness info
    local selected_files=$(echo "$selection" | grep -oP '"selected_memories"\s*:\s*\[\K[^\]]*')
    
    if [[ -z "$selected_files" ]] || [[ "$selected_files" == "" ]]; then
        echo '{"memories": [], "message": "No relevant memories found"}'
        return 0
    fi
    
    # Build result array
    local memories=()
    echo "$selected_files" | tr ',' '\n' | sed 's/[" ]//g' | while read -r filename; do
        if [[ -z "$filename" ]]; then
            continue
        fi
        
        # Find the full path from headers
        local file_path=$(echo "$filtered_json" | grep -oP "\"filename\"\s*:\s*\"$filename\".*?" | grep -oP "\"filePath\"\s*:\s*\"\K[^\"]+")
        local mtime_ms=$(echo "$filtered_json" | grep -oP "\"filename\"\s*:\s*\"$filename\".*?" | grep -oP "\"mtimeMs\"\s*:\s*\K[0-9]+")
        
        if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
            local staleness=$(memoryFreshnessText "$mtime_ms")
            local content=$(cat "$file_path" 2>/dev/null | head -100)
            
            echo "FILE: $filename"
            echo "PATH: $file_path"
            echo "MTIME: $mtime_ms"
            if [[ -n "$staleness" ]]; then
                echo "WARNING: $staleness"
            fi
            echo "---"
            echo "$content"
            echo "==="
        fi
    done
}

#------------------------------------------------------------------------------
# Main execution
#------------------------------------------------------------------------------
main() {
    local query="${1:-}"
    local memory_dir="${2:-$HOME/.openclaw/memory}"
    shift 2 2>/dev/null || true
    local recent_tools="$*"
    
    if [[ -z "$query" ]]; then
        echo "Usage: $0 <query> [memory_dir] [recent_tools...]"
        echo ""
        echo "Arguments:"
        echo "  query        - The user's query or current context"
        echo "  memory_dir   - Path to memory directory (default: ~/.openclaw/memory)"
        echo "  recent_tools - Recently used tools (optional, for filtering)"
        echo ""
        echo "Example:"
        echo "  $0 \"How do I handle API errors?\" ~/.openclaw/memory mcp__github__create_pr"
        exit 1
    fi
    
    # Run the recall pipeline
    findRelevantMemories "$query" "$memory_dir" "$recent_tools"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
