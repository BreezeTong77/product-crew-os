FROM ruby:3.3-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PCO_RUNTIME_BIND=0.0.0.0 \
    PCO_RUNTIME_PORT=8787 \
    PCO_RUNTIME_WORKSPACE=/data/workspace \
    PCO_RUNTIME_EXPORT_ROOT=/data/exports \
    PCO_STAGE_ROUTER_EMBEDDING=real \
    PCO_REQUIRE_REAL_EMBEDDING=1 \
    PCO_REQUIRE_REAL_SUBAGENTS=1 \
    PCO_COZE_SUBAGENT_DELEGATE=workflow_callback \
    PCO_EMBEDDING_PROVIDER=local_open_source_bge_small_zh \
    PCO_BGE_MODEL=BAAI/bge-small-zh-v1.5

RUN apt-get update \
  && apt-get install -y --no-install-recommends sqlite3 python3 python3-pip ca-certificates \
  && python3 -m pip install --no-cache-dir --break-system-packages sentence-transformers \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY product-crew-os-skill /app/product-crew-os-skill

VOLUME ["/data"]
EXPOSE 8787

CMD ["ruby", "/app/product-crew-os-skill/runtime/pco_coze_bridge.rb"]
