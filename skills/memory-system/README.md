# 🧠 OpenClaw Memory System Skill

> **Version**: 3.1.0  
> **Category**: Productivity  
> **License**: MIT

A comprehensive memory system for OpenClaw, inspired by Claude Code's memdir architecture.

---

## ✨ Features (v3.1.0)

- **Three-Layer Memory**: User profile, long-term, and working memory
- **LLM Extraction**: Automatic memory extraction from conversations
- **Heat Scoring**: Intelligent scoring with time-based decay
- **Notifications**: Event-based alerts and weekly digests
- **Dashboard**: Web-based UI for memory management (dark mode)
- **Encrypted Backup**: Multi-destination backup (Local, GitHub, S3, WebDAV)
- **Cron Automation**: Scheduled maintenance tasks

---

## 🚀 Quick Start

### Install
```bash
openclaw skills install memory-system
```

### Configure
```bash
# Set encryption password
export MEMORY_BACKUP_PASSWORD="your-secure-password"

# Copy config templates
cp templates/MEMORY.md /root/.openclaw/workspace/MEMORY.md
```

### Start Dashboard
```bash
cd /root/.openclaw/workspace/cinaskill/skills/memory-system
python3 memory-dashboard/server.py
# Access: http://localhost:8080
```

---

## 📖 Documentation

- [SKILL.md](SKILL.md) - Full skill documentation
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - Architecture details
- [docs/CRON_CONFIG.md](docs/CRON_CONFIG.md) - Cron automation guide
- [templates/](templates/) - Configuration templates

---

## 🛠️ Scripts

| Script | Purpose |
|--------|---------|
| `validate-memory-path.sh` | Path security validation |
| `extract-memory-llm.sh` | LLM-powered extraction |
| `manage-heat.sh` | Heat score management |
| `memory-notify.sh` | Notification system |
| `memory-backup.sh` | Backup & sync |
| `update-scene-frontmatter.sh` | Frontmatter standardizer |

---

## 📊 Memory Types

| Type | Purpose |
|------|---------|
| `user` | User preferences, habits |
| `feedback` | Rules, corrections |
| `project` | Project decisions, incidents |
| `reference` | API docs, external links |
| `session` | Current task state |

---

## 🔒 Security

- Path traversal prevention
- Symlink escape detection
- Directory whitelist enforcement
- AES-256-CBC encryption for backups

---

## 📄 License

MIT License

---

*Last Updated: 2026-04-04*
