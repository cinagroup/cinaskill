#!/bin/bash
# OpenClaw Scene Block Frontmatter Standardizer
# Updates scene_blocks to use standardized metadata format

set -e

SCENE_DIR="/root/.openclaw/memory-tdai/scene_blocks"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }

# Standardize frontmatter for a scene file
standardize_scene() {
    local file="$1"
    local filename=$(basename "$file" .md)
    
    # Check if file already has standard frontmatter
    if head -1 "$file" | grep -q "^-----META-START-----$"; then
        log "Already standardized: $filename"
        return 0
    fi
    
    # Get file stats
    local created=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 || date '+%Y-%m-%d')
    local updated=$(date -Iseconds)
    
    # Try to extract summary from first paragraph
    local summary=$(sed -n '2,10p' "$file" | head -1 | cut -c1-100)
    
    # Detect type from filename
    local type="project"
    if [[ "$filename" == *"用户"* ]] || [[ "$filename" == *"偏好"* ]]; then
        type="user"
    elif [[ "$filename" == *"资产"* ]] || [[ "$filename" == *"业务"* ]]; then
        type="reference"
    fi
    
    # Create temp file with new frontmatter
    local temp_file=$(mktemp)
    
    cat > "$temp_file" << EOF
-----META-START-----
created: ${created}T00:00:00+08:00
updated: $updated
summary: $summary
heat: 1
type: $type
-----META-END-----

EOF
    
    # Append original content (skip if it already has meta)
    cat "$file" >> "$temp_file"
    
    # Replace original
    mv "$temp_file" "$file"
    
    success "Standardized: $filename"
}

# Main
main() {
    log "=========================================="
    log "Scene Block Frontmatter Standardizer"
    log "=========================================="
    
    if [[ ! -d "$SCENE_DIR" ]]; then
        warn "Scene directory not found: $SCENE_DIR"
        exit 1
    fi
    
    local count=0
    for file in "$SCENE_DIR"/*.md; do
        if [[ -f "$file" ]]; then
            standardize_scene "$file"
            ((count++))
        fi
    done
    
    log "=========================================="
    log "Processed $count scene files"
    log "=========================================="
}

main "$@"
