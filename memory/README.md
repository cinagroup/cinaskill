# OpenClaw Memory System

## 📚 记忆系统架构

根据 `openclaw-memory-system` 技能文档实现的多层记忆系统。

## 🗂️ 目录结构

```
~/.openclaw/workspace/
├── memory/                          # 工作区记忆
│   ├── README.md                    # 本文件
│   ├── YYYY-MM-DD.md                # 每日记忆文件
│   └── topics/                      # 主题记忆
│       ├── user-preferences.md      # 用户偏好
│       ├── coding-conventions.md    # 编码约定
│       └── project-decisions.md     # 项目决策
├── MEMORY.md                        # 记忆索引（自动生成）
├── logs/                            # 日常活动日志（KAIROS 模式）
│   └── 2026/
│       └── 04/
│           └── 03.md                # 2026-04-03 活动日志
└── docs/
    └── memory-maintenance.md        # 记忆维护配置文档
```

## 📋 记忆类型

| 类型 | 内容 | 范围 |
|------|------|------|
| **user** | 角色、偏好、专业水平 | 始终私有 |
| **feedback** | 用户纠正的规则 | 私有或共享 |
| **project** | 目标、决策、架构洞察 | 通常共享 |
| **reference** | 外部链接（Slack、Linear、文档） | 共享 |

## ⚠️ 不保存的内容

- ❌ 代码模式（使用 grep）
- ❌ Git 历史（使用 git log）
- ❌ 架构布局（使用 ls/read）
- ❌ 凭证或 API 密钥
- ❌ 可从代码库推导的内容

## 🔧 维护任务

- **每日凌晨 2:00**: 自动维护脚本执行
- **清理策略**: 30 天前的记忆文件
- **索引更新**: 每次维护后自动重建
- **大小限制**: MEMORY.md 最大 200 行/25KB

## 📊 当前状态

```bash
# 查看记忆状态
openclaw memory status

# 搜索记忆
openclaw memory search "query"

# 更新索引
openclaw memory index
```

## 🎯 最佳实践

1. **主题组织** - 按主题而非时间线组织记忆
2. **更新现有文件** - 优先更新而非创建新文件
3. **简洁描述** - 每个文件保持简洁，使用 YAML frontmatter
4. **定期清理** - 删除过时或重复的记忆
5. **验证引用** - 使用记忆前验证代码引用是否仍然有效

---

**最后更新**: 2026-04-03
**维护脚本**: `scripts/memory-maintenance.sh`
