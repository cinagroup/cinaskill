# OpenClaw Memory System Skill

> **Version**: 3.1.0  
> **Author**: 001 (OpenClaw Team)  
> **License**: MIT  
> **Description**: Three-layer memory system with LLM extraction, heat management, notifications, dashboard, encrypted backup, and cron automation

---

## 📋 Overview

This skill implements a comprehensive memory system for OpenClaw, inspired by Claude Code's memdir architecture. It provides:

- **Three-Layer Memory Architecture**: User profile, long-term memory, and working memory
- **LLM-Powered Extraction**: Automatic memory extraction from conversations
- **Heat Score Management**: Intelligent scoring with time-based decay
- **Notification System**: Event-based notifications and weekly digests
- **Visual Dashboard**: Web-based UI for memory management
- **Encrypted Backup**: Multi-destination backup with AES-256 encryption
- **Cron Automation**: Scheduled maintenance tasks

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1: User Profile (用户画像)                        │
│  → memory-tdai/persona.md                               │
│  → memory-tdai/scene_blocks/ (场景记忆，带热度评分)        │
├─────────────────────────────────────────────────────────┤
│  Layer 2: Long-Term Memory (长期记忆)                    │
│  → workspace/MEMORY.md (索引 + 核心记忆)                   │
│  → workspace/memory/longterm/ (归档记忆)                 │
├─────────────────────────────────────────────────────────┤
│  Layer 3: Short-Term / Working (短期/工作记忆)           │
│  → workspace/memory/YYYY-MM-DD.md (每日会话日志)         │
│  → workspace/memory/working/ (临时任务状态)              │
│  → workspace/memory/shortterm/ (待审查记忆)              │
└─────────────────────────────────────────────────────────┘
```

---

## 📦 Installation

```bash
# Using OpenClaw CLI
openclaw skills install memory-system

# Or manually clone
git clone https://github.com/cinagroup/cinaskill.git
cd cinaskill/skills/memory-system
```

---

## 🔧 Configuration

### 1. Memory System Config

Create `~/.openclaw/workspace/.memory-config.json`:

```json
{
  "enabled": true,
  "paths": {
    "memory_dir": "/root/.openclaw/workspace/memory",
    "scene_dir": "/root/.openclaw/memory-tdai/scene_blocks"
  },
  "security": {
    "validate_paths": true,
    "whitelist": [
      "/root/.openclaw/workspace/memory",
      "/root/.openclaw/memory-tdai"
    ]
  }
}
```

### 2. Notification Config

Create `~/.openclaw/workspace/.memory-notify-config.json`:

```json
{
  "enabled": true,
  "channels": ["log", "qqbot"],
  "min_heat_threshold": 5,
  "notify_on": {
    "create": true,
    "update": false,
    "merge": true,
    "weekly": true
  },
  "quiet_hours": {
    "start": "23:00",
    "end": "08:00"
  }
}
```

### 3. Backup Config

Create `~/.openclaw/workspace/.memory-backup-config.json`:

```json
{
  "enabled": true,
  "encryption": {
    "enabled": true,
    "algorithm": "aes-256-cbc",
    "password_env": "MEMORY_BACKUP_PASSWORD"
  },
  "destinations": {
    "local": {
      "enabled": true,
      "path": "/root/.openclaw/workspace/.backups/memory"
    },
    "github": {
      "enabled": false,
      "repo": "username/memory-backup",
      "branch": "main"
    }
  },
  "retention": {
    "daily": 7,
    "weekly": 4,
    "monthly": 12
  }
}
```

---

## 🚀 Usage

### Memory Management Scripts

```bash
# Validate memory path (security)
bash scripts/validate-memory-path.sh /path/to/memory.md

# Extract memories with LLM
bash scripts/extract-memory-llm.sh conversation.txt

# Manage heat scores
bash scripts/manage-heat.sh stats          # Show statistics
bash scripts/manage-heat.sh rank           # Show ranking
bash scripts/manage-heat.sh increment file.md 2
bash scripts/manage-heat.sh decay 7 1      # Apply decay
bash scripts/manage-heat.sh auto           # Auto maintenance

# Notifications
bash scripts/memory-notify.sh test
bash scripts/memory-notify.sh create file.md type "summary"
bash scripts/memory-notify.sh weekly       # Weekly digest

# Backup
bash scripts/memory-backup.sh status
bash scripts/memory-backup.sh backup
bash scripts/memory-backup.sh full         # Full workflow
bash scripts/memory-backup.sh restore file.tar.gz.enc
```

### Dashboard

```bash
# Start dashboard server
cd /root/.openclaw/workspace/cinaskill/skills/memory-system
python3 memory-dashboard/server.py

