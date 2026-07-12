"""Python adapters used by the LangGraph control plane.

Adapters return evidence only. They never mutate stage state, choose a Gate,
write agent memory, or invoke reviewers. Those actions remain graph nodes.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import yaml


class RuntimeBlocked(RuntimeError):
    """A dependency is missing; callers must not turn this into success."""


class AdapterError(RuntimeError):
    """An adapter returned malformed or unusable output."""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:16]}"


def _sha(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _tokens(value: str) -> set[str]:
    raw = value.lower()
    latin = re.findall(r"[a-z0-9_]{2,}", raw)
    han = "".join(re.findall(r"[\u4e00-\u9fff]+", raw))
    grams = [han[index : index + 2] for index in range(max(0, len(han) - 1))]
    return set(latin + grams)


def _cosine(left: Iterable[float], right: Iterable[float]) -> float:
    left_values = list(left)
    right_values = list(right)
    numerator = sum(a * b for a, b in zip(left_values, right_values))
    left_norm = math.sqrt(sum(value * value for value in left_values))
    right_norm = math.sqrt(sum(value * value for value in right_values))
    return numerator / (left_norm * right_norm) if left_norm and right_norm else 0.0


class LocalHashDryRunEmbedding:
    """Useful only for smoke tests. Its output is explicitly not real embedding."""

    model = "local_hash_dry_run"

    def __init__(self, dim: int = 256):
        self.dim = dim

    def available(self) -> bool:
        return True

    def embed(self, text: str) -> Dict[str, Any]:
        vector = [0.0] * self.dim
        for token in _tokens(text):
            vector[int(_sha(token), 16) % self.dim] += 1.0
        norm = math.sqrt(sum(value * value for value in vector))
        if norm:
            vector = [round(value / norm, 8) for value in vector]
        return {
            "provider": "local_hash_dry_run",
            "model": self.model,
            "embedding_dim": self.dim,
            "real_embedding_performed": False,
            "runtime_status": "smoke_only_not_user_runtime",
            "vector": vector,
        }

    def embed_batch(self, texts: Iterable[str]) -> List[Dict[str, Any]]:
        return [self.embed(text) for text in texts]


class LocalOpenSourceBGEEmbedding:
    """Actual local BGE execution through sentence-transformers or FlagEmbedding."""

    def __init__(self, model: Optional[str] = None, python_bin: Optional[str] = None):
        self.model = model or os.environ.get("PCO_BGE_MODEL", "BAAI/bge-small-zh-v1.5")
        self.python_bin = python_bin or os.environ.get("PCO_EMBEDDING_PYTHON", sys.executable)

    def available(self) -> bool:
        try:
            result = subprocess.run(
                [self.python_bin, "-c", "import importlib.util; raise SystemExit(0 if (importlib.util.find_spec('sentence_transformers') or importlib.util.find_spec('FlagEmbedding')) else 1)"],
                capture_output=True,
                text=True,
                timeout=15,
            )
            return result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def embed(self, text: str) -> Dict[str, Any]:
        return self.embed_batch([text])[0]

    def embed_batch(self, texts: Iterable[str]) -> List[Dict[str, Any]]:
        if not self.available():
            raise RuntimeBlocked("runtime_blocked_missing_local_model: install sentence-transformers or FlagEmbedding and download the configured BGE model")
        script = """
import json, sys
payload=json.load(sys.stdin)
model_name=payload['model']
texts=payload['texts']
try:
    from sentence_transformers import SentenceTransformer
    model=SentenceTransformer(model_name)
    vectors=model.encode(texts, normalize_embeddings=True).tolist()
    runtime='sentence_transformers'
except Exception as first:
    try:
        from FlagEmbedding import FlagModel
        model=FlagModel(model_name, use_fp16=False)
        vectors=model.encode(texts, normalize_embeddings=True).tolist()
        runtime='FlagEmbedding'
    except Exception as second:
        print(json.dumps({'error': f'sentence_transformers: {first}; FlagEmbedding: {second}'}), file=sys.stderr)
        raise SystemExit(2)
