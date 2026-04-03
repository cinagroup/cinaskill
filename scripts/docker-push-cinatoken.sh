#!/bin/bash
set -e

# ============================================
# Cinatoken Docker Hub 推送脚本
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }

# 配置
REPO="cinagroup/cinatoken"
DOCKERFILE="./cinatoken/Dockerfile"
CONTEXT="./cinatoken"
WORKSPACE="/home/cina/.openclaw/workspace"

cd "$WORKSPACE" || exit 1

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║     Cinatoken Docker Hub 推送流程                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# 1. 检查 Docker
log_step "检查 Docker 环境..."
if ! command -v docker &> /dev/null; then
  log_error "Docker 未安装或未在 PATH 中"
  echo ""
  echo "安装 Docker:"
  echo "  curl -fsSL https://get.docker.com | sh"
  echo "  sudo usermod -aG docker \$USER"
  exit 1
fi
log_info "Docker 版本：$(docker --version)"

# 2. 检查登录状态
log_step "检查 Docker Hub 登录状态..."
if ! docker info 2>&1 | grep -q "Username"; then
  log_warn "未登录 Docker Hub"
  echo ""
  echo "请选择登录方式:"
  echo "  1) 交互式登录 (输入用户名密码)"
  echo "  2) 使用 Access Token"
  read -p "选择 [1-2]: " LOGIN_CHOICE
  
  case $LOGIN_CHOICE in
    1)
      read -p "Docker Hub 用户名 [cinagroup]: " DOCKER_USER
      DOCKER_USER=${DOCKER_USER:-cinagroup}
      docker login -u "$DOCKER_USER"
      ;;
    2)
      read -p "Docker Hub 用户名 [cinagroup]: " DOCKER_USER
      DOCKER_USER=${DOCKER_USER:-cinagroup}
      echo "请输入 Access Token (输入时不会显示):"
      read -s DOCKER_TOKEN
      echo ""
      echo "$DOCKER_TOKEN" | docker login -u "$DOCKER_USER" --password-stdin
      ;;
    *)
      log_error "无效选择"
      exit 1
      ;;
  esac
  
  if [ $? -ne 0 ]; then
    log_error "登录失败"
    exit 1
  fi
  log_info "登录成功 ✓"
else
  log_info "已登录 Docker Hub ✓"
fi

# 3. 生成镜像标签
log_step "生成镜像标签..."
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
DATE_TAG=$(date +%Y%m%d)
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

TAGS=("latest" "$COMMIT_HASH" "$DATE_TAG")

log_info "Git Commit: $COMMIT_HASH"
log_info "构建时间：$BUILD_TIME"
log_info "将推送标签：${TAGS[*]}"

# 4. 构建并推送
echo ""
log_step "开始构建并推送镜像..."
echo ""

for TAG in "${TAGS[@]}"; do
  FULL_TAG="${REPO}:${TAG}"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_step "🏷️  标签：$FULL_TAG"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # 构建
  log_info "构建镜像..."
  docker build \
    --file "$DOCKERFILE" \
    --tag "$FULL_TAG" \
    --build-arg VERSION="$COMMIT_HASH" \
    --build-arg BUILD_TIME="$BUILD_TIME" \
    --platform linux/amd64,linux/arm64 \
    "$CONTEXT"
  
  if [ $? -ne 0 ]; then
    log_error "构建失败：$FULL_TAG"
    exit 1
  fi
  
  # 推送
  log_info "推送镜像..."
  docker push "$FULL_TAG"
  
  if [ $? -ne 0 ]; then
    log_error "推送失败：$FULL_TAG"
    exit 1
  fi
  
  log_info "推送成功 ✓"
  echo ""
done

# 5. 完成
echo "╔══════════════════════════════════════════════════════╗"
echo "║                  ✅ 推送完成！                       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "📦 可用镜像标签:"
for TAG in "${TAGS[@]}"; do
  echo "   • ${REPO}:${TAG}"
done
echo ""
echo "🔗 Docker Hub:"
echo "   https://hub.docker.com/r/cinagroup/cinatoken/tags"
echo ""
