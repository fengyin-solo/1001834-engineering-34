# 城市地下管网巡检养护平台

面向城市给排水与燃气管网的管段建档、检查井阀门、巡查巡检、内窥检测、缺陷修复与压力流量监测的一体化养护后台。

这是一个前后端分离的管理平台：前端 Vue 3 + Vite + TypeScript，后端 FastAPI（Python）。
两边各自独立启动，前端 dev server 已关掉自动打开页面，启动后按终端打印的地址手工打开。

## 目录结构

```text
.
├── frontend/                 Vue 3 + Vite + TypeScript 前端
│   ├── src/views/            每个业务模块一个页面
│   ├── src/api/              统一请求封装
│   ├── src/stores/           会话与筛选状态
│   └── vite.config.ts        dev server 配置（open: false）
├── backend/                  FastAPI（Python） 后端
│   ├── app/routers/          每个业务模块一组接口
│   ├── app/services/         业务规则与状态流转
│   ├── app/store.py          数据仓库（SQLite 持久化，接口与原内存版一致）
│   ├── app/database.py       SQLite 连接与建表
│   └── app/bootstrap.py      建库 / 幂等灌数 / 状态查询（python -m app.bootstrap）
├── scripts/                  一键编排：setup.sh / dev.sh / doctor.sh / lib.sh
├── .env.example              配置唯一来源模板（首次 setup 复制为 .env）
├── Makefile                  make setup / dev / doctor 等入口
└── docker-compose.yml        端口/配置取自 .env，数据走命名卷，带健康检查
```

## 启动

### 一条命令（推荐）

```bash
make setup
```

等价于 `./scripts/setup.sh`，会依次执行：**环境预检 → 生成配置 → 装依赖 → 建库灌示例数据 →（容器）构建 → 启动 → 健康检查**，
每一步都打印可看懂的结果，失败会提示具体是缺工具、依赖还是环境变量，并可直接重跑（各步幂等、可续）。

- 装了 Docker：自动走容器（`docker compose up --build`）；没有 Docker：自动走本地进程。
- 强制方式：`make setup-local` / `make setup-docker`；只准备不启动：`./scripts/setup.sh --no-start`。
- 起不来分不清原因时先体检：`make doctor`（工具链 / 配置 / 依赖 / 数据库 / 端口 / 服务状态逐项报告）。

数据默认落在 SQLite（`backend/data/app.sqlite3`，容器里是命名卷 `backend-data`）：
**示例数据只补空模块，重跑 setup、重启、换机器/容器都不会覆盖已有数据**。需要恢复出厂示例：`make db-reset CONFIRM=--yes`。

### 配置：只有一个来源

所有端口、地址、跨域都在仓库根目录的 **`.env`**（首次 setup 自动从 `.env.example` 复制，已有则不覆盖）。
本地脚本、Vite、后端、docker compose 统一读它，代码与 Dockerfile 里不再写死环境相关地址：

| 变量 | 含义 | 默认 |
| --- | --- | --- |
| `BACKEND_HOST` / `BACKEND_PORT` | 后端监听 | `127.0.0.1` / `8000` |
| `FRONTEND_HOST` / `FRONTEND_PORT` | 前端监听 | `127.0.0.1` / `5173` |
| `CORS_ORIGINS` | 后端跨域白名单（空格/逗号分隔，留空按前端端口自动放行本机） | 空 |
| `DATABASE_PATH` | SQLite 文件路径，留空用默认；`:memory:` 为纯内存调试 | `backend/data/app.sqlite3` |
| `VITE_PROXY_TARGET` | 本地 Vite 代理后端地址（容器内自动指向 `backend:8000`） | `http://127.0.0.1:8000` |
| `VITE_API_BASE` | 前端直连后端地址，留空走同源代理 | 空 |

### 容器方式

```bash
make setup-docker     # 构建并后台启动；构建失败可重跑（镜像层缓存复用，依赖安装带重试）
docker compose logs -f
docker compose down
```

容器入口会先幂等建库灌数再起服务；两个服务都带健康检查，前端等后端健康后才启动。

### 本地方式 / 原习惯（均保留）

```bash
# 一键准备后的后台服务管理
make dev               # 后台起前后端（幂等）；make dev-stop / dev-status / dev-logs

# 原来的前台分别启动方式，照旧可用（会自动加载根 .env）
cd backend && ./run.sh
cd frontend && npm run dev
```

健康检查：`curl http://127.0.0.1:8000/api/health`（返回含 `storage: sqlite` 与模块数）。
前端默认监听 `http://127.0.0.1:5173/`，dev server 不自动开浏览器；`/api` 由 Vite 代理到后端。

> 换机器/容器后若残留了别平台的 `.venv` 或 `node_modules`（典型表现：软链接失效、esbuild `Exec format error`、
> rollup 找不到原生模块），setup 会自检并自动重建，无需手工删目录。

## 业务模块

| 模块 | 目录 | 业务对象 | 主要字段 |
| --- | --- | --- | --- |
| 管段档案 | `pipe` | 管段 | 管段编号、管道类别、起点井号 |
| 检查井 | `manhole` | 检查井 | 井编号、所在道路、井盖类别 |
| 阀门井室 | `valve` | 阀门 | 阀门编号、阀门类别、所在管段 |
| 泵站设施 | `pumpstation` | 泵站 | 泵站编号、泵站名称、服务区域 |
| 巡查任务 | `patrol` | 巡查单 | 巡查单号、巡查路线、巡查人员 |
| 缺陷登记 | `defect` | 缺陷记录 | 缺陷编号、所在管段、缺陷类别 |
| 内窥检测 | `cctv` | 检测报告 | 检测编号、检测管段、检测设备 |
| 修复施工 | `repair` | 修复单 | 修复单号、关联缺陷、修复方式 |
| 压力监测 | `pressure` | 压力记录 | 监测编号、监测点位、监测时段 |
| 流量监测 | `flow` | 流量记录 | 监测编号、监测断面、监测时段 |
| 泄漏排查 | `leak` | 排查记录 | 排查编号、排查区域、排查方式 |
| 清淤疏浚 | `dredge` | 清淤单 | 清淤单号、清淤管段、淤积厚度 |
| 养护材料 | `material` | 养护材料 | 材料编号、材料名称、规格型号 |
| 养护机械 | `equip` | 养护机械 | 机械编号、机械名称、机械型号 |
| 占道许可 | `traffic` | 占道许可 | 许可编号、申请单位、占道位置 |
| 公众诉求 | `complaint` | 诉求记录 | 诉求编号、诉求来源、诉求内容 |
| 养护资金 | `fund` | 资金记录 | 资金编号、费用类别、项目名称 |
| 管网档案 | `archive` | 档案记录 | 档案编号、关联管段、档案类别 |

## 约定

- 每个模块的前端页面在 `frontend/src/views/<模块>/index.vue`，后端接口在
  `backend/app/routers/<模块>.py`，业务规则在 `backend/app/services/<模块>.py`。
- 列表接口统一返回 `{ items, total, page, size }`，动作接口统一返回 `{ ok, message }`。
- 状态流转只允许在 `app/services` 里改，路由层不做业务判断。
