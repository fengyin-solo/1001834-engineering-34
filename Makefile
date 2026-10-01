.PHONY: setup setup-local setup-docker install backend frontend dev dev-stop dev-status dev-logs doctor seed db-status db-reset clean

# ---- 一键流程 ----
setup:            ## 一条命令：预检→配置→装依赖→建库灌数→构建→启动→健康检查（自动选 docker/local）
	./scripts/setup.sh

setup-local:      ## 强制本地进程模式
	./scripts/setup.sh local

setup-docker:     ## 强制容器模式
	./scripts/setup.sh docker

doctor:           ## 环境体检：区分缺依赖还是环境变量/端口问题
	./scripts/doctor.sh

# ---- 本地服务管理 ----
dev:              ## 后台启动前后端（幂等）
	./scripts/dev.sh start

dev-stop:         ## 停止本地前后端
	./scripts/dev.sh stop

dev-status:       ## 查看进程与健康状态
	./scripts/dev.sh status

dev-logs:         ## 查看前后端日志
	./scripts/dev.sh logs

# ---- 数据（SQLite 持久化，seed 幂等不覆盖已有数据）----
seed:             ## 补充缺失模块的示例数据
	cd backend && .venv/bin/python -m app.bootstrap seed

db-status:        ## 查看数据库各模块行数
	cd backend && (.venv/bin/python -m app.bootstrap status 2>/dev/null || python3 -m app.bootstrap status)

db-reset:         ## 清空并重新灌入示例数据（需确认：make db-reset CONFIRM=--yes）
	cd backend && .venv/bin/python -m app.bootstrap reset $(CONFIRM)

# ---- 开发者原习惯：前台分别启动，完全保留 ----
install:          ## 原样保留：分别准备前后端依赖
	cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	cd frontend && npm install

backend:          ## 原样保留：前台启动后端（自动加载根 .env）
	cd backend && ./run.sh

frontend:         ## 原样保留：前台启动前端
	cd frontend && npm run dev

clean:            ## 清理本地虚拟环境与依赖（不动数据文件）
	rm -rf backend/.venv frontend/node_modules
