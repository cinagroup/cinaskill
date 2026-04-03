#!/bin/bash
set -e

# ============================================
# Cinaseek Docker Hub 推送脚本 (多服务)
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
REPO_PREFIX="cinagroup/cinaseek"
WORKSPACE="/home/cina/.openclaw/workspace/cinaseek"

cd "$WORKSPACE" || exit 1

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║     Cinaseek Docker Hub 推送流程 (多服务)            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# 1. 检查 Docker
log_step "检查 Docker 环境..."
if ! command -v docker &> /dev/null; then
  log_error "Docker 未安装或未在 PATH 中"
  exit 1
fi
log_info "Docker 版本：$(docker --version)"

# 2. 检查登录状态
log_step "检查 Docker Hub 登录状态..."
if ! docker info 2>&1 | grep -q "Username"; then
  log_warn "未登录 Docker Hub"
  read -p "Docker Hub 用户名 [cinagroup]: " DOCKER_USER
  DOCKER_USER=${DOCKER_USER:-cinagroup}
  echo "请输入 Access Token:"
  read -s DOCKER_TOKEN
  echo ""
  echo "$DOCKER_TOKEN" | docker login -u "$DOCKER_USER" --password-stdin
  if [ $? -ne 0 ]; then
    log_error "登录失败"
    exit 1
  fi
  log_info "登录成功 ✓"
else
  log_info "已登录 Docker Hub ✓"
fi

# 3. 生成标签
log_step "生成镜像标签..."
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
DATE_TAG=$(date +%Y%m%d)
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

TAGS=("latest" "$COMMIT_HASH")

log_info "Git Commit: $COMMIT_HASH"
log_info "将推送标签：${TAGS[*]}"

# 4. 服务定义
declare -A SERVICES=(
  ["api-service"]="Dockerfile.api ./services/api-service"
  ["matching-engine"]="Dockerfile.matching ./services/matching-engine"
  ["web-frontend"]="Dockerfile.web ./apps/web"
  ["monitoring-service"]="Dockerfile.monitoring ./services/monitoring-service"
  ["control-center"]="Dockerfile.control-center ."
)

# 5. 构建并推送每个服务
for SERVICE_NAME in "${!SERVICES[@]}"; do
  read -r DOCKERFILE CONTEXT <<< "${SERVICES[$SERVICE_NAME]}"
  
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  log_step "🔧 服务：$SERVICE_NAME"
  echo "╚══════════════════════════════════════════════════════╝"
  
  for TAG in "${TAGS[@]}"; do
    FULL_TAG="${REPO_PREFIX}-${SERVICE_NAME}:${TAG}"
    
    log_info "🏷️  标签：$FULL_TAG"
    
    # 构建
    log_info "构建中..."
    docker build \
      --file "$DOCKERFILE" \
      --tag "$FULL_TAG" \
      --build-arg BUILD_TIME="$BUILD_TIME" \
      --build-arg COMMIT_HASH="$COMMIT_HASH" \
      --platform linux/amd64 \
      "$CONTEXT"
    
    if [ $? -ne 0 ]; then
      log_error "构建失败：$SERVICE_NAME"
      exit 1
    fi
    
    # 推送
    log_info "推送中..."
    docker push "$FULL_TAG"
    
    if [ $? -ne 0 ]; then
      log_error "推送失败：$SERVICE_NAME"
      exit 1
    fi
    
    log_info "推送成功 ✓"
  done
done

# 6. 完成
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                  ✅ 所有服务推送完成！               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "📦 推送的镜像:"
for SERVICE_NAME in "${!SERVICES[@]}"; do
  for TAG in "${TAGS[@]}"; do
    echo "   • ${REPO_PREFIX}-${SERVICE_NAME}:${TAG}"
  done
done
echo ""
