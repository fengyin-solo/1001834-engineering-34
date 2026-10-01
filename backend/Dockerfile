FROM python:3.12-slim
WORKDIR /srv/app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
# 启动前先自检：缺依赖、配置错误、数据文件异常会在日志里分类报出来，而不是莫名退出
CMD ["sh", "-c", "python -m app.doctor && exec uvicorn app.main:app --host 0.0.0.0 --port 8000"]
