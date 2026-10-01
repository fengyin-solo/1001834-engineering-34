FROM python:3.12-slim
WORKDIR /srv/app

# 构建期可重试的依赖安装（--retries 应对抖动；镜像层缓存命中则直接跳过）
COPY requirements.txt ./
RUN pip install --no-cache-dir --retries 5 -r requirements.txt

COPY . .
RUN chmod +x ./docker-entrypoint.sh

# 运行参数全部来自环境变量（docker-compose 从根 .env 注入）
ENV BACKEND_HOST=0.0.0.0 \
    BACKEND_PORT=8000 \
    DATABASE_PATH=/srv/app/data/app.sqlite3

EXPOSE 8000
ENTRYPOINT ["./docker-entrypoint.sh"]

# 健康检查：区分"进程活着"与"应用没起来"
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
  CMD python -c "import os,urllib.request;urllib.request.urlopen('http://127.0.0.1:%s/api/health'%os.environ.get('BACKEND_PORT','8000'),timeout=2).read()" || exit 1
