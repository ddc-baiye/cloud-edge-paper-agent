# PaperAgent OPEA Cloud

This directory contains the **OPEA-native cloud orchestration layer** used by the PaperAgent AI for Good competition edition.

The local edge workflow remains responsible for privacy-sensitive writing assistance on the user's AI PC. The cloud workflow is decomposed into OPEA MicroServices and composed as an OPEA MegaService for enterprise literature retrieval and grounded question answering.

## Why OPEA is used here

PaperAgent maps its cloud RAG workflow to OPEA's modular service model instead of wrapping the existing Python function with an OPEA label:

```text
Question
  |
  v
PaperAgent OPEA MegaService :7008
  |
  |  OPEA ServiceOrchestrator
  v
PaperAgent Retriever MicroService :7011
  |  ServiceType.RETRIEVER
  |  output: OPEA SearchedDoc
  v
PaperAgent Prompt MicroService :7012
  |  ServiceType.PROMPT_TEMPLATE
  |  output: OPEA ChatCompletionRequest
  v
Official OPEA LLM TextGen :9000
  |  ServiceType.LLM
  |  OpeaTextGenService
  v
Grounded academic answer
```

The MegaService builds this runtime DAG:

```text
paperagent-retriever -> paperagent-prompt -> opea-service@llm
```

The custom retriever produces the standard OPEA `SearchedDoc` data model. The custom prompt component turns that retrieval result into OPEA's standard OpenAI-style `ChatCompletionRequest`. This explicitly sends the official OPEA TextGen component through `/chat/completions`, which is compatible with modern OpenAI-compatible chat providers.

## Components

| Component | OPEA role | Port | Implementation |
| --- | --- | ---: | --- |
| `paperagent-retriever` | `ServiceType.RETRIEVER` | 7011 | Custom PaperAgent OPEA MicroService |
| `paperagent-prompt` | `ServiceType.PROMPT_TEMPLATE` | 7012 | Custom PaperAgent OPEA MicroService |
| `opea-llm` | `ServiceType.LLM` | 9000 | Official `opea/llm-textgen` / `OpeaTextGenService` |
| `paperagent-megaservice` | `ServiceType.GATEWAY`, MegaService | 7008 | OPEA `ServiceOrchestrator` |

Only the synthetic competition corpus is shipped in Git. Runtime PDF-derived records remain in ignored/runtime storage.

## Start with Docker Compose

Copy the safe environment template:

```bash
cd CLOUD/opea
cp .env.example .env
```

Edit `.env` and provide your OpenAI-compatible endpoint, model ID and API key:

```dotenv
LLM_ENDPOINT=https://api.deepseek.com
LLM_MODEL_ID=your-model-id
OPENAI_API_KEY=your-key
```

`LLM_ENDPOINT` should be the provider root URL **without a trailing `/v1`**, because the official OPEA TextGen service appends the OpenAI-compatible API prefix.

Start the OPEA cloud pipeline:

```bash
docker compose --env-file .env up -d --build
```

Inspect services:

```bash
docker compose ps
```

All four containers have OPEA HTTP health checks. The MegaService waits until the Retriever, Prompt Builder and LLM services are healthy before it starts.

## Verify the OPEA topology

OPEA health endpoint:

```bash
curl http://localhost:7008/v1/health_check
```

PaperAgent topology endpoint:

```bash
curl http://localhost:7008/v1/topology
```

Expected flow:

```text
paperagent-retriever -> paperagent-prompt -> opea-service@llm
```

Call the PaperAgent MegaService:

```bash
curl -X POST http://localhost:7008/v1/paperagent \
  -H "Content-Type: application/json" \
  -d '{"text":"How can an edge-cloud academic assistant protect private drafts while using cloud literature intelligence?"}'
```

Run the repository smoke test:

```bash
python smoke_test.py
```

The smoke test verifies `/v1/topology`, checks the exact OPEA DAG, calls `/v1/paperagent`, validates the `OPEA` framework marker and rejects an empty model answer.

## Connect the existing Gradio cloud UI

Run the normal PaperAgent cloud UI with:

```bash
export OPEA_GATEWAY_URL=http://localhost:7008
```

On Windows PowerShell:

```powershell
$env:OPEA_GATEWAY_URL = "http://localhost:7008"
```

When this variable is present, `CLOUD/src/app.py` sends academic questions to the OPEA MegaService first. If the OPEA cloud service is temporarily unavailable, the UI automatically falls back to the original compatibility path so the demo remains usable.

## Enterprise extension path

The current competition integration deliberately keeps the topology small and auditable. It can be extended with standard OPEA components without changing the edge API:

```text
DataPrep -> Embedding -> Vector Store
                       |
Question -> Retriever -> Rerank -> Prompt -> Guardrail -> LLM
                                           ^
                                           |
                                  ServiceOrchestrator
```

Good next-stage additions are OPEA DataPrep for document ingestion, an embedding/vector retrieval backend for larger enterprise corpora, and OPEA Guardrails for prompt-injection/PII controls.

## Security

- `.env` is local-only and must never be committed.
- The repository contains no LLM API key or MinerU token.
- Model credentials are injected through environment variables.
- Original/private paper corpora are excluded from the competition repository.
- See the root `SECURITY.md` and `DATA_POLICY.md`.
