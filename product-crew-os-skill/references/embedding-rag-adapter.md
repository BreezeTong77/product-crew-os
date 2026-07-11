# Embedding / RAG Adapter

本文件定义 Product Crew OS 接入 embedding 和 RAG 的最小机制。它服务于意图识别、SOP 命中、Skill 命中、子 Agent 召唤和项目记忆检索，不替代主控教练、Stage Gate 或用户决策。

## 1. 设计目标

Embedding Adapter 只做三件事：

1. 在输入范围门内，与规则/别名并行检索相似 SOP、stage、skill 和角色边界。
2. 在需要复用项目经验时，检索用户授权进入 Project Workspace 的 artifact、decision、review item 和风险记录。
3. 记录每次检索证据，方便 badcase 复盘。

它不负责：

- 绕过输入范围门的硬退出判断。
- 把非产品任务强行归入 Product Crew OS。
- 根据相似案例自动通过 Stage Gate。
- 把项目材料写入公共规则包。
- 替用户采纳、拒绝、暂缓或关闭评审。

## 2. Namespace 隔离

| Namespace | Scope | 内容 | 默认状态 | 可进入公共包 |
| --- | --- | --- | --- | --- |
| `pco_rules` | `product_rule_memory` | 44 SOP、stage taxonomy、skill router、stage-boundary-matrix、badcase、eval cases | 开启 | 是 |
| `project_{id}` | `project_memory` | artifact、decision-log、review-items、risk-log、source-ledger | 用户授权后开启 | 否 |
| `user_overlay` | `user_preference_memory` | 用户偏好、常用纠错、个人工作方式 | 用户授权后开启 | 否 |
| `team_style_overlay` | `team_style_memory` | 团队风格、角色关注点摘要、同事反馈模式 | 用户授权后开启 | 否 |

公共发布包只能内置 `pco_rules`。任何真实公司材料、真实项目材料、用户偏好和团队风格都必须留在独立 workspace 或 overlay 中。

## 3. 检索链路

```text
Input Scope Gate
-> hard non-product exit check
-> exact rule / alias match + pco_rules local/embedding retrieval in parallel
-> hybrid rerank
-> confidence gap check
-> route decision or clarification
-> skill / role / artifact execution
-> retrieval ledger
```

如果输入明确命中天气、翻译、闲聊、股票汇率等硬性非产品任务，embedding query 不得执行。其他模糊输入允许先检索公共 `pco_rules`，用于判断是否可能命中 44 SOP；`project_{id}`、`user_overlay`、`team_style_overlay` 等私有 namespace 必须等用户授权后才可检索。

## 3.1 数据进入 RAG 前的区分与抽取

RAG 不是把所有文件直接丢进向量库。Product Crew OS 先区分来源类型，再决定抽取方式：

| Source Type | 处理方式 | 是否需要 OCR |
| --- | --- | --- |
| Markdown / YAML / JSON | 结构化解析，保留 heading、path、artifact version | 否 |
| 截图 / 图片 | OCR 抽取文字、置信度、页码、bbox | 是 |
| PDF | 先读文本层；文本层缺失或置信度低时 OCR | 条件触发 |
| Word / PPT / Excel | 优先文档解析；嵌入图片再 OCR | 条件触发 |
| 音频 / 会议录音 | ASR 转写后再进入证据结构化 | 否 |

OCR 主路径使用 `PaddleOCR`，原因是中文截图、PDF、版面结构和 Markdown/JSON 输出更适合产品材料。`Tesseract` 作为轻量 fallback，只在 PaddleOCR 不可用或宿主限制时使用。OCR 输出必须至少包含：

- `ocr_text`
- `ocr_confidence`
- `page_index`
- `bbox_json`
- `language_hint`
- `source_ref`

发布包提供 `runtime/source_extractor.rb` 和 `runtime/setup-local-ocr.sh`，但不把宿主尚未安装的 OCR 引擎说成已可用。引擎不可用、语言包缺失、OCR 返回空文本或 provider 输出无法解析时，Runtime 必须返回 `runtime_blocked` / extraction error，不能写出伪造的文本或置信度。只有实际 OCR 返回的字段才会写入 RAG 元数据。

OCR 置信度低于配置阈值时，只能作为低置信证据进入索引；涉及 Stage Gate 时必须提示用户复核，不能把低置信 OCR 当成确定事实。

## 3.2 语义结构化切分与 overlap

Chunk 切分采用 `semantic_structured_overlap`，不是固定字符数硬切。顺序是：

