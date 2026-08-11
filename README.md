# ERPNext + Frappe CRM 部署仓库

一键拉起 **ERPNext v16** 和 **[Frappe CRM](https://github.com/frappe/crm)**，两者装在同一个 bench、同一个站点上，共享用户、权限和数据库。

选型过程和候选方案对比见 [`docs/crm-selection.md`](docs/crm-selection.md)，结论是：Frappe 生态里最好的 CRM 是官方的 `frappe/crm`。

## 快速开始

前置条件：Docker 与 Docker Compose v2，磁盘预留 10 GB 左右（镜像构建期会拉取并编译前端资源）。

```bash
make env      # 从模板生成 docker/.env，按需改站点名和密码
make build    # 构建同时包含 erpnext + crm 的镜像（首次约 15-25 分钟）
make up       # 启动，首次会自动建站并装应用
make logs     # 跟踪建站进度
```

建站完成后：

| 应用 | 地址 |
| --- | --- |
| ERPNext | http://localhost:8080/app |
| Frappe CRM | http://localhost:8080/crm |

默认账号 `Administrator`，密码取自 `docker/.env` 里的 `ADMIN_PASSWORD`（模板默认 `admin`）。

`make help` 可以看到全部命令。

## Windows

`make` 和 `.sh` 脚本在 PowerShell 里用不了，有两条路。

**A. 直接用 PowerShell**（需要 Docker Desktop 已启动）：

```powershell
Copy-Item docker\.env.example docker\.env    # 改掉里面的密码
.\docker\build-image.ps1                     # 等价于 make build

docker compose --env-file docker\.env -f docker\compose.yaml up -d
docker compose --env-file docker\.env -f docker\compose.yaml logs -f
```

对应 `make down` / `make clean` 的是：

```powershell
docker compose --env-file docker\.env -f docker\compose.yaml down
docker compose --env-file docker\.env -f docker\compose.yaml down -v   # 连数据卷一起删
```

注意 PowerShell 的续行符是反引号 `` ` ``，不是 bash 的 `\`；把命令写成一行最省事。

**B. 用 WSL2**（推荐）：在 WSL 里 clone 并执行，`make` 那套原样可用，性能也比 Windows 文件系统上好。Docker Desktop 开启 WSL 集成后，容器与 Windows 共用同一个引擎。

## 为什么要自己构建镜像

Frappe 的一个 bench 里装了哪些应用，是在**镜像构建期**就固定下来的 —— 容器起来之后再 `bench get-app` 不会保留到下次重建。而官方发布的 `frappe/erpnext` 镜像里只有 `frappe` 和 `erpnext`，没有 `crm`。

所以要让两个应用跑在同一个站点上，必须构建一个自定义镜像。本仓库的做法是走官方 [`frappe_docker`](https://github.com/frappe/frappe_docker) 的 layered Containerfile，应用清单由 `docker/apps.json` 提供：

```json
[
  { "url": "https://github.com/frappe/erpnext.git", "branch": "version-16" },
  { "url": "https://github.com/frappe/crm.git",     "branch": "main" }
]
```

`frappe_docker` 本身只作为构建上下文使用，由 `docker/build-image.sh` 按需浅克隆到 `.cache/`，不进版本库。

`apps.json` 是以 build secret 的形式挂进构建过程的，Docker 不会因为它的内容变化而让缓存失效，所以构建脚本用它的 SHA-256 作为 `CACHE_BUST`：改了应用清单就重装应用，没改则命中缓存。上游分支有新提交、需要强制重装时：

```bash
FORCE_REBUILD=1 ./docker/build-image.sh
```

## 仓库结构

```
docker/
  apps.json          # 镜像里要装的应用清单（erpnext + crm）
  compose.yaml       # 完整服务栈
  build-image.sh     # 构建自定义镜像
  build-image.ps1    # 同上，Windows PowerShell 版
  .env.example       # 配置模板，复制为 .env
scripts/
  bench-setup.sh     # 裸机 bench 安装（本地二次开发用）
docs/
  crm-selection.md   # CRM 选型报告
Makefile             # 常用命令封装
```

`docker/compose.yaml` 起的服务与官方 `frappe_docker` 生产编排一致：`backend`、`frontend`(nginx)、`websocket`、`scheduler`、两个队列 worker，加上 `db`(MariaDB)、`redis-cache`、`redis-queue`。另有两个一次性任务：`configurator` 写入 db/redis 配置，`create-site` 首次建站并装应用（站点已存在则跳过，可重复执行）。

## 常用操作

```bash
make shell                                   # 进 backend 容器
make bench CMD="--site erp.localhost list-apps"   # 跑 bench 命令
make backup                                  # 备份站点（含文件）
make down                                    # 停服务，保留数据
make clean                                   # 停服务并删除数据卷（清空数据）
```

## 升级

改 `docker/apps.json` 里的分支或 tag，然后：

```bash
./docker/build-image.sh
make down && make up
make bench CMD="--site erp.localhost migrate"
```

`migrate` 会执行两个应用的数据库变更。**升级前先 `make backup`。**

## 本地开发

需要改 CRM 或 ERPNext 源码时，Docker 方案不合适（应用固化在镜像里），改用裸机 bench。

**前置版本要求比多数教程写的高**，装之前先对一遍，否则会在 `bench init` 中途失败：

| 依赖 | 要求 | 说明 |
| --- | --- | --- |
| Python | **>=3.14,<3.15** | frappe v16 的 `requires-python`。3.13 会在装 frappe 时报 `SyntaxError` |
| Node | **>=24** | frappe v16 的 `engines`。低版本 yarn 直接拒绝安装 |
| MariaDB | >=10.6 | 需要 `utf8mb4` / `utf8mb4_unicode_ci` |
| Redis | 任意近期版本 | bench 自管两个实例（11000 / 13000） |
| `uv` | 必需 | bench 5.31+ 用它建 venv |
| `cron` | 必需 | `bench init` 会调 `crontab`，缺了会在最后一步失败 |

系统没有 Python 3.14 时，用 uv 装一个最省事：

```bash
uv python install 3.14
```

然后：

```bash
pip install frappe-bench
bench init --frappe-branch version-16 \
  --python "$(uv python find 3.14)" frappe-bench
cd frappe-bench
DB_ROOT_PASSWORD=<你的 MariaDB root 密码> \
  /path/to/scripts/bench-setup.sh erp.localhost
bench start
```

ERPNext 首次打开 `/app` 会进入初始设置向导（语言 / 时区 / 货币 / 公司），走完才能用；Frappe CRM 的 `/crm` 不依赖这个向导，装完即可用。

> `bench new-site` 一旦中途失败（比如网络或证书问题），会留下一个**半初始化的站点目录** —— 货币等基础数据没导入，但目录已存在。此时 `bench-setup.sh` 的「站点已存在」判断会跳过重建，接着装 ERPNext 就会报 `Could not find Default Currency: INR`。遇到这个报错，先 `bench drop-site <站点> --db-root-password <密码> --force` 再重跑。

## 版本

| 组件 | 版本 |
| --- | --- |
| ERPNext | `version-16` 分支 |
| Frappe CRM | `main` 分支（最新 tag v1.81.1） |
| Frappe Framework | `version-16` |
| MariaDB | 11.8 |
| Redis | 6.2 |

Frappe CRM 声明兼容 frappe `>=15.0.0,<17.0.0`，与 v16 框架匹配。

## 许可证

本仓库自身只包含部署配置（compose、脚本、文档），不含任何上游源码，许可证由你自行决定。

所部署的 ERPNext 和 Frappe CRM 均为 **AGPL-3.0** —— 以 SaaS 形式对外提供服务时需注意其网络分发条款，详见 [`docs/crm-selection.md`](docs/crm-selection.md#许可证提示)。
