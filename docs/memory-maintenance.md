# OpenClaw Memory Maintenance Configuration

## 📋 配置概述

已配置自动记忆维护任务，确保 OpenClaw 记忆系统保持整洁和高效。

## ⏰ Cron 定时任务

### 任务配置
```bash
# 每天凌晨 2:00 执行记忆维护
0 2 * * * /home/cina/.openclaw/workspace/scripts/memory-maintenance.sh
```

### 任务内容
1. ✅ 创建/检查 memory 目录
2. ✅ 自动创建今日记忆文件 (`memory/YYYY-MM-DD.md`)
3. ✅ 清理 30 天前的旧记忆文件
4. ✅ 检查 MEMORY.md 文件大小
5. ✅ 更新记忆索引
6. ✅ 显示记忆状态

## 📁 相关文件

| 文件 | 用途 |
|------|------|
| `scripts/memory-maintenance.sh` | 维护脚本 |
| `logs/memory/` | 维护日志目录 |
| `memory/YYYY-MM-DD.md` | 每日记忆文件 |
| `MEMORY.md` | 长期记忆文件 |

## 🔧 管理命令

```bash
# 查看当前 cron 任务
crontab -l

# 手动执行维护脚本
/home/cina/.openclaw/workspace/scripts/memory-maintenance.sh

# 查看维护日志
tail -f /home/cina/.openclaw/workspace/logs/memory/maintenance_*.log

# 编辑 cron 任务
crontab -e

# 删除 cron 任务
crontab -l | grep -v "memory-maintenance" | crontab -
```

## 📊 日志位置

维护日志保存在：
```
/home/cina/.openclaw/workspace/logs/memory/maintenance_YYYY-MM-DD_HH-MM-SS.log
```

## ⚙️ 自定义配置

### 修改执行时间
编辑 crontab：
```bash
crontab -e
```

修改时间（格式：`分 时 日 月 周`）：
- `0 2 * * *` - 每天凌晨 2 点
- `0 3 * * 0` - 每周日凌晨 3 点
- `0 4 1 * *` - 每月 1 号凌晨 4 点

### 修改清理策略
编辑 `scripts/memory-maintenance.sh`，修改：
```bash
# 修改保留天数（默认 30 天）
find "$WORKSPACE/memory" -name "*.md" -type f -mtime +30 -exec rm -v {} \;
#                                                            ^^^ 改为其他天数
```

### 修改 MEMORY.md 大小限制
编辑 `scripts/memory-maintenance.sh`，修改：
```bash
# 修改大小限制（默认 1MB = 1048576 bytes）
if [ $SIZE -gt 1048576 ]; then
#              ^^^^^^^ 改为其他大小
```

## 🎯 最佳实践

1. **定期查看日志** - 确保维护任务正常执行
2. **备份重要记忆** - 在清理前备份重要的记忆文件
3. **监控磁盘空间** - 确保 workspace 有足够空间
4. **调整清理策略** - 根据实际需求调整保留天数

## 📝 示例：查看记忆状态

```bash
# 查看记忆索引状态
openclaw memory status

# 搜索记忆
openclaw memory search "deployment"

# 强制重新索引
openclaw memory index --force
```

---

**配置完成时间**: 2026-04-03
**下次执行时间**: 明天凌晨 2:00
