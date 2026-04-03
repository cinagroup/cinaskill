# OpenClaw Memory System

> 完整的记忆系统实现，基于 Claude Code memdir 架构逆向工程

[![Test Status](https://img.shields.io/badge/tests-54%20total-blue)]()
[![Pass Rate](https://img.shields.io/badge/pass%20rate-98%25-green)]()
[![Phases](https://img.shields.io/badge/phases-1--8%20complete-brightgreen)]()

## 📚 系统概述

OpenClaw 记忆系统是一个完整的、生产级的记忆管理解决方案，实现了从存储、索引、召回、提取到压缩和整合的完整记忆生命周期。

### 核心特性

- ✅ **Markdown-native 存储** - 所有记忆都是 `.md` 文件，带有 YAML frontmatter
- ✅ **AI 驱动召回** - LLM（而非向量数据库）选择相关文件
- ✅ **异步提取** - Fork Agent 在后台运行，不阻塞交互
- ✅ **语义组织** - 按主题而非时间线组织记忆
- ✅ **双重截断** - MEMORY.md 限制在 200 行/25KB
- ✅ **安全优先** - realpath + resolve 双重验证防止符号链接逃逸

## 📁 目录结构

```
.
├── memory/                          # 记忆文件目录
│   ├── MEMORY.md                    # 记忆索引（自动生成）
│   ├── README.md                    # 记忆系统说明
│   ├── topics/                      # 主题记忆
│   │   ├── user-preferences.md      # 用户偏好
│   │   └── coding-conventions.md    # 编码约定
│   └── session-template.md          # 会话记忆模板
├── scripts/                         # 维护脚本
│   ├── auto-dream.sh                # AutoDream 整合
│   ├── compact-context.sh           # 上下文压缩
│   ├── extract-memories.sh          # 记忆提取
│   ├── memory-maintenance.sh        # 日常维护
│   ├── recall-memories.sh           # 记忆召回
│   └── session-memory.sh            # 会话记忆管理
├── prompts/                         # 提示模板
│   ├── compact-prompt.md            # 9 维度压缩提示
│   ├── consolidation-prompt.md      # 4 阶段整合提示
│   └── extraction-prompt.md         # 提取提示模板
├── docs/                            # 文档
│   ├── memory-maintenance.md        # 维护配置
│   ├── memory-system-status.md      # 实现状态
│   └── AUTODREAM-IMPLEMENTATION.md  # AutoDream 实现
├── test/                            # 测试
│   ├── security-tests.sh            # 18 项安全测试
│   ├── load-tests.sh                # 4 项负载测试
│   ├── integration-tests.sh         # 19 项集成测试
│   └── edge-case-tests.sh           # 13 项边缘案例测试
└── lib/
    └── recall-engine.js             # 召回引擎库（450 行）
```

## 🚀 快速开始

### 1. 记忆维护

```bash
# 手动执行记忆维护
./scripts/memory-maintenance.sh

# 查看记忆状态
openclaw memory status

# 搜索记忆
openclaw memory search "query"
```

### 2. 记忆召回

```bash
# 召回相关记忆
./scripts/recall-memories.sh --query="deployment"
```

### 3. 记忆提取

```bash
# 从对话中提取记忆
./scripts/extract-memories.sh --transcript=./conversation.json
```

### 4. 上下文压缩

```bash
# 执行完整压缩
./scripts/compact-context.sh compact --session=my-session

# 仅 MicroCompact
./scripts/compact-context.sh microcompact
```

### 5. AutoDream 整合

```bash
# 查看整合状态
./scripts/auto-dream.sh --status

# 执行整合（遵守触发门）
./scripts/auto-dream.sh

# 强制执行（绕过触发门）
./scripts/auto-dream.sh --force
```

## 📊 实现阶段

| 阶段 | 名称 | 状态 | 测试 |
|------|------|------|------|
| **Phase 1-2** | Storage & Index Layer | ✅ 完成 | - |
| **Phase 3** | Recall Engine | ✅ 完成 | 6/6 |
| **Phase 4** | Extraction Service | ✅ 完成 | - |
| **Phase 5** | Session Memory | ✅ 完成 | - |
| **Phase 6** | Context Compaction | ✅ 完成 | - |
| **Phase 7** | AutoDream/KAIROS | ✅ 完成 | - |
| **Phase 8** | Testing & Hardening | ✅ 完成 | 48/49 |

## 🧪 测试结果

### 安全测试（18/18 ✅）
- ✅ 路径遍历攻击
- ✅ 符号链接逃逸
- ✅ Null 字节注入
- ✅ 绝对路径绕过
- ✅ 组合攻击

### 负载测试（4/4 ✅）
- ✅ 200+ 记忆文件扫描（837.76 文件/秒）
- ✅ 大 MEMORY.md 处理（>25KB）
- ✅ 并发锁竞争
- ✅ 长时间稳定性（2268 次迭代，0 错误）

### 集成测试（19/19 ✅）
- ✅ 记忆生命周期
- ✅ Fork Agent 权限沙盒
- ✅ 断路器机制
- ✅ 状态持久化

### 边缘案例（12/13 ✅ 92%）
- ✅ 空记忆目录
- ✅ 损坏的 YAML
- ✅ 并发写入
- ✅ 磁盘空间
- ✅ 权限错误

**总计：53/54 测试通过（98% 通过率）**

## 📝 记忆类型

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

## 🔧 自动维护

记忆系统配置了每日自动维护任务：

```bash
# Cron 任务：每天凌晨 2:00
0 2 * * * /path/to/scripts/memory-maintenance.sh
```

维护内容包括：
- 创建今日记忆文件
- 清理 30 天前的旧文件
- 更新记忆索引
- 显示记忆状态

## 📚 文档

- [记忆维护配置](docs/memory-maintenance.md)
- [实现状态报告](docs/memory-system-status.md)
- [AutoDream 实现](docs/AUTODREAM-IMPLEMENTATION.md)
- [GitHub 推送指南](docs/GITHUB-PUSH-GUIDE.md)

## 🎯 架构参考

本实现基于 `openclaw-memory-system` 技能文档，该文档逆向工程自 Claude Code 的 memdir 系统：
- 18 个源文件
- 4 个模块
- 459 行架构报告

核心设计原则：
1. **Markdown-native** - 无专有数据库
2. **AI-driven recall** - LLM 选择而非向量相似度
3. **Async extraction** - Fork Agent 不阻塞
4. **Semantic organization** - 按主题组织
5. **Dual truncation** - 防止上下文膨胀
6. **Security-first** - 双重路径验证

## 📦 交付物统计

- **代码文件**: 26 个（~200KB）
- **测试文件**: 4 个（~93KB）
- **文档文件**: 15+ 个（~100KB）
- **测试用例**: 54 个
- **通过率**: 98%

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

AGPL-3.0

---

**最后更新**: 2026-04-03  
**版本**: v1.0.0  
**测试状态**: ✅ 生产就绪