print(json.dumps({'model': model_name, 'provider_runtime': runtime, 'vectors': vectors}))
"""
        try:
            result = subprocess.run(
                [self.python_bin, "-c", script],
                input=json.dumps({"model": self.model, "texts": [str(text) for text in texts]}),
                capture_output=True,
                text=True,
                timeout=int(os.environ.get("PCO_BGE_TIMEOUT_SECONDS", "120")),
            )
        except subprocess.TimeoutExpired as error:
            raise RuntimeBlocked("runtime_blocked_timeout: local BGE embedding timed out") from error
        if result.returncode != 0:
            raise RuntimeBlocked(f"runtime_blocked_local_bge_failed: {result.stderr.strip()}")
        try:
            payload = json.loads(result.stdout)
            vectors = payload["vectors"]
        except (KeyError, json.JSONDecodeError) as error:
            raise AdapterError("local BGE response was not valid JSON vectors") from error
        if not all(isinstance(vector, list) and vector for vector in vectors):
            raise AdapterError("local BGE returned an empty vector")
        return [
            {
                "provider": "local_open_source_bge_small_zh",
                "model": payload.get("model", self.model),
                "embedding_dim": len(vector),
                "real_embedding_performed": True,
                "provider_runtime": payload.get("provider_runtime", ""),
                "vector": vector,
            }
            for vector in vectors
        ]


def build_embedding_provider(name: Optional[str] = None) -> LocalHashDryRunEmbedding | LocalOpenSourceBGEEmbedding:
    resolved = (name or os.environ.get("PCO_EMBEDDING_PROVIDER", "local_open_source_bge_small_zh")).lower()
    if resolved in {"local_hash_dry_run", "dry_run", "smoke"}:
        return LocalHashDryRunEmbedding()
    if resolved in {"local_open_source_bge_small_zh", "bge_small_zh", "bge"}:
        return LocalOpenSourceBGEEmbedding()
    raise AdapterError(f"unknown embedding provider: {resolved}")


class SourceExtractor:
    """Structured-file extraction plus real PaddleOCR/Tesseract fallback."""

    IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}
    TEXT_TYPES = {".md": "markdown", ".markdown": "markdown", ".yaml": "yaml", ".yml": "yaml", ".json": "json", ".txt": "text"}
    OCR_THRESHOLD = 0.72

    def __init__(self, python_bin: Optional[str] = None, tesseract_bin: Optional[str] = None):
        self.python_bin = python_bin or os.environ.get("PCO_OCR_PYTHON", sys.executable)
        self.tesseract_bin = tesseract_bin or os.environ.get("PCO_TESSERACT_BIN", "tesseract")

    def capability(self) -> Dict[str, Any]:
        return {
            "paddleocr": self._paddle_available(),
            "tesseract": shutil.which(self.tesseract_bin) is not None,
            "supported_source_types": ["markdown", "yaml", "json", "text", "screenshot", "image"],
            "ocr_threshold": self.OCR_THRESHOLD,
        }

    def extract(self, file_path: str | Path, source_ref: str, source_type: str = "auto", language_hint: str = "chi_sim+eng") -> Dict[str, Any]:
        path = Path(file_path).expanduser().resolve()
        if not path.is_file():
            raise AdapterError(f"source file does not exist: {path}")
        resolved_type = self._source_type(path) if source_type == "auto" else source_type
        stat = path.stat()
        base = {
            "source_ref": source_ref,
            "source_type": resolved_type,
            "source_hash": hashlib.sha256(path.read_bytes()).hexdigest(),
            "source_uri_hash": _sha(source_ref),
            "source_mtime": datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat(),
            "source_path_basename": path.name,
        }
        if resolved_type in {"markdown", "yaml", "json", "text"}:
            content = path.read_text(encoding="utf-8")
            if not content.strip():
                raise AdapterError(f"source file is empty: {path}")
            return base | {
                "content": content,
                "extraction_method": "direct_structured_parser",
                "extraction_confidence": 1.0,
                "ocr_engine": "",
                "ocr_confidence": None,
                "ocr_page_index": -1,
                "ocr_bbox_json": {},
                "gate_evidence_eligible": True,
                "gate_evidence_reason": "structured_source",
            }
        if resolved_type not in {"screenshot", "image"}:
            raise RuntimeBlocked(f"runtime_blocked_source_type_not_implemented: {resolved_type}")
        result = self._paddle_extract(path, language_hint) if self._paddle_available() else None
        result = result or self._tesseract_extract(path, language_hint)
        confidence = float(result["ocr_confidence"])
        return base | result | {
            "extraction_method": "ocr",
            "extraction_confidence": confidence,
            "gate_evidence_eligible": confidence >= self.OCR_THRESHOLD,
            "gate_evidence_reason": "ocr_confidence_sufficient" if confidence >= self.OCR_THRESHOLD else "ocr_confidence_below_threshold",
        }

    def _source_type(self, path: Path) -> str:
        if path.suffix.lower() in self.IMAGE_EXTENSIONS:
            return "screenshot"
        return self.TEXT_TYPES.get(path.suffix.lower(), "unknown")

    def _paddle_available(self) -> bool:
        try:
            result = subprocess.run([self.python_bin, "-c", "import paddleocr"], capture_output=True, timeout=15)
            return result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def _paddle_extract(self, path: Path, language_hint: str) -> Optional[Dict[str, Any]]:
        script = """
