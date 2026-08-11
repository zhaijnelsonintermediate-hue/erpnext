# Frappe / ERPNext 生态 CRM 选型报告

调研日期：2026-08-11

## 结论

**选 [Frappe CRM](https://github.com/frappe/crm)（`frappe/crm`）**，与 ERPNext 装在同一个 bench、同一个站点上。

理由概括为三点：

1. 它是 Frappe 官方出品并在自家业务上使用的产品，不是社区个人项目 —— 在这个生态里，「官方维护」几乎等同于「三年后还在更新」。
2. 它是独立应用而非 ERPNext 的一个模块，销售团队拿到的是一套为销售流程设计的界面，而不是 ERP 后台里的一堆列表页。
3. 它和 ERPNext 装在一起时共享同一套用户、权限和数据库，赢单之后转报价/订单不需要跨系统同步。

## 候选方案

生态里真正可选的只有两个，其余都不构成竞争。

### 候选一：Frappe CRM（`frappe/crm`）

| 项目 | 值 |
| --- | --- |
| 仓库 | https://github.com/frappe/crm |
| 维护方 | Frappe Technologies（官方） |
| 许可证 | AGPL-3.0 |
| Stars | 约 3.3k |
| 最新版本 | v1.81.1 |
| 稳定分支 | `main`（开发分支 `develop`） |
| 框架要求 | frappe `>=15.0.0,<17.0.0`、Python `>=3.10` |
| 前端 | Vue 3 SPA（Frappe UI），挂在 `/crm` 路由 |

发版节奏很密（tag 已经排到 v1.81.x，且 `pot_develop_*` 翻译分支按周滚动），是一个处于高频迭代中的活跃项目。

功能面：

- 线索（Lead）→ 商机（Deal）的转化流程，销售阶段可自定义
- Kanban 看板，拖拽推进阶段；列表视图支持自定义筛选、排序、列
- 线索/商机详情页聚合了活动记录、评论、备注、任务
- 通话集成：Twilio、Exotel（`twilio` 是它声明的直接 Python 依赖）
- WhatsApp 集成、邮件同步
- 与 ERPNext 对接：赢单后可推送生成报价单

### 候选二：ERPNext 内置 CRM 模块

ERPNext 自带 `crm` 模块，包含 Lead、Opportunity、Customer 等 DocType，运行在 Frappe Desk 界面里。

它的优势是与报价、销售订单、发票、项目的耦合最紧 —— 这些本来就是同一个应用里的 DocType，跳转和取数不需要任何集成工作。

它的问题在于：界面是通用的 Desk 后台，对销售人员不友好；对外部沟通渠道（WhatsApp、呼叫中心）没有开箱即用的支持，要自己在 Desk 里搭。

### 为什么没有候选三

生态里没有第三个值得认真评估的 CRM。Frappe 官方另外两个常被一起提到的产品都不是 CRM：

- **Frappe Helpdesk** —— 售后工单系统，解决的是已成交客户的支持问题，和销售管道无关
- **Gameplan** —— 团队协作/讨论工具

社区第三方 CRM 应用普遍存在维护中断、只兼容老版本框架的问题，不建议引入。

## 对比

| 维度 | Frappe CRM | ERPNext 内置 CRM 模块 |
| --- | --- | --- |
| 定位 | 专注销售管道的独立应用 | ERP 的一个模块 |
| 界面 | Vue 3 SPA，为销售场景定制 | Frappe Desk 通用后台 |
| 上手成本 | 低，销售人员看到的只有 CRM | 高，混在 ERP 菜单里 |
| 管道可视化 | Kanban 看板，拖拽推进 | 列表 + 报表为主 |
| WhatsApp / 通话 | 内置 | 需自建 |
| 邮件同步 | 内置 | 需配置 |
| 与财务/库存耦合 | 松，通过 ERPNext 完成开票和履约 | 紧，同一应用内直连 |
| 是否需要额外部署 | 需要，装一个额外应用 | 不需要，ERPNext 自带 |
| 独立于 ERPNext 使用 | 可以 | 不可以 |

## 选型建议

- **既要 ERP 又要像样的销售工具** —— 两个都装（本仓库采用的方案）。销售在 `/crm` 里跑管道，赢单后转到 ERPNext 出报价和发票。
- **只要销售管道，暂时不上 ERP** —— 只装 Frappe CRM。它不依赖 ERPNext。
- **销售流程极简，只是想在开票前记一笔线索** —— 直接用 ERPNext 内置模块，别引入额外应用。

## 本仓库的落地方式

两个应用装进**同一个 bench 的同一个站点**，而不是两套独立部署。这样做的直接好处是共享用户、权限体系和数据库，CRM 与 ERPNext 之间不需要任何数据同步机制。

代价是：一个 bench 里装哪些应用是在**镜像构建期**固定下来的，而官方发布的 `frappe/erpnext` 镜像不含 `crm`。所以本仓库不用官方镜像，而是通过 `docker/apps.json` + 官方 `frappe_docker` 的 layered Containerfile 自行构建一个同时包含两者的镜像。详见 [`../README.md`](../README.md)。

版本上固定为 ERPNext `version-16` 配 Frappe CRM `main`。CRM 声明兼容 frappe `>=15,<17`，因此与 v16 框架匹配。

## 许可证提示

Frappe CRM 与 ERPNext 均为 **AGPL-3.0**。以 SaaS 形式对外提供服务时，AGPL 的网络分发条款要求向使用者提供对应源码。仅内部自用不受影响。如果计划修改源码并对外提供服务，请先确认合规义务。

## 参考

- [frappe/crm - GitHub](https://github.com/frappe/crm)
- [Frappe CRM 官网](https://frappe.io/crm)
- [ERPNext CRM vs Frappe CRM: What's the Difference? - Frappe Blog](https://frappe.io/blog/frappe-crm/erpnext-crm-vs-frappe-crm-whats-the-difference)
- [What is the difference in CRM module in ERPNext and Frappe CRM app? - Frappe Forum](https://discuss.frappe.io/t/what-is-the-difference-in-crm-module-in-erpnext-and-frappe-crm-app/123592)
- [frappe/frappe_docker - 自定义镜像构建](https://github.com/frappe/frappe_docker)