```text
artifact_type
-> markdown_heading
-> yaml_json_path
-> table_block
-> paragraph
-> sentence
```

默认目标 chunk 约 520 个中文字符，允许 220-900 字符区间；相邻 chunk 保留约 15% overlap，最少 80 字符，最多 160 字符。每个 chunk 必须保留父级标题、section path、artifact version、source_ref 和 content_hash。

这样做是为了避免两个常见坏情况：

- 固定长度切分把“阶段门 / 角色 / 风险 / 决策”切散，导致召回片段看似相关但不能用。
- 完全不 overlap 时，问题和答案、标题和正文被切到不同 chunk，命中率不稳定。

Chunk ID 使用：

```text
sha256(namespace + source_ref + section_path + content_hash)
```

同一来源内容没变时不重复 embedding；内容变更后只重建受影响 source 的 chunks。

## 3.3 默认开源 Embedding 模型

默认本地开源 embedding provider 选择：

```text
BAAI/bge-small-zh-v1.5
```

选择理由：

- 中文检索优先，适合 Product Crew OS 的中文 artifact、截图 OCR、会议纪要和项目材料。
- 512 维，小模型，适合本地批处理，精度不追求最大但足够做 SOP/项目记忆召回。
- MIT 许可，适合开源发布包说明。
- 支持 Sentence-Transformers / FlagEmbedding / Transformers 接入。

默认 batch size 为 32，最大 128；向量归一化后进入向量库。查询短句可加中文检索 instruction，passage/chunk 不加 instruction。

`local_hash_dry_run` 只用于 CI smoke，不是真实 embedding，不能作为用户可用能力或 Stage Gate 依据。真实默认 provider 是 `local_open_source_bge_small_zh`。

## 3.4 向量库选择

默认向量库选：

```text
SQLite + sqlite-vec + FTS5
```

原因：

- Product Crew OS 当前是 portable skill 包，单文件 SQLite 更适合本地项目 workspace。
- `sqlite-vec` 可以在 SQLite 内做向量检索，不需要额外服务。
- FTS5 可保留关键词检索，和向量召回做 hybrid rerank。
- 所有 source_ref、namespace、consent_ref、pii_level、artifact version 都能和 Project Workspace 放在同一套本地账本里。

团队版或大规模共享 workspace 后续可以接 Qdrant、pgvector 或 LanceDB，但 v0.1 默认不引入服务型向量数据库。

## 3.5 批处理、增量更新与清理

索引写入必须走 batch job，不允许一边聊天一边静默散写：

```text
source_ref + content_hash + embedding_model -> idempotency_key
```

增量更新规则：

- `content_hash` 未变化：跳过 embedding。
- `content_hash` 变化：只重切和重嵌该 source。
- `artifact_version` 变化：保留旧版本 source_ref，新版本单独入库。
- 用户撤回授权：删除对应 namespace/source，并写 maintenance audit event。
- 来源删除：先 soft delete chunks，再按 TTL 清理。

维护任务：

- 每周清理 stale / orphan chunks。
- 每月或 schema 变更后重建索引。
- 失败 job 保留 14 天用于 badcase 复盘。
- stale chunk 超过 30 天后 vacuum / compact。

## 3.6 数据来源与可观测性

每条可检索内容必须同时进入：

- source ledger：来源、owner、scope、confidence、consent。
- embedding_documents：文档级 source_ref / hash / namespace。
- embedding_chunks：chunk 文本、结构路径、OCR 信息、embedding provider/model。
- embedding_retrieval_events：每次查询的 candidates、score_breakdown、selected item、rejected_reason。

必须监控：

| 指标 | 目的 |
| --- | --- |
| `rag_recall_at_1 / rag_recall_at_3` | 看正确 SOP / artifact 是否被召回 |
| `rag_precision_at_3` | 看前三候选里噪声是否过多 |
| `rag_mrr` | 看正确答案排序是否靠前 |
| `retrieval_latency_p50_ms / p95_ms` | 看检索是否拖慢主控教练 |
| `embedding_batch_latency_ms` | 看批处理成本 |
| `ocr_low_confidence_rate` | 看 OCR 是否污染证据 |
| `source_trace_rate` | 看候选是否可追溯 |
| `namespace_isolation_violations` | 看是否混入项目/用户私有材料 |
| `stale_chunk_rate` | 看索引是否过期 |
| `index_update_failure_rate` | 看增量更新是否稳定 |

召回率和准确率必须分开看：召回率回答“正确材料有没有被找回来”，准确率回答“返回的候选里有多少真的有用”。两者都不达标时，不允许把 RAG 候选作为 Stage Gate 依据。

