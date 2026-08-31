"""PaperAgent academic prompt builder as an OPEA PROMPT_TEMPLATE MicroService.

The official OPEA TextGen service accepts OpenAI-style ChatCompletionRequest.
This service converts the retriever's SearchedDoc into a chat request so the
cloud pipeline works with chat-completions-only OpenAI-compatible providers.
"""

import os

from comps import (
    CustomLogger,
    SearchedDoc,
    ServiceType,
    opea_microservices,
    register_microservice,
)
from comps.cores.proto.api_protocol import ChatCompletionRequest

logger = CustomLogger("paperagent-opea-prompt")


def _env_int(name: str, default: int) -> int:
    try:
        return max(1, int(os.getenv(name, str(default))))
    except (TypeError, ValueError):
        return default


PORT = _env_int("PAPERAGENT_PROMPT_PORT", 7012)
MAX_CONTEXT_CHARS = _env_int("PAPERAGENT_PROMPT_CONTEXT_CHARS", 14000)

SYSTEM_PROMPT = """You are PaperAgent, an enterprise academic literature assistant.
Answer the user's question using the retrieved paper context whenever evidence is available.
Requirements:
1. Clearly distinguish evidence found in retrieved documents from your own inference.
2. Do not fabricate paper titles, authors, experimental results, or citations.
3. If the retrieved context is insufficient, state the limitation explicitly.
4. Prefer concise, structured academic answers.
5. Answer in the same language as the user's question unless the user asks otherwise.
"""


def _context_from_search(input: SearchedDoc) -> str:
    parts = []
    for index, doc in enumerate(input.retrieved_docs or [], 1):
        text = doc.text
        if isinstance(text, list):
            text = "\n".join(str(item) for item in text)
        parts.append(f"[Retrieved Paper {index}]\n{str(text or '').strip()}")
    context = "\n\n".join(parts)
    return context[:MAX_CONTEXT_CHARS]


@register_microservice(
    name="paperagent-prompt",
    service_type=ServiceType.PROMPT_TEMPLATE,
    endpoint="/v1/prompt",
    host="0.0.0.0",
    port=PORT,
    input_datatype=SearchedDoc,
    output_datatype=ChatCompletionRequest,
    description="PaperAgent OPEA academic RAG prompt builder",
)
async def build_academic_prompt(input: SearchedDoc) -> ChatCompletionRequest:
    context = _context_from_search(input)
    question = str(input.initial_query or "").strip()

    if context:
        user_content = (
            f"User question:\n{question}\n\n"
            f"Retrieved paper context:\n{context}\n\n"
            "Please answer using the retrieved evidence."
        )
    else:
        user_content = (
            f"User question:\n{question}\n\n"
            "No relevant paper was retrieved from the current competition corpus. "
            "You may provide a general answer, but explicitly state that no supporting paper was retrieved."
        )

    logger.info(
        f"PaperAgent OPEA prompt: query_chars={len(question)}, "
        f"retrieved_docs={len(input.retrieved_docs or [])}, context_chars={len(context)}"
    )

    return ChatCompletionRequest(
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_content},
        ],
        stream=False,
        temperature=0.2,
        max_tokens=1024,
    )


if __name__ == "__main__":
    logger.info(f"Starting PaperAgent OPEA prompt service on port {PORT}")
    opea_microservices["paperagent-prompt"].start()