import json, sys
from paddleocr import PaddleOCR
path=sys.argv[1]
lang='ch' if 'chi_sim' in sys.argv[2] else 'en'
engine=PaddleOCR(use_angle_cls=True, lang=lang)
result=engine.ocr(path, cls=True)
words=[]
for page_index,page in enumerate(result or []):
    for line in page or []:
        bbox,pair=line
        text,confidence=pair
        if str(text).strip(): words.append({'text':str(text).strip(),'confidence':float(confidence),'bbox':bbox,'page_index':page_index})
if not words: raise SystemExit(2)
print(json.dumps({'content':' '.join(word['text'] for word in words),'ocr_engine':'PaddleOCR','ocr_confidence':sum(word['confidence'] for word in words)/len(words),'ocr_page_index':words[0]['page_index'],'ocr_bbox_json':{'words':words},'language_hint':sys.argv[2]},ensure_ascii=False))
"""
        result = subprocess.run([self.python_bin, "-c", script, str(path), language_hint], capture_output=True, text=True, timeout=180)
        if result.returncode != 0:
            raise AdapterError(f"PaddleOCR failed: {result.stderr.strip()}")
        return json.loads(result.stdout)

    def _tesseract_extract(self, path: Path, language_hint: str) -> Dict[str, Any]:
        if not shutil.which(self.tesseract_bin):
            raise RuntimeBlocked("runtime_blocked_missing_ocr_engine: install PaddleOCR or Tesseract with requested language data")
        result = subprocess.run([self.tesseract_bin, str(path), "stdout", "-l", language_hint, "--psm", "6", "tsv"], capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            raise RuntimeBlocked(f"runtime_blocked_tesseract_failed: {result.stderr.strip()}")
        words: List[Dict[str, Any]] = []
        for row in result.stdout.splitlines()[1:]:
            fields = row.split("\t")
            if len(fields) != 12 or not fields[11].strip():
                continue
            try:
                confidence = float(fields[10]) / 100.0
            except ValueError:
                continue
            if confidence < 0:
                continue
            words.append({"text": fields[11].strip(), "confidence": confidence, "bbox": {"x": int(fields[6]), "y": int(fields[7]), "width": int(fields[8]), "height": int(fields[9])}, "page_index": int(fields[1]) - 1})
        if not words:
            raise AdapterError("Tesseract returned no recognized words")
        return {
            "content": " ".join(word["text"] for word in words),
            "ocr_engine": "Tesseract",
            "ocr_confidence": sum(word["confidence"] for word in words) / len(words),
            "ocr_page_index": words[0]["page_index"],
            "ocr_bbox_json": {"words": words},
            "language_hint": language_hint,
        }


class PersistentRagStore:
    """SQLite, source-aware RAG with structured chunks and incremental updates."""

    DEFAULT_NAMESPACE = "pco_rules"
    DEFAULT_SCOPE = "product_rule_memory"

    def __init__(self, db_path: str | Path, provider: Optional[Any] = None):
        self.db_path = Path(db_path).expanduser().resolve()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.provider = provider or build_embedding_provider()
        with self._connection() as conn:
            conn.executescript(
                """
                PRAGMA journal_mode = WAL;
                CREATE TABLE IF NOT EXISTS pco_rag_documents (
                  doc_id TEXT PRIMARY KEY, namespace TEXT NOT NULL, scope TEXT NOT NULL, source_ref TEXT NOT NULL,
                  title TEXT NOT NULL, content_hash TEXT NOT NULL, index_hash TEXT NOT NULL, extraction_method TEXT NOT NULL,
                  extraction_confidence REAL NOT NULL, pii_level TEXT NOT NULL, consent_ref TEXT NOT NULL, metadata_json TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS pco_rag_chunks (
                  chunk_id TEXT PRIMARY KEY, doc_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, section_path TEXT NOT NULL,
                  text TEXT NOT NULL, vector_json TEXT NOT NULL, embedding_provider TEXT NOT NULL, embedding_model TEXT NOT NULL,
                  metadata_json TEXT NOT NULL, created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS pco_rag_events (
                  event_id TEXT PRIMARY KEY, event_type TEXT NOT NULL, namespace TEXT NOT NULL, details_json TEXT NOT NULL, created_at TEXT NOT NULL
                );
                """
            )

    def upsert_documents(self, namespace: str, scope: str, documents: List[Dict[str, Any]], consent_ref: str = "") -> Dict[str, Any]:
        self._validate_scope(namespace, scope, consent_ref)
        prepared = [self._normalize_document(item, namespace, scope, consent_ref) for item in documents]
        changed = [item for item in prepared if self._is_changed(item)]
        if not changed:
            return {"created": 0, "updated": 0, "skipped": len(prepared), "provider": getattr(self.provider, "model", "")}
        chunks = [(document, chunk) for document in changed for chunk in self._structured_chunks(document)]
        embeddings = self.provider.embed_batch([chunk["text"] for _, chunk in chunks])
        now = _now()
        created = updated = 0
        cursor = 0
        with self._connection() as conn:
            for document in changed:
                exists = conn.execute("SELECT 1 FROM pco_rag_documents WHERE doc_id=?", (document["doc_id"],)).fetchone() is not None
                conn.execute(
                    "INSERT INTO pco_rag_documents(doc_id,namespace,scope,source_ref,title,content_hash,index_hash,extraction_method,extraction_confidence,pii_level,consent_ref,metadata_json,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(doc_id) DO UPDATE SET content_hash=excluded.content_hash,index_hash=excluded.index_hash,extraction_method=excluded.extraction_method,extraction_confidence=excluded.extraction_confidence,pii_level=excluded.pii_level,consent_ref=excluded.consent_ref,metadata_json=excluded.metadata_json,updated_at=excluded.updated_at",
                    (document["doc_id"], namespace, scope, document["source_ref"], document["title"], document["content_hash"], document["index_hash"], document["extraction_method"], document["extraction_confidence"], document["pii_level"], consent_ref, json.dumps(document["metadata"], ensure_ascii=False), now),
                )
                conn.execute("DELETE FROM pco_rag_chunks WHERE doc_id=?", (document["doc_id"],))
                document_chunks = [chunk for doc, chunk in chunks if doc["doc_id"] == document["doc_id"]]
                for chunk in document_chunks:
                    embedding = embeddings[cursor]
                    cursor += 1
                    conn.execute(
                        "INSERT INTO pco_rag_chunks(chunk_id,doc_id,chunk_index,section_path,text,vector_json,embedding_provider,embedding_model,metadata_json,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)",
                        (chunk["chunk_id"], document["doc_id"], chunk["chunk_index"], chunk["section_path"], chunk["text"], json.dumps(embedding["vector"]), embedding["provider"], embedding["model"], json.dumps(chunk["metadata"], ensure_ascii=False), now),
                    )
                created += 0 if exists else 1
                updated += 1 if exists else 0
            self._event(conn, "index_upsert", namespace, {"documents": len(changed), "chunks": len(chunks)})
        return {"created": created, "updated": updated, "skipped": len(prepared) - len(changed), "provider": embeddings[0]["provider"], "model": embeddings[0]["model"]}

    def retrieve(self, query: str, namespace: str = DEFAULT_NAMESPACE, top_k: int = 3, allowed_scopes: Optional[List[str]] = None, consent_ref: str = "", used_for: str = "sop_routing") -> Dict[str, Any]:
        self._validate_retrieval(namespace, consent_ref)
        embedding = self.provider.embed(query)
        permitted = set(allowed_scopes or [])
        with self._connection() as conn:
            rows = conn.execute("SELECT d.scope,d.source_ref,d.extraction_method,d.extraction_confidence,d.pii_level,d.consent_ref,d.metadata_json,c.chunk_id,c.section_path,c.text,c.vector_json,c.metadata_json FROM pco_rag_chunks c JOIN pco_rag_documents d ON d.doc_id=c.doc_id WHERE d.namespace=?", (namespace,)).fetchall()
            candidates = []
            for row in rows:
                if permitted and row["scope"] not in permitted:
                    continue
                if namespace != self.DEFAULT_NAMESPACE and row["consent_ref"] != consent_ref:
                    continue
                metadata = json.loads(row["metadata_json"])
                score = _cosine(embedding["vector"], json.loads(row["vector_json"]))
                eligible, reason = self._evidence_eligibility(namespace, row["extraction_method"], float(row["extraction_confidence"]), row["pii_level"])
                candidates.append({"chunk_id": row["chunk_id"], "stage_id": metadata.get("stage_id"), "case_id": metadata.get("case_id"), "score": round(score, 4), "vector_score": round(score, 4), "source_ref": row["source_ref"], "source_refs": [row["source_ref"]], "section_path": row["section_path"], "text": row["text"], "extraction_method": row["extraction_method"], "extraction_confidence": float(row["extraction_confidence"]), "pii_level": row["pii_level"], "gate_evidence_eligible": eligible, "gate_evidence_reason": reason})
            candidates.sort(key=lambda item: (-item["score"], item["source_ref"]))
            candidates = candidates[:top_k]
            self._event(conn, "retrieval", namespace, {"query_hash": _sha(query), "used_for": used_for, "candidates": candidates})
        return {"provider": embedding["provider"], "model": embedding["model"], "real_embedding_performed": embedding["real_embedding_performed"], "candidates": candidates, "source_refs": list(dict.fromkeys(ref for item in candidates for ref in item["source_refs"]))}

    def stats(self, namespace: str = DEFAULT_NAMESPACE) -> Dict[str, int]:
        with self._connection() as conn:
            docs = conn.execute("SELECT COUNT(*) FROM pco_rag_documents WHERE namespace=?", (namespace,)).fetchone()[0]
            chunks = conn.execute("SELECT COUNT(*) FROM pco_rag_chunks c JOIN pco_rag_documents d ON d.doc_id=c.doc_id WHERE d.namespace=?", (namespace,)).fetchone()[0]
        return {"documents": docs, "chunks": chunks}

    def _normalize_document(self, item: Dict[str, Any], namespace: str, scope: str, consent_ref: str) -> Dict[str, Any]:
        content = str(item.get("content", ""))
        if not content.strip():
            raise AdapterError("RAG document content is required")
        source_ref = str(item.get("source_ref", ""))
        if not source_ref:
            raise AdapterError("RAG source_ref is required")
        metadata = dict(item.get("metadata", {}))
        pii_level = str(metadata.get("pii_level", "public_rule" if namespace == self.DEFAULT_NAMESPACE else "unknown_unclassified"))
        method = str(item.get("extraction_method", "direct_structured_parser"))
        confidence = float(item.get("extraction_confidence", 1.0))
        content_hash = _sha(content)
        provider_identity = "|".join(
            [
                self.provider.__class__.__name__,
                str(getattr(self.provider, "model", "")),
                str(getattr(self.provider, "dim", "")),
            ]
        )
        return {"doc_id": _sha(f"{namespace}|{scope}|{source_ref}"), "namespace": namespace, "scope": scope, "source_ref": source_ref, "title": str(item.get("title", source_ref)), "content": content, "content_hash": content_hash, "index_hash": _sha(f"{content_hash}|{method}|{confidence}|{provider_identity}|{json.dumps(metadata, sort_keys=True, ensure_ascii=False)}"), "extraction_method": method, "extraction_confidence": confidence, "pii_level": pii_level, "metadata": metadata, "consent_ref": consent_ref}

    def _structured_chunks(self, document: Dict[str, Any]) -> List[Dict[str, Any]]:
        sections = []
        heading = document["title"]
        buffer: List[str] = []
        for line in document["content"].splitlines():
            if re.match(r"^#{1,6}\s+", line):
                if buffer:
                    sections.append((heading, "\n".join(buffer)))
                heading = re.sub(r"^#{1,6}\s+", "", line).strip()
                buffer = []
            else:
                buffer.append(line)
        if buffer:
            sections.append((heading, "\n".join(buffer)))
        if not sections:
            sections = [(heading, document["content"])]
        chunks = []
        for section_path, text in sections:
            for value in self._overlap_split(text):
                chunks.append({"chunk_id": _id("chunk"), "chunk_index": len(chunks), "section_path": section_path, "text": value, "metadata": document["metadata"]})
        return chunks

    @staticmethod
    def _overlap_split(text: str, maximum: int = 900, overlap: int = 120) -> List[str]:
        paragraphs = [item.strip() for item in re.split(r"\n{2,}", text) if item.strip()]
        chunks: List[str] = []
        current = ""
        for paragraph in paragraphs:
            if not current or len(current) + len(paragraph) + 2 <= maximum:
                current = f"{current}\n\n{paragraph}".strip()
            else:
                chunks.append(current)
                current = f"{current[-overlap:]}\n\n{paragraph}"
        if current:
            chunks.append(current)
        return chunks

    def _is_changed(self, document: Dict[str, Any]) -> bool:
        with self._connection() as conn:
            row = conn.execute("SELECT index_hash FROM pco_rag_documents WHERE doc_id=?", (document["doc_id"],)).fetchone()
        return not row or row["index_hash"] != document["index_hash"]

    def _validate_scope(self, namespace: str, scope: str, consent_ref: str) -> None:
        if namespace != self.DEFAULT_NAMESPACE and not consent_ref:
            raise RuntimeBlocked("private RAG namespace requires consent_ref")
        if namespace == self.DEFAULT_NAMESPACE and scope != self.DEFAULT_SCOPE:
            raise AdapterError("pco_rules must use product_rule_memory scope")

    def _validate_retrieval(self, namespace: str, consent_ref: str) -> None:
        if namespace != self.DEFAULT_NAMESPACE and not consent_ref:
            raise RuntimeBlocked("private RAG retrieval requires consent_ref")

    @staticmethod
    def _evidence_eligibility(namespace: str, method: str, confidence: float, pii_level: str) -> tuple[bool, str]:
        if namespace == PersistentRagStore.DEFAULT_NAMESPACE and pii_level == "public_rule":
            return True, "public_rule_namespace"
        if pii_level == "unknown_unclassified":
            return False, "pii_level_unclassified"
        if confidence < 0.72:
            return False, "extraction_confidence_below_threshold"
        return bool(method), "source_metadata_sufficient" if method else "extraction_method_missing"

    def _connection(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    @staticmethod
    def _event(connection: sqlite3.Connection, event_type: str, namespace: str, details: Dict[str, Any]) -> None:
        connection.execute("INSERT INTO pco_rag_events(event_id,event_type,namespace,details_json,created_at) VALUES(?,?,?,?,?)", (_id("ragevt"), event_type, namespace, json.dumps(details, ensure_ascii=False), _now()))


class SkillExecutionAdapter:
    """Executes a routed bundled Skill and returns raw, inspectable evidence only.

    This adapter deliberately has no API for changing Product Crew OS state. A
    caller receives an output, never a Stage/Gate/Agent decision. The graph is
    responsible for turning a successful execution into a signed receipt.
    """

    def __init__(self, skill_root: str | Path):
        self.skill_root = Path(skill_root).resolve()
        registry_path = self.skill_root / "config" / "skill-executor-registry.yaml"
        config = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
        self.registry = config.get("skills", {})
        self.defaults = config.get("defaults", {})
        self.bundled_catalog = self._load_bundled_catalog()
        self.bundled_implementation_count = len(list((self.skill_root / "third_party" / "skills").glob("*/SKILL.md")))

    def catalog_status(self) -> Dict[str, int]:
        """Expose packaged implementation coverage without claiming execution."""
        canonical = {
            key
            for key in self.bundled_catalog
            if not key.startswith(("alirez-", "aroy-", "assimovt-", "bmad-", "dean-", "phuryn-", "pop-", "pratik-", "turner-", "skill-"))
        }
        return {
            "bundled_implementations": self.bundled_implementation_count,
            "canonical_router_skills": len(canonical),
            "registered_drivers": len(self.registry),
        }

    def runtime_capabilities(self) -> Dict[str, Any]:
        """Inspect real local execution prerequisites without claiming success."""
        model = os.environ.get("PCO_SKILL_MODEL", str(self.defaults.get("ollama_model", "qwen2.5:3b")))
        base_url = os.environ.get("PCO_OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
        ollama = {"endpoint": base_url, "model": model, "status": "unreachable"}
        try:
            with urlopen(f"{base_url}/api/tags", timeout=3) as response:
                payload = json.loads(response.read().decode("utf-8"))
            available_models = {str(item.get("name", "")) for item in payload.get("models", [])}
            ollama["status"] = "ready" if model in available_models else "model_missing"
            ollama["available_models"] = sorted(available_models)
        except (URLError, HTTPError, TimeoutError, json.JSONDecodeError) as error:
            ollama["detail"] = str(error)

        pencil_path = shutil.which("pencil")
        pencil = {"status": "not_installed", "path": ""}
        if pencil_path:
            pencil = {"status": "installed_not_authenticated", "path": pencil_path}
            try:
                result = subprocess.run([pencil_path, "status"], capture_output=True, text=True, timeout=10)
                output = f"{result.stdout}\n{result.stderr}".lower()
                if result.returncode == 0 and "not authenticated" not in output:
                    pencil["status"] = "ready_requires_user_write_authorization"
            except (OSError, subprocess.TimeoutExpired) as error:
                pencil["detail"] = str(error)
        return {
            "bundled_skills": self.catalog_status(),
            "ollama": ollama,
            "pencil": pencil,
            "figma": {"status": "mcp_connector_required"},
        }

    def execute(self, skill_id: str, input_payload: Dict[str, Any]) -> Dict[str, Any]:
        entry = self.registry.get(skill_id)
        if not entry:
            bundled_source = self.bundled_catalog.get(skill_id)
            if bundled_source:
                return self._execute_ollama_prompt(skill_id, bundled_source, input_payload)
            return self._unavailable(skill_id, "skill_not_registered_for_execution")
        driver = entry.get("driver")
        if driver == "command":
            command_result = self._execute_command(skill_id, entry, input_payload)
            if command_result.get("execution_status") == "executed":
                return command_result
            bundled_source = self._bundled_source_for(skill_id, entry)
            if bundled_source:
                return self._execute_ollama_prompt(skill_id, bundled_source, input_payload, prior_attempt=command_result)
            return command_result
        if driver == "ollama_prompt":
            bundled_source = self._bundled_source_for(skill_id, entry)
            if bundled_source:
                return self._execute_ollama_prompt(skill_id, bundled_source, input_payload)
            return self._unavailable(skill_id, "ollama_skill_source_missing")
        if driver in {"host_callback_required", "mcp_required", "missing_capability"}:
            return self._deployment_required(skill_id, driver, entry.get("reason", ""), entry.get("deployment_notice", {}))
        return self._unavailable(skill_id, "unknown_driver")

    def _bundled_source_for(self, skill_id: str, entry: Dict[str, Any]) -> str:
        configured = str(entry.get("skill_source", "")).strip()
        if configured and (self.skill_root / configured).is_file():
            return configured
        return self.bundled_catalog.get(skill_id, "")

    def _execute_command(self, skill_id: str, entry: Dict[str, Any], input_payload: Dict[str, Any]) -> Dict[str, Any]:
        source = self.skill_root / entry["source"]
        if not source.is_file():
            return self._unavailable(skill_id, "driver_source_missing")
        try:
            arguments = self._command_arguments(entry.get("input_schema", ""), input_payload)
        except AdapterError as error:
            return self._unavailable(skill_id, f"invalid_input: {error}") | {
                "driver": "command",
                "source_ref": entry["source"],
                "execution_proof": {"driver_source": entry["source"], "not_executed_reason": str(error)},
            }
        command = [sys.executable, str(source), *arguments]
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        return {
            "skill_id": skill_id,
            "driver": "command",
            "execution_mode": "native_capability",
            "execution_status": "executed" if result.returncode == 0 else "failed",
            "output_type": entry.get("output_type", "markdown_draft"),
            "output_content": result.stdout,
            "stderr": result.stderr,
            "source_ref": entry["source"],
            "execution_proof": {
                "driver_source": entry["source"],
                "command_sha256": _sha("\0".join(command)),
                "executed_at": _now(),
                "exit_code": result.returncode,
            },
        }

    def _load_bundled_catalog(self) -> Dict[str, str]:
        """Read the published Skill catalogue instead of inventing a second map."""
        index = self.skill_root / "references" / "bundled-skill-index.md"
        if not index.is_file():
            return {}
        catalog: Dict[str, str] = {}
        pattern = re.compile(r"^\| `([^`]+)` \| `(third_party/skills/[^`]+)`")
        for line in index.read_text(encoding="utf-8").splitlines():
            match = pattern.match(line)
            if not match:
                continue
            skill_id, relative_dir = match.groups()
            path = self.skill_root / relative_dir / "SKILL.md"
            if path.is_file():
                # A Skill can have two bundled implementations. Keep the first
                # published choice until the router gains an explicit variant.
                catalog.setdefault(skill_id, str(path.relative_to(self.skill_root)))
                # The folder alias exposes every one of the 49 packaged skill
                # implementations for explicit use without changing the SOP
                # router's canonical 46 capability names.
                catalog.setdefault(Path(relative_dir).name, str(path.relative_to(self.skill_root)))
        return catalog

    def _execute_ollama_prompt(self, skill_id: str, source_ref: str, input_payload: Dict[str, Any], prior_attempt: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Run a bundled instruction Skill through a real local Ollama model.

        This is intentionally an actual HTTP call, not a local string stub. If
        Ollama/model deployment is absent it returns deployment_required, which
        LangGraph will block before the Stage Gate.
        """
        source = self.skill_root / source_ref
        if not source.is_file():
            return self._unavailable(skill_id, "bundled_skill_source_missing")
        model = os.environ.get("PCO_SKILL_MODEL", str(self.defaults.get("ollama_model", "qwen2.5:3b")))
        base_url = os.environ.get("PCO_OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
        prompt_limit = int(self.defaults.get("prompt_max_chars", 24000))
        instructions = source.read_text(encoding="utf-8")[:prompt_limit]
        prompt = (
            "你正在作为 Product Crew OS 的受控专业 Skill 执行工作。\n"
            "只完成下面 Skill 指令要求的专业分析或文档草稿。不要决定产品阶段、不要批准 Gate、"
            "不要写项目记忆、不要召唤或模拟其他 Agent。输出应直接可归档为 Markdown。\n\n"
            f"Skill ID: {skill_id}\n"
            f"Skill instructions:\n{instructions}\n\n"
            "Runtime input:\n"
            f"{json.dumps(input_payload, ensure_ascii=False, indent=2)[:prompt_limit]}\n"
        )
        request_payload = json.dumps({"model": model, "prompt": prompt, "stream": False}).encode("utf-8")
        request = Request(
            f"{base_url}/api/generate",
            data=request_payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urlopen(request, timeout=int(os.environ.get("PCO_SKILL_TIMEOUT_SECONDS", "180"))) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except (URLError, HTTPError, TimeoutError, json.JSONDecodeError) as error:
            return self._deployment_required(
                skill_id,
                "ollama_prompt",
                f"local Ollama execution failed: {error}",
                {
                    "title": "需要部署本地 Skill 模型",
                    "user_message": "该 Skill 已被 LangGraph 选中，但本机 Ollama 服务或模型不可用，因此没有伪造执行结果。",
                    "required_steps": ["启动 Ollama 服务", f"拉取模型 {model}", "确认 PCO_OLLAMA_URL 可访问", "重新运行该 SOP"],
                },
            )
        output = str(payload.get("response", "")).strip()
        if not output:
            return self._deployment_required(
                skill_id,
                "ollama_prompt",
                "local Ollama returned an empty skill output",
                {"title": "Skill 没有返回可归档输出", "user_message": "模型已响应但没有产出内容，本轮不能算 Skill 成功执行。", "required_steps": ["检查模型日志", "调整模型或输入后重试"]},
            )
        result = {
            "skill_id": skill_id,
            "driver": "ollama_prompt",
            "execution_mode": "external_workflow",
            "execution_status": "executed",
            "output_type": "markdown_draft",
            "output_content": output,
            "source_ref": source_ref,
            "execution_proof": {
                "driver_source": source_ref,
                "skill_source_sha256": _sha(source.read_text(encoding="utf-8")),
                "model": model,
                "endpoint": base_url,
                "executed_at": _now(),
                "response_sha256": _sha(output),
            },
        }
        if prior_attempt:
            result["execution_proof"]["prior_attempt"] = {
                "driver": prior_attempt.get("driver", ""),
                "execution_status": prior_attempt.get("execution_status", ""),
                "reason": prior_attempt.get("reason", ""),
            }
        return result

    @staticmethod
    def _command_arguments(schema: str, payload: Dict[str, Any]) -> List[str]:
        if schema == "assumption_list":
            assumptions = list(payload.get("assumptions", []))
            if not assumptions:
                raise AdapterError("assumptions is required")
            arguments = []
            for item in assumptions:
                missing = [key for key in ("statement", "category", "risk", "certainty") if not str(item.get(key, "")).strip()]
                if missing:
                    raise AdapterError(f"assumption fields missing: {', '.join(missing)}")
                try:
                    risk = float(item["risk"])
                    certainty = float(item["certainty"])
                except (TypeError, ValueError) as error:
                    raise AdapterError("assumption.risk and assumption.certainty must be numbers in [0, 1]") from error
                if not 0 <= risk <= 1 or not 0 <= certainty <= 1:
                    raise AdapterError("assumption.risk and assumption.certainty must be numbers in [0, 1]")
                arguments.extend(["--assumption", "|".join(str(item[key]) for key in ("statement", "category", "risk", "certainty"))])
            return arguments
        if schema == "experiment_sample_size":
            if not payload.get("baseline") or not payload.get("mde_absolute"):
                raise AdapterError("baseline and mde_absolute are required")
            result = ["--baseline", str(payload["baseline"]), "--mde-absolute", str(payload["mde_absolute"])]
            if payload.get("power"):
                result.extend(["--power", str(payload["power"])])
            if payload.get("daily_eligible_users"):
                result.extend(["--daily-eligible-users", str(payload["daily_eligible_users"])])
            return result
        raise AdapterError(f"unsupported input schema: {schema}")

    @staticmethod
    def _unavailable(skill_id: str, reason: str) -> Dict[str, Any]:
        return {"skill_id": skill_id, "execution_status": "unavailable", "reason": reason, "execution_proof": None}

    @staticmethod
    def _deployment_required(skill_id: str, driver: str, detail: str, notice: Dict[str, Any]) -> Dict[str, Any]:
        return {"skill_id": skill_id, "execution_status": "deployment_required", "reason": driver, "detail": detail, "must_notify_user": True, "deployment_notice": {"title": notice.get("title", "需要部署执行环境"), "user_message": notice.get("user_message", "该 Skill 尚未部署为可执行能力。"), "required_steps": list(notice.get("required_steps", [])), "authorization_required": notice.get("authorization_required") is True}, "execution_proof": None}
