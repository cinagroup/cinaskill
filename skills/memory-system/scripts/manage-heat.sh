#!/bin/bash
# OpenClaw Heat Score Management System
# Manages memory heat scores with increment, decay, and ranking

set -e

SCENE_DIR="/root/.openclaw/memory-tdai/scene_blocks"
LOG_FILE="/root/.openclaw/workspace/logs/heat-management.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }

# Increment heat for a specific file
increment() {
    local file="$1"
    local amount="${2:-1}"
    
    if [[ ! -f "$file" ]]; then
        warn "File not found: $file"
        return 1
    fi
    
    local current=$(grep "^heat:" "$file" 2>/dev/null | cut -d':' -f2 | xargs || echo "0")
    local new_heat=$((current + amount))
    
    sed -i "s/^heat:.*/heat: $new_heat/" "$file"
    
    local filename=$(basename "$file")
    log "Heat incremented: $filename ($current → $new_heat, +$amount)"
    success "$filename: heat = $new_heat"
}

# Apply time-based decay to all files
apply_decay() {
    local decay_threshold_days="${1:-7}"
    local decay_amount="${2:-1}"
    
    log "Applying heat decay (threshold: ${decay_threshold_days}d, decay: -${decay_amount})"
    
    local today=$(date +%s)
    local count=0
    
    for scene_file in "$SCENE_DIR"/*.md; do
        if [[ -f "$scene_file" ]]; then
            local updated=$(grep "^updated:" "$scene_file" | cut -d':' -f2- | xargs)
            local updated_ts=$(date -d "$updated" +%s 2>/dev/null || echo "$today")
            local age_days=$(( (today - updated_ts) / 86400 ))
            
            if [[ $age_days -ge $decay_threshold_days ]]; then
                local current_heat=$(grep "^heat:" "$scene_file" | cut -d':' -f2 | xargs || echo "1")
                local decay_multiplier=$((age_days / decay_threshold_days))
                local total_decay=$((decay_amount * decay_multiplier))
                local new_heat=$((current_heat - total_decay))
                
                # Minimum heat is 1
                [[ $new_heat -lt 1 ]] && new_heat=1
                
                if [[ $new_heat -ne $current_heat ]]; then
                    sed -i "s/^heat:.*/heat: $new_heat/" "$scene_file"
                    log "Decayed: $(basename "$scene_file") (age: ${age_days}d, $current_heat → $new_heat)"
                    ((count++))
                fi
            fi
        fi
    done
    
    success "Decay applied to $count files"
}

# Show heat ranking
rank() {
    local limit="${1:-10}"
    
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}     Memory Heat Score Ranking${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    printf "${YELLOW}%-6s %-8s %-10s %s${NC}\n" "Rank" "Heat" "Type" "File"
    echo -e "${BLUE}────────────────────────────────────────${NC}"
    
    local rank=1
    while IFS= read -r line; do
        local heat=$(echo "$line" | cut -d'|' -f1)
        local file=$(echo "$line" | cut -d'|' -f2)
        local type=$(grep "^type:" "$SCENE_DIR/$file" 2>/dev/null | cut -d':' -f2 | xargs || echo "unknown")
        local filename=$(basename "$file" .md | cut -c1-30)
        
        printf "%-6s %-8s %-10s %s\n" "$rank" "$heat" "$type" "$filename"
        ((rank++))
        
        [[ $rank -gt $limit ]] && break
    done < <(
        for f in "$SCENE_DIR"/*.md; do
            if [[ -f "$f" ]]; then
                local h=$(grep "^heat:" "$f" 2>/dev/null | cut -d':' -f2 | xargs || echo "0")
                echo "$h|$(basename "$f")"
            fi
        done | sort -t'|' -k1 -rn
    )
    
    echo -e "${BLUE}════════════════════════════════════════${NC}"
}

# Reset heat for all files
reset_all() {
    local default_heat="${1:-1}"
    
    warn "This will reset heat scores for all scene files to $default_heat"
    read -p "Continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for scene_file in "$SCENE_DIR"/*.md; do
            if [[ -f "$scene_file" ]]; then
                sed -i "s/^heat:.*/heat: $default_heat/" "$scene_file"
            fi
        done
        success "All heat scores reset to $default_heat"
    else
        log "Cancelled"
    fi
}

# Show heat statistics
stats() {
    local total=0
    local sum=0
    local max=0
    local min=999999
    
    for scene_file in "$SCENE_DIR"/*.md; do
        if [[ -f "$scene_file" ]]; then
            local heat=$(grep "^heat:" "$scene_file" | cut -d':' -f2 | xargs || echo "0")
            ((total++))
            ((sum += heat))
            [[ $heat -gt $max ]] && max=$heat
            [[ $heat -lt $min ]] && min=$heat
        fi
    done
    
    local avg=0
    if [[ $total -gt 0 ]]; then
        avg=$(echo "scale=2; $sum / $total" | bc)
    fi
    
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}        Heat Score Statistics${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    printf "Total Files:     %d\n" "$total"
    printf "Total Heat:      %d\n" "$sum"
    printf "Average Heat:    %.2f\n" "$avg"
    printf "Highest Heat:    %d\n" "$max"
    printf "Lowest Heat:     %d\n" "$min"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
}

# Auto-maintenance: decay + report
auto_maintenance() {
    log "=========================================="
    log "Auto Heat Maintenance Started"
    log "=========================================="
    
    apply_decay 7 1
    echo ""
    rank 5
    
    log "=========================================="
    log "Auto Heat Maintenance Complete"
    log "=========================================="
}

# Show usage
usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  increment <file> [amount]    Increment heat for a file (default: +1)
  decay [days] [amount]        Apply time decay (default: 7 days, -1)
  rank [limit]                 Show heat ranking (default: top 10)
  stats                        Show heat statistics
  reset [default]              Reset all heat scores (default: 1)
  auto                         Auto maintenance (decay + report)

Examples:
  $(basename "$0") increment scene_blocks/my-file.md 2
  $(basename "$0") decay 14 2
  $(basename "$0") rank 5
  $(basename "$0") stats
  $(basename "$0") auto

EOF
}

# Main
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        inc|increment)
            increment "$@"
            ;;
        decay)
            apply_decay "$@"
            ;;
        rank)
            rank "$@"
            ;;
        stats)
            stats
            ;;
        reset)
            reset_all "$@"
            ;;
        auto)
            auto_maintenance
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            warn "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
