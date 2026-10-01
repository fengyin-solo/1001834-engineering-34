# 城市地下管网巡检养护平台

面向城市给排水与燃气管网的管段建档、检查井阀门、巡查巡检、内窥检测、缺陷修复与压力流量监测的一体化养护后台。

这是一个前后端分离的管理平台：前端 Vue 3 + Vite + TypeScript，后端 FastAPI（Python）。
两边各自独立启动，前端 dev server 已关掉自动打开页面，启动后按终端打印的地址手工打开。

## 快速开始

一条命令完成全部准备（工具链检查、配置文件、前后端依赖、示例数据、自检）：

```bash
make setup
```

- 每一步都会打印做了什么、结果如何；失败时给出原因和处理建议。
- 命令是幂等的：重复执行不会覆盖 `.env`，也不会重置已录入的数据；
  某一步失败后，修复问题再跑一遍 `make setup` 即可续跑，已完成的步骤自动跳过。

然后按原来的习惯启动（两个终端）：

```bash
make backend    # 或 cd backend && ./run.sh
make frontend   # 或 cd frontend && npm run dev
```

健康检查：`curl http://127.0.0.1:8000/api/health`，
前端默认监听 `http://127.0.0.1:5173/`（dev server 不自动打开浏览器）。

## 配置：只有一处来源

所有环境相关配置（端口、跨域、接口代理、数据文件位置）统一以根目录 `.env` 为准，
模板与默认值在 `.env.example`。后端、前端 dev server、前端构建、docker compose 都从这里读，
改配置只动这一个文件。`make setup` 会在 `.env` 不存在时自动从模板生成。

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `BACKEND_HOST` / `BACKEND_PORT` | `127.0.0.1` / `8000` | 后端监听地址 |
| `FRONTEND_HOST` / `FRONTEND_PORT` | `127.0.0.1` / `5173` | 前端 dev server 地址 |
| `ALLOWED_ORIGINS` | 按前端端口自动生成 | 跨域白名单，逗号分隔 |
| `VITE_API_BASE` | 空（走 vite 代理） | 填完整地址则浏览器直连后端 |
| `VITE_PROXY_TARGET` | `http://127.0.0.1:$BACKEND_PORT` | vite 代理目标 |
| `DATA_FILE` | `backend/data/store.json` | 示例数据文件 |

## 数据：不再重来

示例数据落在 `DATA_FILE` 指定的 JSON 文件里（已 gitignore），重启、换机器、
重建容器都不用重录；写操作会自动落盘。相关命令：

```bash
make seed      # 幂等补齐缺失模块，已有数据原样保留
make doctor    # 启动前自检：缺依赖、配置错误、数据异常、端口占用分类报出
cd backend && .venv/bin/python -m app.seed --reset   # 确认要重建时才用
```

## 构建

```bash
make build     # vue-tsc 类型检查 + vite 构建；失败时修复后直接重跑即可
```

## 容器

```bash
make setup           # 先生成 .env（或手工 cp .env.example .env）
docker compose up --build
```

后端容器启动前会自动跑一遍自检，起不来时看日志就能分清是缺依赖、
配置错误还是数据文件异常；数据文件通过卷挂载在 `./backend/data`，容器重建不丢。

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
│   ├── app/store.py          数据仓库（JSON 文件持久化）
│   ├── app/seed.py           内置样例数据 + 幂等初始化命令
│   ├── app/doctor.py         启动前自检
│   └── data/                 示例数据文件（gitignore，自动生成）
├── scripts/setup.sh          make setup 的实现
├── .env.example              唯一配置来源的模板与默认值
├── .gitignore
└── docker-compose.yml
```

## 启动（原始手动方式）

准备动作已统一为 `make setup`（见上文"快速开始"）。如果只想手动装依赖：

### 后端

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
./run.sh
```

健康检查：`curl http://127.0.0.1:8000/api/health`

### 前端

```bash
cd frontend
npm install
npm run dev
```

前端默认监听 `http://127.0.0.1:5173/`，dev server 不会自动打开浏览器，
需要自己访问。`/api` 由 vite 代理到后端（目标地址以根目录 `.env` 为准）。

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
