FROM python:3.13.5-slim AS builder

WORKDIR /app

COPY requirements.txt ./
RUN pip wheel -w /wheelhouse -r requirements.txt


FROM python:3.13.5-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NIA_TODO_HOST=auto \
    NIA_TODO_PORT=8753 \
    NIA_TODO_DATA_DIR=/data \
    NIA_TODO_DB=nia-todo.db

WORKDIR /app

COPY --from=builder /wheelhouse ./wheelhouse
COPY requirements.txt ./
RUN pip install --no-cache-dir --no-index --find-links=wheelhouse -r requirements.txt \
    && rm -rf wheelhouse

COPY . .
RUN install -m 755 scripts/nia-todo-admin-password-reset.sh /usr/local/bin/nia-todo-admin-password-reset \
    && mkdir -p /data \
    && useradd -m -u 10001 nia-todo \
    && chown -R nia-todo:nia-todo /app /data \
    && ls -la /app/web/downloads/

USER nia-todo
EXPOSE 8753
VOLUME ["/data"]

CMD ["./start.sh"]