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
  v
PaperAgent Retriever MicroService :7011
  |  ServiceType.RETRIEVER
  |  output: OPEA SearchedDoc
  v
Official OPEA LLM TextGen :9000
  |  ServiceType.LLM
  |  OpeaTextGenService
  v
Grounded academic answer
```

The MegaService uses OPEA `ServiceOrchestrator` to build the runtime DAG:

```text
paperagent-retriever -> opea-service@llm
```

The custom retriever produces the standard OPEA `SearchedDoc` data model. The official OPEA LLM component accepts that document directly and builds the RAG prompt before invoking the configured OpenAI-compatible model endpoint.

## Components

| Component | OPEA role | Port | Implementation |
| --- | --- | ---: | --- |
| `paperagent-retriever` | `ServiceType.RETRIEVER` | 7011 | Custom PaperAgent OPEA MicroService |
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

## Verify the OPEA topology

```bash
curl http://localhost:7008/v1/topology
```

Expected flow:

```text
paperagent-retriever -> opea-service@llm
```

Call the PaperAgent MegaService:

```bash
curl -X POST http://localhost:7008/v1/paperagent \
  -H "Content-Type: application/json" \
  -d '{"text":"How can an edge-cloud academic assistant protect private drafts while using cloud literature intelligence?"}'
```

The response includes the generated `answer`, the framework marker `OPEA`, and the pipeline component list.

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
Question -> Retriever -> Rerank -> Guardrail -> LLM
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
