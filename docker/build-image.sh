#!/usr/bin/env bash
#
# 构建同时包含 ERPNext 和 Frappe CRM 的自定义 bench 镜像。
#
# 官方发布的 frappe/erpnext 镜像里没有 crm 应用，而 Frappe 一个 bench 里的应用集合
# 是在镜像构建期固定下来的，所以要把两个应用跑在同一个站点上，必须自行构建镜像。
# 构建走官方 frappe_docker 的 layered Containerfile，应用清单来自 docker/apps.json。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -f docker/.env ]; then
  set -a
  # shellcheck disable=SC1091
  . docker/.env
  set +a
fi

IMAGE="${IMAGE:-erpnext-crm:local}"
FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
FRAPPE_DOCKER_REF="${FRAPPE_DOCKER_REF:-main}"
CONTEXT="$ROOT/.cache/frappe_docker"

# frappe_docker 只作为构建上下文使用（Containerfile + resources/ 下的入口脚本），
# 不进版本库，所以放在 .cache 里按需拉取。
if [ -d "$CONTEXT/.git" ]; then
  echo "==> 更新构建上下文 frappe_docker@$FRAPPE_DOCKER_REF"
  git -C "$CONTEXT" fetch --depth 1 origin "$FRAPPE_DOCKER_REF"
  git -C "$CONTEXT" checkout -q FETCH_HEAD
else
  echo "==> 拉取构建上下文 frappe_docker@$FRAPPE_DOCKER_REF"
  rm -rf "$CONTEXT"
  git clone --depth 1 --branch "$FRAPPE_DOCKER_REF" \
    https://github.com/frappe/frappe_docker "$CONTEXT"
fi

# apps.json 是以 build secret 挂进去的，Docker 不会因为它的内容变化而让缓存失效。
# 用它的哈希做 CACHE_BUST，改了应用清单就会重新装应用，没改则命中缓存。
# 需要强制重装（比如上游分支有新提交）时：FORCE_REBUILD=1 ./docker/build-image.sh
CACHE_BUST="$(sha256sum docker/apps.json | cut -d' ' -f1)"
if [ "${FORCE_REBUILD:-0}" = "1" ]; then
  CACHE_BUST="$CACHE_BUST-$(date +%s)"
fi

echo "==> 构建镜像 $IMAGE (frappe $FRAPPE_BRANCH)"
echo "    应用清单："
sed 's/^/      /' docker/apps.json

DOCKER_BUILDKIT=1 docker build \
  --secret "id=apps_json,src=$ROOT/docker/apps.json" \
  --build-arg "FRAPPE_BRANCH=$FRAPPE_BRANCH" \
  --build-arg "CACHE_BUST=$CACHE_BUST" \
  --tag "$IMAGE" \
  --file "$CONTEXT/images/layered/Containerfile" \
  "$CONTEXT"

echo "==> 完成：$IMAGE"
echo "    镜像内应用："
docker run --rm --entrypoint cat "$IMAGE" /home/frappe/frappe-bench/sites/apps.txt 2>/dev/null ||
  docker run --rm --entrypoint ls "$IMAGE" /home/frappe/frappe-bench/apps
