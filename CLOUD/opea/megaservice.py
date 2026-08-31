"""OPEA MegaService for the PaperAgent cloud RAG workflow.

Topology:
    PaperAgent Retriever (custom OPEA MicroService)
        -> OPEA LLM TextGen (official OPEA MicroService)
        -> PaperAgent MegaService response

The edge-side OpenVINO/NPU workflow remains independent. This module is the
enterprise cloud orchestration layer used for the AI for Good OPEA challenge.
"""

import os
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field

from comps import (
    CustomLogger,
    MicroService,
    ServiceOrchestrator,
    ServiceRoleType,
    ServiceType,
    opea_microservices,
    register_microservice,
)
from comps.cores.proto.docarray import LLMParams

logger = CustomLogger("paperagent-opea-megaservice")


def _env_int(name: str, default: int) -> int:
    try:
        return max(1, int(os.getenv(name, str(default))))
    except (TypeError, ValueError):
        return default


GATEWAY_PORT = _env_int("PAPERAGENT_OPEA_GATEWAY_PORT", 7008)
RETRIEVER_HOST = os.getenv("PAPERAGENT_RETRIEVER_HOST", "paperagent-retriever")
RETRIEVER_PORT = _env_int("PAPERAGENT_RETRIEVER_PORT", 7011)
LLM_HOST = os.getenv("PAPERAGENT_LLM_HOST", "opea-llm")
LLM_PORT = _env_int("PAPERAGENT_LLM_PORT", 9000)
DEFAULT_MODEL = os.getenv("LLM_MODEL_ID", "")


class PaperAgentRequest(BaseModel):
    text: str = Field(min_length=1, description="Academic question for the cloud RAG pipeline")
    model: Optional[str] = None
    temperature: float = Field(default=0.2, ge=0.0, le=2.0)
    max_tokens: int = Field(default=1024, ge=1, le=8192)


class PaperAgentResponse(BaseModel):
    answer: str
    framework: str = "OPEA"
    pipeline: list[str] = [
        "paperagent-retriever",
        "opea-service@llm",
        "paperagent-megaservice",
    ]
    raw: Optional[Dict[str, Any]] = None


retriever = MicroService(
    name="paperagent-retriever",
    service_type=ServiceType.RETRIEVER,
    host=RETRIEVER_HOST,
    port=RETRIEVER_PORT,
    endpoint="/v1/retrieval",
    use_remote_service=True,
)

llm = MicroService(
    name="opea-service@llm",
    service_type=ServiceType.LLM,
    host=LLM_HOST,
    port=LLM_PORT,
    endpoint="/v1/chat/completions",
    use_remote_service=True,
)

orchestrator = ServiceOrchestrator()
orchestrator.add(retriever).add(llm)
orchestrator.flow_to(retriever, llm)


def _extract_answer(payload: Any) -> str:
    if payload is None:
        return ""
    if isinstance(payload, str):
        return payload
    if isinstance(payload, dict):
        if isinstance(payload.get("text"), str):
            return payload["text"]
        choices = payload.get("choices") or []
        if choices:
            first = choices[0]
            if isinstance(first, dict):
                if isinstance(first.get("text"), str):
                    return first["text"]
                message = first.get("message") or {}
                if isinstance(message, dict) and isinstance(message.get("content"), str):
                    return message["content"]
        for key in ("answer", "content", "response"):
            if isinstance(payload.get(key), str):
                return payload[key]
    return str(payload)


@register_microservice(
    name="paperagent-megaservice",
    service_role=ServiceRoleType.MEGASERVICE,
    service_type=ServiceType.GATEWAY,
    endpoint="/v1/paperagent",
    host="0.0.0.0",
    port=GATEWAY_PORT,
    input_datatype=PaperAgentRequest,
    output_datatype=PaperAgentResponse,
    description="PaperAgent OPEA MegaService: enterprise academic document assistant",
)
async def paperagent_mega_service(input: PaperAgentRequest) -> PaperAgentResponse:
    llm_params = LLMParams(
        model=input.model or DEFAULT_MODEL or None,
        stream=False,
        temperature=input.temperature,
        max_tokens=input.max_tokens,
        max_new_tokens=input.max_tokens,
    )
    result_dict, runtime_graph = await orchestrator.schedule(
        {"text": input.text},
        llm_parameters=llm_params,
    )
    final_outputs = orchestrator.get_all_final_outputs(result_dict, runtime_graph)
    payload = next(iter(final_outputs.values()), {})
    answer = _extract_answer(payload)

    logger.info(
        f"PaperAgent MegaService completed: question_chars={len(input.text)}, "
        f"answer_chars={len(answer)}"
    )
    return PaperAgentResponse(
        answer=answer,
        raw=payload if isinstance(payload, dict) else None,
    )


# Add a lightweight topology endpoint to make the OPEA composition observable.
gateway = opea_microservices["paperagent-megaservice"]


@gateway.app.get("/v1/topology")
async def topology():
    return {
        "framework": "OPEA",
        "architecture": "MicroServices + ServiceOrchestrator + MegaService",
        "services": [
            {
                "name": "paperagent-retriever",
                "type": "RETRIEVER",
                "endpoint": f"http://{RETRIEVER_HOST}:{RETRIEVER_PORT}/v1/retrieval",
                "implementation": "custom PaperAgent OPEA MicroService",
            },
            {
                "name": "opea-service@llm",
                "type": "LLM",
                "endpoint": f"http://{LLM_HOST}:{LLM_PORT}/v1/chat/completions",
                "implementation": "official OPEA LLM TextGen MicroService",
            },
        ],
        "flow": ["paperagent-retriever", "opea-service@llm"],
    }


if __name__ == "__main__":
    logger.info(f"Starting PaperAgent OPEA MegaService on port {GATEWAY_PORT}")
    opea_microservices["paperagent-megaservice"].start()
