#!/usr/bin/env bash
#
# 裸机 / 开发环境安装：在一个已存在的 frappe-bench 里装上 ERPNext + Frappe CRM。
#
# 适用于本地二次开发（需要改代码、跑 bench start 热重载）的场景。
# 只想跑起来用，走 Docker 更省事，见 README.md。
#
# 前置条件：已经 bench init 出一个 bench，且满足 frappe v16 的版本要求 ——
# Python >=3.14,<3.15、Node >=24、MariaDB >=10.6，另需 uv 和 cron。详见 README.md。
#   uv python install 3.14
#   pip install frappe-bench
#   bench init --frappe-branch version-16 --python "$(uv python find 3.14)" frappe-bench
#   cd frappe-bench
#
# 用法（在 frappe-bench 目录下执行）：
#   /path/to/scripts/bench-setup.sh [站点名]
#
# 环境变量：
#   DB_ROOT_PASSWORD  MariaDB root 密码，不设则由 bench 交互式询问
#   ADMIN_PASSWORD    站点 Administrator 密码，默认 admin

set -euo pipefail

SITE="${1:-${SITE_NAME:-erp.localhost}}"
ERPNEXT_BRANCH="${ERPNEXT_BRANCH:-version-16}"
CRM_BRANCH="${CRM_BRANCH:-main}"

# 用完整仓库 URL 而不是 `bench get-app erpnext` 这样的短名：短名会让 bench 去查
# GitHub API 猜测所属组织，在限制出站访问或未认证的环境里这一步会失败。
ERPNEXT_URL="${ERPNEXT_URL:-https://github.com/frappe/erpnext}"
CRM_URL="${CRM_URL:-https://github.com/frappe/crm}"

if [ ! -d "apps/frappe" ]; then
  echo "错误：当前目录不是 frappe-bench（找不到 apps/frappe）。" >&2
  echo "请先 cd 到 frappe-bench 目录再执行本脚本。" >&2
  exit 1
fi

echo "==> 获取 erpnext@$ERPNEXT_BRANCH"
[ -d "apps/erpnext" ] || bench get-app "$ERPNEXT_URL" --branch "$ERPNEXT_BRANCH"

echo "==> 获取 crm@$CRM_BRANCH"
[ -d "apps/crm" ] || bench get-app "$CRM_URL" --branch "$CRM_BRANCH"

if [ -d "sites/$SITE" ]; then
  echo "==> 站点 $SITE 已存在，直接装应用"
else
  echo "==> 创建站点 $SITE"
  # 不设 DB_ROOT_PASSWORD 时交给 bench 交互式询问；CI / 无人值守下设这个变量。
  root_pw_args=()
  if [ -n "${DB_ROOT_PASSWORD:-}" ]; then
    root_pw_args=(--db-root-password "$DB_ROOT_PASSWORD")
  fi
  bench new-site "$SITE" \
    --admin-password "${ADMIN_PASSWORD:-admin}" \
    "${root_pw_args[@]}"
fi

# install-app 对已装应用会报错，所以先查一遍。
installed="$(bench --site "$SITE" list-apps)"
for app in erpnext crm; do
  if grep -qw "$app" <<<"$installed"; then
    echo "==> $app 已安装，跳过"
  else
    echo "==> 安装 $app 到 $SITE"
    bench --site "$SITE" install-app "$app"
  fi
done

bench use "$SITE"

echo
echo "==> 完成。启动：bench start"
echo "    ERPNext:    http://$SITE:8000"
echo "    Frappe CRM: http://$SITE:8000/crm"
