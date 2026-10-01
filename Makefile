.PHONY: setup install seed doctor backend frontend build

# 一条命令完成全部准备：工具链检查、配置文件、依赖、示例数据、自检。
# 幂等可重试：重复执行不覆盖 .env、不重置已有数据；某步失败后重跑即可续跑。
setup:
	bash scripts/setup.sh

# 保留原有习惯：install 现在委托给幂等的 setup
install: setup

# 单独初始化/补齐示例数据（幂等，已有数据不动）
seed:
	cd backend && .venv/bin/python -m app.seed

# 启动前自检：缺依赖、配置错误、数据异常、端口占用分类报出
doctor:
	cd backend && .venv/bin/python -m app.doctor

# 前端构建（vue-tsc + vite build）；失败时修复后直接重跑本命令即可
build:
	cd frontend && npm run build

# 以下为原有启动方式，保持不变
backend:
	cd backend && ./run.sh

frontend:
	cd frontend && npm run dev