# Access at http://localhost:8080
```

### Cron Jobs

Add to crontab for automatic maintenance:

```bash
# Daily backup (2AM)
0 2 * * * bash scripts/memory-backup.sh full

# Weekly heat decay (Sunday 3AM)
0 3 * * 0 bash scripts/manage-heat.sh auto

# Weekly digest (Monday 9AM)
0 9 * * 1 bash scripts/memory-notify.sh weekly
```

---

## 📁 File Structure

```
memory-system/
├── SKILL.md                          # This file
├── README.md                         # Quick start guide
├── INSTALL.md                        # Installation guide
├── package.json                      # Skill manifest
├── scripts/
│   ├── validate-memory-path.sh       # Path security validation
│   ├── extract-memory-async.sh       # Async memory extraction
│   ├── extract-memory-llm.sh         # LLM-powered extraction
│   ├── manage-heat.sh                # Heat score management
│   ├── memory-notify.sh              # Notification system
│   ├── memory-backup.sh              # Backup & sync
│   └── update-scene-frontmatter.sh   # Frontmatter standardizer
├── memory-dashboard/
│   ├── index.html                    # Dashboard UI
│   ├── app.js                        # Frontend application
│   └── server.py                     # API server
├── templates/
│   ├── MEMORY.md                     # Memory index template
│   └── scene-block.md                # Scene block template
└── docs/
    ├── ARCHITECTURE.md               # Architecture documentation
    └── CRON_CONFIG.md                # Cron automation guide
```

---

## 🔒 Security Features

### Path Validation
- URL-encoded traversal detection
- Null byte rejection
- Backslash rejection (Windows-style paths)
- Symlink escape prevention (`realpath_deepest_existing`)
- Directory whitelist enforcement

### Encryption
- AES-256-CBC encryption for backups
- Password-based key derivation (PBKDF2)
- Environment variable for password storage

### Access Control
- `MEMORY.md` only loaded in main session
- No memory leakage to group chats
- Separate user/project/session scopes

---

## 📊 Memory Types

| Type | Purpose | Example |
|------|---------|---------|
| `user` | User preferences, habits | "Prefers English format" |
| `feedback` | Rules, corrections | "Don't use tables in Discord" |
| `project` | Project decisions, incidents | "Using Kimi 2.5 for images" |
| `reference` | API docs, external links | "WeChat AppID: wx080cd9..." |
| `session` | Current task state | "Working on Phase 3" |

---

## 📈 Heat Score System

### Scoring Rules
- **Initial**: 1 (new memory)
- **On Recall**: +1 (each time accessed)
- **On Create**: +1 (base score)
- **Time Decay**: -1 per week (configurable)
- **Minimum**: 1 (never deleted by decay)

### Ranking Display
```
Rank  Heat  Type     File
1     10    ref      数字资产 - 微信服务号
2     5     user     工作偏好 - 新闻简报
3     3     feedback 发布失败事件复盘
```

---

## 🧩 Integration Examples

### OpenClaw Agent Integration

```javascript
// In your OpenClaw agent's session startup
async function loadMemories() {
    // Load MEMORY.md (main session only)
    if (isMainSession) {
        await loadFile('workspace/MEMORY.md');
    }
    
    // Load daily logs
    await loadFile(`workspace/memory/${today}.md`);
    
    // Search relevant memories
    const relevant = await memorySearch(currentQuery);
    await loadFiles(relevant);
}
```

### Memory Extraction Hook

```bash
# After conversation ends
onConversationEnd() {
    bash scripts/extract-memory-llm.sh "$CONVERSATION_FILE"
}
```

---

## 🐛 Troubleshooting

### Memory Not Loading
1. Check file paths are in whitelist
2. Verify `MEMORY.md` exists in workspace
3. Ensure main session (not group chat)

### Backup Fails
1. Set `MEMORY_BACKUP_PASSWORD` environment variable
2. Check destination permissions
3. Verify network connectivity for remote sync

### Dashboard Not Starting
1. Ensure Python 3.8+ is installed
2. Check port 8080 is available
3. Verify `memory-dashboard/` directory exists

---

## 📚 References

- **Claude Code memdir**: Primary architecture inspiration
- **OpenClaw Docs**: https://docs.openclaw.ai
- **Skill Hub**: https://clawhub.ai

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 📄 License

MIT License - See LICENSE file for details

---

*Version: 3.1.0 | Last Updated: 2026-04-04*
