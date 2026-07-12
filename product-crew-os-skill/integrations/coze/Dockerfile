FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PCO_RUNTIME_BIND=0.0.0.0 \
    PCO_RUNTIME_PORT=8787 \
    PCO_RUNTIME_WORKSPACE=/data/workspace \
    PCO_RUNTIME_EXPORT_ROOT=/data/exports \
    PCO_EMBEDDING_PROVIDER=local_open_source_bge_small_zh \
    PCO_BGE_MODEL=BAAI/bge-small-zh-v1.5

COPY product-crew-os-skill/runtime/requirements-langgraph.txt /tmp/requirements-langgraph.txt

RUN apt-get update \
  && apt-get install -y --no-install-recommends sqlite3 ca-certificates \
  && python -m pip install --no-cache-dir -r /tmp/requirements-langgraph.txt \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY product-crew-os-skill /app/product-crew-os-skill

VOLUME ["/data"]
EXPOSE 8787

CMD ["python", "/app/product-crew-os-skill/runtime/pco_coze_bridge.py"]
