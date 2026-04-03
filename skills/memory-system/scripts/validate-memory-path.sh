#!/bin/bash
# OpenClaw Memory Path Validator
# Based on Claude Code memdir security model
# Prevents path traversal and symlink escape attacks

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Memory directory whitelist
MEMORY_DIRS=(
    "/root/.openclaw/workspace/memory"
    "/root/.openclaw/memory-tdai"
    "/root/.openclaw/workspace/memory-tdai"
)

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }

# Check for path traversal patterns
check_path_traversal() {
    local path="$1"
    
    # Check for null bytes
    if [[ "$path" == *$'\0'* ]]; then
        error "Path contains null bytes: $path"
    fi
    
    # Check for URL-encoded traversal
    if [[ "$path" =~ %2e%2e%2f|%2e%2e/|\.\.%2f|%2e%2e%5c ]]; then
        error "Path contains URL-encoded traversal: $path"
    fi
    
    # Check for backslashes (Windows-style)
    if [[ "$path" == *\\* ]]; then
        error "Path contains backslashes: $path"
    fi
    
    # Check for absolute path requirement
    if [[ "$path" != /* ]]; then
        error "Path must be absolute: $path"
    fi
    
    # Check for too-short paths
    if [[ ${#path} -lt 5 ]]; then
        error "Path too short: $path"
    fi
    
    # Check for root or drive letters
    if [[ "$path" == "/" ]] || [[ "$path" =~ ^/[a-zA-Z]:$ ]]; then
        error "Path is root or drive letter: $path"
    fi
}

# Resolve symlinks by finding deepest existing ancestor
realpath_deepest_existing() {
    local path="$1"
    local current="$path"
    local tail=""
    
    while [[ ! -e "$current" ]]; do
        # Get parent directory
        local parent=$(dirname "$current")
        local base=$(basename "$current")
        
        if [[ "$parent" == "$current" ]]; then
            # Reached root, path doesn't exist at all
            echo "$path"
            return
        fi
        
        current="$parent"
        if [[ -n "$tail" ]]; then
            tail="$base/$tail"
        else
            tail="$base"
        fi
    done
    
    # Resolve the existing ancestor
    local resolved=$(realpath "$current" 2>/dev/null || echo "$current")
    
    # Reconstruct full path
    if [[ -n "$tail" ]]; then
        echo "$resolved/$tail"
    else
        echo "$resolved"
    fi
}

# Check if path is within allowed memory directories
is_in_memory_dir() {
    local path="$1"
    local resolved_path=$(realpath_deepest_existing "$path")
    
    for mem_dir in "${MEMORY_DIRS[@]}"; do
        if [[ "$resolved_path" == "$mem_dir"/* ]] || [[ "$resolved_path" == "$mem_dir" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Main validation function
validate_memory_path() {
    local path="$1"
    local operation="${2:-write}"
    
    log "Validating path: $path (operation: $operation)"
    
    # Step 1: Pattern checks
    check_path_traversal "$path"
    
    # Step 2: Resolve symlinks
    local resolved_path=$(realpath_deepest_existing "$path")
    log "Resolved path: $resolved_path"
    
    # Step 3: Containment check
    if ! is_in_memory_dir "$resolved_path"; then
        error "Path outside memory directories: $resolved_path"
    fi
    
    # Step 4: For write operations, ensure parent directory exists or can be created
    if [[ "$operation" == "write" ]]; then
        local parent_dir=$(dirname "$resolved_path")
        if [[ ! -d "$parent_dir" ]]; then
            log "Creating parent directory: $parent_dir"
            mkdir -p "$parent_dir" || error "Failed to create parent directory"
        fi
    fi
    
    success "Path validated: $resolved_path"
    echo "$resolved_path"
}

# CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <path> [read|write]"
        echo "  Validates that a path is within allowed memory directories"
        echo "  and is safe from path traversal attacks."
        exit 1
    fi
    
    validate_memory_path "$1" "${2:-write}"
fi
