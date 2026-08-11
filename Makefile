COMPOSE := docker compose --env-file docker/.env -f docker/compose.yaml
SITE    := $(shell [ -f docker/.env ] && grep -E '^SITE_NAME=' docker/.env | cut -d= -f2 || echo erp.localhost)
PORT    := $(shell [ -f docker/.env ] && grep -E '^HTTP_PUBLISH_PORT=' docker/.env | cut -d= -f2 || echo 8080)

.DEFAULT_GOAL := help
.PHONY: help env build up down restart logs ps shell bench backup clean

help: ## 显示可用命令
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

docker/.env:
	cp docker/.env.example docker/.env
	@echo "已生成 docker/.env，请检查其中的密码和站点名。"

env: docker/.env ## 从模板生成 docker/.env

build: env ## 构建含 ERPNext + Frappe CRM 的自定义镜像
	./docker/build-image.sh

up: env ## 启动全部服务（首次会自动建站并装应用）
	$(COMPOSE) up -d
	@echo
	@echo "首次启动需要几分钟建站，用 'make logs' 跟踪进度。"
	@echo "  ERPNext:    http://localhost:$(PORT)/app"
	@echo "  Frappe CRM: http://localhost:$(PORT)/crm"

down: ## 停止服务（保留数据卷）
	$(COMPOSE) down

restart: ## 重启服务
	$(COMPOSE) restart

logs: ## 跟踪日志
	$(COMPOSE) logs -f

ps: ## 查看服务状态
	$(COMPOSE) ps

shell: ## 进入 backend 容器
	$(COMPOSE) exec backend bash

bench: ## 执行 bench 命令，如 make bench CMD="--site $(SITE) list-apps"
	$(COMPOSE) exec backend bench $(CMD)

backup: ## 备份站点（含文件），落在 sites 卷的 private/backups 下
	$(COMPOSE) exec backend bench --site $(SITE) backup --with-files

clean: ## 停止服务并删除数据卷（会清空所有数据）
	$(COMPOSE) down -v
