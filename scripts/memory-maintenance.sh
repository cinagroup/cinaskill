#!/bin/bash
# OpenClaw Memory Maintenance Script
# 记忆自动维护脚本

set -e

WORKSPACE="/home/cina/.openclaw/workspace"
LOG_DIR="$WORKSPACE/logs/memory"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="$LOG_DIR/maintenance_$DATE.log"

# 创建日志目录
mkdir -p "$LOG_DIR"

echo "=== OpenClaw Memory Maintenance Started at $(date) ===" | tee -a "$LOG_FILE"

# 1. 检查 memory 目录是否存在
if [ ! -d "$WORKSPACE/memory" ]; then
    echo "Creating memory directory..." | tee -a "$LOG_FILE"
    mkdir -p "$WORKSPACE/memory"
fi

# 2. 创建今日记忆文件（如果不存在）
TODAY=$(date +%Y-%m-%d)
TODAY_FILE="$WORKSPACE/memory/$TODAY.md"
if [ ! -f "$TODAY_FILE" ]; then
    echo "Creating today's memory file: $TODAY_FILE" | tee -a "$LOG_FILE"
    cat > "$TODAY_FILE" << EOF
# Memory - $TODAY

## Daily Log
_自动创建的记忆文件_

## Key Events
- 

## Decisions
- 

## Lessons Learned
- 

## TODO
- [ ] 

---

**创建时间**: $(date -Iseconds)
EOF
fi

# 2b. 创建今日日志文件（如果不存在）
LOG_FILE_PATH="$WORKSPACE/logs/$(date +%Y)/$(date +%m)/$(date +%d).md"
mkdir -p "$(dirname "$LOG_FILE_PATH")"
if [ ! -f "$LOG_FILE_PATH" ]; then
    echo "Creating today's log file: $LOG_FILE_PATH" | tee -a "$LOG_FILE"
    cat > "$LOG_FILE_PATH" << EOF
# Daily Log - $TODAY

## 📅 日期
$TODAY ($(date -d "$TODAY" +%A))

## 🎯 主要任务
- [ ] 

## 📝 活动记录

## 🔍 问题与解决

## 📊 统计数据

## 🎓 学习收获

## 🔮 明日计划

---

**日志创建**: $(date -Iseconds)
EOF
fi

# 3. 清理旧文件
echo "Cleaning up old files..." | tee -a "$LOG_FILE"

# 清理 30 天前的记忆文件（排除 README.md 和 topics 目录）
find "$WORKSPACE/memory" -maxdepth 1 -name "*.md" -type f -mtime +30 ! -name "README.md" -exec rm -v {} \; | tee -a "$LOG_FILE"

# 清理 90 天前的日志文件
find "$WORKSPACE/logs" -name "*.md" -type f -mtime +90 -exec rm -v {} \; | tee -a "$LOG_FILE"

# 4. 检查 MEMORY.md 文件大小
MEMORY_FILE="$WORKSPACE/MEMORY.md"
if [ -f "$MEMORY_FILE" ]; then
    SIZE=$(wc -c < "$MEMORY_FILE")
    if [ $SIZE -gt 1048576 ]; then  # 大于 1MB
        echo "MEMORY.md is large ($SIZE bytes), consider archiving..." | tee -a "$LOG_FILE"
    fi
fi

# 5. 更新记忆索引
echo "Updating memory index..." | tee -a "$LOG_FILE"
cd "$WORKSPACE" && openclaw memory index 2>&1 | tee -a "$LOG_FILE"

# 6. 显示记忆状态
echo "Memory status:" | tee -a "$LOG_FILE"
cd "$WORKSPACE" && openclaw memory status 2>&1 | tee -a "$LOG_FILE"

echo "=== OpenClaw Memory Maintenance Completed at $(date) ===" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
