# PaperAgent: OPEA-based Cloud-Edge Academic Intelligence

## 1. Problem and AI for Good Value

Academic writing and literature analysis increasingly depend on generative AI, but a single cloud-only workflow creates two practical problems: sensitive drafts may need to leave the user's device, while local-only models are not ideal for scalable literature retrieval and enterprise knowledge orchestration.

PaperAgent addresses this by separating tasks according to privacy and compute characteristics. Privacy-sensitive writing assistance runs locally on an AI PC, while literature retrieval and grounded academic question answering are composed as modular OPEA services. The result is an academic assistant that combines local data protection, open-source model inference, and cloud-native GenAI orchestration.

PaperAgent is designed for researchers, universities, R&D teams, and enterprise knowledge workers that need AI-assisted writing and literature understanding without forcing every task into the same execution environment.

## 2. Solution Overview

PaperAgent has two coordinated execution layers:

- **Edge AI layer**: Qwen3-8B INT4 OpenVINO runs on Intel NPU for grammar checking and academic polishing. HY-MT1.5-1.8B is prepared as OpenVINO INT4 and runs on CPU for academic translation.
- **OPEA cloud layer**: literature retrieval, prompt construction, LLM generation, orchestration, and grounded answer delivery are decomposed into OPEA MicroServices and composed by a MegaService.

```text
Academic Draft                         Academic Question
     |                                       |
     v                                       v
Edge AI PC                          PaperAgent OPEA MegaService
     |                                       |
     +-- Qwen3 / NPU                         v
     |   Grammar + Polish             Retriever MicroService
     |                                       |
     +-- HY-MT / CPU                         v
         Translation                  Prompt MicroService
                                             |
                                             v
                                      OPEA LLM TextGen
                                             |
                                             v
                                      Grounded Answer
```

Model weights are not committed to the source repository. The one-click deployment downloads the required runtime models automatically. ModelScope is the default source, with Hugging Face retained as a fallback.

## 3. OPEA-based Technical Architecture

PaperAgent implements an actual OPEA service composition rather than only calling an external API from a monolithic application.

| Layer | Implementation | OPEA Role |
| --- | --- | --- |
| Retrieval | `CLOUD/opea/retriever_service.py` | `ServiceType.RETRIEVER` MicroService |
| Prompt construction | `CLOUD/opea/prompt_service.py` | `ServiceType.PROMPT_TEMPLATE` MicroService |
| Generation | official `opea/llm-textgen` service | LLM MicroService |
| Orchestration | `CLOUD/opea/megaservice.py` | `ServiceOrchestrator` + MegaService |
| Application | Gradio/Vue/Flask + Nginx | User interaction and edge/cloud integration |

The OPEA runtime DAG is:

```text
paperagent-retriever
        |
        v
paperagent-prompt
        |
        v
opea-service@llm
        |
        v
PaperAgent MegaService
```

The retriever emits OPEA-compatible searched-document objects. The prompt service converts retrieved evidence into a chat-native request, and the MegaService exposes a unified API for the application layer.

## 4. Deployment and Reproducibility

The competition repository provides a single Windows entry point:

```powershell
.\deploy.bat
```

The deployment workflow performs:

1. Environment and runtime checks.
2. Model preparation from ModelScope by default.
3. Qwen3-8B INT4 OpenVINO download for Intel NPU.
4. HY-MT1.5-1.8B download and OpenVINO INT4 preparation for CPU translation.
5. Python/Node/Nginx environment preparation.
6. OPEA Docker Compose deployment.
7. Edge service, cloud UI, and unified Nginx startup.
8. Sensitive-source scan and runtime health verification.

For machines where ModelScope is temporarily unavailable, the model preparation script falls back to Hugging Face. Existing local models are reused automatically.

The repository contains only a synthetic paper record for demonstration. Real development corpora, runtime uploads, credentials, machine-specific paths, model weights, and internal network configuration are excluded.

## 5. Prototype Quality and Evaluation Focus

The recommended evaluation workflow is:

1. Deploy PaperAgent with `deploy.bat`.
2. Open the unified UI at `http://localhost:5000/`.
3. Test local grammar checking or polishing on the AI PC.
4. Test local academic translation with HY-MT.
5. Run a literature question through the OPEA RAG path.
6. Inspect the OPEA topology endpoint at `http://localhost:7008/v1/topology`.
7. Verify the service chain `retriever -> prompt -> llm` and the grounded answer returned by the MegaService.

PaperAgent is intentionally evaluated on functional integration, modularity, privacy-aware task placement, open-source reproducibility, and end-to-end prototype quality rather than unsupported synthetic performance claims.

## 6. Open-source Commitment

PaperAgent source code is released under the Apache License 2.0. Third-party frameworks and model weights remain subject to their respective upstream licenses. Model weights are downloaded from their official or maintained distribution sources during deployment and are not redistributed inside this repository.
