#!/bin/bash
# OpenClaw Memory Event Notification System
# Sends notifications for significant memory events

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/root/.openclaw/workspace"
LOG_FILE="$WORKSPACE_DIR/logs/memory-notify.log"
CONFIG_FILE="$WORKSPACE_DIR/.memory-notify-config.json"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Notification types
NOTIFY_CREATE="create"
NOTIFY_UPDATE="update"
NOTIFY_MERGE="merge"
NOTIFY_DECAY="decay"
NOTIFY_WEEKLY="weekly"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# Initialize config
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "enabled": true,
  "channels": ["log", "qqbot"],
  "min_heat_threshold": 5,
  "notify_on": {
    "create": true,
    "update": false,
    "merge": true,
    "decay": false,
    "weekly": true
  },
  "quiet_hours": {
    "start": "23:00",
    "end": "08:00"
  }
}
EOF
        log "Created default config: $CONFIG_FILE"
    fi
}

# Check if notification is enabled
is_enabled() {
    local event_type="$1"
    
    if ! command -v jq &>/dev/null; then
        log "jq not found, notifications disabled"
        return 1
    fi
    
    local enabled=$(jq -r '.enabled' "$CONFIG_FILE" 2>/dev/null || echo "false")
    local notify_event=$(jq -r ".notify_on.$event_type" "$CONFIG_FILE" 2>/dev/null || echo "false")
    
    [[ "$enabled" == "true" ]] && [[ "$notify_event" == "true" ]]
}

# Check if in quiet hours
is_quiet_hours() {
    local start=$(jq -r '.quiet_hours.start' "$CONFIG_FILE" 2>/dev/null || echo "23:00")
    local end=$(jq -r '.quiet_hours.end' "$CONFIG_FILE" 2>/dev/null || echo "08:00")
    
    local now=$(date +%H%M)
    local start_num=${start/:/}
    local end_num=${end/:/}
    
    # Handle overnight quiet hours
    if [[ $start_num -gt $end_num ]]; then
        [[ $now -ge $start_num ]] || [[ $now -lt $end_num ]]
    else
        [[ $now -ge $start_num ]] && [[ $now -lt $end_num ]]
    fi
}

# Send notification via QQBot
send_qqbot() {
    local title="$1"
    local message="$2"
    local level="${3:-info}"
    
    log "Sending QQBot notification: $title"
    
    # Format message
    local formatted_message=$(cat << EOF
${MAGENTA}🧠 记忆系统通知${NC}

${BLUE}${title}${NC}

$message

---
*OpenClaw Memory System*
EOF
)
    
    # Use OpenClaw message tool (via sessions_send or direct)
    # This is a placeholder - integrate with actual message system
    echo "$formatted_message" >> "$WORKSPACE_DIR/logs/notifications-queue.md"
    
    success "QQBot notification queued"
}

# Send log notification
send_log() {
    local title="$1"
    local message="$2"
    local level="${3:-INFO}"
    
    case "$level" in
        info)  log "${BLUE}[INFO]${NC} $title: $message" ;;
        warn)  log "${YELLOW}[WARN]${NC} $title: $message" ;;
        error) log "${RED}[ERROR]${NC} $title: $message" ;;
        success) log "${GREEN}[SUCCESS]${NC} $title: $message" ;;
    esac
}

# Main notification dispatcher
notify() {
    local event_type="$1"
    local title="$2"
    local message="$3"
    local metadata="${4:-{}}"
    
    init_config
    
    # Check if enabled
    if ! is_enabled "$event_type"; then
        log "Notification disabled for event: $event_type"
        return 0
    fi
    
    # Check quiet hours
    if is_quiet_hours; then
        log "In quiet hours, queuing notification: $title"
        # Queue for later delivery
        echo "{\"time\":\"$(date -Iseconds)\",\"type\":\"$event_type\",\"title\":\"$title\",\"message\":\"$message\"}" >> "$WORKSPACE_DIR/logs/notifications-queue.jsonl"
        return 0
    fi
    
    # Send to configured channels
    local channels=$(jq -r '.channels[]' "$CONFIG_FILE" 2>/dev/null || echo "log")
    
    for channel in $channels; do
        case "$channel" in
            log)
                send_log "$title" "$message" "info"
                ;;
            qqbot)
                send_qqbot "$title" "$message" "info"
                ;;
            *)
                log "Unknown channel: $channel"
                ;;
        esac
    done
}

