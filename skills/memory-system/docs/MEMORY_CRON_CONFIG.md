# OpenClaw 记忆系统定时任务配置

> **配置日期**: 2026-04-03  
> **记忆系统版本**: v3.0  
> **时区**: Asia/Shanghai (GMT+8)

---

## 📋 Cron 任务列表

### 每日任务

| 时间 | 任务 | 脚本 | 日志文件 |
|------|------|------|----------|
| **02:00** | 加密备份 | `memory-backup.sh full` | `logs/memory-backup.log` |
| **04:00** | Frontmatter 标准化 | `update-scene-frontmatter.sh` | `logs/scene-update.log` |
| **每小时** | 健康检查 | `test MEMORY.md` | `logs/memory-health.log` |

### 每周任务

| 时间 | 任务 | 脚本 | 日志文件 |
|------|------|------|----------|
| **周日 03:00** | 热度衰减 + 排名 | `manage-heat.sh auto` | `logs/heat-auto.log` |
| **周一 09:00** | 周度摘要通知 | `memory-notify.sh weekly` | `logs/memory-weekly.log` |

### 每月任务

| 时间 | 任务 | 脚本 | 日志文件 |
|------|------|------|----------|
| **1 号 05:00** | 记忆清理 | `memory-backup.sh cleanup` | `logs/memory-cleanup.log` |

---

## 🔧 任务说明

### 1. 每日加密备份 (02:00)
```bash
0 2 * * * bash /root/.openclaw/workspace/cinaskill/skills/memory-system/scripts/memory-backup.sh full
```

**执行内容**:
- 扫描所有记忆文件
- 创建 tar.gz 压缩包
- AES-256-CBC 加密 (需设置 `MEMORY_BACKUP_PASSWORD`)
- 同步到配置的目的地 (Local/GitHub/S3/WebDAV)
- 清理超过保留期的旧备份

**输出示例**:
```
[INFO] Creating backup: memory_backup_20260403_020000_xxxxxxxx
[INFO] Copied workspace memory files
[INFO] Created archive: 24K
[SUCCESS] Backup created: memory_backup_20260403_020000_xxxxxxxx.tar.gz.enc
```

---

### 2. 每周热度衰减 (周日 03:00)
```bash
0 3 * * 0 bash /root/.openclaw/workspace/cinaskill/skills/memory-system/scripts/manage-heat.sh auto
```

**执行内容**:
- 计算每个记忆文件的天数
- 应用时间衰减 (每 7 天 -1 热度)
- 更新 frontmatter 中的热度值
- 生成热度排名报告

**输出示例**:
```
[INFO] Applying heat decay (threshold: 7d, decay: -1)
[INFO] Decayed: 数字资产 - 微信服务号.md (age: 14d, 10 → 8)
[SUCCESS] Decay applied to 2 files

🔥 Heat Ranking:
1. 数字资产 - 微信服务号 (heat: 8)
2. 工作偏好 - 新闻简报 (heat: 5)
```

---

### 3. 周度摘要通知 (周一 09:00)
```bash
0 9 * * 1 bash /root/.openclaw/workspace/cinaskill/skills/memory-system/scripts/memory-notify.sh weekly
```

**执行内容**:
- 统计本周新增记忆数
- 统计本周更新记忆数
- 计算总热度
- 生成 TOP 3 热门记忆
- 发送通知 (log/qqbot)

**输出示例**:
```
[INFO] Generating weekly memory digest...
📊 统计数据:
- 新增记忆：3
- 更新记忆：5
- 总热度：24

🔥 热门记忆 TOP 3:
- 数字资产 - 微信服务号 (热度：10)
- 工作偏好 - 新闻简报 (热度：5)
- 演示 - 记忆系统测试 (热度：2)
```

---

### 4. Frontmatter 标准化 (04:00)
```bash
0 4 * * * bash /root/.openclaw/workspace/cinaskill/skills/memory-system/scripts/update-scene-frontmatter.sh
```

**执行内容**:
- 扫描 `scene_blocks/` 目录
- 检查每个文件的 frontmatter
- 标准化格式 (created/updated/summary/heat/type)
- 确保元数据完整性

---

### 5. 每月记忆清理 (1 号 05:00)
```bash
0 5 1 * * bash /root/.openclaw/workspace/cinaskill/skills/memory-system/scripts/memory-backup.sh cleanup
```

**执行内容**:
- 清理超过保留期的备份
- 保留策略：7 天每日 + 4 周每周 + 12 月每月
- 删除孤立的记忆文件

---

### 6. 每小时健康检查 (整点)
```bash
0 * * * * test -f /root/.openclaw/workspace/MEMORY.md && echo "[$(date)] Memory system OK"
```

**执行内容**:
- 检查 `MEMORY.md` 是否存在
- 记录健康状态到日志

---

## 📁 日志文件位置

```
/root/.openclaw/workspace/logs/
├── memory-backup.log       # 备份日志
├── heat-auto.log           # 热度衰减日志
├── memory-weekly.log       # 周度摘要日志
├── scene-update.log        # Frontmatter 更新日志
├── memory-cleanup.log      # 清理日志
└── memory-health.log       # 健康检查日志
```

---

## 🔍 查看日志

```bash
# 查看最新备份
tail -20 /root/.openclaw/workspace/logs/memory-backup.log

# 查看热度衰减历史
cat /root/.openclaw/workspace/logs/heat-auto.log

# 查看健康检查
tail -50 /root/.openclaw/workspace/logs/memory-health.log

# 实时监控
tail -f /root/.openclaw/workspace/logs/memory-*.log
```

---

## ⚙️ 配置修改

### 修改 Cron 时间
```bash
crontab -e
# 编辑对应任务的时间字段
```

### 禁用特定任务
```bash
crontab -e
# 在任务行前添加 # 注释
# 0 2 * * * bash ... → # 0 2 * * * bash ...
```

### 添加新任务
```bash
crontab -e
# 添加新行，格式：分 时 日 月 周 命令
```

---

## 🧪 手动测试

```bash
# 测试备份脚本
bash /root/.openclaw/workspace/cinaskill/skills/memory-system/scripts/memory-backup.sh status

# 测试热度管理
bash /root/.openclaw/workspace/cinaskill/skills/memory-system/scripts/manage-heat.sh stats

# 测试周度摘要
bash /root/.openclaw/workspace/cinaskill/skills/memory-system/scripts/memory-notify.sh weekly

# 测试健康检查
test -f /root/.openclaw/workspace/MEMORY.md && echo "OK" || echo "FAIL"
```

---

## 📊 监控建议

### 每日检查
- [ ] 备份日志是否有 SUCCESS
- [ ] 健康检查是否持续 OK

### 每周检查
- [ ] 热度衰减报告
- [ ] 周度摘要内容

### 每月检查
- [ ] 清理任务执行情况
- [ ] 备份存储空间使用

---

## 🔐 安全配置

### 环境变量
```bash
# ~/.bashrc 或 ~/.zshrc
export MEMORY_BACKUP_PASSWORD="your-secure-password"
export WEBDAV_USER="your-webdav-username"      # 可选
export WEBDAV_PASSWORD="your-webdav-password"  # 可选
```

### 文件权限
```bash
# 确保脚本可执行
chmod +x /root/.openclaw/workspace/cinaskill/skills/memory-system/scripts/*.sh

# 日志文件权限
chmod 640 /root/.openclaw/workspace/logs/memory-*.log
```

---

*配置文档 v1.0 - Last Updated: 2026-04-03*
