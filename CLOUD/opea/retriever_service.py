"""PaperAgent domain retriever implemented as an OPEA MicroService.

This service reuses the sanitized PaperAgent JSONL corpus and the existing
lexical retrieval logic. It exposes the standard OPEA retrieval endpoint and
returns ``SearchedDoc`` for the downstream PaperAgent prompt MicroService.
"""

import os
import sys
from pathlib import Path
from typing import Any, Dict

CLOUD_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = CLOUD_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from chat_bot import lexical_select, load_papers  # noqa: E402
from comps import (  # noqa: E402
    CustomLogger,
    SearchedDoc,
    ServiceType,
    TextDoc,
    opea_microservices,
    register_microservice,
)

logger = CustomLogger("paperagent-opea-retriever")


def _env_int(name: str, default: int) -> int:
    try:
        return max(1, int(os.getenv(name, str(default))))
    except (TypeError, ValueError):
        return default


PORT = _env_int("PAPERAGENT_RETRIEVER_PORT", 7011)
TOP_K = _env_int("PAPERAGENT_TOP_K", 3)
MAX_TEXT_CHARS = _env_int("PAPERAGENT_RETRIEVER_TEXT_CHARS", 5000)


def _query_from_doc(doc: TextDoc) -> str:
    text = doc.text
    if isinstance(text, list):
        return "\n".join(str(item) for item in text if item is not None).strip()
    return str(text or "").strip()


def _paper_context(paper: Dict[str, Any]) -> str:
    title = str(paper.get("title") or "Untitled")
    authors = str(paper.get("authors") or "")
    summary = str(paper.get("summary") or "")
    body = str(paper.get("original_text") or "")[:MAX_TEXT_CHARS]
    return (
        f"Title: {title}\n"
        f"Authors: {authors}\n"
        f"Summary: {summary}\n"
        f"Paper text excerpt:\n{body}"
    ).strip()


@register_microservice(
    name="paperagent-retriever",
    service_type=ServiceType.RETRIEVER,
    endpoint="/v1/retrieval",
    host="0.0.0.0",
    port=PORT,
    input_datatype=TextDoc,
    output_datatype=SearchedDoc,
    description="PaperAgent academic paper retriever for the OPEA cloud RAG pipeline",
)
async def retrieve_papers(input: TextDoc) -> SearchedDoc:
    query = _query_from_doc(input)
    if not query:
        return SearchedDoc(retrieved_docs=[], initial_query="", top_n=1)

    papers = load_papers()
    selected = lexical_select(query, papers, limit=TOP_K)
    docs = [TextDoc(text=_paper_context(paper)) for paper in selected]

    logger.info(
        f"PaperAgent OPEA retrieval: query_chars={len(query)}, "
        f"corpus={len(papers)}, selected={len(docs)}"
    )

    return SearchedDoc(
        retrieved_docs=docs,
        initial_query=query,
        top_n=max(1, len(docs)),
    )


if __name__ == "__main__":
    logger.info(f"Starting PaperAgent OPEA retriever on port {PORT}")
    opea_microservices["paperagent-retriever"].start()