# Notify on memory creation
notify_create() {
    local file="$1"
    local memory_type="$2"
    local summary="$3"
    
    local filename=$(basename "$file")
    local heat=$(grep "^heat:" "$file" 2>/dev/null | cut -d':' -f2 | xargs || echo "1")
    
    local message=$(cat << EOF
**新记忆已创建**

📁 文件：\`$filename\`
🏷️ 类型：$memory_type
🔥 热度：$heat
📝 摘要：$summary
EOF
)
    
    notify "$NOTIFY_CREATE" "🆕 新记忆创建" "$message"
}

# Notify on memory update
notify_update() {
    local file="$1"
    local change_summary="$2"
    
    local filename=$(basename "$file")
    local heat=$(grep "^heat:" "$file" 2>/dev/null | cut -d':' -f2 | xargs || echo "1")
    
    local message=$(cat << EOF
**记忆已更新**

📁 文件：\`$filename\`
🔥 热度：$heat
📝 变更：$change_summary
EOF
)
    
    notify "$NOTIFY_UPDATE" "📝 记忆更新" "$message"
}

# Notify on memory merge
notify_merge() {
    local file="$1"
    local merged_count="$2"
    
    local filename=$(basename "$file")
    
    local message=$(cat << EOF
**记忆已合并**

📁 文件：\`$filename\`
🔀 合并条目：$merged_count
EOF
)
    
    notify "$NOTIFY_MERGE" "🔀 记忆合并" "$message"
}

# Weekly digest
weekly_digest() {
    log "Generating weekly memory digest..."
    
    local today=$(date +%s)
    local week_ago=$((today - 604800))
    
    local created_count=0
    local updated_count=0
    local total_heat=0
    
    for scene_file in /root/.openclaw/memory-tdai/scene_blocks/*.md; do
        if [[ -f "$scene_file" ]]; then
            local created=$(grep "^created:" "$scene_file" | cut -d':' -f2- | xargs)
            local updated=$(grep "^updated:" "$scene_file" | cut -d':' -f2- | xargs)
            local heat=$(grep "^heat:" "$scene_file" | cut -d':' -f2 | xargs || echo "0")
            
            local created_ts=$(date -d "$created" +%s 2>/dev/null || echo "0")
            local updated_ts=$(date -d "$updated" +%s 2>/dev/null || echo "0")
            
            ((total_heat += heat))
            
            if [[ $created_ts -ge $week_ago ]]; then
                ((created_count++))
            elif [[ $updated_ts -ge $week_ago ]]; then
                ((updated_count++))
            fi
        fi
    done
    
    local message=$(cat << EOF
**本周记忆系统摘要**

📊 统计数据：
- 新增记忆：$created_count
- 更新记忆：$updated_count
- 总热度：$total_heat

🔥 热门记忆 TOP 3:
$(for f in /root/.openclaw/memory-tdai/scene_blocks/*.md; do
    if [[ -f "$f" ]]; then
        h=$(grep "^heat:" "$f" 2>/dev/null | cut -d':' -f2 | xargs || echo "0")
        n=$(basename "$f" .md)
        echo "$h|$n"
    fi
done | sort -t'|' -k1 -rn | head -3 | while IFS='|' read -r heat name; do
    echo "- $name (热度：$heat)"
done)
EOF
)
    
    notify "$NOTIFY_WEEKLY" "📈 周度记忆摘要" "$message"
}

# Process queued notifications
process_queue() {
    local queue_file="$WORKSPACE_DIR/logs/notifications-queue.jsonl"
    
    if [[ -f "$queue_file" ]] && [[ -s "$queue_file" ]]; then
        log "Processing $(wc -l < "$queue_file") queued notifications..."
        
        # Send each queued notification
        while IFS= read -r line; do
            local type=$(echo "$line" | jq -r '.type' 2>/dev/null || echo "")
            local title=$(echo "$line" | jq -r '.title' 2>/dev/null || echo "Queued Notification")
            local message=$(echo "$line" | jq -r '.message' 2>/dev/null || echo "")
            
            if [[ -n "$type" ]]; then
                send_log "Queued $type" "$title: $message"
            fi
        done < "$queue_file"
        
        # Clear queue
        > "$queue_file"
        success "Queue processed"
    fi
}

# Show usage
usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  create <file> <type> <summary>    Notify on memory creation
  update <file> <changes>           Notify on memory update
  merge <file> <count>              Notify on memory merge
  weekly                            Generate weekly digest
  process-queue                     Process queued notifications
  config                            Show/edit configuration
  test                              Send test notification

Examples:
  $(basename "$0") create scene_blocks/test.md user "User prefers English"
  $(basename "$0") weekly
  $(basename "$0") process-queue

EOF
}

# Main
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        create)
            notify_create "$@"
            ;;
        update)
            notify_update "$@"
            ;;
        merge)
            notify_merge "$@"
            ;;
        weekly)
            weekly_digest
            ;;
        process-queue|process)
            process_queue
            ;;
        config)
            init_config
            cat "$CONFIG_FILE"
            ;;
        test)
            notify "test" "🧪 测试通知" "这是记忆系统通知测试"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
