---
name: Coding Conventions
description: 编码约定和最佳实践
type: project
created: 2026-04-03
updated: 2026-04-03
---

# Coding Conventions

## TypeScript/JavaScript

### 代码风格
- **缩进**: 2 空格
- **引号**: 单引号
- **分号**: 使用
- **行宽**: 100 字符

### 命名约定
```typescript
// 变量和函数：camelCase
const userName = '000';
function getUserInfo() {}

// 类：PascalCase
class UserService {}

// 常量：UPPER_SNAKE_CASE
const MAX_RETRY_COUNT = 3;

// 类型：PascalCase
interface UserInfo {}
type UserStatus = 'active' | 'inactive';
```

### 错误处理
```typescript
// 使用 try-catch 处理异步错误
async function fetchData() {
  try {
    const response = await api.get('/data');
    return response.data;
  } catch (error) {
    logger.error('Failed to fetch data', error);
    throw error;
  }
}

// 自定义错误类
class ApiError extends Error {
  constructor(public code: string, message: string) {
    super(message);
  }
}
```

### 注释规范
```typescript
// 单行注释：使用 //

/**
 * 多行注释：使用 JSDoc 格式
 * @param userId - 用户 ID
 * @returns 用户信息
 */
function getUser(userId: number): Promise<UserInfo> {}
```

## Docker

### Dockerfile 最佳实践
```dockerfile
# 使用多阶段构建
FROM node:20-alpine AS builder
WORKDIR /build
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /build/dist /usr/share/nginx/html
```

### docker-compose 规范
```yaml
version: '3.8'
services:
  app:
    image: cinagroup/cinatoken:latest
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## Git

### 提交信息格式
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type 类型**:
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式
- `refactor`: 重构
- `test`: 测试
- `chore`: 构建/工具

### 分支命名
```
feature/<name>     # 新功能
fix/<name>         # Bug 修复
hotfix/<name>      # 紧急修复
release/<version>  # 发布分支
```

## API 设计

### RESTful 规范
```typescript
// 资源命名：复数名词
GET    /api/users          # 获取用户列表
GET    /api/users/:id      # 获取单个用户
POST   /api/users          # 创建用户
PUT    /api/users/:id      # 更新用户
DELETE /api/users/:id      # 删除用户

// 状态码
200 OK                    # 成功
201 Created               # 创建成功
400 Bad Request           # 请求错误
401 Unauthorized          # 未授权
403 Forbidden             # 禁止访问
404 Not Found             # 未找到
500 Internal Server Error # 服务器错误
```

### 响应格式
```typescript
{
  success: boolean,
  data: any,
  message?: string,
  error?: {
    code: string,
    details: any
  }
}
```

---

**最后更新**: 2026-04-03
**维护**: 根据项目演进自动更新