## 4. Adapter Contract

每个 embedding provider 必须实现同一组输入输出：

```json
{
  "query": "帮我判断现在该写 PRD 还是先做验证",
  "namespace": "pco_rules",
  "top_k": 5,
  "allowed_scopes": ["product_rule_memory"],
  "blocked_scopes": ["project_memory", "user_preference_memory", "team_style_memory"]
}
```

输出：

```json
{
  "retrieval_mode": "embedding_rag",
  "provider": "local_open_source_bge_small_zh",
  "candidate_routes": [
    {
      "stage_id": "request_triage",
      "score": 0.82,
      "source_ref": "tests/prompt-eval-cases.yaml#S01_request_triage"
    }
  ],
  "confidence_gap": 0.18,
  "source_refs": ["tests/prompt-eval-cases.yaml#S01_request_triage"]
}
```

Smoke 环境可以使用 `local_hash_dry_run` 验证索引契约，但必须明确标记 `real_embedding_performed=false`，不能把它算作真实 embedding provider。

## 5. Hybrid Rerank

最终 route score 不应只看向量相似度。建议使用：

```text
route_score =
  0.45 * rule_score +
  0.35 * vector_score +
  0.10 * source_priority +
  0.10 * recent_feedback_score
```

低置信规则：

- `confidence_gap < 0.12`：必须澄清，不自动推进。
- `template_degraded_rate > 0`：可以继续产出 artifact，但不能算 skill 正常命中。
- Required / Triggered role 缺席：必须标记 `pending`、`runtime_blocked` 或进入 badcase。

## 6. Schema

最小数据库结构见：

- `runtime/db/embedding-rag-schema.sql`

核心表：

- `embedding_documents`
- `embedding_chunks`
- `embedding_vector_indexes`
- `rag_ingestion_jobs`
- `embedding_retrieval_events`
- `rag_retrieval_quality_metrics`
- `rag_maintenance_events`

每条长期可检索内容必须带：

- `namespace`
- `scope`
- `source_ref`
- `source_type`
- `extraction_method`
- `content_hash`
- `pii_level`
- `consent_ref`
- `public_package_allowed`

## 7. 测试门禁

接入 embedding 前，必须先通过 dry-run：

```bash
ruby product-crew-os-skill/tests/run-embedding-rag-dry-run.rb
```

dry-run 验证：

- `pco_rules` namespace 可以被索引，并可在输入范围门内辅助首轮路由。
- 硬性非产品任务不会触发检索；模糊任务只允许检索公共 `pco_rules`，不能碰私有 namespace。
- 每个 candidate 有 source_ref。
- `rag_stage_hit_at_1` 和 `rag_stage_hit_at_3` 达到配置阈值。
- `false_positive_domain_entry_rate` 为 0。
- 真实项目材料不会进入公共规则索引。

RAG ingestion contract 验证：

```bash
ruby product-crew-os-skill/tests/run-rag-ingestion-contract.rb
```

它验证 OCR、语义 overlap chunk、开源 embedding、SQLite vector store、batch indexing、incremental update、maintenance 和 monitoring 是否都有可检查契约。

## 8. 真实 Provider 接入边界

真实 embedding provider 默认是本地开源 `BAAI/bge-small-zh-v1.5`；向量库可以是 `sqlite-vec`、pgvector、LanceDB 或其他本地/团队部署方案，但必须满足：

- 支持 namespace filter。
- 支持 source_ref 回传。
- 支持项目级删除或重建索引。
- 不把 query 或 chunk 静默写入第三方长期存储，除非用户授权。
- 网络或 provider 不可用时，回退到 local SOP retrieval，而不是跳过路由证据。

## 9. 本地开源 BGE Provider

真实本地 provider 使用 `BAAI/bge-small-zh-v1.5`。推荐安装方式：

```bash
python3 -m pip install sentence-transformers
ruby product-crew-os-skill/tests/run-local-open-source-embedding-provider-contract.rb
```

也可以使用 `FlagEmbedding`：

```bash
python3 -m pip install FlagEmbedding
ruby product-crew-os-skill/tests/run-local-open-source-embedding-provider-contract.rb
```

只有当 contract 返回：

- `provider = local_open_source_bge_small_zh`
- `model` 包含 `bge-small-zh`
- `embedding_dim > 0`
- `real_embedding_performed = true`

才能宣称本地 embedding 真实可用。

如果依赖或模型不可用，必须返回 `runtime_blocked_missing_local_model`。这不是 PASS，也不能被主控教练说成“已经接入 embedding”。
